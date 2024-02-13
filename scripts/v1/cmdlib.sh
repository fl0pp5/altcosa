#!/usr/bin/env bash


set -eou pipefail

RED=$(tput setaf 1)
RESET=$(tput sgr0)

function fatal() {
	if test -t 1; then
		echo "${RED}fatal:$RESET $*" 1>&2
	else
		echo "fatal: $*" 1>&2
	fi
}

function check_root_uid() {
    [ $UID -eq 0 ] || {
        fatal "$(basename "$0") needs to be run as root (uid=0) only"
        exit 1
    }
}

# get the command api string for executing script
#
# example:
#   ./scripts/cmd-init.sh -a
#   echo> $ARG_ARCH $ARG_BRANCH $ARG_REPODIR $OPT_API $OPT_HELP
function get_cmd_api() {
    local variables=
    local api=

    variables=$(declare | grep -E '(ARG|OPT)_.+')
    # split variables by '\n' sign
    for var in ${variables//\n/}
    do
        # split variable by '=' sign
        api+="\$$(echo "$var" | awk -F "=" '{print $1}') "
    done
    echo "$api"
}

# export the stream by arch, branch and repodir
# after success call, variables related to stream allowed in scope
function export_stream_by_parts() {
    local arch=$1
    local branch=$2
    local repodir=$3
    local name="${4:-base}"

    cmd="
import sys

from altcosa.core.alt import *

try:
    print(Stream('$repodir', 'altcos', '$arch', '$branch', '$name').export())
except Exception as e:
    print(e)
    sys.exit(1)
"

    output="$(python3 -c "$cmd" 2>&1)" || {
        fatal "$output"
        exit 1
    }

    eval "$output"
}

function export_stream() {
    local stream=$1
    local repodir=$2

    cmd="
import sys

from altcosa.core.alt import *

try:
    print(Stream.from_str('$repodir', '$stream').export())
except Exception as e:
    print(e)
    sys.exit(1)
"
    output="$(python3 -c "$cmd" 2>&1)" || {
        fatal "$output"
        exit 1
    }

    eval "$output"
}


function get_commit() {
    local stream=$1
    local repodir=$2
    local mode=$3

    local ostree_mode_n

    case "$mode" in
        bare)
            ostree_mode_n=0 ;;
        archive)
            ostree_mode_n=1 ;;
    esac

    cmd="
import sys

from altcosa.core.alt import Stream, Repository

try:
    stream = Stream.from_str('$repodir', '$stream')
    repo = Repository(stream, $ostree_mode_n)
    commit = repo.last_commit()
    if commit is None:
        raise Exception('no one commit found')
    print(commit, end='')
except Exception as e:
    pass
"

    output="$(python3 -c "$cmd" 2>&1)" || {
        # if commit not found, just return nothing
        return
    }

    echo "$output"
}

# Split passwd file (/etc/passwd) into
# /usr/etc/passwd - home users password file (uid >= 500)
# /lib/passwd - system users password file (uid < 500)
function split_passwd() {
    local from_pass=$1
    local sys_pass=$2
    local user_pass=$3

    touch "$sys_pass"
    touch "$user_pass"

    set -f

    local ifs=$IFS

    exec < "$from_pass"
    while read -r line
    do
        IFS=:
		# shellcheck disable=SC2086
		set -- $line
		IFS=$ifs

        user=$1
        uid=$3

        if [[ $uid -ge 500 || $user = "root" || $user = "systemd-network" ]]
        then
            echo "$line" >> "$user_pass"
        else
            echo "$line" >> "$sys_pass"
        fi
    done
}

# Split group file (/etc/group) into
# /usr/etc/group - home users group file (uid >= 500)
# /lib/group - system users group file (uid < 500)
function split_group() {
    local from_group=$1
    local sys_group=$2
    local user_group=$3

    touch "$sys_group"
    touch "$user_group"

    set -f

    local ifs=$IFS

    exec < "$from_group"
    while read -r line
    do
        IFS=:
		# shellcheck disable=SC2086
		set -- $line
		IFS="$ifs"

        user=$1
        uid=$3
        if [[ $uid -ge 500 ||
              $user = "root" ||
              $user = "adm" ||
              $user = "wheel" ||
              $user = "systemd-network" ||
              $user = "systemd-journal" ||
              $user = "docker" ]]
        then
            echo "$line" >> "$user_group"
        else
            echo "$line" >> "$sys_group"
        fi
    done
}

prepare_apt_dirs() {
	local root_dir=$1

	sudo mkdir -p \
		"$root_dir"/var/lib/apt/lists/partial \
		"$root_dir"/var/cache/apt/archives/partial \
		"$root_dir"/var/cache/apt/gensrclist \
		"$root_dir"/var/cache/apt/genpkglist

	sudo chmod -R 770 "$root_dir"/var/cache/apt
	sudo chmod -R g+s "$root_dir"/var/cache/apt
	sudo chown root:rpm "$root_dir"/var/cache/apt
}
