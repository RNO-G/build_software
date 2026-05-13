# cvmfs_spack
Spack-based builder for the RNOG cvmfs

## To compile, we run like
```
bash build_version.sh trunk el9
```

That would build the trunk version for el9.

It works by dropping you into a singularity/apptainer imagine.
So it's going to look for `el9.sif`.

And it's going to try and install spack with the `trunk.yaml` in `versions/`.
And then use the builder scripts in that repo.

## Building the apptainer imagge
To build the sif, we do:
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
tracking the current AlmaLinux 9 stream. WIPAC oes the latter.

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

### A note on `freeglut-devel`

`freeglut-devel` was dropped from RHEL/Rocky 9's base repos and is not in
default EPEL 9 either. It is not required for the RNOG stack and has been
removed from the el9 `%post` package list. If a downstream Spack package
ever needs it, prefer adding `freeglut` as a Spack package over hunting it
down as an RPM, so the build stays self-contained.
