#!/usr/bin/env bash
set -eou pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/cmdlib.sh

__usage="Usage: $__name [OPTIONS]...
Create the disk partitions for device

Arguments:
    Options:
        --stream - stream name (e.g. altcos/x86_64/sisyphus/base) (required)
        --repodir - ALTCOS repository root directory (required)
        --disk - target disk device (required, e.g. /dev/loop0, /dev/sda)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_STREAM=
OPT_REPODIR=
OPT_DISK=

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,stream:,repodir:,disk:' --name "$__name" -- "$@")
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

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

UNINITIALIZED_GPT_UUID="00000000-0000-4000-a000-000000000001"
EFIPN=2
BOOTPN=3
ROOTPN=4

EFI_PART="$OPT_DISK"p"$EFIPN"
BOOT_PART="$OPT_DISK"p"$BOOTPN"
ROOT_PART="$OPT_DISK"p"$ROOTPN"

export_stream "$OPT_STREAM" "$OPT_REPODIR"

# shellcheck disable=SC2153
case "$ARCH" in 
    x86_64)
        sgdisk -Z "$OPT_DISK" \
        -U "${UNINITIALIZED_GPT_UUID}" \
        -n 1:0:+1M -c 1:BIOS-BOOT -t 1:21686148-6449-6E6F-744E-656564454649 \
        -n ${EFIPN}:0:+127M -c ${EFIPN}:EFI-SYSTEM -t ${EFIPN}:C12A7328-F81F-11D2-BA4B-00A0C93EC93B \
        -n ${BOOTPN}:0:+384M -c ${BOOTPN}:boot \
        -n ${ROOTPN}:0:0 -c ${ROOTPN}:root -t ${ROOTPN}:0FC63DAF-8483-4772-8E79-3D69D8477DE4
        ;;
esac

partprobe "$OPT_DISK"

case "$ARCH" in
    x86_64)
        mkfs.fat -F32 "$EFI_PART"
        mkfs.ext4 -L boot "$BOOT_PART"
        mkfs.ext4 -L root "$ROOT_PART"
        ;;
esac
