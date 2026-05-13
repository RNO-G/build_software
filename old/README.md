# build_software
the software builder via spack

## Step 1: Get Containers

First, we need to get the containers for the OS's we are building for:

```
apptainer pull osg_el8.sif docker://opensciencegrid/osgvo-el8:latest
apptainer pull osg_el9.sif docker://opensciencegrid/osgvo-el9:latest
```

## Step 2: Build

Build all variants:
`bash build_all.sh`

