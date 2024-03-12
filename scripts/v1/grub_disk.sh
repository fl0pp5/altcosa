#!/usr/bin/env bash
set -eou pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/cmdlib.sh

__usage="Usage: $__name [OPTIONS]...
Install grub for target disk

Arguments:
    Options:
        --stream - stream name (e.g. altcos/x86_64/sisyphus/base) (required)
        --repodir - ALTCOS repository root directory (required)
        --disk - target disk device (required, e.g. /dev/loop0, /dev/sda)
        --mount - target root mount point (required)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_STREAM=
OPT_REPODIR=
OPT_DISK=
OPT_MOUNT=

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,stream:,repodir:,disk:,mount:' --name "$__name" -- "$@")
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
        --disk)
            OPT_DISK=$2
            shift 2
            ;;
        --mount)
            OPT_MOUNT=$2
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
: "${OPT_DISK:?Missing --disk option}"
: "${OPT_MOUNT:?Missing --mount option}"

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

EFI_SUPPORT=0
if efibootmgr; then
    EFI_SUPPORT=1
fi

export_stream "$OPT_STREAM" "$OPT_REPODIR"

# shellcheck disable=SC2153
case "$ARCH" in
    x86_64)
        grub-install \
            --target=i386-pc \
            --root-directory="$OPT_MOUNT" \
            "$OPT_DISK"

        if [ "$EFI_SUPPORT" -eq 1 ]; then
            grub-install \
                --target=x86_64-efi \
                --root-directory="$OPT_MOUNT" \
                --efi-directory="$OPT_MOUNT/efi" \
                "$OPT_DISK"
        fi
    ;;
esac
