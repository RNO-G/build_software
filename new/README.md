# cvmfs_spack
Spack-based builder for the RNOG cvmfs

A much more detailed discussion of the builder is located in `support/docs.md`.

### Quickstart
```
bash build_version.sh trunk el9
```

That would build the trunk version for el9.

It works by dropping you into a singularity/apptainer imagine.
So it's going to look for `el9.sif`.

And it's going to try and install spack with the `trunk.yaml` in `versions/`.
And then use the builder scripts in that repo.
