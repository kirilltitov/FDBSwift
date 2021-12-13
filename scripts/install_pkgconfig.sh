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
SUFFIX_DIR="lib/pkgconfig"
SUFFIX_FILE="${SUFFIX_DIR}/${FILE}"

if [ "$(uname)" == "Darwin" ]; then
    PREFIX="/usr/local"
    TARGET_DIR="${PREFIX}/${SUFFIX_DIR}"
    TARGET_FILE="${PREFIX}/${SUFFIX_FILE}"
    echo "Creating directory ${TARGET_DIR} if not exists"
    mkdir -p $TARGET_DIR
    echo "Creating pkgconfig ${TARGET_FILE}"
    cp "${PKGCONFIG}.mac" $TARGET_FILE
    LIBPATH="${PREFIX}/lib/libfdb_c.dylib"
    install_name_tool -id $LIBPATH $LIBPATH
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    TARGET_FILE="/usr/${SUFFIX_FILE}"
    echo "Creating pkgconfig ${TARGET_FILE}"
    cp "${PKGCONFIG}.linux" $TARGET_FILE
fi
