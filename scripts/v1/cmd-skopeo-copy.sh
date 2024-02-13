#!/usr/bin/env bash

set -eou pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/cmdlib.sh

check_root_uid

__usage="Usage: $__name [OPTIONS]...
skopeo-copy wrapper for stream

Arguments:
    Options:
        --stream - ALTCOS target architecture (required)
        --repodir - ALTCOS repository root directory (required)
        --images - list of container images to copy (required)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_STREAM=
OPT_REPODIR=
OPT_IMAGES=

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,stream:,repodir:,images:' --name "$__name" -- "$@")
eval set -- "$valid_args"

while true ; do
    case "$1" in
        --stream)
            OPT_STREAM=$2
            shift 2
            ;;
        --repodir)
            OPT_REPODIR=$2
            shift 2
            ;;
        --images)
            OPT_IMAGES=$2
            break
            ;;
        -a|--api)
            echo -n "$(get_cmd_api)"
            exit
            ;;
        -h|--help)
            echo "$__usage"
            exit
            ;;
        -c|--check)
            OPT_CHECK=1
            shift
            ;;
        --)
            shift
            break
            ;;
    esac
done

# check the required variables
: "${OPT_STREAM:?Missing --stream option}"
: "${OPT_REPODIR:?Missing --repodir option}"
: "${OPT_IMAGES:?Missing --images option}"

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

echo "$OPT_IMAGES"

export_stream "$OPT_STREAM" "$OPT_REPODIR"

if [ ! -d "$MERGED_DIR" ]; then
    fatal "directory \"$MERGED_DIR\" does not exist (stream is not checkouted)"
    exit 1
fi

DOCKER_IMAGES_DIR="$MERGED_DIR"/usr/dockerImages
mkdir -p "$DOCKER_IMAGES_DIR"

for image in $OPT_IMAGES; do
    echo "$image"

    archive_file=$(echo "$image" | tr '/' '_' | tr ':' '_')
    archive_file=$DOCKER_IMAGES_DIR/$archive_file
    rm -rf "$archive_file"

    xzfile="$archive_file.xz"
    if [ ! -f "$xzfile" ]
    then
        rm -f "$archive_file"
        skopeo copy --additional-tag="$image" docker://"$image" docker-archive:"$archive_file"
        xz -9 "$archive_file"
    fi
done
