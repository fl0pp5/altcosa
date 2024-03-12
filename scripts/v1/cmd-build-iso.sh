#!/usr/bin/env bash

set -eou pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/cmdlib.sh

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
        --mipdir - mkimage-profiles root directory (required)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_ARCH=
OPT_BRANCH=
OPT_NAME=
OPT_REPODIR=
OPT_IMAGEDIR=
OPT_MODE=
OPT_MIPDIR=

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,arch:,branch:,name:,repodir:,imagedir:,mode:,mipdir:' --name "$__name" -- "$@")
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
        --mipdir)
            OPT_MIPDIR=$2
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
: "${OPT_MIPDIR:?Missing --mipdir option}"

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

export_stream_by_parts "$OPT_ARCH" "$OPT_BRANCH" "$OPT_REPODIR" "$OPT_NAME"

PLATFORM=metal
FORMAT=iso

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

echo "$PASSWORD" | sudo -S mkdir -p "$ARTIFACT_DIR"
echo "$PASSWORD" | sudo -S chmod -R 755 "$ARTIFACT_DIR"

IMAGE_FILE="$ARTIFACT_DIR"/"$OPT_BRANCH"_"$OPT_NAME"."$OPT_ARCH"."$VERSION"."$PLATFORM"."$FORMAT"

RPMBUILD_DIR="$(mktemp --tmpdir -d "$(basename "$0")"_rpmbuild-XXXXXX)"
mkdir "$RPMBUILD_DIR"/SOURCES

APT_DIR="$HOME"/apt

CUR_DIR="$(pwd)"
cd "$__dir"/specs/startup-installer-altcos
# shellcheck disable=SC2153
gear-rpm \
    -bb \
    --define "stream $STREAM" \
    --define "_rpmdir $APT_DIR/$ARCH/RPMS.dir/" \
    --define "_rpmfilename startup-installer-altcos-0.2.5-alt1.x86_64.rpm"
cd "$CUR_DIR"

echo "$PASSWORD" | sudo -S tar -cf - \
    -C "$(dirname "$COMMIT_DIR")" var \
    | xz -9 -c -T0 --memlimit=2048MiB - > "$RPMBUILD_DIR"/SOURCES/var.tar.xz

mkdir "$RPMBUILD_DIR"/altcos_root

ostree admin init-fs \
    --modern "$RPMBUILD_DIR"/altcos_root

OSTREE_DIR=
case "$OPT_MODE" in
    bare)
        OSTREE_DIR="$OSTREE_BARE_DIR"
        ;;
    archive)
        OSTREE_DIR="$OSTREE_ARCHIVE_DIR"
        ;;
esac

echo "$PASSWORD" | sudo -S ostree \
    pull-local \
    --repo "$RPMBUILD_DIR"/altcos_root/ostree/repo \
    "$OSTREE_DIR" \
    "$STREAM"

echo "$PASSWORD" | sudo -S tar -cf - -C "$RPMBUILD_DIR"/altcos_root . \
    | xz -9 -c -T0 --memlimit=2048MiB - > "$RPMBUILD_DIR"/SOURCES/altcos_root.tar.xz
echo "$PASSWORD" | sudo -S rm -rf "$RPMBUILD_DIR"/altcos_root

rpmbuild \
    --define "_topdir $RPMBUILD_DIR" \
    --define "_rpmdir $APT_DIR/$ARCH/RPMS.dir/" \
    --define "_rpmfilename altcos-archives-0.1-alt1.x86_64.rpm" \
    -bb "$__dir"/specs/altcos-archives.spec

echo "$PASSWORD" | sudo -S rm -rf "$RPMBUILD_DIR"

echo "$PASSWORD" | sudo -S chmod a+w "$OPT_IMAGEDIR"

make \
    -C "$OPT_MIPDIR" \
    APTCONF="$APT_DIR"/apt.conf."$OPT_BRANCH"."$OPT_ARCH" \
    BRANCH="$OPT_BRANCH" \
    IMAGEDIR="$OPT_IMAGEDIR" \
    live-install-altcos.iso

mv "$(realpath "$OPT_IMAGEDIR"/live-install-altcos-latest-x86_64.iso)" "$IMAGE_FILE"

find "$OPT_IMAGEDIR" -type l -delete

echo "$IMAGE_FILE"
