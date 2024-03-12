#!/usr/bin/env python3

import argparse
import dataclasses
import enum
import sys
import typing

from loguru import logger

import gi  # type: ignore # noqa: I100

gi.require_version("OSTree", "1.0")

from gi.repository import GLib, OSTree  # type: ignore # noqa: I202,E402

from altcosa.core.alt import Commit, Repository, Stream, Version  # noqa: E402


class VersionPart(enum.StrEnum):
    MAJOR = "major"
    MINOR = "minor"
    DATE = "date"


class VersionView(enum.StrEnum):
    PATH = "path"   # e.g. 20230201/4/1
    NATIVE = "native"  # e.g. 20230201.4.1
    FULL = "full"  # e.g. sisyphus_base.20230201.4.1


@dataclasses.dataclass
class CliOptions:
    stream: str
    repodir: str
    commit: str | None = None
    inc_part: VersionPart | None = None
    version_view: VersionView | None = None

    def __post_init__(self) -> None:
        self.inc_part = VersionPart(self.inc_part) if self.inc_part else None
        self.version_view = VersionView(self.version_view) if self.version_view else None

    @classmethod
    def from_args(cls, args: argparse.Namespace) -> typing.Self:
        """
        Create a new CliOptions instance from argparse arguments
        args must contain the following fields:
            - stream
            - repodir
            - commit (optional)
            - inc_part (optional)
            - version_view (optional)

        :param args: arguments from the cli
        :type args: argparse.Namespace
        :return: instance of CliOptions
        :rtype: typing.Self
        """
        return cls(args.stream, args.repodir, args.commit, args.inc_part, args.version_view)

    def handle(self) -> None:
        version = self._handle()
        result = str(version)

        match self.version_view:
            case VersionView.PATH:
                result = version.like_path()
            case VersionView.NATIVE:
                result = str(version)
            case VersionView.FULL:
                result = version.full()

        print(result)

    def _handle(self) -> Version:  # noqa: C901
        stream = Stream.from_str(self.repodir, self.stream)

        try:
            repository = Repository(stream, OSTree.RepoMode.BARE)
        except GLib.Error as e:
            logger.error(e)
            sys.exit(1)

        if self.commit:
            commit = Commit(repository, self.commit)

            if not commit.exists():
                logger.error(f"Commit \"{commit}\" does not exist")
                sys.exit(1)

            version = commit.version

            return self._inc_part(version)

        try:
            last_commit = repository.last_commit()
        except GLib.Error as e:
            logger.error(e)
            sys.exit(1)

        if last_commit is None:

            if not self.inc_part:
                logger.error("No one commit found")
                sys.exit(1)

            # return the new version if no one exists
            return Version(0, 0, stream.branch, stream.name)

        version = last_commit.version

        return self._inc_part(version)

    def _inc_part(self, version: Version) -> Version:
        """
        Increment the version part by a self.inc_part field if not None

        :param version: version to increment
        :type version: Version
        :return: instance of incremented version
        :rtype: Version
        """
        match self.inc_part:
            case VersionPart.MINOR:
                version.minor += 1
            case VersionPart.MAJOR:
                version.major += 1
            case VersionPart.DATE:
                version = Version(0, 0, version.branch, version.name)

        return version


def main() -> None:
    parser = argparse.ArgumentParser()

    parser.add_argument("stream",
                        help="ALTCOS stream (e.g. `altcos/x86_64/p10/base`)")
    parser.add_argument("repodir",
                        help="ALTCOS repository directory")
    parser.add_argument("-c", "--commit",
                        help="commit hashsum")
    parser.add_argument("--inc-part",
                        dest="inc_part",
                        choices=[*VersionPart],
                        default=None,
                        help="version part to increment/update")
    parser.add_argument("--view",
                        dest="version_view",
                        choices=[*VersionView])

    args = parser.parse_args()

    CliOptions.from_args(args).handle()


if __name__ == '__main__':
    main()
