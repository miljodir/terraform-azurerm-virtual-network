#!/usr/bin/env bash
set -euo pipefail

if [[ "${CHECK_ENGINE:-}" != "tofu" ]]; then
  exit 0
fi

if [[ "${GITHUB_ACTIONS:-}" != "true" || -z "${RUNNER_TEMP:-}" ]]; then
  echo "::error::This source adjustment is only for the shared workflow's disposable copy."
  exit 1
fi

copy_root="$(realpath -e "$RUNNER_TEMP/module-check")"
working_directory="$(pwd -P)"
if [[ "$working_directory" != "$copy_root" ]]; then
  echo "::error::Refusing to edit outside the shared workflow's root-module copy."
  exit 1
fi

source_file="main.tf"
if [[ ! -f "$source_file" || -L "$source_file" ]]; then
  echo "::error::Expected a regular root main.tf file."
  exit 1
fi

python3 scripts/tests/test_qualify_nsg_source.py
python3 scripts/qualify_nsg_source.py "$source_file"
