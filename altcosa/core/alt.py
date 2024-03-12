from __future__ import annotations

import dataclasses
import datetime
import enum
import pathlib
import typing

import gi  # type: ignore

gi.require_version("OSTree", "1.0")

from gi.repository import GLib, Gio, OSTree  # type: ignore # noqa: I202,E402


class OSName(enum.StrEnum):
    ALTCOS = "altcos"


class Arch(enum.StrEnum):
    x86_64 = "x86_64"


class Branch(enum.StrEnum):
    SISYPHUS = "sisyphus"
    P10 = "p10"


@dataclasses.dataclass
class Stream:
    repodir: str
    osname: OSName = OSName.ALTCOS
    arch: Arch = Arch.x86_64
    branch: Branch = Branch.SISYPHUS
    name: str = "base"

    def __post_init__(self) -> None:
        """
        Check the fields types
        """
        self.repodir = str(self.repodir)
        self.osname = OSName(self.osname)
        self.arch = Arch(self.arch)
        self.branch = Branch(self.branch)
        self.name = str(self.name)

    def __str__(self) -> str:
        return f"{self.osname}/{self.arch}/{self.branch}/{self.name}"

    @classmethod
    def from_str(cls, repodir: str, stream: str) -> typing.Self:
        """
        Create a Stream from a string

        :param repodir: repository directory
        :type repodir: str
        :param stream: string stream representation (e.g. altcos/x86_64/p10/base)
        :type stream: str
        :raises ValueError:
        :return: instance of Stream
        :rtype: typing.Self
        """
        try:
            return cls(repodir, *stream.split("/"))  # type: ignore
        except TypeError:
            raise ValueError(f"Invalid stream format: \"{stream}\"")

    @property
    def base(self) -> typing.Self:
        """
        Make the base stream

        :return: instance of Stream
        :rtype: typing.Self
        """
        return type(self)(self.repodir, self.osname, self.arch, self.branch)

    @property
    def stream_dir(self) -> pathlib.Path:
        """
        Get stream directory path

        :return: instance of pathlib.Path
        :rtype: pathlib.Path
        """

        return pathlib.Path(self.repodir, self.branch, self.arch, self.name)

    @property
    def alt_dir(self) -> pathlib.Path:
        """
        Get alt specific content directory path

        :return: instance of pathlib.Path
        :rtype: pathlib.Path
        """
        return self.stream_dir.joinpath("alt")

    @property
    def rootfs_dir(self) -> pathlib.Path:
        """
        Get rootfs images directory path

        :return: instance of pathlib.Path
        :rtype: pathlib.Path
        """
        return self.base.stream_dir.joinpath("rootfs")

    @property
    def rootfs_archive(self) -> pathlib.Path:
        """
        Get rootfs archive file path

        :return: instance of pathlib.Path
        :rtype: pathlib.Path
        """
        return self.rootfs_dir.joinpath(f"altcos-latest-{self.arch}.tar")

    @property
    def work_dir(self) -> pathlib.Path:
        """
        Get work directory path (contains overlayfs stuff)

        :return: instance of pathlib.Path
        :rtype: pathlib.Path
        """
        return self.alt_dir.joinpath("work")

    @property
    def vars_dir(self) -> pathlib.Path:
        """
        Get vars directory path (contains `var` directories for diffirent versions of streams)

        :return: instance of pathlib.Path
        :rtype: pathlib.Path
        """
        return self.alt_dir.joinpath("vars")

    @property
    def merged_dir(self) -> pathlib.Path:
        """
        Get merged directory path (contains chroot env)

        :return: instance of pathlib.Path
        :rtype: pathlib.Path
        """
        return self.work_dir.joinpath("merged")

    @property
    def ostree_dir(self) -> pathlib.Path:
        """
        Get ostree specific directory path

        :return: instance of pathlib.Path
        :rtype: pathlib.Path
        """
        return self.base.stream_dir.joinpath("ostree")

    @property
    def ostree_bare_dir(self) -> pathlib.Path:
        """
        Get bare ostree repository directory path

        :return: instance of pathlib.Path
        :rtype: pathlib.Path
        """
        return self.ostree_dir.joinpath("bare")

    @property
    def ostree_archive_dir(self) -> pathlib.Path:
        """
        Get archive ostree repository directory path

        :return: instance of pathlib.Path
        :rtype: pathlib.Path
        """
        return self.ostree_dir.joinpath("archive")

    def export(self) -> str:
        """
        Make bash export-like string with all data about the stream

        :return: bash export-like string
        :rtype: str
        """
        attrs = [attr for attr in dir(Stream) if isinstance(getattr(Stream, attr), property)]
        exports = [f"export {attr.upper()}={getattr(self, attr)}" for attr in attrs]
        exports.extend([f"export {attr.upper()}={getattr(self, attr)}" for attr in self.__dict__])
        exports.append(f"export STREAM={self}")

        return ";".join(exports)


