#!/usr/bin/env python3

import argparse
import json

import yaml

from altcosa.config.v1.executor import Executor, Config
from altcosa.config.utils import Storage


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "config",
        help="YAML formatted config file")
    parser.add_argument(
        "--preset-file",
        help="JSON formatted file",
        default=None)

    args = parser.parse_args()

    with open(args.config) as file:
        content = yaml.safe_load(file)

    if args.preset_file:
        with open(args.preset_file) as file:
            Storage().pool.update(json.load(file))

    print(Storage().pool)
    config = Config.model_validate(content)

    Executor(config).execute()


if __name__ == "__main__":
    main()
