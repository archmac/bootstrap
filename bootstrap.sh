#!/bin/bash

set -e
set -u
set -o pipefail

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

function skip() {
    :
}

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
        echo "=== FAILED ===" 1>&2
        tail -40 "$name.log" 1>&2
        echo "=== full log at: '$PWD/$name.log' ===" 1>&2
        exit 1
    fi
}

function within() {
    pushd "$1" >/dev/null
    shift
    "$@"
    rc=$?
    popd >/dev/null
    return $rc
}

function make_install() {
    ./configure --prefix="$bootstrap_dir" "$@" || return $?
    make || return $?
    make install || return $?
}

function make_libtool() {
    make_install --program-prefix=g --enable-ltdl-install
}

function make_autoconf() {
    perl -pi -e 's/libtoolize/glibtoolize/g' bin/autoreconf.in || return $?
    perl -pi -e 's/libtoolize/glibtoolize/g' man/autoreconf.1 || return $?
    make_install
}

function make_automake() {
    make_install || return $?
    (perl -pe 's/^ {6}//' > "$bootstrap_dir/share/aclocal/dirlist") <<<"
      $bootstrap_dir/share/aclocal
      /usr/share/aclocal
    "
}

function make_openssl() {
    case $(uname -m) in
        x86_64)
            perl ./Configure --prefix="$bootstrap_dir" no-ssl3 no-ssl3-method zlib-dynamic shared enable-cms darwin64-x86_64-cc enable-ec_nistp_64_gcc_128 || return $?
            ;;
        arm64)
            perl ./Configure --prefix="$bootstrap_dir" no-ssl3 no-ssl3-method zlib-dynamic shared enable-cms darwin64-arm64-cc enable-ec_nistp_64_gcc_128 || return $?
            ;;
        *)
            fail "unsupported arch"
            ;;
    esac
    make depend || return $?
    make || return $?
    make install || return $?
}

function make_libarchive() {
    #patch < "$(fetch 'https://projects.archlinux.org/svntogit/packages.git/plain/trunk/0001-Limit-write-requests-to-at-most-INT_MAX.patch?h=packages/libarchive')"
    #patch < "$(fetch 'https://projects.archlinux.org/svntogit/packages.git/plain/trunk/0001-mtree-fix-line-filename-length-calculation.patch?h=packages/libarchive')"
    #patch < "$(fetch 'https://projects.archlinux.org/svntogit/packages.git/plain/trunk/libarchive-3.1.2-acl.patch?h=packages/libarchive')"
    #patch < "$(fetch 'https://projects.archlinux.org/svntogit/packages.git/plain/trunk/libarchive-3.1.2-sparce-mtree.patch?h=packages/libarchive')"
    ./build/autogen.sh || return $?
    make_install --without-xml2 --without-nettle --without-lzo2 --without-openssl --with-expat
}

