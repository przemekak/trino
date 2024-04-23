#!/usr/bin/env bash

set -xeuo pipefail

usage() {
    cat <<EOF 1>&2
Usage: $0 [-h] [-a <ARCHITECTURES>] [-r <VERSION>]
Builds the Trino Docker image

-h       Display help
-a       Build the specified comma-separated architectures, defaults to amd64,arm64,ppc64le
-r       Build the specified Trino release version, downloads all required artifacts
-j       Build the Trino release with specified Temurin JDK release
EOF
}

# Retrieve the script directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "${SCRIPT_DIR}" || exit 2

SOURCE_DIR="${SCRIPT_DIR}/../.."

ARCHITECTURES=(amd64 arm64 ppc64le)
TRINO_VERSION=

# Must match https://api.adoptium.net/q/swagger-ui/#/Release%20Info/getReleaseNames
TEMURIN_RELEASE=$(cat "${SOURCE_DIR}/.temurin-release")

while getopts ":a:h:r:t:" o; do
    case "${o}" in
        a)
            IFS=, read -ra ARCHITECTURES <<< "$OPTARG"
            ;;
        r)
            TRINO_VERSION=${OPTARG}
            ;;
        h)
            usage
            exit 0
            ;;
        t)
            TEMURIN_RELEASE="${OPTARG}"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

function check_environment() {
    if ! command -v jq &> /dev/null; then
        echo >&2 "Please install jq"
        exit 1
    fi
}

function temurin_download_link() {
  local RELEASE_NAME="${1}"
  local ARCH="${2}"

  case "${ARCH}" in
    arm64)
      echo "https://api.adoptium.net/v3/binary/version/${RELEASE_NAME}/linux/aarch64/jdk/hotspot/normal/eclipse?project=jdk"
    ;;
    amd64)
      echo "https://api.adoptium.net/v3/binary/version/${RELEASE_NAME}/linux/x64/jdk/hotspot/normal/eclipse?project=jdk"
    ;;
    ppc64le)
      echo "https://api.adoptium.net/v3/binary/version/${RELEASE_NAME}/linux/ppc64le/jdk/hotspot/normal/eclipse?project=jdk"
    ;;
  *)
    echo "${ARCH} is not supported for Docker image"
    exit 1
    ;;
  esac
}

check_environment

if [ -n "$TRINO_VERSION" ]; then
    echo "🎣 Downloading server and client artifacts for release version ${TRINO_VERSION}"
    for artifactId in io.trino:trino-server:"${TRINO_VERSION}":tar.gz io.trino:trino-cli:"${TRINO_VERSION}":jar:executable; do
        "${SOURCE_DIR}/mvnw" -C dependency:get -Dtransitive=false -Dartifact="$artifactId"
    done
    local_repo=$("${SOURCE_DIR}/mvnw" -B help:evaluate -Dexpression=settings.localRepository -q -DforceStdout)
    trino_server="$local_repo/io/trino/trino-server/${TRINO_VERSION}/trino-server-${TRINO_VERSION}.tar.gz"
    trino_client="$local_repo/io/trino/trino-cli/${TRINO_VERSION}/trino-cli-${TRINO_VERSION}-executable.jar"
    chmod +x "$trino_client"
else
    TRINO_VERSION=$("${SOURCE_DIR}/mvnw" -f "${SOURCE_DIR}/pom.xml" --quiet help:evaluate -Dexpression=project.version -DforceStdout)
    echo "🎯 Using currently built artifacts from the core/trino-server and client/trino-cli modules and version ${TRINO_VERSION}"
    trino_server="${SOURCE_DIR}/core/trino-server/target/trino-server-${TRINO_VERSION}.tar.gz"
    trino_client="${SOURCE_DIR}/client/trino-cli/target/trino-cli-${TRINO_VERSION}-executable.jar"
fi

echo "🧱 Preparing the image build context directory"
WORK_DIR="$(mktemp -d)"
cp "$trino_server" "${WORK_DIR}/"
cp "$trino_client" "${WORK_DIR}/"
tar -C "${WORK_DIR}" -xzf "${WORK_DIR}/trino-server-${TRINO_VERSION}.tar.gz"
rm "${WORK_DIR}/trino-server-${TRINO_VERSION}.tar.gz"
cp -R bin "${WORK_DIR}/trino-server-${TRINO_VERSION}"
cp -R default "${WORK_DIR}/"

TAG_PREFIX="trino:${TRINO_VERSION}"

