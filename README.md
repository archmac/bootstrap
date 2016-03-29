stage 1: make pacman (which has makepkg) and its dependencies from source, ignoring /usr/local, and make install into an isolated directory
stage 1b: configure makepkg to build final packages targeting /usr/local, with proper flags+arch, and depending only on /usr/local packages
stage 2: build pacman+deps packages and install them via pacman

stage 1:
bootstrap: build
bootstrap pristine: clean and build
bootstrap shell: run shell with PATH set within bootstrap
stage1b:
+CARCH="x86_64"
+CHOST="x86_64-apple-darwin15.4.0"
+CPPFLAGS="-D_FORTIFY_SOURCE=2"
+CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe -fstack-protector-strong"
+CXXFLAGS="-march=x86-64 -mtune=generic -O2 -pipe -fstack-protector-strong"
+LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro"
+PKGEXT='.pkg.tar.xz'