function make_fakeroot() {
    # https://github.com/Homebrew/homebrew-core/pull/73692
    # https://github.com/mackyle/fakeroot
    # https://bugs.archlinux.org/task/69572
    # https://github.com/archlinux/svntogit-packages/blob/b89a2f75f218fa262193b14973a703d6c80a486f/trunk/PKGBUILD
    # https://salsa.debian.org/clint/fakeroot/-/merge_requests/10

    #patch -p1 -i ../../fakeroot-0002-OS-X-10.10-introduced-id_t-int-in-gs-etpriority.patch || return $?
    #patch -p1 -i ../../fakeroot-0001-Implement-openat-2-wrapper-which-handles-optional-ar.patch || return $?
    #patch -p1 -i ../../fakeroot-darwin-openat.patch || return $?

    #perl -pi -e 's/_DARWIN_NO_64_BIT_INODE/_DARWIN_USE_64_BIT_INODE/g' libfakeroot.c
    #perl -pi -e 's/_DARWIN_NO_64_BIT_INODE/_DARWIN_USE_64_BIT_INODE/g' libfakeroot_unix2003.c
    #perl -pi -e 's/_DARWIN_NO_64_BIT_INODE/_DARWIN_USE_64_BIT_INODE/g' communicate.c
    #perl -pi -e 's/_DARWIN_NO_64_BIT_INODE/_DARWIN_USE_64_BIT_INODE/g' faked.c

    patch -p0 <<'PATCH' || return $?
--- configure.ac	2021-05-16 13:10:01.000000000 +0200
+++ -	2021-05-16 13:10:04.000000000 +0200
@@ -604,8 +604,6 @@
 AC_CONFIG_FILES([
    Makefile
    scripts/Makefile
-   doc/Makefile
-   doc/de/Makefile doc/es/Makefile doc/fr/Makefile doc/nl/Makefile doc/pt/Makefile doc/sv/Makefile
    test/Makefile test/defs])
 AC_OUTPUT
PATCH
    patch -p0 <<'PATCH' || return $?
--- Makefile.am	2021-02-18 23:31:25.000000000 +0100
+++ -	2021-05-16 13:15:15.000000000 +0200
@@ -1,6 +1,6 @@
 AUTOMAKE_OPTIONS=foreign
 ACLOCAL_AMFLAGS = -I build-aux
-SUBDIRS=doc scripts test
+SUBDIRS=scripts test
 
 noinst_LTLIBRARIES = libcommunicate.la libmacosx.la
 libcommunicate_la_SOURCES = communicate.c
PATCH

    env CFLAGS="-mmacosx-version-min=10.15" LIBTOOLIZE=glibtoolize ./bootstrap || return $?
    ./configure --prefix="$bootstrap_dir" --libdir="$bootstrap_dir/lib/libfakeroot" --disable-static --with-ipc=sysv --disable-dependency-tracking --disable-silent-rules || return $?

    #make wraptmpf.h || return $?
    #patch -p1 -i ../../fakeroot-darwin-openat-wraptmp.patch || return $?

    make || return $?
    make install
}

function make_pacman() {
    patch -p0 < ../../pacman-usr.patch || return $?
    patch -p0 < ../../pacman-usr-local.patch || return $?
    patch -p0 < ../../pacman-tmp-scriptlet.patch || return $?
    patch -p0 < ../../pacman-lazy-chroot.patch || return $?
    patch -p0 < ../../makepkg-chmod.patch || return $?
    patch -p0 < ../../makepkg-gtouch.patch || return $?
    patch -p0 < ../../pacman-no-ro-check.patch || return $?
    patch -p0 < ../../pacman-macos-signals.patch || return $?
    patch -p0 < ../../pacman-sigaction-include.patch || return $?

    patch -p0 <<'PATCH'
--- scripts/makepkg.sh.in	2020-06-22 10:33:22.000000000 +0200
+++ -	2021-05-16 15:46:18.000000000 +0200
@@ -635,7 +635,7 @@
 
 	write_kv_pair "pkgarch" "$pkgarch"
 
-	local sum="$(sha256sum "${BUILDFILE}")"
+	local sum="$(gsha256sum "${BUILDFILE}")"
 	sum=${sum%% *}
 	write_kv_pair "pkgbuild_sha256sum" $sum
PATCH

    patch -p0 <<'PATCH'
--- scripts/repo-add.sh.in	2021-05-16 17:50:58.000000000 +0200
+++ -	2021-05-16 17:51:02.000000000 +0200
@@ -286,9 +286,9 @@
 
 	# compute checksums
 	msg2 "$(gettext "Computing checksums...")"
-	md5sum=$(md5sum "$pkgfile")
+	md5sum=$(gmd5sum "$pkgfile")
 	md5sum=${md5sum%% *}
-	sha256sum=$(sha256sum "$pkgfile")
+	sha256sum=$(gsha256sum "$pkgfile")
 	sha256sum=${sha256sum%% *}
 
 	# remove an existing entry if it exists, ignore failures
PATCH

    export CFLAGS="-I${bootstrap_dir}/include"
    export LIBARCHIVE_CFLAGS="-I${bootstrap_dir}/include"
    export LIBARCHIVE_LIBS="-larchive"
    export LIBCURL_CFLAGS="-I/usr/include/curl"
    export LIBCURL_LIBS="-lcurl"
    #export LIBSSL_CFLAGS="-I${bootstrap_dir/include"
    #export LIBSSL_LIBS="-lssl"
    export BASH_SHELL="$bootstrap_dir/bin/bash"
    ./configure --prefix="$bootstrap_dir" --enable-doc --with-scriptlet-shell="$bootstrap_dir/bin/bash" --with-curl --disable-silent-rules --disable-dependency-tracking || return $?
    make V=1 || return $?
    #make -C contrib || return $?
    make install || return $?
    #make -C contrib install || return $?

    case $(uname -m) in
        x86_64)
            perl -pi -e 's/#(C(?:XX|)FLAGS)="(.*?)"/$1="-march=x86-64 -mtune=generic $2"/' "$bootstrap_dir/etc/makepkg.conf"
            ;;
        arm64)
            perl -pi -e 's/#(C(?:XX|)FLAGS)="(.*?)"/$1="-march=arm64 -mtune=generic $2"/' "$bootstrap_dir/etc/makepkg.conf"
            ;;
        *)
            fail "unsupported arch"
            ;;
    esac
    perl -pi -e "s/(PKGEXT)='.*?'/\$1='.pkg.tar.gz'/" "$bootstrap_dir/etc/makepkg.conf"
    perl -pi -e "s/(SRCEXT)='.*?'/\$1='.src.tar.gz'/" "$bootstrap_dir/etc/makepkg.conf"
    perl -pi -e "s/(PURGE_TARGETS)=.*?$/\$1=({usr\/{,local\/},opt\/arch\/}{,share}\/info\/dir .packlist \*.pod)/" "$bootstrap_dir/etc/makepkg.conf"
}

