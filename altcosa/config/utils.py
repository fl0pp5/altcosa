from __future__ import annotations

import os
import subprocess
from dataclasses import asdict, dataclass
from typing import Generic, Self, TypeVar

from altcosa.config.common import PROJECT_DIR


_T = TypeVar("_T")


class SingletonMeta(type, Generic[_T]):
    _instances: dict[SingletonMeta[_T], _T] = {}

    def __call__(cls) -> _T:
        if cls not in cls._instances:
            instance = super().__call__()
            cls._instances[cls] = instance
        return cls._instances[cls]


class Storage(metaclass=SingletonMeta):
    def __init__(self) -> None:
        self.pool: dict[str, str] = {}


@dataclass
class ProcOptions:
    stdout: int = subprocess.PIPE
    stderr: int = subprocess.PIPE


class CmdBuilder:
    __slots__ = ("_cmd", "_args", "_opts", "_proc_opts", "_root")

    def __init__(self, cmd: str) -> None:
        self._cmd = cmd
        self._args: list[str] = []
        self._opts: dict[str, str] = {}
        self._proc_opts = ProcOptions()
        self._root: bool = False

    def args(self, *args: str) -> Self:
        self._args.extend(args)
        return self

    def opts(self, **kwargs: str) -> Self:
        self._opts = kwargs
        return self

    def stdout(self, fd: int = subprocess.PIPE) -> Self:
        self._proc_opts.stdout = fd
        return self

    def stderr(self, fd: int = subprocess.PIPE) -> Self:
        self._proc_opts.stderr = fd
        return self

    def root(self, use: bool) -> Self:
        self._root = use
        return self

    def build(self) -> subprocess.Popen:
        prefix = ""

        if self._root:
            if os.getenv("PASSWORD") is None:
                raise ValueError("password is required")

            prefix = f"echo $PASSWORD | sudo -SEH PYTHONPATH={PROJECT_DIR}"

        args = " ".join(self._args)
        args += " " + " ".join(f"--{k} {v}" for k, v in self._opts.items())
        cmd = f"{prefix} {self._cmd} {args}"

        return subprocess.Popen(cmd, **asdict(self._proc_opts), shell=True)
