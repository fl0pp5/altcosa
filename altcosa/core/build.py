import enum


class Platform(enum.StrEnum):
    QEMU = "qemu"
    METAL = "metal"


class Format(enum.StrEnum):
    QCOW2 = "qcow2"
    ISO = "iso"


BUILDS = {
    Platform.QEMU: [
        Format.QCOW2,
    ],
    Platform.METAL: [
        Format.ISO,
    ],
}
