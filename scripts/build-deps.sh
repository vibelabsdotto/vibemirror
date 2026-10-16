#!/bin/bash
# Builds static, universal (arm64 + x86_64) libcrypto and libplist for macOS 14+
# into .deps/. Package.swift links these instead of Homebrew's single-arch builds.
set -euo pipefail

OPENSSL_VERSION=3.6.4
LIBPLIST_VERSION=2.7.0
MIN_MACOS=14.0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/.deps"
WORK="$DEPS/work"
mkdir -p "$WORK" "$DEPS/lib" "$DEPS/include"
export MACOSX_DEPLOYMENT_TARGET=$MIN_MACOS
JOBS=$(sysctl -n hw.ncpu)

fetch() {
    local url=$1 out=$2
    [[ -f "$out" ]] || curl -fsSL "$url" -o "$out"
}

build_openssl() {
    [[ -f "$DEPS/lib/libcrypto.a" ]] && return
    fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" "$WORK/openssl.tar.gz"
    for arch in arm64 x86_64; do
        rm -rf "$WORK/openssl-$arch" && mkdir -p "$WORK/openssl-$arch"
        tar -xzf "$WORK/openssl.tar.gz" -C "$WORK/openssl-$arch" --strip-components 1
        (cd "$WORK/openssl-$arch" &&
            ./Configure "darwin64-$arch-cc" no-shared no-tests no-apps no-docs "-mmacosx-version-min=$MIN_MACOS" >/dev/null &&
            make -j"$JOBS" build_libs >/dev/null)
    done
    lipo -create "$WORK/openssl-arm64/libcrypto.a" "$WORK/openssl-x86_64/libcrypto.a" -output "$DEPS/lib/libcrypto.a"
    rm -rf "$DEPS/include/openssl"
    cp -R "$WORK/openssl-arm64/include/openssl" "$DEPS/include/openssl"
}

build_libplist() {
    [[ -f "$DEPS/lib/libplist-2.0.a" ]] && return
    fetch "https://github.com/libimobiledevice/libplist/releases/download/$LIBPLIST_VERSION/libplist-$LIBPLIST_VERSION.tar.bz2" "$WORK/libplist.tar.bz2"
    for arch in arm64 x86_64; do
        rm -rf "$WORK/plist-$arch" && mkdir -p "$WORK/plist-$arch"
        tar -xjf "$WORK/libplist.tar.bz2" -C "$WORK/plist-$arch" --strip-components 1
        local host=$([[ $arch == arm64 ]] && echo aarch64-apple-darwin || echo x86_64-apple-darwin)
        (cd "$WORK/plist-$arch" &&
            CFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS -O2" CXXFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS -O2" \
            ./configure --host=$host --disable-shared --enable-static --without-cython --without-tests --prefix="$WORK/plist-$arch/out" >/dev/null &&
            make -j"$JOBS" -C libcnary >/dev/null && make -j"$JOBS" -C src libplist-2.0.la >/dev/null)
    done
    lipo -create "$WORK/plist-arm64/src/.libs/libplist-2.0.a" "$WORK/plist-x86_64/src/.libs/libplist-2.0.a" -output "$DEPS/lib/libplist-2.0.a"
    rm -rf "$DEPS/include/plist"
    cp -R "$WORK/plist-arm64/include/plist" "$DEPS/include/plist"
}

build_openssl
build_libplist
lipo -info "$DEPS/lib/libcrypto.a" "$DEPS/lib/libplist-2.0.a"
