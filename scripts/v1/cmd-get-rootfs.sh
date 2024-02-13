#!/usr/bin/env bash

set -eou pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/cmdlib.sh

__usage="Usage: $__name [OPTIONS]...
Get base rootfs image via mkimage-profiles
This image will be used as the base of the ostree image

Arguments:
    Options:
        --arch - ALTCOS target architecture (required)
        --branch - ALTCOS target repository branch (required)
        --repodir - ALTCOS repository root directory (required)
        --mipdir - mkimage-profiles root directory (required)

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_ARCH=
OPT_BRANCH=
OPT_REPODIR=
OPT_MIPDIR=

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
valid_args=$(getopt -o 'ahc' --long 'api,help,check,arch:,branch:,repodir:,mipdir:' --name "$__name" -- "$@")
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
        --mipdir)
            OPT_MIPDIR=$2
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
: "${OPT_MIPDIR:?Missing --mipdir option}"

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

export_stream_by_parts "$OPT_ARCH" "$OPT_BRANCH" "$OPT_REPODIR"

if [ ! -e "$OPT_MIPDIR" ]; then
    fatal "directory \"$OPT_MIPDIR\" not found"
    exit 1
fi

PKG_REPO_BRANCH=Sisyphus
if [ "$OPT_BRANCH" != sisyphus ]; then
    PKG_REPO_BRANCH="$OPT_BRANCH/branch"
fi

PKG_REPO_NS=alt
if [ "$OPT_BRANCH" != sisyphus ]; then
    PKG_REPO_NS="$OPT_BRANCH"
fi

# On current moment allowed only x86_64
PKG_REPO_ARCH=64

# APT configuration for the concrete stream
APT_DIR="$HOME"/apt
mkdir -p \
    "$APT_DIR"/lists/partial \
    "$APT_DIR"/cache/"$OPT_BRANCH"/archives/partial \
    "$APT_DIR"/"$OPT_ARCH"/RPMS.dir

cat <<EOF > "$APT_DIR"/apt.conf."$OPT_BRANCH"."$OPT_ARCH"
Dir::Etc::SourceList $APT_DIR/sources.list.$OPT_BRANCH.$OPT_ARCH;
Dir::Etc::SourceParts /var/empty;
Dir::Etc::main "/dev/null";
Dir::Etc::parts "/var/empty";
APT::Architecture "$PKG_REPO_ARCH";
Dir::State::lists $APT_DIR/lists;
Dir::Cache $APT_DIR/cache/$OPT_BRANCH;
EOF

cat <<EOF > "$APT_DIR"/sources.list."$OPT_BRANCH"."$OPT_ARCH"
rpm [$PKG_REPO_NS] http://ftp.altlinux.org/pub/distributions ALTLinux/$PKG_REPO_BRANCH/$OPT_ARCH classic
rpm [$PKG_REPO_NS] http://ftp.altlinux.org/pub/distributions ALTLinux/$PKG_REPO_BRANCH/noarch classic
rpm-dir file:$APT_DIR $OPT_ARCH dir
EOF

# Pass control to the mkimage-profiles
cd "$OPT_MIPDIR"
make \
    DEBUG=1 \
    APTCONF="$APT_DIR"/apt.conf."$OPT_BRANCH"."$OPT_ARCH" \
    BRANCH="$OPT_BRANCH" \
    ARCH="$OPT_ARCH" \
    IMAGEDIR="$ROOTFS_DIR" \
    vm/altcos.tar
