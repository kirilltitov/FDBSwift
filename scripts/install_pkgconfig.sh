#!/usr/bin/env bash

if [ $EUID != 0 ]; then
    if [ "$(uname)" == "Darwin" ]; then
        echo "This script requires privileged access in order to put `
            `a pkgconfig file into /usr/local/lib/pkgconfig `
            `(and also create it if it doesn't exist yet, it happens on fresh macOS)"
    elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
        echo "This script requires privileged access in order to put `
            `a pkgconfig file into /usr/lib/pkgconfig"
    fi

    sudo "$0" "$@"
    exit $?
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FILE=libfdb.pc
PKGCONFIG="${DIR}/${FILE}"
DEST_DIR="lib/pkgconfig/${FILE}"

if [ "$(uname)" == "Darwin" ]; then
    _PATH="/usr/local"
    TARGET="${_PATH}/${DEST_DIR}"
    mkdir -p $TARGET
    cp "${PKGCONFIG}.mac" $TARGET
    LIBPATH="${_PATH}/lib/libfdb_c.dylib"
    install_name_tool -id $LIBPATH $LIBPATH
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    cp "${PKGCONFIG}.linux" "/usr/${DEST_DIR}"
fi
