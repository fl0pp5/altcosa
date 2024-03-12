import dataclasses
import enum


class Platform(enum.StrEnum):
    QEMU = "qemu"
    METAL = "metal"


class Format(enum.StrEnum):
    QCOW2 = "qcow2"
    ISO = "iso"


@dataclasses.dataclass
class Artifact:
    location: str | None = None
    signature: str | None = None
    uncompressed: str | None = None
    uncompressed_signature: str | None = None


@dataclasses.dataclass
class Build:
    platform: Platform
    fmt: Format
    disk: Artifact | None = None
    kernel: Artifact | None = None
    initrd: Artifact | None = None
    rootfs: Artifact | None = None


BUILDS = {
    Platform.QEMU: [
        Format.QCOW2,
    ],
    Platform.METAL: [
        Format.ISO,
    ],
}
