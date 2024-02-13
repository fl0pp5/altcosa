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
        --mode - OSTree repository mode (required)
        --next - next version part increment (major|minor) (required)
        --message - commit message (required)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_STREAM=
OPT_REPODIR=
OPT_MODE=
OPT_NEXT=
OPT_MESSAGE=

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,stream:,repodir:,mode:,next:,message:' --name "$__name" -- "$@")
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
        --next)
            OPT_NEXT=$2
            shift 2
            ;;
        --message)
            OPT_MESSAGE=$2
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
: "${OPT_MODE:?Missing --mode option}"
: "${OPT_NEXT:?Missing --next option}"
: "${OPT_MESSAGE:?Missing --message option}"

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

export_stream "$OPT_STREAM" "$OPT_REPODIR"

OSTREE_DIR=
case "$OPT_MODE" in
    bare)
        OSTREE_DIR="$OSTREE_BARE_DIR"
        ;;
    archive)
        OSTREE_DIR="$OSTREE_ARCHIVE_DIR"
        ;;
esac

COMMIT="$(get_commit "$STREAM" "$OPT_REPODIR" "$OPT_MODE")"
if [ -z "$COMMIT" ]; then
    COMMIT="$(get_commit "$OSNAME"/"$ARCH"/"$BRANCH"/base "$OPT_REPODIR" "$OPT_MODE")"
    VERSION_GET_ARGS="$STREAM $OPT_REPODIR --view full --inc-part $OPT_NEXT"
else
    VERSION_GET_ARGS="$STREAM $OPT_REPODIR --view full --inc-part $OPT_NEXT --commit $COMMIT"
fi

# shellcheck disable=SC2086
VERSION="$(python3 "$__dir"/cmd-ver.py $VERSION_GET_ARGS --view full)"
# shellcheck disable=SC2086
VERSION_PATH="$(python3 "$__dir"/cmd-ver.py $VERSION_GET_ARGS --view path)"

VAR_DIR="$VARS_DIR"/"$VERSION_PATH"

cd "$WORK_DIR"
rm -f upper/etc root/etc

mkdir -p "$VAR_DIR"

cd upper
mkdir -p var/lib/apt var/cache/apt

prepare_apt_dirs "$PWD"

rsync -av var "$VAR_DIR"

rm -rf run var
mkdir var

TO_DELETE=$(find . -type c)
cd "$WORK_DIR"/root
rm -rf "$TO_DELETE"

cd ../upper

set +eo pipefail
find . -depth | (cd ../merged;cpio -pmdu "$WORK_DIR"/root)
set -eo pipefail

cd ..
umount merged

ADD_METADATA=
if [ "$NAME" != "base" ]; then
    ADD_METADATA=" --add-metadata-string=parent_commit_id=$COMMIT"
    ADD_METADATA="$ADD_METADATA --add-metadata-string=parent_version=$VERSION"
fi

NEW_COMMIT=$(
    ostree commit \
        --repo="$OSTREE_DIR" \
        --tree=dir="$COMMIT" \
        -b "$STREAM" \
        -m "$OPT_MESSAGE" \
        --no-bindings \
        --mode-ro-executables \
        "$ADD_METADATA" \
        --add-metadata-string=version="$VERSION")

cd "$VARS_DIR"
ln -sf "$VERSION_PATH" "$NEW_COMMIT"
rm -rf "$COMMIT"

ostree summary --repo="$OSTREE_DIR" --update

rm -rf "$WORK_DIR"

echo "$NEW_COMMIT"
