#!/usr/bin/env python3

import argparse
import dataclasses
import enum
import sys
import typing

from loguru import logger

import gi  # noqa: I100

gi.require_version("OSTree", "1.0")

from gi.repository import GLib, OSTree  # noqa: I202,E402

from altcosa.core.alt import Repository, Stream  # noqa: E402


class Mode(enum.StrEnum):
    BARE = "bare"
    ARCHIVE = "archive"


@dataclasses.dataclass
class CliOptions:
    stream: str
    repodir: str
    mode: Mode

    def __post_init__(self) -> None:
        self.mode = Mode(self.mode)

    @classmethod
    def from_args(cls, args: argparse.Namespace) -> typing.Self:
        """
        Create a new CliOptions instance from argparse arguments
        args must contain the following fields:
            - stream
            - repodir
            - mode

        :param args: arguments from the cli
        :type args: argparse.Namespace
        :return: instance of CliOptions
        :rtype: typing.Self
        """
        return cls(args.stream, args.repodir, args.mode)

    def handle(self) -> None:
        mode = OSTree.RepoMode.BARE if self.mode == Mode.BARE else OSTree.RepoMode.ARCHIVE

        stream = Stream.from_str(self.repodir, self.stream)
        try:
            repository = Repository(stream, mode)
        except GLib.Error as e:
            logger.error(e)
            sys.exit(1)

        try:
            last_commit = repository.last_commit()
        except GLib.Error as e:
            logger.error(e)
            sys.exit(1)

        print(last_commit)


def main() -> None:
    parser = argparse.ArgumentParser()

    parser.add_argument("stream",
                        help="ALTCOS stream (e.g. `altcos/x86_64/p10/base`)")
    parser.add_argument("repodir",
                        help="ALTCOS repository directory")
    parser.add_argument("mode", choices=[*Mode])

    args = parser.parse_args()

    CliOptions.from_args(args).handle()


if __name__ == "__main__":
    main()
