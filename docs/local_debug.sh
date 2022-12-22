#!/bin/bash
set -ex

#docker build -f BaseDockerfile -t bxwill/bxs:home-cloud-doc-base .

previous_build=$(docker images | grep local | grep debug | awk '{print $3}')

[[ -z ${previous_build} ]] || {
    docker image rm -f ${previous_build}
}

docker build -t local:debug .

docker run --rm -p 4000:4000 -it local:debug 
