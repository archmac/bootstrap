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
    rm -rf "$bootstrap_dir" "$build_dir"
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
    make_install --program-prefix=g --enable-ltdl-install
}

function make_autoconf() {
    perl -pi -e 's/libtoolize/glibtoolize/' bin/autoreconf.in
    perl -pi -e 's/libtoolize/glibtoolize/' man/autoreconf.1
    make_install
}

function make_automake() {
    make_install
    (perl -pe 's/^ {6}//' > "$bootstrap_dir/share/aclocal/dirlist") <<<"
      $bootstrap_dir/share/aclocal
      /usr/share/aclocal
    "
}

function make_openssl() {
    perl ./Configure --prefix="$bootstrap_dir" no-ssl2 zlib-dynamic shared enable-cms darwin64-x86_64-cc enable-ec_nistp_64_gcc_128 #--openssldir=
    make depend
    make
    make install
}

function make_libarchive() {
    patch < "$(fetch 'https://projects.archlinux.org/svntogit/packages.git/plain/trunk/0001-Limit-write-requests-to-at-most-INT_MAX.patch?h=packages/libarchive')"
    patch < "$(fetch 'https://projects.archlinux.org/svntogit/packages.git/plain/trunk/0001-mtree-fix-line-filename-length-calculation.patch?h=packages/libarchive')"
    patch < "$(fetch 'https://projects.archlinux.org/svntogit/packages.git/plain/trunk/libarchive-3.1.2-acl.patch?h=packages/libarchive')"
    patch < "$(fetch 'https://projects.archlinux.org/svntogit/packages.git/plain/trunk/libarchive-3.1.2-sparce-mtree.patch?h=packages/libarchive')"
    ./build/autogen.sh
    make_install --without-xml2 --without-nettle --without-lzo2
}

function make_fakeroot() {
    patch < "$(fetch 'https://bugs.debian.org/cgi-bin/bugreport.cgi?msg=5;filename=0002-OS-X-10.10-introduced-id_t-int-in-gs-etpriority.patch;att=2;bug=766649')"
    patch < "$(fetch 'https://bugs.debian.org/cgi-bin/bugreport.cgi?msg=5;filename=0001-Implement-openat-2-wrapper-which-handles-optional-ar.patch;att=1;bug=766649')"
    (perl -pe 's/^ {6}//' | patch) <<<'
      index 15fdd1d..29d738d 100644
      --- a/libfakeroot.c
      +++ b/libfakeroot.c
      @@ -2446,6 +2446,6 @@ int openat(int dir_fd, const char *pathname, int flags, ...)
               va_end(args);
               return next_openat(dir_fd, pathname, flags, mode);
           }
      -    return next_openat(dir_fd, pathname, flags);
      +    return next_openat(dir_fd, pathname, flags, NULL);
       }
       #endif
    '
    ./configure --prefix="$bootstrap_dir" --libdir="$bootstrap_dir/lib/libfakeroot" --disable-static --with-ipc=sysv --disable-dependency-tracking --disable-silent-rules
    make wraptmpf.h
    (perl -pe 's/^ {6}//' | patch) <<<'
      diff --git a/wraptmpf.h b/wraptmpf.h
      index dbfccc9..0e04771 100644
      --- a/wraptmpf.h
      +++ b/wraptmpf.h
      @@ -575,6 +575,10 @@ static __inline__ int next_mkdirat (int dir_fd, const char *pathname, mode_t mod
       #endif /* HAVE_MKDIRAT */
       #ifdef HAVE_OPENAT
       extern int openat (int dir_fd, const char *pathname, int flags, ...);
      +static __inline__ int next_openat (int dir_fd, const char *pathname, int flags, mode_t mode) __attribute__((always_inline));
      +static __inline__ int next_openat (int dir_fd, const char *pathname, int flags, mode_t mode) {
      +  return openat (dir_fd, pathname, flags, mode);
      +}

       #endif /* HAVE_OPENAT */
       #ifdef HAVE_RENAMEAT
    '
    make
    make install
}

function make_pacman() {
    patch -p0 < ../../pacman-usr.patch
    patch -p0 < ../../pacman-usr-local.patch
    patch -p0 < ../../pacman-tmp-scriptlet.patch

    export CFLAGS="-I${bootstrap_dir}/include"
    export LIBARCHIVE_CFLAGS="-I${bootstrap_dir}/include"
    export LIBARCHIVE_LIBS="-larchive"
    export LIBCURL_CFLAGS="-I/usr/include/curl"
    export LIBCURL_LIBS="-lcurl"
    #export LIBSSL_CFLAGS="-I${bootstrap_dir/include"
    #export LIBSSL_LIBS="-lssl"
    ./configure --prefix="$bootstrap_dir" --enable-doc --with-scriptlet-shell="$bootstrap_dir/bin/bash" --with-curl --disable-silent-rules --disable-dependency-tracking
    make
    make -C contrib
    make install
    make -C contrib install

    perl -pi -e 's/#(C(?:XX|)FLAGS)="(.*?)"/$1="-march=x86-64 -mtune=generic $2"/' "$bootstrap_dir/etc/makepkg.conf"
    perl -pi -e "s/(PKGEXT)='.*?'/\$1='.pkg.tar.xz'/" "$bootstrap_dir/etc/makepkg.conf"
    perl -pi -e "s/(SRCEXT)='.*?'/\$1='.src.tar.xz'/" "$bootstrap_dir/etc/makepkg.conf"
    perl -pi -e "s/(PURGE_TARGETS)=.*?$/\$1=({usr\/{,local\/},opt\/arch\/}{,share}\/info\/dir .packlist \*.pod)/" "$bootstrap_dir/etc/makepkg.conf"
}

