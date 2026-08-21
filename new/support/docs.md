# CVMFS Spack Docs

## Overview

CVMFS works by distributing copies of the software.
The "source" of the software is known as the "stratum zero" server.
For RNO-G, this is a virtual machine at UMD.
In particular, it is the `rno-g-cvmfs.physics.umd.edu` machine.

### Why is deploying software tricky?

The first tricky thing about hosting the software
is that it has to be installed into the `/cvmfs/...` path.
This is not a generically writable path.
It can only be written to during a "transaction",
and it's not good for the transaction to be "open"
for very long.
This means the software has to be compiled somewhere
else, and then moved into place during the transaction.

The second tricky thing is that we want to build software for >1 operating system (currently we support EL8, EL9, and Ubuntu).

The solution to tricky problems 1 and 2 is to build the software
inside a container.
The container can be chosen to be the operating system
desired, and using the container, we can write files
to `/tmp`, but bind `/tmp` to the desired path *within* the container. And then move the files at the end. So that's the idea.

The third tricky thing is that every computer is different. 
So that even if you know the user is using EL8-derived operating system, you don't know precisely what version of EL8 they have.
So, the way we manage this is by assuming only the most basic things for the image.
E.g. we choose the most basic version of Alma 8,
and we compile almost everything else (including really basic stuff like gcc) ourselves.

