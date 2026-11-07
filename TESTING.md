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
- Input validation is tested with `expect_failures`, which passes only when the
  listed variable validation or precondition fails.
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

- When tests run, the module is the *root* module. Terraform then rejects
  outputs that contain sensitive attributes unless they are marked
  `sensitive = true` (consumers calling the module are not affected). Put
  test-only override files in `tests/overrides/` named `*_override.tf`, e.g.

  ```hcl
  output "storage_account" {
    sensitive = true
  }
  ```

  The shared workflow copies them into the module root after validation and
  before running tests.

These are unit-style tests: they verify how the module turns inputs into
resource configuration. They do not prove that Azure accepts the configuration;
that still happens when a consuming workload runs `terraform plan`/`apply`.

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

Requires Terraform >= 1.7 and OpenTofu with native test support.

The root OpenTofu suite must run from a disposable copy with the NSG module
source qualified as `registry.terraform.io/miljodir/nsg/azurerm`; CI performs
this guarded adjustment automatically. Do not change the tracked source line
for this local compatibility step.

```sh
terraform init -backend=false
terraform test            # all tests
terraform test -verbose   # include plan output
terraform -chdir=modules/rbac_role init -backend=false -test-directory=tests
terraform -chdir=modules/rbac_role test -test-directory=tests
# Run these root-module commands only in the disposable copy described above.
tofu init -backend=false
tofu test                  # all tests
tofu test -verbose         # include plan output
tofu -chdir=modules/rbac_role init -backend=false -test-directory=tests
tofu -chdir=modules/rbac_role test -test-directory=tests
terraform test -filter=tests/defaults.tftest.hcl
python3 scripts/tests/test_qualify_nsg_source.py
```

Remove copied `*_override.tf` files afterwards (they are git-ignored).
