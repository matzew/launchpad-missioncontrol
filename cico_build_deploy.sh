#!/usr/bin/bash

GENERATOR_DOCKER_HUB_USERNAME=openshiftioadmin
REGISTRY_URI="push.registry.devshift.net"
REGISTRY_NS="openshiftio"
REGISTRY_IMAGE="launchpad-missioncontrol"
REGISTRY_URL=${REGISTRY_URI}/${REGISTRY_NS}/${REGISTRY_IMAGE}
DOCKER_HUB_URL="openshiftio/launchpad-missioncontrol"
BUILDER_IMAGE="launchpad-missioncontrol-builder"
BUILDER_CONT="launchpad-missioncontrol-builder-container"
DEPLOY_IMAGE="launchpad-missioncontrol-deploy"
TAG_LENGTH=7

TARGET_DIR="web/target"

function tag_push() {
    TARGET_IMAGE=$1
    USERNAME=$2
    PASSWORD=$3
    REGISTRY=$4

    docker tag ${DEPLOY_IMAGE} ${TARGET_IMAGE}
    if [ -n "${USERNAME}" ] && [ -n "${PASSWORD}" ]; then
        docker login -u ${USERNAME} -p ${PASSWORD} ${REGISTRY}
    fi
    docker push ${TARGET_IMAGE}
}

# Show command before executing
set -x

# Exit on error
set -e

if [ -z $CICO_LOCAL ]; then
    [ -f jenkins-env ] && cat jenkins-env | grep -e PASS -e GIT -e DEVSHIFT> inherit-env
    [ -f inherit-env ] && . inherit-env

    # We need to disable selinux for now, XXX
    /usr/sbin/setenforce 0

    # Get all the deps in
    yum -y install docker make git

    # Get all the deps in
    yum -y install docker make git
    service docker start
fi

#CLEAN
docker ps | grep -q ${BUILDER_CONT} && docker stop ${BUILDER_CONT}
docker ps -a | grep -q ${BUILDER_CONT} && docker rm ${BUILDER_CONT}
rm -rf ${TARGET_DIR}/

#BUILD
docker build -t ${BUILDER_IMAGE} -f Dockerfile.build .

mkdir ${TARGET_DIR}/
docker run --detach=true --name ${BUILDER_CONT} -t -v $(pwd)/${TARGET_DIR}:/${TARGET_DIR}:Z ${BUILDER_IMAGE} /bin/tail -f /dev/null #FIXME

docker exec ${BUILDER_CONT} mvn -B clean install
docker exec -u root ${BUILDER_CONT} cp web/target/launchpad-missioncontrol.war /${TARGET_DIR}

#BUILD DEPLOY IMAGE
docker build -t ${DEPLOY_IMAGE} -f Dockerfile.deploy .

#PUSH
if [ -z $CICO_LOCAL ]; then
    TAG=$(echo $GIT_COMMIT | cut -c1-${TAG_LENGTH})
    tag_push "${REGISTRY_URL}:${TAG}" ${DEVSHIFT_USERNAME} ${DEVSHIFT_PASSWORD} ${REGISTRY_URI}
    tag_push "${REGISTRY_URL}:latest" ${DEVSHIFT_USERNAME} ${DEVSHIFT_PASSWORD} ${REGISTRY_URI}


    if [ -n "${GENERATOR_DOCKER_HUB_PASSWORD}" ]; then
        tag_push "${DOCKER_HUB_URL}:${TAG}" ${GENERATOR_DOCKER_HUB_USERNAME} ${GENERATOR_DOCKER_HUB_PASSWORD}
        tag_push "${DOCKER_HUB_URL}:latest" ${GENERATOR_DOCKER_HUB_USERNAME} ${GENERATOR_DOCKER_HUB_PASSWORD}
    fi
fi
