properties(
    [
        githubProjectProperty(
            displayName: 'docker-doctr-api',
            projectUrlStr: 'https://github.com/ruepp-jenkins/docker-doctr-api'
        ),
        // Concurrent builds of the same branch would write the same tags, and the manifest could
        // pick up half of one build and half of another.
        disableConcurrentBuilds(abortPrevious: true)
    ]
)

// `checkout scm` rather than a `git` step with a URL and a credentials id spelled out here.
//
// Two reasons. The job already knows both — it found this file by cloning the repository — so
// repeating them is a second copy that can disagree with the first. And `scm` carries the exact
// revision that produced this Jenkinsfile, so both architecture agents check out the same commit
// even if the branch moves in between — which matters now that two agents check out independently
// instead of one.
def checkoutRepo() {
    checkout scm
    sh 'chmod +x scripts/*.sh'
}

// One architecture, built natively on its own agent. The caller checks the repository out, not this
// function. The post blocks below cannot move here — junit and cleanWs are stage directives, not
// steps.
def buildImage(String arch, String platform) {
    withEnv(["EXPECTED_PLATFORM=${platform}", "TEST_REPORT_SUFFIX=${arch}"]) {
        // Two attempts, a minute apart, because what fails here is usually not the build. A Jenkins
        // restart during `docker buildx build` kills the session to buildkitd ("received prior
        // goaway ... graceful_stop") and takes the shared builder with it; a registry push can meet
        // a transient 5xx. Running start.sh again answers both, because it is idempotent:
        // docker_initialize.sh recreates a builder it no longer finds, BuildKit replays the test
        // stage from cache, and pushing the same content by digest twice is a no-op. The minute is
        // for the restart case, where the node has only just reconnected and its Docker daemon may
        // still be coming up.
        //
        // A red test suite is retried too, and that is affordable: the cached test stage replays and
        // the Dockerfile's `verified` stage refuses again within seconds. An aborted build is not
        // retried at all — `retry` rethrows the interruption rather than looping, so this does not
        // fight the abortPrevious above.
        def attempt = 0
        retry(2) {
            attempt++
            if (attempt > 1) {
                echo "Build (${arch}) failed; retrying once in 60s"
                sleep time: 60, unit: 'SECONDS'
            }

            // Bound here rather than in the pipeline's environment block, which would export the
            // registry password into every sh step on every agent — the cleanup and the test suite
            // included, neither of which log in. This is the only step in this function that does:
            // start.sh calls scripts/docker_initialize.sh.
            withCredentials([string(credentialsId: 'DOCKER_API_PASSWORD',
                                    variable: 'DOCKER_API_PASSWORD')]) {
                sh './scripts/start.sh'
            }
        }

        // The image was pushed without a tag, so its digest is the only handle on it — and it is on
        // the wrong machine. stash is the one channel declarative pipelines offer between agents. It
        // has to happen here in steps: the post block below wipes the workspace.
        stash name: "digest-${arch}", includes: "digest-${arch}.txt"
    }
}

def publishManifest() {
    unstash 'digest-amd64'
    unstash 'digest-arm64'
    // The second and last place that logs in — see buildImage for why the binding is here.
    withCredentials([string(credentialsId: 'DOCKER_API_PASSWORD',
                            variable: 'DOCKER_API_PASSWORD')]) {
        sh './scripts/docker_manifest.sh'
    }
}

