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
original='  source                    = "miljodir/nsg/azurerm"'
qualified='  source                    = "registry.terraform.io/miljodir/nsg/azurerm"'

if [[ ! -f "$source_file" || -L "$source_file" ]]; then
  echo "::error::Expected a regular root main.tf file."
  exit 1
fi

original_count="$(grep -Fxc -- "$original" "$source_file" || true)"
qualified_count="$(grep -Fxc -- "$qualified" "$source_file" || true)"
if [[ "$original_count" != "1" || "$qualified_count" != "0" ]]; then
  echo "::error::Expected exactly one unqualified NSG source and no qualified replacement."
  exit 1
fi

temporary_file="$(mktemp)"
trap 'rm -f "$temporary_file"' EXIT
awk -v original="$original" -v qualified="$qualified" '
  $0 == original { matches++; print qualified; next }
  { print }
  END { if (matches != 1) exit 1 }
' "$source_file" > "$temporary_file"
mv "$temporary_file" "$source_file"
trap - EXIT

if [[ "$(grep -Fxc -- "$qualified" "$source_file" || true)" != "1" ]]; then
  echo "::error::OpenTofu source qualification did not produce the expected root module."
  exit 1
fi

echo "Qualified the NSG registry source in the disposable root-module copy for OpenTofu."