To deal with that larger issue --- that we basically need to build a shadow operating system --- we use [spack](https://github.com/spack/spack).

## The Container

### The Bind-Mount Installation

As stated above, everything gets built inside an apptainer/singularity image (`el9.sif`,
`el8.sif`, `ubuntu2204.sif` — one per OS we support).
The build is steered by a master script, `build_version.sh`.
We call it like:

```
bash build_version.sh trunk el9
```

`trunk` here is the "version" (there's also `unstable`), and `el9` is the OS.
The script looks for `./el9.sif`, so you need to have already built that
image (see below about the container).
`build_version.sh` goes on to call `build.sh`,
which is specific to the version you want to build, e.g. trunk, unstable, and so forth.

Inside the container, the build scripts
 believe they are writing to
`/cvmfs/rnog.opensciencegrid.org/software/trunk/el9`. That path shows up in
all their compiler flags, rpaths, install prefixes, etc. Again, this is because we can't write there directly. 
CVMFS is read-only unless you're the Stratum0
server mid-transaction, and even then you don't want a half-finished spack
build sitting in the production repo.

So `build_version.sh` bind-mounts a scratch directory *on top of* that path,
just for the container:

```bash
apptainer exec -c \
    -H $PWD \
    -B "$SCRATCH_DIR":/scratch \
    -B "$BUILD_DIR":"$DESTDIR" \
    -B "$SCRATCH_DIR":/var \
    -B "$PWD":"$PWD" \
    "$IMAGE" \
    "$BUILD_SCRIPT" "$GIT_REPO_DIR" "$VERSION" "$OS" "$DESTDIR" "$NPROC"
```

`BUILD_DIR` is `/tmp/rnog_build/software/<version>/<os>` on the host.
`DESTDIR` is the real `/cvmfs/...` path. Inside the container, anything
written to `$DESTDIR` actually lands in `/tmp/rnog_build/...` on the outside.
The build is none the wiser — as far as it's concerned it's installing
straight into its final home, hardcoded paths and all — but nothing has
touched the real CVMFS repo yet. Once the build finishes, what you actually
have is a complete, ready-to-go copy of the install tree sitting in
`/tmp/rnog_build`, waiting to be moved into place.

### Deploying the software

Once the build finishes, you've got a finished file tree sitting in
`/tmp/rnog_build/software/<version>/<os>`. It is *not* live yet — nobody
pointed at `/cvmfs/rnog.opensciencegrid.org` can see it. To actually publish it,
we first open a transaction:

```
cvmfs_server transaction rnog.opensciencegrid.org
```

This makes `/cvmfs/rnog.opensciencegrid.org` briefly writable. Copy (you want something like 
`rsync -a`, which grabs all the hidden files--- see below) the built tree from
`/tmp/rnog_build/software/<version>/<os>` into the matching path under
`/cvmfs/rnog.opensciencegrid.org/software/<version>/<os>`. Then:

```
cvmfs_server publish rnog.opensciencegrid.org
```

That closes the transaction and pushes the new catalog out. If you bail
partway through and don't want to publish, `cvmfs_server abort
rnog.opensciencegrid.org` throws away whatever you staged.

A couple of things worth knowing before you do this for real:
- Only do one transaction at a time — CVMFS will refuse a second one
  concurrently.
- Publishing regenerates the whole catalog, so it's not instant. Don't panic
  if it takes a minute.

### Building the apptainer image
To build the singularity image file (SIF), we do:
```
apptainer build output.sif recipe.cfg
```

The commands you need to build the three containers are:
```
apptainer build el8.sif support/centos8.cfg
apptainer build el9.sif support/rocky9_0.cfg
apptainer build ubuntu2204.sif support/ubuntu2204.cfg
```

### Why Rocky 9.0 and not AlmaLinux 9.x?

Note that we advise using Rocky 9 over Alma Linux 9.

The el9 container is based on Rocky Linux 9.0 rather than
tracking the current AlmaLinux 9 stream. WIPAC does the latter.

The reason is that this matters for runtime compatibility in a subtle way.
RHEL/Alma backported a `GLIBC_2.35`-tagged
symbol called `_dl_find_object` into the 9.x libc.
This symbol is used by modern libgcc's stack unwinder.
As a result, any binary compiled on a current
AlmaLinux 9 system links against `_dl_find_object@GLIBC_2.35` and will fail to
run on systems whose libc lacks that backport.
At the of this writing (May 2026), this caused a problem for running at OSC,
which used RHEL 9.4. This never got get `_dl_find_object`.

Failures on those hosts look like:
```
gcc: /usr/lib64/libc.so.6: version `GLIBC_2.35' not found (required by gcc)
```
and (via `ldd -r`):
```
undefined symbol: _dl_find_object, version GLIBC_2.35
```

Rocky Linux 9.0 at the vault (`dl.rockylinux.org/vault/rocky/9.0/`),
predates this backport. Its libc tops out at `GLIBC_2.34` with no
`_dl_find_object` symbol exposed, so the libgcc shipped with our Spack-built
gcc falls back to the older `dl_iterate_phdr`-based unwinder. Binaries
produced here therefore run on any EL9.x host, including 9.4 RHEL sites that
never advance past the original 2.34.

If you've just built, and want to check this, you might run:
```bash
apptainer shell el9.sif
# Want: empty output (no public GLIBC_2.35 symbols)
nm -D /lib64/libc.so.6 | grep '@@GLIBC_2\.35'
# Want: list stops at GLIBC_2.34
strings /lib64/libc.so.6 | grep '^GLIBC_' | sort -V | tail
```

A binary that you compiled should *not* have GLIBC_2.35 exposed.
Check like this:
```bash
# Should show nothing >= GLIBC_2.35
objdump -T /cvmfs/rnog.opensciencegrid.org/software/.../bin/gcc \
    | grep GLIBC_ | awk '{print $5}' | sort -uV
```

Note that the Rocky 9.0 vault is officially "unsupported / historical."
But that's probably okay here because the container is a build environment only 
and the resulting binaries are really built with spack except for the very basics.


## The Build Scripts

### The `build.sh` script

Once you're in `build.sh` (the per-version builder, e.g.
`builders/trunk/build.sh`), a few subdirectories get created under `$DESTDIR`
(which, remember, is really `/tmp/rnog_build/...` while building):

- **`source/`** — checked-out source for the RNOG-specific packages
  (librnog, mattak, libRootFftwWrapper, healpix)
- **`misc_build/`** — this is the spack *view*. All the dependencies spack
  installs (gcc, root, python, gsl, fftw, boost, cfitsio, etc.) get
  hash-scattered into spack's own internal directory structure, and the view is what
  collapses all of that into one normal-looking `bin/`, `lib/`, `include/`
  tree so downstream stuff can find it without knowing spack exists
- **`rnog_build/`** — where the RNOG-specific packages actually get
  installed (these get built *against* `misc_build`, using it as their
  dependency root)
- **`.spack_internals/`** — a **hidden** directory holding spack itself and
  the spack environment. Easy to forget it's there since it starts with a
  dot, but it needs to survive the trip into CVMFS just like everything
  else, or a rebuild later will think spack was never cloned

That last one matters in practice: if you ever move/rsync this tree by hand,
use something like `rsync -a` (or `cp -a`), not a glob like `dest/*`, or
you'll silently leave `.spack_internals` behind.

Spack itself is only used for the "basics" — the compiler and the general
scientific stack. It is *not* used to build the RNOG-specific analysis
software; those get their own small `build_*.sh` scripts that compile
against the spack view.

At the very end, `build.sh` also drops a `setup.sh` into `$DESTDIR` that sets
up `PATH`, `LD_LIBRARY_PATH`, `PYTHONPATH`, `ROOTSYS`, etc. pointing at
`rnog_build` and `misc_build`. That's the file end users will eventually
source to actually use the stack.

### The Spack yaml file

Each version (`trunk`, `unstable`, ...) has a matching yaml file, e.g. `builders/trunk/trunk.yaml`. This is the actual spack environment spec — it's the thing that tells spack what to build and how. A trimmed version looks like:

```yaml
spack:
  specs:
    - gcc@15.2.0 +binutils ^zlib-ng~opt
    - cmake@4.1.2
    - root@6.36.04 +python +gsl +tmva +roofit +http +ssl +spectrum
    ...
  concretizer:
    unify: true
  repos:
    builtin:
      git: https://github.com/spack/spack-packages.git
      tag: v2025.11.0
```

`specs` is the actual package list — pinned versions and variants, so `trunk` always builds the same ROOT with the same flags rather than whatever happens to be newest. `concretizer: unify: true` tells spack to solve for one consistent set of dependency versions across the whole list, instead of letting e.g. ROOT and healpix each pull in their own separate copy of zlib. And `repos` pins the actual spack package recipes to a tagged commit — this matters more than it sounds like, since upstream spack packages change over time, and without pinning, a rebuild six months from now could quietly pick up different build recipes than the original one used.

This yaml is what gets handed to spack when the environment is created:

```bash
spack env create "$ENV_NAME" "$YAML_SOURCE" --with-view "$MISC_DIR"
```

That `--with-view "$MISC_DIR"` is the connection back to `misc_build/` — the yaml defines *what* gets built, and the view is *where* it all gets collapsed into a normal-looking install tree afterward.




### A note on `freeglut-devel`

`freeglut-devel` was dropped from RHEL/Rocky 9's base repos and is not in
default EPEL 9 either. It is not required for the RNOG stack and has been
removed from the el9 `%post` package list. If a downstream Spack package
ever needs it, prefer adding `freeglut` as a Spack package over hunting it
down as an RPM, so the build stays self-contained.
