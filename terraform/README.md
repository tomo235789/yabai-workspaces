# Terraform — GitHub repo configuration

Manages **non-secret** repository settings as code: branch protection (CI must
pass + PR required before merging to `main`) and Actions permissions.

The signing / notarization **secrets are NOT managed here** — set them with
`gh secret set` (below) so their plaintext never lands in Terraform state.

## Apply

```sh
cd terraform
export GITHUB_TOKEN=ghp_xxx          # PAT with repo admin scope (or a GitHub App)
cp terraform.tfvars.example terraform.tfvars   # edit if needed
terraform init
terraform plan
terraform apply
```

`terraform.tfvars` and `*.tfstate` are gitignored. Commit `.terraform.lock.hcl`.

## Secrets (set once, outside Terraform)

The release workflow (`.github/workflows/release.yml`) needs these. Set them with
the GitHub CLI so nothing sensitive touches Terraform state — see
[RELEASING.md](../RELEASING.md) for how to obtain each value:

```sh
gh secret set SIGNING_CERTIFICATE_P12_BASE64 < devid.p12.base64
gh secret set SIGNING_CERTIFICATE_PASSWORD
gh secret set SIGNING_IDENTITY
gh secret set NOTARY_APPLE_ID
gh secret set NOTARY_TEAM_ID
gh secret set NOTARY_PASSWORD
```

## Notes

- `ci_check_name` must match the job name in `.github/workflows/ci.yml`
  (`Build, test & lint`). Change both together if you rename the job.
- Branch protection's required check only enforces once the check has run at
  least once on the branch.
- If you later want approvals or a gated `release` environment, add
  `github_repository_environment` / raise `required_approving_review_count`.
