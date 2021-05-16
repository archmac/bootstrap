# bootstrapping pacman for Arch Mac

To correctly kickstart pacman with proper references to dynamic libraries, three stages are needed.

Indeed there's this macOS binary behaviour that makes it store absolute paths to dynamic libraries. Therefore if we stopped at the second stage, some references to the first stage would be kept.

## Stage 1: set the ladder up

```
caffeinate ./bootstrap stage1
```

Make pacman (which has makepkg) and its build and runtime dependencies from source. This is ignoring `/usr/local`, thus third-party user-installed binaries, by resetting PATH to a very basic value.

Prefix is set to `stage1`, so that `make install` proceeds into an isolated directory. The installation is raw and unmanaged, `pacman` is not involved.

Here we also configure `makepkg` to build packages targeting installation into `/opt/arch`, with proper flags and arch for the platform.

## Stage 2: climb the ladder

```
caffeinate ./bootstrap stage2
```

We build a minimal selection of packages from `mini`. The `PKGBUILD`s are intentionally minimalistic. The build order is hardcoded because of circular dependencies.

`stage1/etc/makepkg.conf` is copied to `stage2` and altered to store source and binary packages in `stage2/{packages,srcpackages}`.

Once built, each package is installed, progressively populating `/opt/arch`. Because of logical circular dependencies, `makepkg` and `pacman` are run with `--nodeps`. The circular dependency is logical, but the early packages logically depending on later ones will be built against - and ultimately reference - `stage1`. This is why we need `stage3`.

## Stage 3: cut the branch we were sitting on

```
caffeinate ./bootstrap stage3
```

The `mini` packages of `stage2` get rebuilt, while `stage1` is hidden.

`/opt/arch/etc/makepkg.conf` is copied to `stage3` and altered to store source and binary packages in `stage3/{packages,srcpackages}`.

At this stage we can start to notice some effects of dependencies on the process, as already installed packages will get reinstalled:

- xz depends on gettext (libintl), thus when `xz` will fail miserably midway when reinstalling `gettext`
- `bash` gets regularly run by `pacman` at various stages, and depends on `readline` and `gettext`, which causes similar troubles when upgrading these packages

Therefore:

- `bash` gets statically built with its own vendored `readline` and `libintl`
- `xz` should be built statically as well, but it's not as easy, therefore another default compression format than `xz` is used

## Stage 4: build from a repo

That's it. `pacman` and `makepkg` are bootstrapped and ready to cleanly build packages from a repo's `PKGBUILD`s selection.

Such a repo could probably be used at `stage3` instead of `mini`, but the goal was to minimise variability in time. I guess a git commit cold be pinned or something, but then bootstrapping still ends up depending on an external that requires the bootstrapping step, e.g starting a new arch /cough/M1/cough/ would mean altering an external repo. Given the small number of packages it's simpler this way, and that way the bootstrap step is entirely self-contained.
