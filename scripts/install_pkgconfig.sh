#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FILE=libfdb.pc
PKGCONFIG="${DIR}/${FILE}"
DEST_DIR="lib/pkgconfig/${FILE}"

if [ "$(uname)" == "Darwin" ]; then
    cp "${PKGCONFIG}.mac" "/usr/local/${DEST_DIR}"
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    cp "${PKGCONFIG}.linux" "/usr/${DEST_DIR}"
fi
