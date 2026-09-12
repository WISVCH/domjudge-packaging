#!/bin/sh -eu

# Run from the repository root (not docker-nix/) - the build needs flake.nix
# and flake.lock from the repo root as build context alongside judgehost/.

if [ "$#" -ne 1 ]
then
        echo "Usage $0 <docker tag>"
fi
docker_tag="$1"

# Build the builder
docker build -t "${docker_tag}-build" -f docker-nix/judgehost/Dockerfile.build .

# Build chroot
builder_name=$(echo "${docker_tag}" | sed 's/[^a-zA-Z0-9_-]/-/g')
docker rm -f "${builder_name}" > /dev/null 2>&1 || true
docker run --privileged --name "${builder_name}" --cap-add=sys_admin "${docker_tag}-build"
docker cp "${builder_name}:/chroot.tar.gz" .
docker cp "${builder_name}:/judgehost.tar.gz" .
docker rm -f "${builder_name}"
docker rmi "${docker_tag}-build"

# Build actual judgehost
docker build -t "${docker_tag}" -f docker-nix/judgehost/Dockerfile .
