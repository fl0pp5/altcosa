#!/usr/bin/env bash

set -eou pipefail

__dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
__name="$(basename "$0")"

# shellcheck disable=SC1091
source "$__dir"/cmdlib.sh

check_root_uid

__usage="Usage: $__name [OPTIONS]...
Convert rootfs-image to stream repository

Arguments:
    Options:
        --arch - ALTCOS target architecture (required)
        --branch - ALTCOS target repository branch (required)
        --repodir - ALTCOS repository root directory (required)
        --url - ALTCOS update server url (default: https://altcos.altlinux.org)
        --message - OSTree commit message (default: \"stream initial commit\")

        -a, --api - print API-like arguments
        -h, --help - print this message
        -c, --check - check the passed arguments and exit"

OPT_ARCH=
OPT_BRANCH=
OPT_REPODIR=
OPT_URL="https://altcos.altlinux.org"
OPT_MESSAGE="stream initial commit"

# this two variables need to appear in API string (get_cmd_api)
# they checks by getopt bottom
# shellcheck disable=SC2034
OPT_API=
# shellcheck disable=SC2034
OPT_HELP=

OPT_CHECK=0

# shellcheck disable=SC2154
VALID_ARGS=$(getopt -o 'ahc' --long 'api,help,check,arch:,branch:,repodir:,url:,message:' --name "$__name" -- "$@")
eval set -- "$VALID_ARGS"

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
        --url)
            OPT_URL=$2
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
            exit
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

if [ "$OPT_CHECK" -eq 1 ]; then
    exit
fi

export_stream_by_parts "$OPT_ARCH" "$OPT_BRANCH" "$OPT_REPODIR"

if [ -d "$VARS_DIR" ]; then
    fatal "stream \"$STREAM\" is already converted"
    exit 1
fi


OSTREE_DIR=$OSTREE_BARE_DIR

# temp directory for rootfs extract
TMPDIR="$(mktemp --tmpdir -d "$(basename "$0")"-XXXXXX)"
ROOT_TMPDIR="$TMPDIR"/root

mkdir -p "$ROOT_TMPDIR"

tar xf "$ROOTFS_ARCHIVE" -C "$ROOT_TMPDIR" \
    --exclude=./dev/tty \
    --exclude=./dev/tty0 \
    --exclude=./dev/console \
    --exclude=./dev/urandom \
    --exclude=./dev/random \
    --exclude=./dev/full \
    --exclude=./dev/zero \
    --exclude=./dev/pts/ptmx \
    --exclude=./dev/null

rm -f "$ROOT_TMPDIR"/etc/resolv.conf
ln -sf /run/systemd/resolve/resolv.conf "$ROOT_TMPDIR"/etc/resolv.conf

PKG_REPO_NS=alt
if [ "$OPT_BRANCH" != sisyphus ]; then
    PKG_REPO_NS="$OPT_BRANCH"
fi

# system configuration
sed -i "s/#rpm \[$PKG_REPO_NS\] http/rpm \[$PKG_REPO_NS\] http/" "$ROOT_TMPDIR"/etc/apt/sources.list.d/alt.list
sed -i 's/^LABEL=ROOT\t/LABEL=boot\t/g' "$ROOT_TMPDIR"/etc/fstab
sed -i 's/^AcceptEnv /#AcceptEnv /g' "$ROOT_TMPDIR"/etc/openssh/sshd_config
sed -i 's/^# WHEEL_USERS ALL=(ALL) ALL$/WHEEL_USERS ALL=(ALL) ALL/g' "$ROOT_TMPDIR"/etc/sudoers
echo "zincati ALL=NOPASSWD: ALL" > "$ROOT_TMPDIR"/etc/sudoers.d/zincati
sed -i 's|^HOME=/home$|HOME=/var/home|g' "$ROOT_TMPDIR"/etc/default/useradd
echo "blacklist floppy" > "$ROOT_TMPDIR"/etc/modprobe.d/blacklist-floppy.conf

# https://ostreedev.github.io/ostree/deployment
mkdir -m 0775 "$ROOT_TMPDIR"/sysroot
ln -s sysroot/ostree "$ROOT_TMPDIR"/ostree

for dir in home opt srv mnt; do
    mv -f "$ROOT_TMPDIR"/"$dir" "$ROOT_TMPDIR"/var
    ln -sf var/"$dir" "$ROOT_TMPDIR"/"$dir"
done

mv -f "$ROOT_TMPDIR"/root "$ROOT_TMPDIR/var/roothome"
mv -f "$ROOT_TMPDIR"/usr/local "$ROOT_TMPDIR/var/usrlocal"
ln -sf var/roothome "$ROOT_TMPDIR"/root
ln -sf ../var/usrlocal "$ROOT_TMPDIR"/usr/local

mkdir -p "$ROOT_TMPDIR"/etc/ostree/remotes.d
echo "
[remote \"altcos\"]
url=$OPT_URL/streams/$OPT_BRANCH/$OPT_ARCH/ostree/archive
gpg-verify=false
" > "$ROOT_TMPDIR"/etc/ostree/remotes.d/altcos.conf

echo "
# ALTLinux CoreOS Cincinnati backend
[cincinnati]
base_url=\"$OPT_URL\"
" > "$ROOT_TMPDIR"/etc/zincati/config.d/50-altcos-cincinnati.toml

echo "
[Match]
Name=eth0

[Network]
DHCP=yes
" > "$ROOT_TMPDIR"/etc/systemd/network/20-wired.network

sed -i -e 's|#AuthorizedKeysFile\(.*\)|AuthorizedKeysFile\1 .ssh/authorized_keys.d/ignition|' \
    "$ROOT_TMPDIR"/etc/openssh/sshd_config

chroot "$ROOT_TMPDIR" groupadd altcos

# shellcheck disable=SC2016 
chroot "$ROOT_TMPDIR" useradd \
    -g altcos \
    -G docker,wheel \
    -d /var/home/altcos \
    --create-home \
    -s /bin/bash altcos \
    -p '$y$j9T$ZEYmKSGPiNFOZNTjvobEm1$IXLGt5TxdNC/OhJyzFK5NVM.mt6VvdtP6mhhzSmvE94' # password: 1

split_passwd "$ROOT_TMPDIR"/etc/passwd "$ROOT_TMPDIR"/lib/passwd /tmp/passwd.$$
mv /tmp/passwd.$$ "$ROOT_TMPDIR"/etc/passwd

split_group "$ROOT_TMPDIR"/etc/group "$ROOT_TMPDIR"/lib/group /tmp/group.$$
mv /tmp/group.$$ "$ROOT_TMPDIR"/etc/group

sed \
    -e 's/passwd:.*$/& altfiles/' \
    -e 's/group.*$/& altfiles/' \
    -i "$ROOT_TMPDIR"/etc/nsswitch.conf

mv "$ROOT_TMPDIR"/var/lib/rpm "$ROOT_TMPDIR"/lib/rpm
sed 's/\%{_var}\/lib\/rpm/\/lib\/rpm/' -i "$ROOT_TMPDIR"/usr/lib/rpm/macros

KERNEL=$(find "$ROOT_TMPDIR"/boot -type f -name "vmlinuz-*")
SHA=$(sha256sum "$KERNEL" | awk '{print $1;}')
mv "$KERNEL" "$KERNEL-$SHA"

rm -f \
    "$ROOT_TMPDIR"/boot/vmlinuz \
    "$ROOT_TMPDIR"/boot/initrd*

# cat <<EOF > "$ROOT_TMPDIR"/ostree.conf
# EOF

chroot "$ROOT_TMPDIR" dracut \
    -v \
    --reproducible \
    --gzip \
    --no-hostonly \
    -f /boot/initramfs-"$SHA" \
    --add ignition \
    --add ostree \
    --include /ostree.conf /etc/tmpfiles.d/ostree.conf \
    --include /etc/systemd/network/eth0.network /etc/systemd/network/eth0.network \
    --omit-drivers=floppy \
    --omit=nfs \
    --omit=lvm \
    --omit=iscsi \
    --kver "$(ls "$ROOT_TMPDIR"/lib/modules)"

rm -rf "$ROOT_TMPDIR"/usr/etc
mv "$ROOT_TMPDIR"/etc "$ROOT_TMPDIR"/usr/etc

VERSION="$(python3 "$__dir"/cmd-ver.py \
    "$STREAM" \
    "$OPT_REPODIR" \
    --inc-part date \
    --view full)"

VERSION_PATH="$(python3 "$__dir"/cmd-ver.py \
    "$STREAM" \
    "$OPT_REPODIR" \
    --inc-part date \
    --view path)"

mkdir -p "$VARS_DIR"/"$VERSION_PATH"
rsync -av "$ROOT_TMPDIR"/var "$VARS_DIR"/"$VERSION_PATH"

rm -rf "${ROOT_TMPDIR:?}"/var
mkdir "$ROOT_TMPDIR"/var

# shellcheck disable=SC2153
COMMIT=$(
    ostree commit \
        --repo="$OSTREE_DIR" \
        --tree=dir="$ROOT_TMPDIR" \
        -b "$STREAM" \
        -m "$OPT_MESSAGE" \
        --no-xattrs \
        --no-bindings \
        --mode-ro-executables \
        --add-metadata-string=version="$VERSION")

cd "$VARS_DIR" || exit 1
ln -sf "$VERSION_PATH" "$COMMIT"

rm -rf "$TMPDIR"

echo "$COMMIT"
