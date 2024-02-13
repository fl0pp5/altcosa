#!/usr/bin/env bash

set -eou pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/cmdlib.sh

check_root_uid

__usage="Usage: $__name [OPTIONS]...
Apply the butane config on the stream

Arguments:
    Options:
        --stream - ALTCOS target architecture (required)
        --repodir - ALTCOS repository root directory (required)
        --butane - butane config data as text (required)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_STREAM=
OPT_REPODIR=
OPT_BUTANE=

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,stream:,repodir:,butane:' --name "$__name" -- "$@")
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
        --butane)
            OPT_BUTANE=$2
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
: "${OPT_BUTANE:?Missing --butane option}"

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

export_stream "$OPT_STREAM" "$OPT_REPODIR"

TMP_BUTANE_FILE="/tmp/$$.btn"
TMP_IGNITION_FILE="/tmp/$$.ign"

echo "$OPT_BUTANE" >> "$TMP_BUTANE_FILE"

butane -p -d \
    "$STREAM_DIR" \
    "$TMP_BUTANE_FILE" \
| tee "$TMP_IGNITION_FILE"

/usr/lib/dracut/modules.d/30ignition/ignition \
    -platform file \
    --stage files \
    -config-cache "$TMP_IGNITION_FILE" \
    -root "$MERGED_DIR"

chroot "$MERGED_DIR" \
    systemctl preset-all --preset-mode=enable-only

rm -f \
    "$TMP_BUTANE_FILE" \
    "$TMP_IGNITION_FILE"
