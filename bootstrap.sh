#!/bin/bash

set -e
set -u

echo "gettext"
if [[ ! -e $HOME/pacman-deps/share/man/man1/gettext.1 ]]; then
(
curl -4 -O https://ftp.gnu.org/gnu/gettext/gettext-0.19.2.tar.xz
tar -xJvf gettext-0.19.2.tar.xz
cd gettext-0.19.2
./configure --prefix=$HOME/pacman-deps
make
make install
) > gettext.log 2>&1
fi

echo "autoconf"
if [[ ! -e $HOME/pacman-deps/share/man/man1/autoconf.1 ]]; then
(
curl -4 -O http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
tar -xzvf autoconf-2.69.tar.gz
cd autoconf-2.69
./configure --prefix=$HOME/pacman-deps
make
make install
) > autoconf.log 2>&1
fi

echo "automake"
if [[ ! -e $HOME/pacman-deps/share/man/man1/automake.1 ]]; then
(
curl -4 -O http://ftp.gnu.org/gnu/automake/automake-1.14.1.tar.gz
tar -xzvf automake-1.14.1.tar.gz
cd automake-1.14.1
./configure --prefix=$HOME/pacman-deps
make
make install
) > automake.log 2>&1
fi

echo "pkg-config"
if [[ ! -e $HOME/pacman-deps/share/man/man1/pkg-config.1 ]]; then
(
curl -O https://pkgconfig.freedesktop.org/releases/pkg-config-0.28.tar.gz
tar -xzvf pkg-config-0.28.tar.gz
cd pkg-config-0.28
./configure --prefix=$HOME/pacman-deps --with-internal-glib
make
make install
) > pkg-config.log 2>&1
fi

echo "libtool"
if [[ ! -e $HOME/pacman-deps/share/man/man1/libtool.1 ]]; then
(
curl -4 -O http://ftp.gnu.org/gnu/libtool/libtool-2.4.6.tar.gz
tar -xzvf libtool-2.4.6.tar.gz
cd libtool-2.4.6
./configure --prefix=$HOME/pacman-deps
make
make install
) > libtool.log 2>&1
fi

echo "bash"
if [[ ! -e $HOME/pacman-deps/share/man/man1/bash.1 ]]; then
(
curl -4 -O http://ftp.gnu.org/gnu/bash/bash-4.3.tar.gz
tar -xzvf bash-4.3.tar.gz
cd bash-4.3
./configure --prefix=$HOME/pacman-deps
make
make install
) > bash.log 2>&1
fi

echo "libarchive"
if [[ ! -e $HOME/pacman-deps/share/man/man5/libarchive-formats.5 ]]; then
(
curl -4 -LO http://www.libarchive.org/downloads/libarchive-3.1.2.tar.gz
tar -xzvf libarchive-3.1.2.tar.gz
cd libarchive-3.1.2
PATH=$HOME/pacman-deps/bin:$PATH ./build/autogen.sh
./configure --prefix=$HOME/pacman-deps
make
make install
) > libarchive.log 2>&1
fi

echo "asciidoc"
if [[ ! -e $HOME/pacman-deps/share/man/man1/asciidoc.1 ]]; then
(
curl -4 -LO http://downloads.sourceforge.net/project/asciidoc/asciidoc/8.6.9/asciidoc-8.6.9.tar.gz
tar -xzvf asciidoc-8.6.9.tar.gz
cd asciidoc-8.6.9
./configure --prefix=$HOME/pacman-deps
make
make install
) > asciidoc.log 2>&1
fi

echo "fakeroot"
if [[ ! -e $HOME/pacman-deps/bin/fakeroot ]]; then
(
curl -4 -L https://github.com/duskwuff/darwin-fakeroot/archive/v1.1.tar.gz -o darwin-fakeroot-v1.1.tar.gz
curl -4 -LO https://raw.githubusercontent.com/kladd/pacman-osx-pkgs/osx-10.10/core/darwin-fakeroot/darwin-fakeroot.patch
tar xvfz darwin-fakeroot-v1.1.tar.gz
cd darwin-fakeroot-1.1
patch -Np0 < ../darwin-fakeroot.patch
# Defaults to /usr/local
make PREFIX=$HOME/pacman-deps
make PREFIX=$HOME/pacman-deps install
) > fakeroot.log 2>&1
fi

echo "openssl"
if [[ ! -e $HOME/pacman-deps/ssl/man/man1/openssl.1 ]]; then
(
curl -4 -LO https://www.openssl.org/source/openssl-1.0.2g.tar.gz
tar xvfz openssl-1.0.2g.tar.gz
cd openssl-1.0.2g
perl ./Configure --prefix=$HOME/pacman-deps no-ssl2 darwin64-x86_64-cc enable-ec_nistp_64_gcc_128 #--openssldir=
make depend
make
make install
) > openssl.log 2>&1
fi

echo "pacman"
if [[ ! -e $HOME/pacman-deps/share/man/man1/pacman.1 ]]; then
(
#git clone git://projects.archlinux.org/pacman.git
#cd pacman
curl -4 -O https://sources.archlinux.org/other/pacman/pacman-4.2.1.tar.gz
tar xvfz pacman-4.2.1.tar.gz
cd pacman-4.2.1
export PATH=$HOME/pacman-deps/bin:$PATH
export CFLAGS="-I${HOME}/pacman-deps/include"
#export LIBARCHIVE_CFLAGS="-I${HOME}/pacman-deps/include"
#export LIBARCHIVE_LIBS="-larchive"
export LIBCURL_CFLAGS="-I/usr/include/curl"
export LIBCURL_LIBS="-lcurl"
#export LIBSSL_CFLAGS="-I${HOME}/pacman-deps/include"
#export LIBSSL_LIBS="-lssl"
./configure --prefix=$HOME/pacman-deps --enable-doc --with-scriptlet-shell=$HOME/pacman-deps/bin/bash --with-curl
make
make -C contrib
make install
make -C contrib install
) > pacman.log 2>&1 || (tail -40 pacman.log; exit 1)
fi
