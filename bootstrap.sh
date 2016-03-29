#!/bin/bash

set -e
set -u

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

bootstrap_dir="$PWD/stage1"
build_dir="$PWD/build"

export PATH="$bootstrap_dir/bin:$PATH"

if [[ $# -ge 1 && $1 == "shell" ]]; then
    cd "$bootstrap_dir"
    bash -i
    exit
fi

if [[ $# -ge 1 && $1 == "pristine" ]]; then
    rm -rf bootstrap build
fi

function fetch() {
    local url="$1"
    local out
    if [[ $# -ge 2 && -n $2 ]]; then
        out="$2"
    else
        out="${url##*/}"
    fi
    if [[ ! -f "$out" ]]; then
        echo "* fetching $url" 1>&2
        curl -4 -L -o "$out" "$url" >/dev/null
    fi
    echo "$out"
}

function expand() {
    local archive="$1"
    local args
    case $1 in
        *.tar.xz)
            args="-J"
            ;;
        *.tar.gz)
            args="-z"
            ;;
        *.tar.bz2)
            args="-j"
            ;;
        *)
            exit 1
            ;;
    esac
    tar -x $args -f "$archive" >/dev/null
    echo "${archive%.tar.*}"
}

function lazy() {
    if [[ ! -e "$1" ]]; then
        shift
        "$@"
    fi
}

function log() {
    local name="$1"
    shift
    echo "* $name"
    if ! "$@" >"$name.log" 2>&1; then
        tail -40 "$name.log" 1>&2
        exit 1
    fi
}

function within() {
    pushd "$1"
    shift
    "$@"
    popd
}

function make_install() {
    ./configure --prefix="$bootstrap_dir" "$@"
    make
    make install
}

function make_libtool() {
    make_install
    ln -s "$bootstrap_dir/bin/"{libtoolize,glibtoolize}
}

function make_openssl() {
    perl ./Configure --prefix="$bootstrap_dir" no-ssl2 darwin64-x86_64-cc enable-ec_nistp_64_gcc_128 #--openssldir=
    make depend
    make
    make install
}

function make_libarchive() {
    ./build/autogen.sh
    make_install
}

function make_fakeroot() {
    patch -Np0 < "$(fetch https://raw.githubusercontent.com/kladd/pacman-osx-pkgs/osx-10.10/core/darwin-fakeroot/darwin-fakeroot.patch)"
    make PREFIX="$bootstrap_dir"
    make PREFIX="$bootstrap_dir" install
}

function make_pacman() {
    export CFLAGS="-I${bootstrap_dir}/include"
    export LIBARCHIVE_CFLAGS="-I${bootstrap_dir}/include"
    export LIBARCHIVE_LIBS="-larchive"
    export LIBCURL_CFLAGS="-I/usr/include/curl"
    export LIBCURL_LIBS="-lcurl"
    #export LIBSSL_CFLAGS="-I${bootstrap_dir/include"
    #export LIBSSL_LIBS="-lssl"
    ./configure --prefix="$bootstrap_dir" --enable-doc --with-scriptlet-shell="$bootstrap_dir/bin/bash" --with-curl
    make
    make -C contrib
    make install
    make -C contrib install

    perl -pi -e 's/#(C(?:XX|)FLAGS)="(.*?)"/$1="-march=x86-64 -mtune=generic $2"/' "$bootstrap_dir/etc/makepkg.conf"
    perl -pi -e "s/(PKGEXT)='.*?'/\$1='.pkg.tar.xz'/" "$bootstrap_dir/etc/makepkg.conf"
    perl -pi -e "s/(SRCEXT)='.*?'/\$1='.src.tar.xz'/" "$bootstrap_dir/etc/makepkg.conf"
}

function make_gpg() {
    local sdk_path
    sdk_path="$(xcodebuild -sdk -version | grep Path | grep Developer/SDKs/MacOSX10 | cut -d' ' -f2)"
    LDFLAGS="-lresolv" gl_cv_absolute_stdint_h="$sdk_path/usr/include/stdint.h" ./configure --prefix="$bootstrap_dir" --enable-maintainer-mode --enable-symcryptrun
    LDFLAGS="-lresolv" make
    make install

    ln -s "$bootstrap_dir/bin/"{gpg2,gpg}
}

mkdir -p "$build_dir"
cd "$build_dir"

# shellcheck disable=SC2016,SC2046
{
    lazy "$bootstrap_dir/share/man/man1/gettext.1" \
    log gettext within $(expand $(fetch https://ftp.gnu.org/gnu/gettext/gettext-0.19.7.tar.xz)) make_install

    lazy "$bootstrap_dir/share/man/man1/autoconf.1" \
    log autoconf within $(expand $(fetch http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz)) make_install

    lazy "$bootstrap_dir/share/man/man1/automake.1" \
    log automake within $(expand $(fetch http://ftp.gnu.org/gnu/automake/automake-1.15.tar.gz)) make_install

    lazy "$bootstrap_dir/share/man/man1/pkg-config.1" \
    log pkg_config within $(expand $(fetch https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.1.tar.gz)) make_install --with-internal-glib

    lazy "$bootstrap_dir/share/man/man1/libtool.1" \
    log libtool within $(expand $(fetch http://ftp.gnu.org/gnu/libtool/libtool-2.4.6.tar.gz)) make_libtool

    lazy "$bootstrap_dir/share/man/man1/bash.1" \
    log bash within $(expand $(fetch http://ftp.gnu.org/gnu/bash/bash-4.3.tar.gz)) make_install

    lazy "$bootstrap_dir/bin/xz" \
    log xz within $(expand $(fetch http://tukaani.org/xz/xz-5.2.2.tar.gz)) make_install

    lazy "$bootstrap_dir/bin/openssl" \
    log openssl within $(expand $(fetch https://www.openssl.org/source/openssl-1.0.2g.tar.gz)) make_openssl

    lazy "$bootstrap_dir/share/man/man5/libarchive-formats.5" \
    log libarchive within $(expand $(fetch http://www.libarchive.org/downloads/libarchive-3.1.2.tar.gz)) make_libarchive

    lazy "$bootstrap_dir/share/man/man1/asciidoc.1" \
    log asciidoc within $(expand $(fetch http://downloads.sourceforge.net/project/asciidoc/asciidoc/8.6.9/asciidoc-8.6.9.tar.gz)) make_install

    lazy "$bootstrap_dir/bin/fakeroot" \
    log fakeroot within $(expand $(fetch https://github.com/duskwuff/darwin-fakeroot/archive/v1.1.tar.gz darwin-fakeroot-1.1.tar.gz)) make_fakeroot


    lazy "$bootstrap_dir/share/man/man1/gpg-error-config.1" \
    log libgpg-error within $(expand $(fetch ftp://ftp.gnupg.org/gcrypt/libgpg-error/libgpg-error-1.21.tar.bz2)) make_install

    lazy "$bootstrap_dir/share/man/man1/hmac256.1" \
    log libgcrypt within $(expand $(fetch ftp://ftp.gnupg.org/gcrypt/libgcrypt/libgcrypt-1.6.5.tar.bz2)) make_install --disable-static --disable-padlock-support

    lazy "$bootstrap_dir/share/info/assuan.info" \
    log libassuan within $(expand $(fetch ftp://ftp.gnupg.org/gcrypt/libassuan/libassuan-2.4.2.tar.bz2)) make_install

    lazy "$bootstrap_dir/share/info/ksba.info" \
    log libksba within $(expand $(fetch ftp://ftp.gnupg.org/gcrypt/libksba/libksba-1.3.3.tar.bz2)) make_install

    lazy "$bootstrap_dir/bin/pth-config" \
    log pth within $(expand $(fetch http://ftpmirror.gnu.org/pth/pth-2.0.7.tar.gz)) make_install --enable-maintainer-mode

    lazy "$bootstrap_dir/bin/pinentry" \
    log pinentry within $(expand $(fetch ftp://ftp.gnupg.org/gcrypt/pinentry/pinentry-0.9.7.tar.bz2)) make_install

    lazy "$bootstrap_dir/bin/gpg2" \
    log gpg within $(expand $(fetch https://www.mirrorservice.org/sites/ftp.gnupg.org/gcrypt/gnupg/gnupg-2.0.29.tar.bz2)) make_gpg

    lazy "$bootstrap_dir/bin/pacman" \
    log pacman within $(expand $(fetch https://sources.archlinux.org/other/pacman/pacman-5.0.1.tar.gz)) make_pacman
}

"$bootstrap_dir/bin/pacman" -V
"$bootstrap_dir/bin/makepkg" -V

