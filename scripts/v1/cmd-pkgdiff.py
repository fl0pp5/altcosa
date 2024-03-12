#!/usr/bin/env python3
# mypy: ignore-errors

import argparse
import dataclasses
import json
import pathlib
import shlex
import subprocess
import sys
import tempfile
from typing import Self, TypeAlias, no_type_check

import gi

gi.require_version("OSTree", "1.0")

from gi.repository import OSTree  # noqa: I202,E402

from loguru import logger  # noqa: E402

import rpm  # noqa: E402

from altcosa.core.alt import Commit, Repository, Stream  # noqa: E402


PROGRAM_NAME = pathlib.Path(sys.argv[0]).name


@dataclasses.dataclass
class Package:
    _header: rpm.hdr

    @no_type_check
    def __eq__(self, other: object) -> bool:
        return rpm.versionCompare(self._header, other._header) == 0

    @no_type_check
    def __lt__(self, other: object) -> bool:
        return rpm.versionCompare(self._header, other._header) == -1

    @no_type_check
    def __gt__(self, other: object) -> bool:
        return rpm.versionCompare(self._header, other._header) == 1

    @property
    @no_type_check
    def name(self) -> str:
        return self._header[rpm.RPMTAG_NAME].decode()

    @property
    @no_type_check
    def version(self) -> str:
        return self._header[rpm.RPMTAG_VERSION].decode()

    @property
    @no_type_check
    def release(self) -> str:
        return self._header[rpm.RPMTAG_RELEASE].decode()

    @property
    @no_type_check
    def epoch(self) -> int:
        return self._header[rpm.RPMTAG_EPOCH]

    @property
    @no_type_check
    def summary(self) -> str:
        return self._header[rpm.RPMTAG_SUMMARY].decode()

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "version": self.version,
            "release": self.release,
            "epoch": self.epoch,
            "summary": self.summary,
        }


PackageMapping: TypeAlias = dict[str, Package]


class BDBReader:
    """
    Berkeley DB reader for OSTree repository
    """
    def __init__(self, content: bytes) -> None:
        """
        :param content: content of /lib/rpm/Packages
        :type content: bytes
        """
        self.content = content

    @classmethod
    def from_commit(cls, commit: Commit) -> Self:
        """
        Get the Packages DB from the given commit

        :param commit: commit hashsum
        :type commit: Commit
        :return: BDBReader instance
        :rtype: Self
        """

        # read the /lib/rpm/Packages raw content
        cmd = shlex.split(
            f"ostree cat {commit} --repo={commit.repository.path} /lib/rpm/Packages",
        )

        content = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        ).stdout

        return cls(content)

    def translate(self) -> PackageMapping:
        """
        Translate raw package information to the dataclass

        :return: mapped Package instance by own name
        :rtype: PackageMapping
        """

        with tempfile.TemporaryDirectory(prefix=PROGRAM_NAME) as dbpath:
            db = pathlib.Path(dbpath, "Packages")
            db.write_bytes(self.content)

            if dbpath:
                rpm.addMacro("_dbpath", dbpath)

            pkgs = {hdr[rpm.RPMTAG_NAME]: Package(hdr) for hdr in rpm.TransactionSet().dbMatch()}

            if dbpath:
                rpm.delMacro("_dbpath")

        return pkgs


@dataclasses.dataclass
class UpdateDiff:
    new_pkg: Package
    old_pkg: Package

    def to_dict(self) -> dict[str, PackageMapping]:
        return {
            "new": self.new_pkg.to_dict(),
            "old": self.old_pkg.to_dict(),
        }


def get_update_diff_list(a: PackageMapping, b: PackageMapping) -> list[UpdateDiff]:  # noqa: VNE001
    return [UpdateDiff(a[name], b[name]) for name in a.keys() & b.keys() if a[name] > b[name]]


def get_unique_pkgs(a: PackageMapping, b: PackageMapping) -> PackageMapping:  # noqa: VNE001
    unique_names = set(a.keys()).difference(set(b.keys()))
    return {name: a[name] for name in unique_names}


def main() -> None:
    parser = argparse.ArgumentParser(description="Collect stream's metadata")
    parser.add_argument(
        "--stream",
        help="stream name (e.g. altcos/x86_64/sisyphus/base)",
        required=True,
    )
    parser.add_argument(
        "--repodir",
        help="ALTCOS repository directory",
        required=True,
    )
    parser.add_argument(
        "--commit",
        help="commit hashsum (default: latest)",
        default="latest",
    )
    parser.add_argument(
        "--mode",
        help="OSTree mode",
        choices=["bare", "archive"],
        required=True,
    )
    parser.add_argument(
        "-w", "--write",
        help="write info to the <streamdir>/metadata.json",
        action="store_true",
    )
    parser.add_argument(
        "-c", "--check",
        help="check the passed arguments and exit (need for compability with config API)",
        action="store_true"
    )

    args = parser.parse_args()

    if args.check:
        sys.exit(0)

    stream = Stream.from_str(args.repodir, args.stream)
    mode = OSTree.RepoMode.BARE if args.mode == "bare" else OSTree.RepoMode.ARCHIVE
    repo = Repository(stream, mode)

    if args.commit == "latest":
        if not (commit := repo.last_commit()):
            logger.error("no one commit found")
            sys.exit(1)
    else:
        if not (commit := Commit(repo, args.commit)).exists():
            logger.error(f"commit \"{commit}\" not found")
            sys.exit(1)

    pkgs = BDBReader.from_commit(commit).translate()
    [installed, updated, new, removed] = [[]] * 4

    installed = [pkg.to_dict() for pkg in pkgs.values()]

    if (parent_commit := commit.parent) is not None:
        parent_pkgs = BDBReader.from_commit(parent_commit).translate()
        new = [pkg.to_dict() for pkg in get_unique_pkgs(pkgs, parent_pkgs).values()]
        removed = [pkg.to_dict() for pkg in get_unique_pkgs(parent_pkgs, pkgs).values()]
        updated = [diff.to_dict() for diff in get_update_diff_list(pkgs, parent_pkgs)]

    metadata = {
        "reference": str(stream),
        "version": str(commit.version),
        "description": str(commit.description),
        "commit": str(commit),
        "parent": str(parent_commit) if parent_commit else None,
        "package_info": {
            "installed": installed,
            "new": new,
            "removed": removed,
            "updated": updated,
        },
    }

    if args.write:
        metadata_path = stream.vars_dir.joinpath(
            commit.version.like_path(), "metadata.json")
        with open(metadata_path, "w") as file:
            json.dump(metadata, file)
    else:
        print(json.dumps(metadata))


if __name__ == "__main__":
    main()
