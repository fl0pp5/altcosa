import enum

import jinja2

from pydantic import BaseModel, validator

from altcosa.config.common import ConfigExecutionError
from altcosa.config.utils import CmdBuilder, Storage


class DefineValueMode(enum.StrEnum):
    JINJA = "jinja"
    MANUAL = "manual"
    SHELL = "shell"


class DefineItem(BaseModel):
    """
    Schema for variables define

    name - variable name
    value - variable value
    mode - value variable interpretation mode
    """
    name: str
    value: str
    mode: DefineValueMode = DefineValueMode.JINJA

    def process(self) -> None:
        """
        execute define item at config file by mode of interpretation

        allowed modes:
            - JINJA: resolve like jinja variable
            - SHELL: resolve like shell command result
            - MANUAL: resolve like value that pass the user
        """
        storage = Storage()

        match self.mode:
            case DefineValueMode.JINJA:
                tmpl = jinja2.Environment(loader=jinja2.BaseLoader()).from_string(self.value)
                storage.pool[self.name] = tmpl.render(**storage.pool)
            case DefineValueMode.SHELL:
                proc = CmdBuilder(self.value).build()
                if proc.wait() != 0:
                    if not proc.stderr:
                        raise ValueError("process has not stderr pipe")
                    raise ConfigExecutionError(f"value \"{self.value}\" exec is "
                                               f"failed: {proc.stderr.read().decode()}")
                if not proc.stdout:
                    raise ValueError("process has not stdout pipe")

                storage.pool[self.name] = proc.stdout.read().decode()
            case DefineValueMode.MANUAL:
                storage.pool[self.name] = self.value


class PipeItem(BaseModel):
    """
    Schema for pipe task

    name - name of the script to execute
        allowed scripts stores at `scripts/v*` directory and looks like `cmd-*`
        at config file `cmd-` prefix not required
    args - arguments that will be passed to the script
    define - variables define
    as_root - run script as root
    skip - script will be skipped if True
    log - script will be logged if True
    store_result_at - store script result at defined variable
    """
    name: str
    args: dict[str, str]
    define: list[DefineItem] = []
    as_root: bool = False
    skip: bool = False
    log: bool = True
    store_result_at: str | None = None

    @validator("name")
    @classmethod
    def name_must_contain_version(cls, v: str) -> str:  # noqa: VNE001
        """
        name format example: init.sh@1
        """
        script, version = v.split("@")

        int(version)

        return v


class Config(BaseModel):
    version: int
    define: list[DefineItem]
    pipe: list[PipeItem]
