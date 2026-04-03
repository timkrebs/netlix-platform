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