function make_gpg() {
    local sdk_path
    sdk_path="$(xcodebuild -sdk -version | grep Path | grep Developer/SDKs/MacOSX10 | cut -d' ' -f2)"
    LDFLAGS="-lresolv" gl_cv_absolute_stdint_h="$sdk_path/usr/include/stdint.h" ./configure --prefix="$bootstrap_dir" --enable-maintainer-mode --enable-symcryptrun --disable-dependency-tracking
    LDFLAGS="-lresolv" make
    make install

    ln -s "$bootstrap_dir/bin/"{gpg2,gpg}
}

# shellcheck disable=SC2016,SC2046
function bootstrap_stage1()
{
    mkdir -p "$build_dir"
    pushd "$build_dir"

    lazy "$bootstrap_dir/share/man/man1/gettext.1" \
    log gettext within $(expand $(fetch https://ftp.gnu.org/gnu/gettext/gettext-0.19.7.tar.xz)) make_install --disable-dependency-tracking --disable-silent-rules --disable-debug --with-included-gettext --with-included-glib --with-included-libcroco --with-included-libunistring --without-git --without-cvs --without-xz

    lazy "$bootstrap_dir/share/man/man1/glibtool.1" \
    log libtool within $(expand $(fetch http://ftp.gnu.org/gnu/libtool/libtool-2.4.6.tar.gz)) make_libtool

    lazy "$bootstrap_dir/share/man/man1/autoconf.1" \
    log autoconf within $(expand $(fetch http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz)) make_autoconf

    lazy "$bootstrap_dir/share/man/man1/automake.1" \
    log automake within $(expand $(fetch http://ftp.gnu.org/gnu/automake/automake-1.15.tar.gz)) make_automake

    lazy "$bootstrap_dir/share/man/man1/pkg-config.1" \
    log pkg-config within $(expand $(fetch https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.1.tar.gz)) make_install --with-internal-glib --disable-debug
    # LD_FLAGS
    # --with-pc-path=

    lazy "$bootstrap_dir/share/man/man1/bash.1" \
    log bash within $(expand $(fetch http://ftp.gnu.org/gnu/bash/bash-4.3.tar.gz)) make_install

    lazy "$bootstrap_dir/bin/xz" \
    log xz within $(expand $(fetch http://tukaani.org/xz/xz-5.2.2.tar.gz)) make_install --disable-debug --disable-dependency-tracking --disable-silent-rules

    lazy "$bootstrap_dir/bin/openssl" \
    log openssl within $(expand $(fetch https://www.openssl.org/source/openssl-1.0.2g.tar.gz)) make_openssl

    lazy "$bootstrap_dir/share/man/man5/libarchive-formats.5" \
    log libarchive within $(expand $(fetch http://www.libarchive.org/downloads/libarchive-3.1.2.tar.gz)) make_libarchive

    lazy "$bootstrap_dir/share/man/man1/asciidoc.1" \
    log asciidoc within $(expand $(fetch http://downloads.sourceforge.net/project/asciidoc/asciidoc/8.6.9/asciidoc-8.6.9.tar.gz)) make_install

    lazy "$bootstrap_dir/bin/fakeroot" \
    log fakeroot within $(expand $(fetch http://http.debian.net/debian/pool/main/f/fakeroot/fakeroot_1.20.2.orig.tar.bz2 fakeroot-1.20.2.tar.bz2)) make_fakeroot

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

    "$bootstrap_dir/bin/pacman" -V
    "$bootstrap_dir/bin/makepkg" -V
    popd
}

function bootstrap_stage2() {
    export PATH="/opt/arch/sbin:/opt/arch/bin:$PATH"
    local repo="mini"
    local pkgs="filesystem libtool autoconf automake pkg-config gettext readline bash xz openssl libarchive asciidoc fakeroot libgpg-error libgcrypt libassuan libksba pth pinentry gnupg gpgme pacman-mirrorlist pacman"

    sudo mkdir -p /opt/arch/var/lib/pacman
    for pkg in $pkgs; do
        if [[ ! -e "$repo/$pkg/PKGBUILD" ]]; then
            echo "missing $pkg"
            continue
        fi

        if pacman -Q -b /opt/arch/var/lib/pacman $pkg >/dev/null 2>&1; then
            echo "skipping $pkg"
            continue
        fi

        pushd "$repo/$pkg"
        makepkg --skippgpcheck --nocheck --nodeps --force
        sudo pacman --upgrade --dbpath /opt/arch/var/lib/pacman --noconfirm --nodeps "${pkg}"-*.pkg.tar.xz
        popd
    done
}

function bootstrap_stage3() {
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
    export PATH="/opt/arch/sbin:/opt/arch/bin:$PATH"
    local repo="mini"
    local pkgs="filesystem libtool autoconf automake pkg-config gettext readline bash xz openssl libarchive asciidoc fakeroot libgpg-error libgcrypt libassuan libksba pth pinentry gnupg gpgme pacman-mirrorlist pacman"

    sudo rm -rf $repo/*/{pkg,src}
    for pkg in $pkgs; do
        if [[ ! -e "$repo/$pkg/PKGBUILD" ]]; then
            echo "missing $pkg"
            continue
        fi

        pushd "$repo/$pkg"
        makepkg --skippgpcheck --nocheck --force
        sudo pacman --upgrade --noconfirm "${pkg}"-*.pkg.tar.xz
        popd
    done
}

if [[ $# -ge 1 && $1 == "stage1" ]]; then
    bootstrap_stage1
fi

if [[ $# -ge 1 && $1 == "stage2" ]]; then
    bootstrap_stage2
fi

if [[ $# -ge 1 && $1 == "stage3" ]]; then
    bootstrap_stage3
fi
