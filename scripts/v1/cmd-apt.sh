#!/usr/bin/env bash

set -eou pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/cmdlib.sh

check_root_uid

__usage="Usage: $__name [OPTIONS]...
Package manager wrapper for stream

Arguments:
    Options:
        --stream - ALTCOS target architecture (required)
        --repodir - ALTCOS repository root directory (required)
        --action - apt-get action (install|update|dist-upgrade|remove) (required)
        --pkgs - list of packages (optional)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_STREAM=
OPT_REPODIR=
OPT_ACTION=
OPT_PKGS=

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,stream:,repodir:,action:,pkgs:' --name "$__name" -- "$@")
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
        --action)
            OPT_ACTION=$2
            shift 2
            ;;
        --pkgs)
            #shift  # remove --pkgs from list
            #__length=$(($# - 1))
            OPT_PKGS=$2  # ${*:1:$__length}  # remove dash characters at end from list
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
: "${OPT_ACTION:?Missing --action option}"

case "$OPT_ACTION" in
    install|remove)
        : "${OPT_PKGS:?Missing --pkgs option}"
        ;;
    update|dist-upgrade)
        if [ -n "$OPT_PKGS" ]; then
            echo "--pkgs option is not supported by \"$OPT_ACTION\" action"
            exit 1
        fi
        ;;
    *)
        fatal "invalid apt-get action \"$OPT_ACTION\""
        exit 1
esac

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

export_stream "$OPT_STREAM" "$OPT_REPODIR"

if [ ! -d "$MERGED_DIR" ]; then
    fatal "directory \"$MERGED_DIR\" does not exist (stream is not checkouted)"
    exit 1
fi

prepare_apt_dirs "$MERGED_DIR"

# shellcheck disable=SC2086
chroot "$MERGED_DIR" \
    apt-get "$OPT_ACTION" -y -o RPM:DBPath='lib/rpm' $OPT_PKGS
