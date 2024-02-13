import subprocess
import sys

import jinja2

from loguru import logger

from altcosa.config.common import SCRIPTS_REGISTRY
from altcosa.config.utils import CmdBuilder, Storage
from altcosa.config.v1.schema import Config
from altcosa.config.v1.validator import Validator


class Executor:
    def __init__(self, config: Config) -> None:
        self.config = Validator(config).validate()

    def _execute_global_define(self) -> None:
        for item in self.config.define:
            item.process()

    def _execute_pipe(self) -> None:  # noqa: C901
        storage = Storage()

        for item in self.config.pipe:
            if item.skip:
                continue

            for define_item in item.define:
                define_item.process()

            for arg_name, arg_value in item.args.items():
                tmpl = jinja2.Environment(loader=jinja2.BaseLoader()).from_string(arg_value)
                item.args[arg_name] = tmpl.render(**storage.pool)

            script = SCRIPTS_REGISTRY[item.name]
            proc = (
                CmdBuilder(script).
                opts(**item.args).
                root(item.as_root).
                stderr(subprocess.STDOUT).
                build()
            )

            if not proc.stdout:
                raise ValueError("process has not stdout pipe")

            whole_output = ""

            for output in proc.stdout:
                output = output.decode()

                if item.log:
                    print(output, end="")

                whole_output += output

            if item.store_result_at:
                storage.pool[item.store_result_at] = whole_output

            if proc.wait() != 0:
                logger.error("process is failed")
                logger.error(item.name)
                sys.exit(1)

    def execute(self) -> None:
        self._execute_global_define()
        self._execute_pipe()