class Repository:
    __slots__ = ("stream", "mode", "path", "storage")

    def __init__(self, stream: Stream, mode: OSTree.RepoMode) -> None:
        self.stream = stream
        self.mode = mode

        if self.mode == OSTree.RepoMode.BARE:
            self.path = self.stream.ostree_bare_dir
        elif self.mode == OSTree.RepoMode.ARCHIVE:
            self.path = self.stream.ostree_archive_dir

        self.storage = OSTree.Repo.new(Gio.file_new_for_path(str(self.path)))
        self.storage.open()

    def last_commit(self) -> Commit | None:
        """
        Get the last commit of the repository by repository stream

        :return: last commit
        :rtype: Commit | None
        """
        if (hashsum := self.storage.resolve_rev(str(self.stream), True)[1]) is None:
            return None
        return Commit(self, hashsum)


@dataclasses.dataclass
class Version:
    major: int
    minor: int
    branch: Branch
    name: str = "base"
    date: str | None = None

    def __post_init__(self) -> None:
        self.major = int(self.major)
        self.minor = int(self.minor)
        self.branch = Branch(self.branch)
        self.date = self.date or datetime.datetime.now().strftime("%Y%m%d")

    def __str__(self) -> str:
        return f"{self.date}.{self.major}.{self.minor}"

    @classmethod
    def from_str(cls, version: str) -> typing.Self:
        """
        Make version instance from a string representation
        e.g.
            sisyphus_base.20230101.0.2 -> Version(0, 2, Branch.SISYPHUS, "base", "20230101")

        :param version: version string representation
        :type version: str
        :return: instance of Version
        :rtype: Version
        """

        (prefix, date, major, minor) = version.split(".")

        (branch, name) = prefix.split("_")

        return cls(int(major), int(minor), Branch(branch), name, date)

    def like_path(self) -> str:
        if self.date is None:
            raise ValueError("date field is None. (wtf dude?)")

        return str(pathlib.Path(self.date, str(self.major), str(self.minor)))

    def full(self) -> str:
        return f"{self.branch}_{self.name}.{self}"


@dataclasses.dataclass
class Commit:
    repository: Repository
    hashsum: str

    def __str__(self) -> str:
        return self.hashsum

    def exists(self) -> bool:
        try:
            self.repository.storage.load_commit(self.hashsum)
        except GLib.Error:
            return False
        return True

    @property
    def version(self) -> Version:
        """
        Get version from commit metadata

        :return: instance of Version
        :rtype: Version
        """
        content = self.repository.storage.load_commit(self.hashsum)
        return Version.from_str(content[1][0]["version"])

    @property
    def description(self) -> str:
        """
        Get description from commit metadata

        :return: commit message
        :rtype: str
        """
        return str(self.repository.storage.load_commit(self.hashsum)[1][4])

    @property
    def parent(self) -> typing.Self | None:
        """
        Get commit parent instance

        :return: commit parent if exists
        :rtype: typing.Self | None
        """
        content = self.repository.storage.load_commit(self.hashsum)
        parent_hashsum = OSTree.commit_get_parent(content[1])

        return type(self)(self.repository, parent_hashsum) if parent_hashsum else None