function make_gpg() {
    local sdk_path
    sdk_path="$(xcodebuild -sdk -version | grep Path | grep Developer/SDKs/MacOSX10 | cut -d' ' -f2)"
    LDFLAGS="-lresolv" gl_cv_absolute_stdint_h="$sdk_path/usr/include/stdint.h" ./configure --prefix="$bootstrap_dir" --enable-maintainer-mode --enable-symcryptrun --disable-dependency-tracking
    LDFLAGS="-lresolv" make
    make install

    ln -s gpg "$bootstrap_dir/bin/gpg2"
}

# shellcheck disable=SC2016,SC2046
function bootstrap_stage1()
{
    mkdir -p "$build_dir"
    pushd "$build_dir" >/dev/null

    lazy "$bootstrap_dir/share/man/man1/gettext.1" \
    log gettext within $(expand $(fetch https://ftp.gnu.org/pub/gnu/gettext/gettext-0.21.tar.xz)) make_install --disable-dependency-tracking --disable-silent-rules --disable-debug --with-included-gettext --with-included-glib --with-included-libcroco --with-included-libunistring --without-git --without-cvs --without-xz --disable-java

    lazy "$bootstrap_dir/share/man/man1/glibtool.1" \
    log libtool within $(expand $(fetch http://ftp.gnu.org/gnu/libtool/libtool-2.4.6.tar.xz)) make_libtool

    # automake 1.16.3 doesn't like autoconf 2.70+
    lazy "$bootstrap_dir/share/man/man1/autoconf.1" \
    log autoconf within $(expand $(fetch http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.xz)) make_autoconf

    lazy "$bootstrap_dir/share/man/man1/automake.1" \
    log automake within $(expand $(fetch http://ftp.gnu.org/gnu/automake/automake-1.16.3.tar.xz)) make_automake

    lazy "$bootstrap_dir/share/man/man1/pkg-config.1" \
    log pkg-config within $(expand $(fetch https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz)) make_install --with-internal-glib --disable-debug
    # LD_FLAGS
    # --with-pc-path=

    lazy "$bootstrap_dir/share/man/man1/bash.1" \
    log bash within $(expand $(fetch http://ftp.gnu.org/gnu/bash/bash-5.1.tar.gz)) make_install --with-curses --enable-readline --with-included-gettext --without-bash-malloc

    lazy "$bootstrap_dir/bin/xz" \
    log xz within $(expand $(fetch http://tukaani.org/xz/xz-5.2.5.tar.gz)) make_install --disable-debug --disable-dependency-tracking --disable-silent-rules

    lazy "$bootstrap_dir/bin/openssl" \
    log openssl within $(expand $(fetch https://www.openssl.org/source/openssl-1.1.1k.tar.gz)) make_openssl

    lazy "$bootstrap_dir/share/man/man5/libarchive-formats.5" \
    log libarchive within $(expand $(fetch http://www.libarchive.org/downloads/libarchive-3.5.1.tar.gz)) make_libarchive

    lazy "$bootstrap_dir/share/man/man1/asciidoc.1" \
    log asciidoc within $(expand $(fetch http://downloads.sourceforge.net/project/asciidoc/asciidoc/8.6.9/asciidoc-8.6.9.tar.gz)) make_install

    lazy "$bootstrap_dir/bin/fakeroot" \
    log fakeroot within $(expand $(fetch https://salsa.debian.org/clint/fakeroot/-/archive/24d6b0857396cad87b2cabd32fb8af9ef4799915/fakeroot-24d6b0857396cad87b2cabd32fb8af9ef4799915.tar.bz2)) make_fakeroot
    #log fakeroot within $(expand $(fetch https://mirrors.ocf.berkeley.edu/debian/pool/main/f/fakeroot/fakeroot_1.24.orig.tar.gz fakeroot-1.24.tar.gz)) make_fakeroot
    #log fakeroot within $(expand $(fetch http://http.debian.net/debian/pool/main/f/fakeroot/fakeroot_1.25.3.orig.tar.gz fakeroot-1.25.3.tar.gz)) make_fakeroot

    lazy "$bootstrap_dir/share/libgpg-error/errorref.txt" \
    log libgpg-error within $(expand $(fetch https://www.gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.42.tar.bz2)) make_install

    lazy "$bootstrap_dir/share/man/man1/hmac256.1" \
    log libgcrypt within $(expand $(fetch https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.9.3.tar.bz2)) make_install --disable-static --disable-padlock-support

    lazy "$bootstrap_dir/share/info/assuan.info" \
    log libassuan within $(expand $(fetch https://www.gnupg.org/ftp/gcrypt/libassuan/libassuan-2.5.5.tar.bz2)) make_install

    lazy "$bootstrap_dir/share/info/ksba.info" \
    log libksba within $(expand $(fetch https://www.gnupg.org/ftp/gcrypt/libksba/libksba-1.5.1.tar.bz2)) make_install

    lazy "$bootstrap_dir/bin/npth-config" \
    log npth within $(expand $(fetch https://www.gnupg.org/ftp/gcrypt/npth/npth-1.6.tar.bz2)) make_install --enable-maintainer-mode

    lazy "$bootstrap_dir/bin/pinentry" \
    log pinentry within $(expand $(fetch https://www.gnupg.org/ftp/gcrypt/pinentry/pinentry-1.1.1.tar.bz2)) make_install

    lazy "$bootstrap_dir/bin/gpg2" \
    log gpg within $(expand $(fetch https://www.gnupg.org/ftp/gcrypt/gnupg/gnupg-2.3.1.tar.bz2)) make_gpg

    lazy "$bootstrap_dir/bin/gsha256sum" \
    log coreutils within $(expand $(fetch https://ftp.gnu.org/gnu/coreutils/coreutils-8.31.tar.xz)) make_install --libexecdir="$bootstrap_dir/lib" --program-prefix=g --without-gmp --enable-no-install-program=groups,hostname,kill,uptime gl_cv_func_ftello_works=yes

    lazy "$bootstrap_dir/bin/pacman" \
    log pacman within $(expand $(fetch https://sources.archlinux.org/other/pacman/pacman-5.2.2.tar.gz)) make_pacman
    #log pacman within $(expand $(fetch https://sources.archlinux.org/other/pacman/pacman-5.1.2.tar.gz)) make_pacman

    "$bootstrap_dir/bin/pacman" -V
    "$bootstrap_dir/bin/makepkg" -V
    popd >/dev/null
}

function bootstrap_stage2() {
    mkdir -p stage2/{packages,sources,srcpackages,makepkglogs}
    cp  "$bootstrap_dir/etc/makepkg.conf" stage2/makepkg.conf
    perl -pi -e "s,#(PKGDEST)=.*\$,\$1=$PWD/stage2/packages," "stage2/makepkg.conf"
    perl -pi -e "s,#(SRCDEST)=.*\$,\$1=$PWD/stage2/sources," "stage2/makepkg.conf"
    perl -pi -e "s,#(SRCPKGDEST)=.*\$,\$1=$PWD/stage2/srcpackages," "stage2/makepkg.conf"
    perl -pi -e "s,#(LOGDEST)=.*\$,\$1=$PWD/stage2/makepkglogs," "stage2/makepkg.conf"

    export PATH="/opt/arch/sbin:/opt/arch/bin:$PATH"
    local repo="mini"
    local pkgs=(
        filesystem
        libtool
        autoconf
        automake
        pkg-config
        gettext
        bash
        xz
        openssl
        libarchive
        asciidoc
        fakeroot
        libgpg-error
        libgcrypt
        libassuan
        libksba
        npth
        pinentry
        gnupg
        gpgme
        coreutils
        pacman-mirrorlist
        pacman
    )

    sudo mkdir -p /opt/arch/var/lib/pacman
    for pkg in "${pkgs[@]}"; do
        if [[ ! -e "$repo/$pkg/PKGBUILD" ]]; then
            echo "missing $pkg"
            continue
        fi

        if pacman -Q -b /opt/arch/var/lib/pacman $pkg >/dev/null 2>&1; then
            echo "skipping $pkg"
            continue
        fi

        pushd "$repo/$pkg" >/dev/null
        makepkg --config ../../stage2/makepkg.conf --skipchecksums --skipinteg --skippgpcheck --nocheck --nodeps --force --allsource
        makepkg --config ../../stage2/makepkg.conf --skipchecksums --skipinteg --skippgpcheck --nocheck --nodeps --force
        popd >/dev/null
        sudo pacman --upgrade --dbpath /opt/arch/var/lib/pacman --noconfirm --nodeps "stage2/packages/${pkg}"-*.pkg.tar.gz
    done
}

function bootstrap_stage3() {
    mkdir -p stage3/{packages,sources,srcpackages,makepkglogs}
    cp /opt/arch/etc/makepkg.conf stage3/makepkg.conf
    perl -pi -e "s,#(PKGDEST)=.*\$,\$1=$PWD/stage3/packages," "stage3/makepkg.conf"
    perl -pi -e "s,#(SRCDEST)=.*\$,\$1=$PWD/stage3/sources," "stage3/makepkg.conf"
    perl -pi -e "s,#(SRCPKGDEST)=.*\$,\$1=$PWD/stage3/srcpackages," "stage3/makepkg.conf"
    perl -pi -e "s,#(LOGDEST)=.*\$,\$1=$PWD/stage3/makepkglogs," "stage3/makepkg.conf"

    export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
    export PATH="/opt/arch/sbin:/opt/arch/bin:$PATH"
    local repo="mini"
    local pkgs=(
        filesystem
        libtool
        autoconf
        automake
        pkg-config
        gettext
        bash
        xz
        openssl
        libarchive
        asciidoc
        fakeroot
        libgpg-error
        libgcrypt
        libassuan
        libksba
        npth
        pinentry
        gnupg
        gpgme
        coreutils
        pacman-mirrorlist
        pacman
    )

    sudo rm -rf $repo/*/{pkg,src}
    for pkg in "${pkgs[@]}"; do
        if [[ ! -e "$repo/$pkg/PKGBUILD" ]]; then
            echo "missing $pkg"
            continue
        fi

        pushd "$repo/$pkg" >/dev/null
        makepkg --config ../../stage3/makepkg.conf --skipchecksums --skipinteg --skippgpcheck --nocheck --nodeps --force --allsource
        makepkg --config ../../stage3/makepkg.conf --skipchecksums --skipinteg --skippgpcheck --nocheck --nodeps --force
        popd >/dev/null
        sudo pacman --upgrade --noconfirm "stage3/packages/${pkg}"-*.pkg.tar.gz
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
