# Netlix Platform — Enterprise Improvement Plan

This document tracks findings from a comprehensive audit of the Netlix Platform project.
The goal is to make this an enterprise-grade HashiCorp reference architecture suitable for
customer demos and internal enablement.

**Architecture:** HCP Terraform Stacks (8 components, 2 deployments)

---

## Completed

| # | Item | Resolution |
|---|------|------------|
| 1 | Secrets committed to git | Removed all `.tfvars`, state files, `.terraform/` dirs |
| 2 | Terraform state files in git | Properly gitignored, HCP Terraform manages state |
| 3 | `.terraform/` binaries in git | Properly gitignored |
| 4 | Architecture split (Stacks vs Workspaces) | Committed to **Terraform Stacks** |
| 5 | Provider version constraints too loose | Using `~>` pessimistic constraints in providers |
| 6 | Missing tags (Sentinel would block) | `default_tags` in AWS provider config |
| 7 | No `deletion_protection` on critical resources | RDS: multi-AZ, deletion protection, final snapshot for non-dev envs |
| 8 | Sentinel test coverage incomplete | All 6 policies now have pass/fail tests with mock data |
| 10 | CI references non-existent Go code | CI validates 8 Terraform components + format check + Sentinel tests |
| 11 | No `CODEOWNERS` file | Created `.github/CODEOWNERS` with team ownership rules |
| 13 | Hardcoded values in K8s manifests | Kustomize overlays for dev/staging with environment patches |
| 14 | Single NAT gateway | Multi-NAT for non-dev envs (`single_nat_gateway = environment == "dev"`) |
| 16 | VPC flow logs not implemented | Networking component has flow logs |
| 18 | EKS endpoint without CIDR restriction | Configurable via `cluster_endpoint_public_access_cidrs`; staging uses private-only |
| 28 | No `terraform fmt` CI check | CI has format check job for components + bootstrap |
| 30 | Inconsistent `required_version` | Standardized across all components (`>= 1.9`) |

---

## Phase 5 — Enterprise Hardening

### Container & Workload Security

