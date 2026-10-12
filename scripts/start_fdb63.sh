#!/usr/bin/env bash
# Starts a local FoundationDB 6.3 cluster for compatibility tests: libfdb_c 7.4 talks to it via the multi-version
# client, loading the 6.3 client library as an external client (with API version 630).
#
# Usage: start_fdb63.sh <directory>
# Leaves in <directory>: fdb.cluster (port 4600) and ext/ with the 6.3 client library. Use with
#   FDB_NETWORK_OPTION_EXTERNAL_CLIENT_DIRECTORY=<directory>/ext FDB_CLUSTER_FILE=<directory>/fdb.cluster
#
# Environment: FDB63_VERSION (default 6.3.23)

set -euo pipefail

VERSION="${FDB63_VERSION:-6.3.23}"
DIR="$(mkdir -p "$1" && cd "$1" && pwd)"
cd "${DIR}"

for package in clients server; do
    curl -sSfLO "https://github.com/apple/foundationdb/releases/download/${VERSION}/foundationdb-${package}_${VERSION}-1_amd64.deb"
    dpkg-deb -x "foundationdb-${package}_${VERSION}-1_amd64.deb" dist
done

mkdir -p ext data
cp dist/usr/lib/libfdb_c.so "ext/libfdb_c_${VERSION}.so"
echo "fdb63:fdb63@127.0.0.1:4600" > fdb.cluster

setsid dist/usr/sbin/fdbserver -p 127.0.0.1:4600 -C fdb.cluster -d data -L data > server.log 2>&1 < /dev/null &

FDBCLI="dist/usr/bin/fdbcli -C fdb.cluster --timeout 10"
for _ in $(seq 1 30); do
    if ${FDBCLI} --exec "configure new single memory" > /dev/null 2>&1 \
        || ${FDBCLI} --exec "status minimal" 2>/dev/null | grep -q "available"; then
        break
    fi
    sleep 2
done
for _ in $(seq 1 30); do
    if ${FDBCLI} --exec "status minimal" 2>/dev/null | grep -q "The database is available"; then
        ${FDBCLI} --exec "status minimal"
        exit 0
    fi
    sleep 2
done

echo "FoundationDB ${VERSION} cluster is not available" >&2
cat server.log >&2
exit 1
