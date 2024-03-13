#!/usr/bin/env bash

set -eou pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/cmdlib.sh

check_root_uid

__usage="Usage: $__name [OPTIONS]...
Checkout ALTCOS repository to the filesystem like another (or same) stream

Arguments:
    Options:
        --stream - stream name (e.g. altcos/x86_64/sisyphus/base) (required)
        --repodir - ALTCOS repository root directory (required)
        --imagedir - images directory (required)
        --platform - platform name (e.g. qemu,metal)
        --format - format name (e.g. qcow2,iso)
        --commit - commit hashsum (optional, default latest)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_STREAM=
OPT_REPODIR=
OPT_IMAGEDIR=
OPT_PLATFORM=
OPT_FORMAT=
OPT_COMMIT=latest

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,stream:,repodir:,imagedir:,platform:,format:,commit:' --name "$__name" -- "$@")
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
        --imagedir)
            OPT_IMAGEDIR=$2
            shift 2
            ;;
        --platform)
            OPT_PLATFORM=$2
            shift 2
            ;;
        --format)
            OPT_FORMAT=$2
            shift 2
            ;;
        --commit)
            OPT_COMMIT=$2
            shift 2
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
: "${OPT_IMAGEDIR:?Missing --imagedir option}"
: "${OPT_PLATFORM:?Missing --platform option}"
: "${OPT_FORMAT:?Missing --format option}"

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

export_stream "$OPT_STREAM" "$OPT_REPODIR"

case "$OPT_COMMIT" in
    latest)
        # shellcheck disable=SC2153
        OPT_COMMIT="$(get_commit "$STREAM" "$OPT_REPODIR" "archive")"
        ;;
esac

VERSION="$(python3 "$__dir"/cmd-ver.py \
    "$OPT_STREAM" \
    "$OPT_REPODIR" \
    -c "$OPT_COMMIT" \
    --view native)"

ARTIFACT_DIR="$OPT_IMAGEDIR"/"$BRANCH"/"$ARCH"/"$NAME"/"$VERSION"/"$OPT_PLATFORM"/"$OPT_FORMAT"

IMAGE_FILE="$ARTIFACT_DIR"/"$BRANCH"_"$NAME"."$ARCH"."$VERSION"."$OPT_PLATFORM"."$OPT_FORMAT"

xz -T0 --memlimit=2048MiB "$IMAGE_FILE"
