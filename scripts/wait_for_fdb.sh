#!/usr/bin/env bash
# Waits until a local FoundationDB cluster is healthy (up to a minute)

for _ in $(seq 1 30); do
    if fdbcli --exec status --timeout 5 2>/dev/null | grep -q "Healthy"; then
        fdbcli --exec status --timeout 5
        exit 0
    fi
    sleep 2
done

echo "FoundationDB cluster is not healthy" >&2
fdbcli --exec status --timeout 5
exit 1
