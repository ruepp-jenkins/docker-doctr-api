#!/bin/sh
set -eu

# Any explicit command (e.g. `docker run ... ruepp/doctr-api python -c ...`) runs as-is.
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

set -- uvicorn server.main:app \
    --host "${HOST}" \
    --port "${PORT}" \
    --workers "${WORKERS}" \
    --log-level "${LOG_LEVEL}" \
    --proxy-headers \
    --forwarded-allow-ips "${FORWARDED_ALLOW_IPS}"

if [ -n "${ROOT_PATH}" ]; then
    set -- "$@" --root-path "${ROOT_PATH}"
fi

echo "Starting docTR API ${DOCTR_VERSION:-} on ${HOST}:${PORT} (workers: ${WORKERS})"
exec "$@"
