from loguru import logger

from altcosa.config.common import ConfigValidationError, ConfigVersionError, SCRIPTS_REGISTRY, ScriptNotFoundError
from altcosa.config.utils import CmdBuilder
from altcosa.config.v1.schema import Config


class Validator:
    def __init__(self, config: Config) -> None:
        self.config = config

    def _validate_version(self) -> None:
        if self.config.version != 1:
            raise ConfigVersionError(f"invalid version number: \"{self.config.version}\"")

    def _validate_pipe(self) -> None:
        validate_failed = False

        for item in self.config.pipe:
            if (script := SCRIPTS_REGISTRY.get(item.name)) is None:
                raise ScriptNotFoundError(f"script \"{script}\" not found")

            proc = CmdBuilder(script).args("-c").opts(**item.args).root(item.as_root).build()

            if proc.wait() != 0:
                validate_failed = True

                if proc.stderr is None:
                    raise ValueError("process has no stderr pipe")

                output = proc.stderr.read().decode()
                logger.error(f"failed to check \"{item.name}\" script arguments: {output}")

        if validate_failed:
            raise ConfigValidationError("validation is failed see the logs")

    def validate(self) -> Config:
        self._validate_version()
        self._validate_pipe()

        return self.config
