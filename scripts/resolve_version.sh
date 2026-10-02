#!/bin/bash
# Decides which docTR release this build packages. Prints "<tag> <is-latest>" on stdout, e.g.
# "v1.1.0 true"; everything else goes to stderr so the Jenkinsfile can capture stdout as-is.
#
# Inputs:
#   DOCTR_VERSION_OVERRIDE   optional release tag to build instead of the latest one, e.g. v1.0.1
#
# Called once by the Jenkinsfile's Prepare stage. Every agent then builds from the value resolved
# here: if each one asked GitHub itself, a release published mid-build would give the two
# architectures different versions under one tag.
#
# "Latest" is GitHub's own notion (/releases/latest): the newest non-draft, non-prerelease release.
# That is also exactly what the Jenkinsfile's URLTrigger watches, so a new release triggers a build
# that resolves to that release.
set -euo pipefail

REPO="mindee/doctr"
API="https://api.github.com/repos/${REPO}/releases/latest"

fetch_latest() {
    local body
    body="$(curl -fsSL --retry 3 --retry-delay 5 \
        -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: ruepp-jenkins/docker-doctr-api' \
        "${API}")" || {
        echo "ERROR: could not query ${API}" >&2
        return 1
    }
    # sed rather than jq: the agent needs Docker, git and curl, nothing more.
    printf '%s' "${body}" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

LATEST="$(fetch_latest)"
if [ -z "${LATEST}" ]; then
    echo "ERROR: no tag_name in the answer of ${API}" >&2
    exit 1
fi
echo "Latest docTR release: ${LATEST}" >&2

VERSION="${DOCTR_VERSION_OVERRIDE:-}"
VERSION="${VERSION#"${VERSION%%[![:space:]]*}"}"
VERSION="${VERSION%"${VERSION##*[![:space:]]}"}"
if [ -z "${VERSION}" ]; then
    VERSION="${LATEST}"
fi

# The value ends up in a git ref, a build arg and an image tag. Anything that is not a plain version
# is refused here rather than half-way through the build.
if ! printf '%s' "${VERSION}" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+([.-]?[A-Za-z0-9]+)*$'; then
    echo "ERROR: '${VERSION}' does not look like a docTR release tag (e.g. v1.1.0)" >&2
    exit 1
fi

if ! git ls-remote --exit-code --tags "https://github.com/${REPO}.git" "refs/tags/${VERSION}" >/dev/null; then
    echo "ERROR: ${REPO} has no tag '${VERSION}'" >&2
    exit 1
fi

IS_LATEST=false
if [ "${VERSION}" = "${LATEST}" ]; then
    IS_LATEST=true
fi

echo "Building docTR ${VERSION} (latest: ${IS_LATEST})" >&2
printf '%s %s\n' "${VERSION}" "${IS_LATEST}"
