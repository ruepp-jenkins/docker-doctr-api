#!/bin/sh
# Runs INSIDE the image build (Dockerfile stage `test`), not on a Jenkins agent.
#
# Deliberately never fails: the `test-results` target has to export a JUnit report even for a red
# suite, otherwise Jenkins has nothing to publish and the build log is the only record of what broke.
# The verdict is written to $OUT/exit-code, and the Dockerfile's `verified` stage is what refuses to
# build an image from it.
#
# Three parts:
#   upstream  the API tests shipped with the docTR release (api/tests), unchanged
#   image     this repository's tests (tests/): health route, baked-in models, OCR round trip
#   server    the real entrypoint, started in the background and probed over HTTP
set -u

OUT="${1:-/out}"
mkdir -p "${OUT}"
status=0

echo "== upstream API tests"
if ! python -m pytest upstream-tests -p no:cacheprovider -o junit_suite_name=upstream \
        --junitxml="${OUT}/upstream.junit.xml"; then
    status=1
fi

echo "== image tests"
if ! python -m pytest tests -p no:cacheprovider -o junit_suite_name=image \
        --junitxml="${OUT}/image.junit.xml"; then
    status=1
fi

echo "== server smoke test"
PORT=18080 HOST=127.0.0.1 WORKERS=1 LOG_LEVEL=warning ROOT_PATH="" FORWARDED_ALLOW_IPS=127.0.0.1 \
    sh /opt/doctr-api/docker-entrypoint.sh > /tmp/server.log 2>&1 &
server_pid=$!
smoke=1
i=0
while [ "${i}" -lt 60 ]; do
    if curl -fsS http://127.0.0.1:18080/health > /tmp/health.json 2>/dev/null; then
        smoke=0
        break
    fi
    i=$((i + 1))
    sleep 1
done
kill "${server_pid}" 2>/dev/null
wait "${server_pid}" 2>/dev/null

if [ "${smoke}" -eq 0 ]; then
    echo "ok: $(cat /tmp/health.json)"
    cat > "${OUT}/smoke.junit.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<testsuites><testsuite name="smoke" tests="1" failures="0" errors="0"><testcase classname="smoke" name="entrypoint_serves_health"/></testsuite></testsuites>
XML
else
    echo "server did not answer /health within 60s:" >&2
    cat /tmp/server.log >&2
    status=1
    cat > "${OUT}/smoke.junit.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<testsuites><testsuite name="smoke" tests="1" failures="1" errors="0"><testcase classname="smoke" name="entrypoint_serves_health"><failure message="no answer on /health within 60s"/></testcase></testsuite></testsuites>
XML
fi

printf '%s\n' "${status}" > "${OUT}/exit-code"
echo "== result: ${status} (0 = all green)"
exit 0
