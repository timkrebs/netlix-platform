# Netlix Platform — Project Conventions

## Architecture

This is an **HCP Terraform Stacks** project. All infrastructure is defined as Stack components
under `terraform/components/`, orchestrated by root-level `.tfcomponent.hcl` and `.tfdeploy.hcl` files.

- **Do not add `provider` blocks** inside component modules — providers are configured at the Stack level in `providers.tfcomponent.hcl`
- **Do not add `backend` or `cloud` blocks** — HCP Terraform Stacks manages state automatically
- Components must declare `versions.tf` with `required_version >= 1.9` and required providers

## Environments

Two deployments: `dev` and `staging`, defined in `deployments.tfdeploy.hcl`.

- `dev`: relaxed settings (single NAT, no deletion protection, public EKS endpoint)
- `staging`: production-like (multi-NAT, deletion protection, private-only EKS endpoint)

Environment checks should use `var.environment == "dev"` or `var.environment != "dev"`,
never `== "production"` (that environment doesn't exist).

## Credentials

All credentials use OIDC workload identity or HCP Terraform variable sets.
**Never commit static credentials, tokens, or API keys.**

- AWS: OIDC identity token via `assume_role_with_web_identity`
- HCP: variable set `netlix-hcp`
- Vault: variable set `netlix-vault`

## Sentinel Policies

6 policies in `sentinel/policies/`. Every policy must have pass/fail tests in
`sentinel/test/<policy-name>/` with mock data files.

## Kubernetes Manifests

App manifests in `app/` use Kustomize overlays (`app/overlays/dev/`, `app/overlays/staging/`)
for environment-specific values. Base manifests should not contain hardcoded environment values.

## Naming Conventions

- Terraform variables: `snake_case`
- Stack components: `snake_case` (e.g., `vault_config`, `hvn_peering`)
- Component directories: `kebab-case` (e.g., `vault-config`, `hvn-peering`)
- Kubernetes resources: `kebab-case`
- AWS resource names: `{project}-{environment}` prefix (e.g., `netlix-dev`)

## Testing

- `terraform fmt -check -recursive` for formatting
- `terraform validate` for each component (CI matrix)
- `sentinel test -verbose` for policy tests
- Kustomize: `kubectl kustomize app/overlays/dev/` to verify overlays
