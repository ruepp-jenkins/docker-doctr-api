#!/bin/bash
# Resolves the repository and tags this build publishes. Sourced, not executed.
#
# Inputs:
#   IMAGE_FULLNAME   repository stem, e.g. ruepp/doctr-api
#   DOCTR_VERSION    docTR release tag being packaged, e.g. v1.1.0 (scripts/resolve_version.sh)
#   DOCTR_IS_LATEST  "true" when DOCTR_VERSION is GitHub's latest release
#
# Exports:
#   IMAGE_REPO   repository this build pushes to
#   BASE_TAG     the tag the finished manifest list carries
#   FINAL_TAGS   every tag the manifest list gets, space separated
#
# The image tag is the upstream release tag, unchanged: ruepp/doctr-api:v1.1.0 contains docTR v1.1.0.
# A rebuild of the same release (new base image, changes in this repository) overwrites that tag.
# `latest` only moves when the newest release is built, so rebuilding an older release by hand
# cannot pull `latest` backwards.
#
# There is no per-architecture tag. Each architecture pushes by digest and the manifest list is the
# only thing that gets named — see scripts/start.sh for how the digest reaches the manifest step.

: "${IMAGE_FULLNAME:?IMAGE_FULLNAME is not set}"
: "${DOCTR_VERSION:?DOCTR_VERSION is not set (resolved by scripts/resolve_version.sh)}"

# A slash is legal in a branch name and illegal in a tag, so `feature/x` would otherwise be pushed as
# a repository named after the branch's first segment rather than as a tag.
SAFE_BRANCH="$(echo "${BRANCH_NAME:-local}" | tr '/' '-')"

case "${BRANCH_NAME:-}" in
    master|main)
        IMAGE_REPO="${IMAGE_FULLNAME}"
        BASE_TAG="${DOCTR_VERSION}"
        FINAL_TAGS="${BASE_TAG}"
        if [ "${DOCTR_IS_LATEST:-false}" = "true" ]; then
            FINAL_TAGS="${FINAL_TAGS} latest"
        fi
        ;;
    *)
        IMAGE_REPO="${IMAGE_FULLNAME}-test"
        BASE_TAG="${SAFE_BRANCH}-${DOCTR_VERSION}"
        FINAL_TAGS="${BASE_TAG}"
        ;;
esac

export IMAGE_REPO BASE_TAG FINAL_TAGS
