#!/usr/bin/env bash
# Runs the official FoundationDB binding tester against FDBBindingTester, comparing results with the reference
# Python binding. Requires a running local cluster, Swift, python3, pip and git.
#
# Environment: FDB_VERSION (default 7.4.8), SEEDS (number of random api tests, default 10), OPS (ops per test, 1000)

set -euo pipefail

FDB_VERSION="${FDB_VERSION:-7.4.8}"
SEEDS="${SEEDS:-10}"
OPS="${OPS:-1000}"
# Ints wider than 64 bits (and negative ints below Int64.min) aren't supported by the tuple layer yet
MAX_INT_BITS=63

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo "Fetching binding tester ${FDB_VERSION}"
git clone -q --depth 1 --branch "${FDB_VERSION}" --filter=blob:none --sparse \
    https://github.com/apple/foundationdb.git "${WORK}/foundationdb"
git -C "${WORK}/foundationdb" sparse-checkout set bindings/bindingtester bindings/python

# The Python binding in the source tree lacks generated files, take them from the released package
pip download -q "foundationdb==${FDB_VERSION}" --no-deps -d "${WORK}/wheel"
python3 -I -m zipfile -e "${WORK}"/wheel/*.whl "${WORK}/wheel/extracted"
cp "${WORK}"/wheel/extracted/fdb/{fdboptions,apiversion}.py "${WORK}/foundationdb/bindings/python/fdb/"

# The binding tester touches tenant metadata on start
fdbcli --exec "configure tenant_mode=optional_experimental" --timeout 30

swift build -c release --product FDBBindingTester --package-path "${ROOT}"
TESTER="$(swift build -c release --show-bin-path --package-path "${ROOT}")/FDBBindingTester"

export PYTHONPATH="${WORK}/foundationdb/bindings/python"
cd "${WORK}/foundationdb/bindings/bindingtester"

failures=0
run() {
    local output
    output="$(python3 bindingtester.py "${TESTER}" --no-tenants --max-int-bits "${MAX_INT_BITS}" "$@" 2>&1)" || true
    if grep -q "had 0 incorrect result(s) and 0 error(s)" <<< "${output}"; then
        grep "^Test with" <<< "${output}"
    else
        echo "${output}"
        failures=$((failures + 1))
    fi
}

run --compare python --test-name scripted
for _ in $(seq 1 "${SEEDS}"); do
    run --compare python --test-name api --num-ops "${OPS}" --api-version 740
done
# Concurrent tests can't be compared with another binding, they are checked for consistency instead
run --test-name api --num-ops "${OPS}" --concurrency 3 --api-version 740

if [ "${failures}" -ne 0 ]; then
    echo "${failures} binding tester run(s) failed" >&2
    exit 1
fi
echo "All binding tester runs passed"
