# Testing

This module is tested with the native [`terraform test`](https://developer.hashicorp.com/terraform/language/tests)
and `tofu test` frameworks. GitHub Actions runs both engines against the root
module and the internal RBAC child module on every pull request, on pushes to
`main`, and when manually dispatched (see
`.github/workflows/terraform-test.yaml`).

## What runs in CI

| Engine | Commands | Purpose |
| ------ | -------- | ------- |
| Terraform | `terraform fmt -check -recursive`, `terraform init -backend=false`, `terraform validate`, `terraform test` | Formatting, configuration validity, and module behavior |
| OpenTofu | `tofu fmt -check -recursive`, `tofu init -backend=false`, `tofu validate`, `tofu test` | The same checks, independently verified for OpenTofu compatibility |

CI selects the latest stable OpenTofu release matching `1.x`; this is a
floating version and can advance as new 1.x releases are published. OpenTofu
v1.13.9 was a specifically verified release, not the CI version pin.

## How the tests work

- Root module tests live in `tests/`; the internal RBAC module has a direct
  test in `modules/rbac_role/tests/`. Test files end in `.tftest.hcl`.
- Every test file declares `mock_provider` blocks. Mocked providers never call
  Azure: no credentials are needed and **no real resources are created**.
  Resource attributes that Azure would compute (for example `id`) get generated
  fake values.
- Each `run` block plans (`command = plan`) or "applies" against the mocks
  (`command = apply`) with a set of input variables, then checks the result with
  `assert` blocks.
- `expect_failures` can be used to verify that a variable validation or
  precondition rejects invalid input.
- Data sources and nested modules that would need real lookups can be replaced
  with `override_data` / `override_module`.
- The shared NSG module source uses the explicit `registry.terraform.io`
  hostname in the OpenTofu job's disposable working copy because OpenTofu
  otherwise resolves an unqualified module source against its own registry.
  The original source address and downloaded module implementation are
  unchanged. `scripts/prepare-opentofu.sh` changes only the source attribute in
  the unique `module "nsgs"` block in the shared workflow's disposable
  directory. Its regression tests reject changed targets or sources, duplicate
  blocks or source attributes, and commented decoys without mutating rejected
  fixtures. This checks OpenTofu using the Terraform Registry; it does not
  verify whether the NSG module is published in the OpenTofu Registry.
- Role-assignment creation is tested directly in `modules/rbac_role/tests/`,
  so the root test need not rely on how an engine represents a child module
  that has no outputs.

These are unit-style tests: they verify how the module turns inputs into
resource configuration. They do not prove that Azure accepts the configuration;
that still happens when a consuming workload runs `terraform plan`/`apply`.

The root suite exercises the real registry NSG module with mocked Azure
resources. Its source-port regression omits `source_port_range` in a custom rule
and also covers explicit null, wildcard, a single range, and comma-separated
ports alongside plural destination ports and address prefixes. Omitted/null
source ports must default to `"*"` before reaching the dependency; explicit
ports must remain unchanged.

## Writing a test

```hcl
mock_provider "azurerm" {}

variables {
  resource_group_name = "rg-test"
}

run "defaults" {
  command = plan

  assert {
    condition     = azurerm_example.this.name == "expected"
    error_message = "Name should default to 'expected'."
  }
}

run "rejects_invalid_input" {
  command = plan

  variables {
    some_setting = "not-allowed"
  }

  expect_failures = [var.some_setting]
}
```

Guidelines:

- Add or update a test whenever you change behaviour, defaults or validation.
- Use obviously fake values (`rg-test`, `00000000-0000-0000-0000-000000000000`,
  documentation IP ranges such as `192.0.2.0/24`). Never use real subscription
  IDs, tenant IDs, names or addresses — this repository is public.
- Prefer one behaviour per `run` block with a descriptive name.

## Running locally

Requires Terraform >= 1.7, OpenTofu with native test support, Python 3, and
Git Bash on Windows for the shell examples below.

The source-preparation regression tests run in CI as part of the OpenTofu
preparation step. The root OpenTofu suite must run from a disposable copy with
the NSG module source qualified as
`registry.terraform.io/miljodir/nsg/azurerm`; CI performs this guarded
adjustment automatically. The local recipe below uses `git archive HEAD`, so it
includes only committed files and excludes uncommitted edits. Do not change the
tracked source line for this compatibility step.

```sh
(
set -euo pipefail
terraform init -backend=false
terraform test            # all tests
terraform test -verbose   # include plan output
# Terraform's test-file filter uses platform-specific path separators.
filter='tests/virtual_network.tftest.hcl'
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -s)" == CYGWIN* ]]; then
  filter='tests\virtual_network.tftest.hcl'
fi
test_output="$(terraform test -no-color -filter="$filter" 2>&1)" || {
  printf '%s\n' "$test_output"
  exit 1
}
printf '%s\n' "$test_output"
if ! printf '%s\n' "$test_output" | grep -Eq 'Success! [1-9][0-9]* passed'; then
  echo "Terraform did not report any passing tests for the selected file." >&2
  exit 1
fi
terraform -chdir=modules/rbac_role init -backend=false -test-directory=tests
terraform -chdir=modules/rbac_role test -test-directory=tests
# Use the following in Git Bash on Windows to create the OpenTofu working copy.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git archive HEAD | tar -x -C "$tmp"
python3 "$tmp/scripts/qualify_nsg_source.py" "$tmp/main.tf"
(
  set -euo pipefail
  cd "$tmp"
  tofu init -backend=false
  test_output="$(tofu test -no-color 2>&1)" || {
    printf '%s\n' "$test_output"
    exit 1
  }
  printf '%s\n' "$test_output"
  if ! printf '%s\n' "$test_output" | grep -Eq 'Success! [1-9][0-9]* passed'; then
    echo "OpenTofu did not report any passing tests for the root module." >&2
    exit 1
  fi
)
tofu -chdir=modules/rbac_role init -backend=false -test-directory=tests
tofu -chdir=modules/rbac_role test -test-directory=tests
python3 scripts/tests/test_qualify_nsg_source.py
)
```