pipeline {
    // No global agent: the whole point of this pipeline is that the architecture builds run on
    // different machines, so every stage names its own.
    agent none

    parameters {
        // Empty means: the latest docTR release on GitHub, which is what every triggered build
        // does. Set it to rebuild an older release by hand; `latest` then stays where it is.
        string(name: 'DOCTR_VERSION_OVERRIDE',
               defaultValue: '',
               description: 'docTR release tag to build (e.g. v1.0.1). Empty = latest GitHub release.')
    }

    environment {
        IMAGE_FULLNAME = 'ruepp/doctr-api'

        // Every agent builds its own architecture and nothing else. 'host' is what tells
        // scripts/docker_platforms.sh to skip the QEMU registration: with a machine per platform
        // there is nothing left to emulate, and the --privileged binfmt container is no longer
        // needed on either agent.
        DOCKER_PLATFORMS = 'host'

        // The architectures scripts/docker_manifest.sh joins into one manifest list.
        MANIFEST_ARCHS = 'amd64 arm64'
    }

    triggers {
        // Two reasons to build, both watched here:
        //
        // 1. A new docTR release. GitHub's /releases/latest answers with the newest non-draft,
        //    non-prerelease release; '$.tag_name' changes exactly when one is published. The build
        //    then resolves the same endpoint (scripts/resolve_version.sh) and publishes the image
        //    under that very tag, plus `latest`.
        //    Unauthenticated, this API allows 60 requests per hour and IP — one every 30 minutes is
        //    far below that.
        //
        // 2. A new Python base image. Docker Hub's repository API answers anonymously, and '$.digest'
        //    changes exactly when the tag is republished. Do not watch 'tag_last_pulled' or
        //    'tag_last_pushed' — the first changes on every pull by anyone. The build then republishes
        //    the current release with the patched base under its existing tag.
        //    The tag mirrors the PYTHON_VERSION default in the Dockerfile. Change both together.
        URLTrigger(
            cronTabSpec: 'H/30 * * * *',
            labelRestriction: 'urltrigger',
            entries: [
                URLTriggerEntry(
                    url: 'https://api.github.com/repos/mindee/doctr/releases/latest',
                    contentTypes: [
                        JsonContent(
                            [
                                JsonContentEntry(jsonPath: '$.tag_name')
                            ]
                        )
                    ]
                ),
                URLTriggerEntry(
                    url: 'https://hub.docker.com/v2/repositories/library/python/tags/3.12-slim',
                    contentTypes: [
                        JsonContent(
                            [
                                JsonContentEntry(jsonPath: '$.digest')
                            ]
                        )
                    ]
                )
            ]
        )
    }

    stages {
        stage('Prepare') {
            // The docTR version goes into the build and into every tag, including the one the
            // manifest step below looks up. Resolved once here rather than by each agent: a release
            // published while the build runs would otherwise give the two architectures different
            // versions, joined under one tag.
            agent { label 'docker' }
            steps {
                checkoutRepo()
                script {
                    def resolved = sh(script: './scripts/resolve_version.sh', returnStdout: true).trim().split(/\s+/)
                    env.DOCTR_VERSION = resolved[0]
                    env.DOCTR_IS_LATEST = resolved[1]
                    currentBuild.description = "docTR ${env.DOCTR_VERSION}" +
                        (env.DOCTR_IS_LATEST == 'true' ? ' (latest)' : '')
                }
                echo "docTR release for this build: ${env.DOCTR_VERSION} (latest: ${env.DOCTR_IS_LATEST})"
            }
            post {
                always {
                    cleanWs()
                }
            }
        }

        stage('Build') {
            // Parallel across architectures. Each agent builds and pushes its own architecture by
            // digest; the manifest step below joins the two into one multi-arch tag.
            parallel {
                stage('amd64') {
                    agent { label 'docker' }
                    steps {
                        checkoutRepo()
                        buildImage('amd64', 'linux/amd64')
                    }
                    post {
                        always {
                            // 'always', so the report is published even when the build fails — which
                            // is precisely when knowing which test broke is worth something.
                            // allowEmptyResults stays false on purpose: a missing report means the
                            // tests did not run, and that should fail loudly rather than pass quietly.
                            junit testResults: 'test-results/*.junit.xml',
                                  allowEmptyResults: false,
                                  keepProperties: true
                            sh './scripts/docker_cleanup.sh'
                            cleanWs()
                        }
                    }
                }
                stage('arm64') {
                    agent { label 'oracle_docker' }
                    steps {
                        checkoutRepo()
                        buildImage('arm64', 'linux/arm64')
                    }
                    post {
                        always {
                            junit testResults: 'test-results/*.junit.xml',
                                  allowEmptyResults: false,
                                  keepProperties: true
                            sh './scripts/docker_cleanup.sh'
                            cleanWs()
                        }
                    }
                }
            }
        }

        stage('Manifest') {
            // Reached only when both architectures pushed: a failed branch fails the parallel stage
            // and this never runs, so a broken build cannot end up as a published tag that silently
            // serves one architecture.
            agent { label 'docker' }
            steps {
                checkoutRepo()
                publishManifest()
            }
            post {
                always {
                    cleanWs()
                }
            }
        }
    }

    post {
        always {
            // No cleanWs here: with `agent none` this block has no workspace to clean, and asking
            // for one fails the build after everything already succeeded. Each stage cleans its own.
            discordSend result: currentBuild.currentResult,
                description: env.GIT_URL,
                link: env.BUILD_URL,
                title: JOB_NAME,
                webhookURL: DISCORD_WEBHOOK
        }
    }
}
