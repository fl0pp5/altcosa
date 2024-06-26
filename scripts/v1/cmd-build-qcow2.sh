#!/usr/bin/env bash

set -eou pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/cmdlib.sh

check_root_uid

__usage="Usage: $__name [OPTIONS]...
Build qcow2-image based on stream repository

Arguments:
    Options:
        --arch - ALTCOS target architecture (required)
        --branch - ALTCOS target repository branch (required)
        --name - ALTCOS ref name (required)
        --repodir - ALTCOS repository root directory (required)
        --imagedir - images directory (required)
        --mode - OSTree repository mode (required)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_ARCH=
OPT_BRANCH=
OPT_NAME=
OPT_REPODIR=
OPT_IMAGEDIR=
OPT_MODE=

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,arch:,branch:,name:,repodir:,imagedir:,mode:' --name "$__name" -- "$@")
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
        --name)
            OPT_NAME=$2
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
        --mode)
            OPT_MODE=$2

            case "$OPT_MODE" in
                bare|archive) ;;
                *)
                    fatal "invalid mode $OPT_MODE"
                    exit 1
                    ;;
            esac
            shift 2
            ;;
        -a|--api)
            echo -n "$(get_cmd_api)"
            exit;;
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
: "${OPT_NAME:?Missing --name option}"
: "${OPT_REPODIR:?Missing --repodir option}"
: "${OPT_IMAGEDIR:?Missing --imagedir option}"
: "${OPT_MODE:?Missing --mode option}"

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

export_stream_by_parts "$OPT_ARCH" "$OPT_BRANCH" "$OPT_REPODIR" "$OPT_NAME"

ROOT_SIZE=4G
PLATFORM=qemu
FORMAT=qcow2

EFI_SUPPORT=0
if efibootmgr; then
    EFI_SUPPORT=1
fi

# shellcheck disable=SC2153
COMMIT="$(get_commit "$STREAM" "$OPT_REPODIR" "$OPT_MODE")"

VERSION="$(python3 "$__dir"/cmd-ver.py \
    "$STREAM" \
    "$OPT_REPODIR" \
    -c "$COMMIT" \
    --view native)"

VERSION_PATH="$(python3 "$__dir"/cmd-ver.py \
    "$STREAM" \
    "$OPT_REPODIR" \
    -c "$COMMIT" \
    --view path)"

COMMIT_DIR="$VARS_DIR"/"$VERSION_PATH"/var

ARTIFACT_DIR="$OPT_IMAGEDIR"/"$OPT_BRANCH"/"$OPT_ARCH"/"$OPT_NAME"/"$VERSION"/"$PLATFORM"/"$FORMAT"
mkdir -p "$ARTIFACT_DIR"

IMAGE_FILE="$ARTIFACT_DIR"/"$OPT_BRANCH"_"$OPT_NAME"."$OPT_ARCH"."$VERSION"."$PLATFORM"."$FORMAT"

RAW_FILE=$(mktemp --tmpdir "$(basename "$0")"-XXXXXX.raw)
TMPDIR=$(mktemp --tmpdir -d "$(basename "$0")"-XXXXXX)

TMPDIR_BOOT="$TMPDIR/boot"
TMPDIR_EFI="$TMPDIR/efi"
TMPDIR_REPO="$TMPDIR/ostree/repo"

fallocate -l "$ROOT_SIZE" "$RAW_FILE"

LOOP_DEV=$(losetup --show -f "$RAW_FILE")

EFI_PART="$LOOP_DEV"p2
BOOT_PART="$LOOP_DEV"p3
ROOT_PART="$LOOP_DEV"p4

"$__dir"/create_disk.sh --stream "$STREAM" --repodir "$OPT_REPODIR" --disk "$LOOP_DEV"

mount "$ROOT_PART" "$TMPDIR"

mkdir -p "$TMPDIR_EFI"
mount "$EFI_PART" "$TMPDIR_EFI"

mkdir -p "$TMPDIR_BOOT"
mount "$BOOT_PART" "$TMPDIR_BOOT"

ostree admin \
    init-fs \
    --modern "$TMPDIR"

OSTREE_DIR=
case "$OPT_MODE" in
    bare)
        OSTREE_DIR="$OSTREE_BARE_DIR"
        ;;
    archive)
        OSTREE_DIR="$OSTREE_ARCHIVE_DIR"
        ;;
esac

ostree pull-local \
    --repo "$TMPDIR_REPO" \
    "$OSTREE_DIR" \
    "$COMMIT"

"$__dir"/grub_disk.sh --stream "$STREAM" --repodir "$OPT_REPODIR" --disk "$LOOP_DEV" --mount "$TMPDIR"

ln -s ../loader/grub.cfg "$TMPDIR"/boot/grub/grub.cfg

ostree config \
    --repo "$TMPDIR_REPO" \
    set sysroot.bootloader grub2

ostree config \
    --repo "$TMPDIR_REPO" \
    set sysroot.readonly true

# shellcheck disable=SC2153
ostree refs \
    --repo "$TMPDIR_REPO" \
    --create altcos:"$STREAM" \
    "$COMMIT"

ostree admin \
    os-init "$OSNAME" \
    --sysroot "$TMPDIR"

OSTREE_BOOT_PARTITION="/boot" ostree admin deploy altcos:"$STREAM" \
    --sysroot "$TMPDIR" \
    --os "$OSNAME" \
    --karg-append=ignition.platform.id=qemu \
    --karg-append=\$ignition_firstboot \
    --karg-append=net.ifnames=0 \
    --karg-append=biosdevname=0 \
    --karg-append=rw \
    --karg-append=quiet \
    --karg-append=root=UUID="$(blkid --match-tag UUID -o value "$ROOT_PART")"

rm -rf "$TMPDIR"/ostree/deploy/"$OSNAME"/var

rsync -av "$COMMIT_DIR" \
        "$TMPDIR"/ostree/deploy/"$OSNAME"

touch "$TMPDIR"/ostree/deploy/"$OSNAME"/var/.ostree-selabeled
touch "$TMPDIR"/boot/ignition.firstboot

if [ "$EFI_SUPPORT" -eq 1 ]; then
    mkdir -p "$TMPDIR_EFI"/EFI/BOOT
    mv "$TMPDIR_EFI"/EFI/altlinux/shimx64.efi "$TMPDIR_EFI"/EFI/BOOT/bootx64.efi
    mv "$TMPDIR_EFI"/EFI/altlinux/{grubx64.efi,grub.cfg} "$TMPDIR_EFI"/EFI/BOOT/
fi

echo "UUID=$(blkid --match-tag UUID -o value "$BOOT_PART") /boot ext4 ro,nosuid,nodev,relatime,seclabel 1 2" \
    >> "$TMPDIR"/ostree/deploy/"$OSNAME"/deploy/"$COMMIT".0/etc/fstab

for dir in bin sbin libx32 lib lib64; do
    ln -sf ./deploy/"$COMMIT".0/"$dir"  "$TMPDIR"/ostree/deploy/altcos/"$dir"
done

umount -R "$TMPDIR"
rm -rf "$TMPDIR"
losetup -d "$LOOP_DEV"

qemu-img convert -O qcow2 "$RAW_FILE" "$IMAGE_FILE"
rm "$RAW_FILE"

echo "$IMAGE_FILE"