| # | Item | Status | Resolution |
|---|------|--------|------------|
| 31 | Dockerfile runs as root | Done | Switched to `distroless/static-debian12:nonroot`, `USER nonroot:nonroot` |
| 32 | No `securityContext` on pods | Done | Added pod-level (`runAsNonRoot`, `runAsUser: 65532`, `seccompProfile: RuntimeDefault`) and container-level (`allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `drop: ALL`) to web + api |
| 33 | No container image scanning in CI/CD | Done | Trivy scan (CRITICAL/HIGH) in CI (`image-scan` job) and CD (gate before GHCR push) |
| 34 | No Kubernetes NetworkPolicies | Done | Default-deny + explicit allow for web/api (DNS, Consul, Vault, Datadog egress) |
| 35 | No Pod Security Standards on namespace | Done | Namespace manifest: enforce baseline, warn+audit restricted |
| 36 | Bootstrap IAM role uses AdministratorAccess | Done | Scoped inline policy: EC2, EKS, RDS, Route53, ACM, IAM, KMS, CloudWatch, SNS, STS |
| 37 | Vault TFC policy is `path "*"` with sudo | Won't fix | HCP Vault requires full access at parent namespace for cross-namespace operations; scoped paths don't propagate to child namespaces |

### CI/CD Maturity

| # | Item | Status | Resolution |
|---|------|--------|------------|
| 38 | CD pipeline commits directly to main | Done | Branch-based gitops: CD triggers on `dev`/`staging` branches, promotion via PR workflow |
| 39 | No manifest validation in CI | Done | `kubeconform` validates rendered Kustomize overlays (dev/staging) in CI; skips Vault CRDs |
| 40 | No promotion strategy between envs | Done | Manual promotion workflow (`promote.yaml`): dev→staging→main with PR review gate |
| 41 | Staging image tag is `latest` | Done | SHA-pinned tags per environment (`staging-<sha>`), set by branch-aware CD |

### Observability

| # | Item | Status | Resolution |
|---|------|--------|------------|
| 42 | Datadog configured but agent not deployed | Done | Replaced with AWS CloudWatch Container Insights (EKS addon); IRSA role for agent; removed all Datadog config |
| 43 | No alerting or SLO definitions | Done | 10 CloudWatch alarms (pod CPU/memory/restarts, node CPU/memory, RDS, VPC flow logs); SNS notifications |
| 44 | VPC Flow Logs not analyzed | Done | CloudWatch metric filter on REJECT actions + alarm (>100 rejected/5min); SNS notifications |
| 48 | No observability dashboard | Done | CloudWatch dashboard with 6 rows: cluster, pods, health, RDS, network, alarm status |

### Performance & Load Testing

| # | Item | Status | Resolution |
|---|------|--------|------------|
| 47 | No load testing framework | Done | Distributed Locust setup (master + workers) on EKS; GitHub Actions workflow with configurable thresholds; validates HPA autoscaling |

### Disaster Recovery

| # | Item | Status | Resolution |
|---|------|--------|------------|
| 45 | No EKS cluster backup (Velero) | TODO | Add Velero for CRD/ConfigMap backup |
| 46 | No cross-region RDS replica | TODO | Add read replica or cross-region backup copy |

---

## Remaining — Medium Priority

### 9. Sentinel `enforce-cost-limit` Top-Level Print

The `if` block after the `main` rule uses top-level imperative code. While valid Sentinel,
it could be cleaner as a helper rule with `when` clause. Cosmetic only.

### 19. Vault Admin Policy Too Broad

`path "*"` with full sudo capabilities in `terraform/components/vault-config/auth.tf`.
This is intentional for the bootstrap userpass admin account, but should be documented
as bootstrap-only. For production, create a scoped admin policy.

---

## Remaining — Low Priority (Operational Excellence)

| # | Item | Recommendation |
|---|------|----------------|
| 12 | No `CLAUDE.md` project instructions | Add project conventions file |
| 17 | No Terraform tests (`.tftest.hcl`) | Add integration tests for critical components |
| 23 | No ResourceQuotas | Add per-namespace quotas in K8s manifests |
| 24 | No PodDisruptionBudgets | Add PDBs for web/api workloads |
| 25 | No HorizontalPodAutoscaler | Add HPA for production |
| 29 | No pre-commit hooks | Add `.pre-commit-config.yaml` |
| 34 | No `.terraform-docs.yml` | Add for auto-generated module docs |

---

## Implementation Progress

### Phase 1 — Security & Architecture (done)

- [x] Remove all secrets from repo
- [x] Commit to Terraform Stacks architecture
- [x] Create 8 Stack components with dependency wiring
- [x] Configure OIDC workload identity (no static credentials)
- [x] Set up HCP Terraform variable sets
- [x] Bootstrap AWS OIDC trust
- [x] Update `.gitignore` for Stacks
- [x] Update CI workflow
- [x] Update README for Stacks

### Phase 2 — Governance (done)

- [x] Fix existing broken Sentinel tests (missing mock files)
- [x] Add tests for `enforce-cost-limit`, `no-public-s3-buckets`, `require-vpc-flow-logs`
- [x] Integrate Sentinel tests into main CI workflow

### Phase 3 — Hardening (done)

- [x] Kustomize overlays for K8s manifests (dev/staging)
- [x] Parameterize Datadog monitoring (cluster name, environment tags)
- [x] Add CODEOWNERS
- [x] EKS public endpoint CIDR restriction (configurable per deployment)
- [x] Fix RDS protection logic (was checking for "production", now checks `!= "dev"`)

### Phase 4 — Operational Excellence (done)

- [x] Add pre-commit hooks (`.pre-commit-config.yaml`)
- [x] Add CLAUDE.md project conventions
- [x] Add PodDisruptionBudgets for web/api
- [x] Add HorizontalPodAutoscalers (CPU 70%, memory 80%, 2-10 replicas)
- [x] Add ResourceQuota for consul namespace
- [x] Add Terraform tests (`.tftest.hcl`) for networking, dns, eks, rds
- [x] Add `.terraform-docs.yml` for auto-generated module docs
- [x] Fix networking NAT gateway logic (was checking `"production"`, now `"dev"`)

---

## Phase 6 — Vault Security Hardening (in flight)

Checkpoint tag before starting: `checkpoint/pre-phase1-vault-rotation-2026-04-30-dev`.

### Goals

Three items from the cross-cutting audit (Phase 5 follow-up), sequenced to minimize migration
risk and to give the demo a coherent "least-privilege + live rotation" narrative:

- **6.1** — Per-service Vault policies (least-privilege)
- **6.2** — JWT signing-key rotation (N+1 keys, no pod restart)
- **6.3** — Root token hygiene (non-root admin for ongoing TF, documented rotation)

Each item is committed separately; each is independently revertible. None of them remove
existing roles/policies until the new ones are proven — old `netlix-vso` and `netlix-app`
policies stay in place as backstops during migration.

### 6.1 — Per-service Vault policies (foundation)

**Problem:** [terraform/components/vault-config/policies.tf:8](terraform/components/vault-config/policies.tf#L8) — both `netlix-vso`
and `netlix-app` grant `secret/data/netlix/*` (wildcard). Compromise of any service
exposes every secret in `secret/netlix/*` (db, jwt, grafana admin, feature flags).
Today VSO authenticates *once* with this wildcard role and syncs everything.

**Approach:** Keep VSO's centralized-pull model, but split by *secret class* via per-secret
ServiceAccounts that VSO impersonates. Each secret class gets its own Vault role + policy
scoped to a single KVv2 / PKI path.

**Resources to add:**

| Service Account (consul) | VaultAuth CRD (consul)   | Vault role (env)     | Vault policy                | Grants                                   |
| ------------------------ | ------------------------ | -------------------- | --------------------------- | ---------------------------------------- |
| `vso-shop-db`            | `vault-auth-shop-db`     | `netlix-shop-db`     | `netlix-shop-db-reader`     | read `secret/data/netlix/db`             |
| `vso-shop-jwt`           | `vault-auth-shop-jwt`    | `netlix-shop-jwt`    | `netlix-shop-jwt-reader`    | read `secret/data/netlix/jwt`            |
| `vso-shop-config`        | `vault-auth-shop-config` | `netlix-shop-config` | `netlix-shop-config-reader` | read `secret/data/netlix/featureflags`   |
| `vso-shop-pki`           | `vault-auth-shop-pki`    | `netlix-shop-pki`    | `netlix-shop-pki-issuer`    | `pki_int/issue/netlix-app` (create only) |

**Migration steps (each safe to revert):**

1. Add 4 SAs in [app/manifests/base/vso-impersonators.yaml](app/manifests/base/vso-impersonators.yaml) (new file)
2. Add 4 Vault auth roles + 4 policies in [terraform/components/vault-config/](terraform/components/vault-config/) (new files: `policies-per-service.tf`, `auth-per-service.tf`)
3. Add 4 VaultAuth CRDs in [app/manifests/base/vault-auth-per-secret.yaml](app/manifests/base/vault-auth-per-secret.yaml) (new file)
4. Switch [app/manifests/shop/vault-secrets.yaml](app/manifests/shop/vault-secrets.yaml) `vaultAuthRef`: `default` → per-secret name
5. Same for [app/manifests/shop/feature-flags.yaml](app/manifests/shop/feature-flags.yaml) and [app/manifests/shop/pki-secrets.yaml](app/manifests/shop/pki-secrets.yaml)
6. Old `netlix-vso` policy/role kept in place (becomes unused but doesn't break anything)

**Reversibility:** revert the manifest commit → VaultStaticSecrets fall back to `default` VaultAuth → `netlix-vso` wildcard role still works.

### 6.2 — JWT signing-key rotation (N+1 keys, hot-reload)

**Problem:** [auth/main.go:107-121](app/services/auth/main.go#L107) reads `JWT_SIGNING_KEY` once at startup;
[orders/main.go:151-171](app/services/orders/main.go#L151) does the same. Rotating the key in Vault breaks every
pre-rotation token until both services are fully re-rolled.

**Approach:** Mirror the feature-flag pattern (worked great there):
- Vault KVv2 stores a key-set: `{"keys": [{"id":"v2","key":"...","status":"primary"}, {"id":"v1","key":"...","status":"verifying"}]}`
- VSO syncs to a K8s Secret with one key `keys.json`
- Auth + orders mount the Secret as a *file* (no env var), poll every 30 s
- Auth signs with the `primary` key, sets `kid` JWT header
- Orders verifies by `kid` (looks up matching key in current set), accepts both `primary` and `verifying` keys
- Rotation procedure: `vault kv put secret/netlix/jwt keys=...` — both pods pick up within ~60 s, no restart, in-flight tokens stay valid

**Backwards compatibility:** Tokens with no `kid` header (old format) fall through to the primary key, so existing sessions keep working through the upgrade.

**File changes:**
- Edit [terraform/components/vault-config/kv.tf:38-46](terraform/components/vault-config/kv.tf#L38) — multi-key structure with `lifecycle.ignore_changes = [data_json]`
- Edit [app/manifests/shop/vault-secrets.yaml:69-73](app/manifests/shop/vault-secrets.yaml#L69) — VSO template writes `keys.json` file, not env var
- Edit [app/manifests/shop/auth.yaml](app/manifests/shop/auth.yaml) — mount `shop-jwt` as a volume, drop `envFrom: shop-jwt`
- Edit [app/manifests/shop/orders.yaml](app/manifests/shop/orders.yaml) — same volume mount
- New: [app/services/auth/jwks.go](app/services/auth/jwks.go) — `JWKSManager` with file watcher, sign/verify helpers
- New: [app/services/orders/jwks.go](app/services/orders/jwks.go) — verify-only JWKS helper
- Edit [app/services/auth/main.go](app/services/auth/main.go) and [auth/jwt.go](app/services/auth/jwt.go) — use JWKS instead of single key
- Edit [app/services/orders/main.go](app/services/orders/main.go) — use JWKS verifier

**Reversibility:** revert source + manifest commit. Existing tokens still verify with the primary key.

### 6.3 — Root token hygiene

**Problem:** [terraform/workspaces/vault-cluster/providers.tf:35-39](terraform/workspaces/vault-cluster/providers.tf#L35) uses `var.vault_root_token` for every TF apply. The token is in HCP TF state forever and never rotated.

**Approach (low-risk):** Don't try to automate root rotation — that's how you accidentally lock yourself out. Instead:

1. Add a `vault_token` resource that issues a long-lived (1 year), renewable, **non-root** admin token from the existing admin policy
2. Output it (sensitive)
3. Document the manual rotation procedure in [docs/vault-root-rotation.md](docs/vault-root-rotation.md):
    - First apply: bootstraps with `var.vault_root_token` as today
    - Operator copies the new admin token from `terraform output -raw tf_admin_token` into HCP TF workspace var `vault_root_token`
    - Re-apply: provider now uses non-root admin token
    - Operator runs `vault operator generate-root` to issue a fresh root token (recovery key quorum)
    - Operator runs `vault token revoke -accessor <old-root-accessor>` to invalidate the original
4. Add audit-log query example in the doc — proves the rotation is observable

**Reversibility:** revert the resource + remove the doc. No actual cluster state changes happen until the operator runs the manual procedure.

### Order of operations

1. **Commit A — `feat(vault): per-service Vault policies (Phase 6.1)`**: adds new resources, no behavior change yet
2. **Commit B — `feat(vault): switch VaultStaticSecrets to per-service auth (Phase 6.1 cutover)`**: flips `vaultAuthRef` on each secret one at a time. Validate each in Loki + `kubectl get secret`.
3. **Commit C — `feat(vault): JWT N+1 key rotation (Phase 6.2)`**: depends on the `netlix-shop-jwt-reader` policy from A; multi-key structure + JWKS code
4. **Commit D — `feat(vault): non-root admin token + rotation runbook (Phase 6.3)`**: independent, just adds Terraform resource + docs

Each commit lands on `dev`, gets applied via HCP TF, validated, then we proceed to the next.
