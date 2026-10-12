#!/usr/bin/env bash
# Runs the official FoundationDB binding tester against FDBBindingTester, comparing results with the reference
# Python binding. Requires a running local cluster, Swift, python3, pip and git.
#
# Environment: FDB_VERSION (default 7.4.8), SEEDS (number of random api tests, default 10), OPS (ops per test, 1000),
# API_VERSION (default 740), CLUSTER_FILE (default: the default cluster file).
#
# With API_VERSION below 710 (e.g. 630 for a FoundationDB 6.3 cluster via the multi-version client, see
# start_fdb63.sh) the harness itself is switched to that API version and tenants are not tested.

set -euo pipefail

FDB_VERSION="${FDB_VERSION:-7.4.8}"
SEEDS="${SEEDS:-10}"
OPS="${OPS:-1000}"
API_VERSION="${API_VERSION:-740}"
CLUSTER_FILE="${CLUSTER_FILE:-}"
# The full range of tuple integers, like the reference Python binding
MAX_INT_BITS=2040

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

HARNESS="${WORK}/foundationdb/bindings/bindingtester"
OPTIONS=(--api-version "${API_VERSION}")
if [ -n "${CLUSTER_FILE}" ]; then
    OPTIONS+=(--cluster-file "${CLUSTER_FILE}")
fi

if [ "${API_VERSION}" -ge 710 ]; then
    # Tenants are tested too, so they must be enabled in the cluster
    fdbcli --exec "configure tenant_mode=optional_experimental" --timeout 30
    COMPARE_SCRIPTED=(--compare python)
else
    # The harness talks to the cluster with the latest API version, switch it to the tested one,
    # and skip its tenant cleanup (there are no tenants before 710)
    python3 -I - "${HARNESS}" "${API_VERSION}" <<'PYTHON'
import re, sys
harness, version = sys.argv[1], int(sys.argv[2])
path = harness + "/__init__.py"
source = open(path).read()
open(path, "w").write(re.sub(r"(?m)^FDB_API_VERSION = .*$", "FDB_API_VERSION = %d" % version, source))
path = harness + "/bindingtester.py"
source = open(path).read()
source = re.sub(r"(?m)^    (\d+),\n", lambda m: m.group(0) if int(m.group(1)) <= version else "", source)
source = source.replace("        while True:\n            tr = self.db.create_transaction()",
                        "        while not self.args.no_tenants:\n            tr = self.db.create_transaction()")
open(path, "w").write(source)
PYTHON
    OPTIONS+=(--no-tenants)
    # The reference Python tester's unit tests expect a healthy client status, which an external client doesn't
    # report, so the scripted test is checked on its own
    COMPARE_SCRIPTED=()
fi

swift build -c release --product FDBBindingTester --package-path "${ROOT}"
TESTER="$(swift build -c release --show-bin-path --package-path "${ROOT}")/FDBBindingTester"

# Register the tester like the official ones are, so that it's tested with all tuple types and 2040-bit integers
# (unknown testers are limited to 64-bit integers and common types only)
cat >> "${WORK}/foundationdb/bindings/bindingtester/known_testers.py" <<PYTHON

testers["swift"] = Tester(
    "swift", "${TESTER}", ${MAX_INT_BITS}, 630, MAX_API_VERSION, types=ALL_TYPES, tenants_enabled=True
)
PYTHON

export PYTHONPATH="${WORK}/foundationdb/bindings/python"
cd "${HARNESS}"

failures=0
run() {
    local output
    output="$(python3 bindingtester.py swift "${OPTIONS[@]}" "$@" 2>&1)" || true
    if grep -q "had 0 incorrect result(s) and 0 error(s)" <<< "${output}"; then
        grep "^Test with" <<< "${output}"
    else
        echo "${output}"
        failures=$((failures + 1))
    fi
}

run "${COMPARE_SCRIPTED[@]}" --test-name scripted
for _ in $(seq 1 "${SEEDS}"); do
    run --compare python --test-name api --num-ops "${OPS}"
done
for _ in $(seq 1 "${SEEDS}"); do
    run --compare python --test-name directory --num-ops "${OPS}"
done
# Concurrent tests can't be compared with another binding, they are checked for consistency instead
run --test-name api --num-ops "${OPS}" --concurrency 3
run --test-name directory --num-ops "${OPS}" --concurrency 3
run --test-name directory_hca --num-ops "${OPS}" --concurrency 4

if [ "${failures}" -ne 0 ]; then
    echo "${failures} binding tester run(s) failed" >&2
    exit 1
fi
echo "All binding tester runs passed"