for arch in "${ARCHITECTURES[@]}"; do
    echo "🫙  Building the image for $arch with Temurin Release ${TEMURIN_RELEASE}"
    docker build \
        "${WORK_DIR}" \
        --progress=plain \
        --pull \
        --build-arg JDK_VERSION="${TEMURIN_RELEASE}" \
        --build-arg JDK_DOWNLOAD_LINK="https://starburst-public-benchmarks-reports.s3.us-east-2.amazonaws.com/zing24.03.0.0-4-jdk21.0.2-linux_aarch64.tar.gz?response-content-disposition=inline&X-Amz-Security-Token=IQoJb3JpZ2luX2VjECgaCXVzLWVhc3QtMSJIMEYCIQDfVkkwOMbLk9vmBj9pN0WUdAnvm9me76W%2BZ1nPd8Pn6QIhAI7CtacV0iu1MFqn8w0yhkhEyzFi%2Bzk%2FGUfK44XJfIc5KoQECHAQAhoMODg4NDY5NDEyNzE0IgyoT6Q5aMgUMAXaD9wq4QMuBHTNzbehqCvRAyD6LrZXcD%2FI3ZVwy1Wo5xKNIE9Gja2Hiuwxjsf4WlaBpVZUEwftOOr0IN2TScuFbeUSXbTPtnj1Y%2BwA7UvY14b83MP3S2lRwOQgs%2By4hlSQWxtJBvOPE2l%2BMNJKbdfNMAl4b9Ed5tHv%2FjyFfYgLACYUiUS%2FZzG3%2FggxQOQz31MksbYqUt9FHuBZfiJFfLNpWWVRpkXwUwNO8uUs9ehoeF4P%2BCbfHpqzzutoT6cM69k52ikQDYluQkxPou3%2BYUUpooY%2FNIBnWNrB1ZJmIB5D2oMkbVI4LsPu%2F%2Fl9mRqpKzLL1YqX5ZN7kJ43rGqTgUHMLFKZAOw1gpZLtxj%2Fc1pjsyWdf5S4ntaqBE9KEjpVOoNx1bySLTqDu3Sf0npYnfFRr%2BoOe5c10nAPrVRWz9FN5vP%2Bukn7LsUEDTdaYwEjvB9lHfI6nRjX1Np%2F2hWuE0hE4WdiYbyqcshAo85V6Vb1ADESnDyLgUFg34HVwaJtt%2B9QG0jztTK%2FrtfjN6WQrUjnKwnfWTXcine1nJl9tbVGm8rPHHdl8YfhV9pnul9%2BcJk3aIE7A1kAniCp2MOIOagMnVUSu4nfnIfzD9grP%2FEksiW2zaCQDXejtxRQgTGk30MIlFUODNPaMPi7nbEGOpMCfMxpiwVeGVDwl9HJTXQMlDQvm72UkBH1kc1rTIWtttZGMA4p8u2A%2FsBvBDVQrzZxoxN7kIe%2BsJlEMtQhYwc%2BVjTfF5%2Ffpd0WnIPcM8ujWLgQl%2By8Yay%2FIrgZDew72O%2FDcxMXQVFKyqQjSSWrDVeXCU46%2FggnCzTg0pGsewIXV4drQXt%2BQ4D%2FKi5hytOu0xo4xI4S6zJDtwWzcA46JvsCyE6eK9ERPRDWqIMFBXY6u6%2FrOuVEw5NjYzib1cSF93xNNT0bpIJ4hf5fa5fGP%2BgZJ5o6u6WH1QBO00YbC5Nwxj%2F3siChdm6gr%2FU7Yb%2F7yf%2FXLSCwWGtNWUIwZLzXo2kqvqIVaPm7uncI0vZ0YdNsFcgISUg%3D&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Date=20240423T101840Z&X-Amz-SignedHeaders=host&X-Amz-Expires=43200&X-Amz-Credential=ASIA45XHHLNVM3ECUVWC%2F20240423%2Fus-east-2%2Fs3%2Faws4_request&X-Amz-Signature=c2c3a6b9323b0f28f83cbd4036d02218730e850dc91f239c2c0aeae6be05e829" \
        --platform "linux/$arch" \
        -f Dockerfile \
        -t "${TAG_PREFIX}-$arch" \
        --build-arg "TRINO_VERSION=${TRINO_VERSION}"
done

echo "🧹 Cleaning up the build context directory"
rm -r "${WORK_DIR}"

echo "🏃 Testing built images"
source container-test.sh

for arch in "${ARCHITECTURES[@]}"; do
    # TODO: remove when https://github.com/multiarch/qemu-user-static/issues/128 is fixed
    if [[ "$arch" != "ppc64le" ]]; then
        test_container "${TAG_PREFIX}-$arch" "linux/$arch"
    fi
    docker image inspect -f '🚀 Built {{.RepoTags}} {{.Id}}' "${TAG_PREFIX}-$arch"
done
