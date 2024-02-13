import pathlib


PROJECT_DIR = pathlib.Path(__file__).parent.parent.parent
SCRIPTS_DIR = pathlib.Path(f"{PROJECT_DIR}/scripts")

SCRIPTS_REGISTRY: dict[str, str] = {}

if not SCRIPTS_REGISTRY:
    for version in SCRIPTS_DIR.glob("v*"):
        for script in version.glob("cmd-*"):
            script_name = script.name
            script_label = script_name.removeprefix("cmd-")
            script_version = version.name.removeprefix("v")

            SCRIPTS_REGISTRY[f"{script_label}@{script_version}"] = str(script)


class ConfigError(Exception):
    pass


class ConfigVersionError(ConfigError):
    pass


class ConfigValidationError(ConfigError):
    pass


class ConfigExecutionError(ConfigError):
    pass


class ScriptNotFoundError(ConfigError):
    pass
