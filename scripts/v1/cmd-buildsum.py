#!/usr/bin/env python3
# mypy: ignore-errors

import argparse
import json
import os
import pathlib
import sys
import typing

import pydantic

from altcosa.core.alt import Arch, Branch, Version
from altcosa.core.build import Artifact, Format, Platform

FormatMapping: typing.TypeAlias = dict[Format, Artifact]
PlatformMapping: typing.TypeAlias = dict[Platform, FormatMapping]
VersionMapping: typing.TypeAlias = dict[str, PlatformMapping]
StreamMapping: typing.TypeAlias = dict[str, VersionMapping]
ArchMapping: typing.TypeAlias = dict[str, StreamMapping]
BranchMapping: typing.TypeAlias = dict[Branch, ArchMapping]


class Collector:
    def __init__(self, branch: Branch, storage: str | os.PathLike) -> None:
        self.branch = branch
        self.storage = storage
        self.root = pathlib.Path(self.storage, self.branch)

    def collect_artifact(
        self,
        arch: Arch,
        stream: str,
        version: Version,
        platform: Platform,
        fmt: Format,
    ) -> Artifact:
        artifacts = [
            artifact
            for artifact in self.root.glob(
                f"{arch}/{stream}/{version}/{platform}/{fmt}/*",
            )
        ]

        [location, signature, uncompressed, uncompressed_signature] = [None] * 4

        for artifact in artifacts:
            if artifact.name.endswith(".xz.sig"):
                signature = artifact
            elif artifact.name.endswith(".xz"):
                location = artifact
            elif artifact.name.endswith(".sig"):
                uncompressed_signature = artifact
            else:
                uncompressed = artifact

        return Artifact(
            location, signature, uncompressed, uncompressed_signature,
        )

    def collect_format(
        self,
        arch: Arch,
        stream: str,
        version: Version,
        platform: Platform,
    ) -> FormatMapping:
        formats = {}
        for fmt in self.root.glob(f"{arch}/{stream}/{version}/{platform}/*"):
            fmt = Format(fmt.name)
            formats[fmt] = self.collect_artifact(arch, stream, version, platform, fmt)
        return formats

    def collect_platform(
        self, arch: Arch, stream: str, version: Version,
    ) -> PlatformMapping:
        platforms = {}
        for platform in self.root.glob(f"{arch}/{stream}/{version}/*"):
            platform = Platform(platform.name)
            platforms[platform] = self.collect_format(arch, stream, version, platform)
        return platforms

    def collect_version(self, arch: Arch, stream: str) -> VersionMapping:
        versions = {}
        for version in self.root.glob(f"{arch}/{stream}/*"):
            version_name = f"{self.branch}_{stream}.{version.name}"
            versions[version.name] = self.collect_platform(
                arch, stream, Version.from_str(version_name),
            )
        return versions

    def collect_stream(self, arch: Arch) -> StreamMapping:
        streams = {}
        for stream in self.root.glob(f"{arch}/*"):
            streams[stream.name] = self.collect_version(arch, stream.name)
        return streams

    def collect_arch(self) -> ArchMapping:
        architectures = {}
        for arch in self.root.glob("*"):
            arch = Arch(arch.name)
            architectures[arch.value] = self.collect_stream(arch)
        return architectures

    def collect(self) -> BranchMapping:
        return {self.branch: self.collect_arch()}


class SisyphusBuilds(pydantic.BaseModel):
    sisyphus: typing.Any


class P10Builds(pydantic.BaseModel):
    p10: typing.Any


def main() -> None:
    parser = argparse.ArgumentParser(description="Collect branch builds information")
    parser.add_argument(
        "--branch",
        help="repository branch",
        choices=[*Branch],
        required=True,
    )
    parser.add_argument(
        "--storage",
        help="builds storage directory",
        required=True,
    )
    parser.add_argument(
        "-w", "--write",
        action="store_true",
        help="Write build summary to the storage directory",
    )
    parser.add_argument(
        "-c", "--check",
        help="check the passed arguments and exit (need for compability with config API)",
    )

    args = parser.parse_args()

    builds = {Branch.SISYPHUS: SisyphusBuilds, Branch.P10: P10Builds}

    branch = Branch(args.branch)
    summary = Collector(branch, args.storage).collect()
    summary = builds[branch].model_validate(summary).model_dump(mode="json")

    if args.write:
        summary_path = pathlib.Path(args.storage, f"{args.branch}.json")
        with open(summary_path, "w") as file:
            json.dump(summary, file)
    else:
        print(json.dumps(summary))


if __name__ == "__main__":
    main()
