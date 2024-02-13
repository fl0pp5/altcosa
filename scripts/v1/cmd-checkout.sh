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
        --src - source stream name (e.g. altcos/x86_64/sisyphus/base) (required)
        --dest - destination stream name (required)
        --repodir - ALTCOS repository root directory (required)
        --mode - OSTree repository mode (required)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_SRC=
OPT_DEST=
OPT_REPODIR=
OPT_MODE=

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,src:,dest:,repodir:,mode:' --name "$__name" -- "$@")
eval set -- "$valid_args"

while true ; do
    case "$1" in
        --src)
            OPT_SRC=$2
            shift 2
            ;;
        --dest)
            OPT_DEST=$2
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
: "${OPT_SRC:?Missing --src option}"
: "${OPT_DEST:?Missing --dest option}"
: "${OPT_REPODIR:?Missing --repodir option}"
: "${OPT_MODE:?Missing --mode option}"

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

export_stream "$OPT_SRC" "$OPT_REPODIR"

SRC_OSTREE_DIR=
case "$OPT_MODE" in
    bare)
        SRC_OSTREE_DIR="$OSTREE_BARE_DIR"
        ;;
    archive)
        SRC_OSTREE_DIR="$OSTREE_ARCHIVE_DIR"
        ;;
esac

COMMIT="$(get_commit "$STREAM" "$REPODIR" "$OPT_MODE")"

COMMIT_DIR="$VARS_DIR"/"$COMMIT"
if [ ! -e "$COMMIT_DIR" ]; then
    fatal "directory \"$COMMIT_DIR\" does not exists"
    exit 1
fi

export_stream "$OPT_DEST" "$OPT_REPODIR"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

ostree checkout \
    --repo "$SRC_OSTREE_DIR" \
    "$COMMIT"
ln -sf "$COMMIT" root

if [[ $(findmnt -M merged) ]]; then
    umount merged
fi

for file in merged upper work; do
    mkdir "$file"
done

mount \
    -t overlay overlay \
    -o lowerdir="$COMMIT",upperdir=upper,workdir=work \
    merged && cd merged

ln -sf usr/etc etc
rsync -a "$COMMIT_DIR"/var .

mkdir -p \
    run/lock \
    run/systemd/resolve \
    tmp/.private/root
cp /etc/resolv.conf run/systemd/resolve/resolv.conf

echo "stream \"$OPT_SRC\" checkout at \"$OPT_DEST\""
