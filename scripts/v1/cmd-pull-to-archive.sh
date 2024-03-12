#!/usr/bin/env bash

set -eou pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/cmdlib.sh

check_root_uid

__usage="Usage: $__name [OPTIONS]...
Pull bare repository to archive

Arguments:
    Options:
        --stream - stream name (e.g. altcos/x86_64/sisyphus/base) (required)
        --repodir - ALTCOS repository root directory (required)
        --commit - commit hashsum (optional, default latest)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_STREAM=
OPT_REPODIR=
OPT_COMMIT=latest

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,stream:,repodir:,commit:' --name "$__name" -- "$@")
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

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

export_stream "$OPT_STREAM" "$OPT_REPODIR"

case "$OPT_COMMIT" in
    latest)
        # shellcheck disable=SC2153
        OPT_COMMIT="$(get_commit "$STREAM" "$OPT_REPODIR" "bare")"
        ;;
esac

# shellcheck disable=SC2153
ostree pull-local \
    --depth=-1 \
    "$OSTREE_BARE_DIR" \
    "$STREAM" \
    "$OPT_COMMIT" \
    --repo="$OSTREE_ARCHIVE_DIR"

ostree summary --repo="$OSTREE_ARCHIVE_DIR" --update
