#!/bin/bash

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

bootstrap_dir="$(pwd)/bootstrap"

export PATH="$bootstrap_dir/bin:$PATH"


if [[ $1 == "shell" ]]; then
    cd bootstrap
    bash -i
    exit
fi

if [[ $1 == "pristine" ]]; then
    ls -1 | grep -v bootstrap.sh | xargs rm -rf
fi

set -e
set -u

echo "* gettext"
if [[ ! -e "$bootstrap_dir/share/man/man1/gettext.1" ]]; then
(
set -e
curl -4 -O https://ftp.gnu.org/gnu/gettext/gettext-0.19.7.tar.xz
tar -xJvf gettext-0.19.7.tar.xz
cd gettext-0.19.7
./configure --prefix="$bootstrap_dir"
make
make install
) > gettext.log 2>&1 || (tail -40 gettext.log; exit 1)
fi

echo "* autoconf"
if [[ ! -e "$bootstrap_dir/share/man/man1/autoconf.1" ]]; then
(
set -e
curl -4 -O http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
tar -xzvf autoconf-2.69.tar.gz
cd autoconf-2.69
./configure --prefix="$bootstrap_dir"
make
make install
) > autoconf.log 2>&1 || (tail -40 autoconf.log; exit 1)
fi

echo "* automake"
if [[ ! -e "$bootstrap_dir/share/man/man1/automake.1" ]]; then
(
set -e
curl -4 -O http://ftp.gnu.org/gnu/automake/automake-1.15.tar.gz
tar -xzvf automake-1.15.tar.gz
cd automake-1.15
./configure --prefix="$bootstrap_dir"
make
make install
) > automake.log 2>&1 || (tail -40 automake.log; exit 1)
fi

echo "* pkg-config"
if [[ ! -e "$bootstrap_dir/share/man/man1/pkg-config.1" ]]; then
(
set -e
curl -O https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.1.tar.gz
tar -xzvf pkg-config-0.29.1.tar.gz
cd pkg-config-0.29.1
./configure --prefix="$bootstrap_dir" --with-internal-glib
make
make install
) > pkg-config.log 2>&1 || (tail -40 pkg-config.log; exit 1)
fi

echo "* libtool"
if [[ ! -e "$bootstrap_dir/share/man/man1/libtool.1" ]]; then
(
set -e
curl -4 -O http://ftp.gnu.org/gnu/libtool/libtool-2.4.6.tar.gz
tar -xzvf libtool-2.4.6.tar.gz
cd libtool-2.4.6
./configure --prefix="$bootstrap_dir"
make
make install
ln -s "$bootstrap_dir/bin/"{libtoolize,glibtoolize}
) > libtool.log 2>&1 || (tail -40 libtool.log; exit 1)
fi

echo "* bash"
if [[ ! -e "$bootstrap_dir/share/man/man1/bash.1" ]]; then
(
set -e
curl -4 -O http://ftp.gnu.org/gnu/bash/bash-4.3.tar.gz
tar -xzvf bash-4.3.tar.gz
cd bash-4.3
./configure --prefix="$bootstrap_dir"
make
make install
) > bash.log 2>&1 || (tail -40 bash.log; exit 1)
fi

echo "* libarchive"
if [[ ! -e "$bootstrap_dir/share/man/man5/libarchive-formats.5" ]]; then
(
set -e
curl -4 -LO http://www.libarchive.org/downloads/libarchive-3.1.2.tar.gz
tar -xzvf libarchive-3.1.2.tar.gz
cd libarchive-3.1.2
./build/autogen.sh
./configure --prefix="$bootstrap_dir"
make
make install
) > libarchive.log 2>&1 || (tail -40 libarchive.log; exit 1)
fi

echo "* asciidoc"
if [[ ! -e "$bootstrap_dir/share/man/man1/asciidoc.1" ]]; then
(
set -e
curl -4 -LO http://downloads.sourceforge.net/project/asciidoc/asciidoc/8.6.9/asciidoc-8.6.9.tar.gz
tar -xzvf asciidoc-8.6.9.tar.gz
cd asciidoc-8.6.9
./configure --prefix="$bootstrap_dir"
make
make install
) > asciidoc.log 2>&1 || (tail -40 asciidoc.log; exit 1)
fi

echo "* openssl"
if [[ ! -e "$bootstrap_dir/ssl/man/man1/openssl.1" ]]; then
(
set -e
curl -4 -LO https://www.openssl.org/source/openssl-1.0.2g.tar.gz
tar xvfz openssl-1.0.2g.tar.gz
cd openssl-1.0.2g
perl ./Configure --prefix="$bootstrap_dir" no-ssl2 darwin64-x86_64-cc enable-ec_nistp_64_gcc_128 #--openssldir=
make depend
make
make install
) > openssl.log 2>&1 || (tail -40 openssl.log; exit 1)
fi

echo "* fakeroot"
if [[ ! -e "$bootstrap_dir/bin/fakeroot" ]]; then
(
set -e
curl -4 -L https://github.com/duskwuff/darwin-fakeroot/archive/v1.1.tar.gz -o darwin-fakeroot-v1.1.tar.gz
curl -4 -LO https://raw.githubusercontent.com/kladd/pacman-osx-pkgs/osx-10.10/core/darwin-fakeroot/darwin-fakeroot.patch
tar xvfz darwin-fakeroot-v1.1.tar.gz
cd darwin-fakeroot-1.1
patch -Np0 < ../darwin-fakeroot.patch
make PREFIX="$bootstrap_dir"
make PREFIX="$bootstrap_dir" install
) > fakeroot.log 2>&1 || (tail -40 fakeroot.log; exit 1)
fi

echo "* xz"
if [[ ! -e "$bootstrap_dir/bin/xz" ]]; then
(
set -e
curl -4 -O http://tukaani.org/xz/xz-5.2.2.tar.gz
tar xvfz xz-5.2.2.tar.gz
cd xz-5.2.2
./configure --prefix="$bootstrap_dir"
make
make install
) > xz.log 2>&1 || (tail -40 xz.log; exit 1)
fi

echo "* pacman"
if [[ ! -e "$bootstrap_dir/bin/pacman" ]]; then
(
set -e
curl -4 -O https://sources.archlinux.org/other/pacman/pacman-5.0.1.tar.gz
tar xvfz pacman-5.0.1.tar.gz
cd pacman-5.0.1
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
) > pacman.log 2>&1 || (tail -40 pacman.log; exit 1)
fi

"$bootstrap_dir/bin/pacman" -V

"$bootstrap_dir/bin/makepkg" -V
