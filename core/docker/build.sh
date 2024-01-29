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
JDK_VERSION=$(cat "${SOURCE_DIR}/.java-version")

while getopts ":a:h:r:j:" o; do
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
        j)
            JDK_VERSION="${OPTARG}"
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

function temurin_jdk_link() {
  local JDK_VERSION="${1}"
  local ARCH="${2}"

  versionsUrl="https://api.adoptium.net/v3/info/release_names?heap_size=normal&image_type=jdk&os=linux&page=0&page_size=20&project=jdk&release_type=ga&semver=false&sort_method=DEFAULT&sort_order=DESC&vendor=eclipse&version=%28${JDK_VERSION}%2C%5D"
  if ! result=$(curl -fLs "$versionsUrl" -H 'accept: application/json'); then
    echo >&2 "Failed to fetch release names for JDK version [${JDK_VERSION}, ) from Temurin API : $result"
    exit 1
  fi

  if ! RELEASE_NAME=$(echo "$result" | jq -er '.releases[]' | grep "${JDK_VERSION}" | head -n 1); then
    echo >&2 "Failed to determine release name: ${RELEASE_NAME}"
    exit 1
  fi

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
    echo "🫙  Building the image for $arch with JDK ${JDK_VERSION}"
    docker build \
        "${WORK_DIR}" \
        --progress=plain \
        --pull \
        --build-arg JDK_VERSION="${JDK_VERSION}" \
        --build-arg JDK_DOWNLOAD_LINK="https://starburst-public-benchmarks-reports.s3.us-east-2.amazonaws.com/zing23.12.0.0-4-jdk21.0.1-linux_aarch64.tar.gz?response-content-disposition=inline&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEDMaCmV1LW5vcnRoLTEiRzBFAiAGzMWQdzmJ8xs1181bsOeldX%2B%2Fw0PUehz00IOj2%2BDkegIhANV1v1uhwldpqgv9EFVuQhV3W%2BfI7DdNtbVPlw8MhHWjKssDCOz%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEQAhoMODg4NDY5NDEyNzE0IgxRzUxW0AxTrT%2Benb0qnwP4ulBmLHrpUVTRbPh49v1%2BI46sIH1rUTm1aIqGbcDWXo2O5p%2B4yWPyt6QNfQFitquX8d%2BHgcesYxFVeuRRnTo77iO07l8B070RxPuipmramyv8RNtFya2W%2BPiEx6e6qDVzSGE3uAKuv9ZqDuDBes5HvEPAHYRVe0f76Z8H52YNf1AW8LcDIghAgaezq66TMho67XeIfgleSofjih5FGQeyaJsUIjWzvLkFgAAW%2BuittEhj7228Dczlv6Jf2K5zMHvWfalHKEAA9pCa997cM0BoWWRUMoQbGr84wviqR4hGs5Bn5WypM5%2BKqre7ZO2gFYjvpHobmwne6YWoCBTu6dv5FPdcs77SNcHHNtOIYaGbdbsfVxomzn%2Fs4rSL2j0skJZqtr%2FCb9jELIeof7DiQv%2FfGO14dWzz7OHcl44COha3%2B1BomrvSxJjncbeLHD64CWWpIY6doP3iTJYRasJSjpUod04Tx8ZpDmxZuha96S%2FH38nF6kgeNIrpKaxBTA50BkkxhauiQGJ0nGcOejmDHCAUx9Lh1ClppiLnMEf2TQzUMNiN3q0GOoQCZVGiyc817KGXeI8inoUsCfWfqlgv3fP1yMoDzItl9FPcjJyYt7BPLNwLcIDcmnqGSD0J4TpR5WzJCL7iQiG8DwcqJDSmtqkgL6J4bmUvlSGaSt8bDYVQ8LOECKPEtbwFFGD0duoUrQb1XMNZYVVoJBQDu%2B1cyWhSbRmhA1quLuzUQ7QC%2Bz0zXi%2B6Tm38ELaV2kbtWGrREofk2SJXTw0Gj3UgiAwSbN8QJW07ZEyZwfpcuiiVgmWbGewbXMEWmsSUtFPzDscLWSDS%2Bc7%2BXf%2FMvu%2B7Wbxd5rpOeOjVFhof8hzxRPSssdYXG0AvMS7fC14TnJxSi%2FRujqhV92NoFIzZmInWYDw%3D&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Date=20240129T111054Z&X-Amz-SignedHeaders=host&X-Amz-Expires=43200&X-Amz-Credential=ASIA45XHHLNVINZSEI4V%2F20240129%2Fus-east-2%2Fs3%2Faws4_request&X-Amz-Signature=9d1af2ca70a7230c9f6f9cf6877723c73932c51d8e690cbb9b825ec4af745b01" \
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
