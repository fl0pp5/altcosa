#!/usr/bin/env bash

set -eou pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/cmdlib.sh

__usage="Usage: $__name [OPTIONS]...
Initialize the stream repository with the specified architecture and branch

Arguments:
    Options:
        --arch - ALTCOS target architecture (required)
        --branch - ALTCOS target repository branch (required)
        --repodir - ALTCOS repository root directory (required)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_ARCH=
OPT_BRANCH=
OPT_REPODIR=

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,arch:,branch:,repodir:' --name "$__name" -- "$@")
eval set -- "$valid_args"

while true ; do
    case "$1" in
        --arch)
            OPT_ARCH=$2
            shift 2
            ;;
        --branch)
            OPT_BRANCH=$2
            shift 2
            ;;
        --repodir)
            OPT_REPODIR=$2
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
: "${OPT_ARCH:?Missing --arch option}"
: "${OPT_BRANCH:?Missing --branch option}"
: "${OPT_REPODIR:?Missing --repodir option}"

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

export_stream_by_parts "$OPT_ARCH" "$OPT_BRANCH" "$OPT_REPODIR"

for dir in "$OSTREE_BARE_DIR" "$OSTREE_ARCHIVE_DIR"; do
    if [ -e "$dir" ]; then
        fatal "stream repository already exists (arch: $OPT_ARCH, branch: $OPT_BRANCH)"
        exit 1
    fi

    mkdir -p "$dir"
done

ostree init --repo="$OSTREE_BARE_DIR" --mode=bare
ostree init --repo="$OSTREE_ARCHIVE_DIR" --mode=archive
