# Netlix Platform

**Netlix** is a production-grade reference architecture showcasing HashiCorp technologies in a real-world AWS deployment. It simulates a SaaS startup running its platform on Kubernetes, demonstrating the complete Terraform Cloud workflow — from VCS-driven runs through Sentinel policy checks and cost estimation to automated infrastructure provisioning — integrated with HCP Vault Dedicated for secrets management and Kubernetes-native delivery via VSO.

**Domain:** [netlix.dev](https://netlix.dev)

## Architecture

```
Developer → git push → GitHub → TFC Stacks → Sentinel → AWS
                                                          ├── VPC + Networking
                                                          ├── EKS Cluster
                                                          ├── RDS PostgreSQL
                                                          └── HCP Vault → VSO → ArgoCD → App
```

### Component Dependency Graph

```
networking ─────────┬──► eks ──────────┬──► vso ──► argocd
                    │                  │
                    └──► rds ──────────┘
                                       │
                           vault_config ┘
```

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Infrastructure as Code | Terraform Cloud (Stacks) |
| Policy as Code | Sentinel |
| Secrets Management | HCP Vault Dedicated |
| Secrets Delivery | Vault Secrets Operator (VSO) |
| GitOps | ArgoCD |
| Container Orchestration | Amazon EKS |
| Database | Amazon RDS (PostgreSQL) |
| CI/CD | GitHub Actions |
| Application | Go |

## Repository Structure

```
netlix-platform/
├── terraform/
│   ├── stacks/deployments/          # Stack deployment config
│   ├── components/
│   │   ├── networking/              # VPC, subnets, NAT, flow logs
│   │   ├── eks/                     # EKS cluster, IRSA roles
│   │   ├── rds/                     # PostgreSQL, encryption, security groups
│   │   ├── vault-config/            # PKI, KV, DB engine, K8s auth, policies
│   │   ├── vso/                     # Vault Secrets Operator (Helm)
│   │   └── argocd/                  # ArgoCD + Application manifest
│   └── modules/tags/                # Shared tagging module
├── sentinel/
│   ├── policies/                    # 6 Sentinel policies
│   └── test/                        # Policy test fixtures
├── app/                             # Go web application
├── bootstrap/                       # AWS OIDC trust (run once)
└── .github/workflows/               # CI, release, Sentinel tests
```

## Prerequisites

- [Terraform CLI](https://developer.hashicorp.com/terraform/install) >= 1.9
- [Terraform Cloud](https://app.terraform.io) organization with Stacks enabled
- [HCP](https://portal.cloud.hashicorp.com) account with Vault Dedicated cluster
- AWS account with IAM permissions
- GitHub repository with Actions enabled
- Go 1.22+ (for local app development)

## Getting Started

### Phase 0 — Bootstrap

1. **TFC organization** `tim-krebs-org` with Stacks + Cost Estimation enabled
2. **Set up HCP Vault Dedicated** cluster `netlix-vault` in project `netlix`
3. **Bootstrap AWS OIDC trust:**
   ```bash
   cd bootstrap
   terraform init
   terraform apply
   ```
4. **Connect GitHub** via TFC GitHub App

### Phase 1 — Governance

1. Push Sentinel policies to `sentinel/` directory
2. Create TFC policy set `netlix-sentinel` pointing to `sentinel/` path
3. Verify PR flow shows speculative plan + Sentinel checks

### Phase 2 — Core Infrastructure

1. Configure TFC Stack `netlix-dev` with VCS connection
2. Set variable sets: `netlix-aws`, `netlix-hcp`, `netlix-tags`
3. Push to `main` — TFC deploys networking → EKS → RDS

### Phase 3 — Vault + VSO

1. TFC deploys `vault-config` component (PKI, KV, DB engine, K8s auth)
2. TFC deploys `vso` component (Helm chart with default connection)
3. Set up [netlix-gitops](https://github.com/timkrebs/netlix-gitops) repo with VSO CRDs

### Phase 4 — Application

1. Build and push app image: `git tag v0.1.0 && git push --tags`
2. ArgoCD syncs from gitops repo
3. App live at `app.netlix.dev` with Vault-managed TLS and dynamic DB credentials

## Sentinel Policies

| Policy | Enforcement | Description |
|--------|------------|-------------|
| `require-mandatory-tags` | Hard | All AWS resources must have `environment`, `project`, `managed_by` tags |
| `enforce-encryption-at-rest` | Hard | RDS, EBS, and EKS must use encryption |
| `restrict-instance-types` | Soft | Only approved EC2/RDS instance families allowed |
| `enforce-cost-limit` | Soft | Monthly cost must stay under $2,000 |
| `no-public-s3-buckets` | Hard | S3 buckets must block public access |
| `require-vpc-flow-logs` | Advisory | VPCs should have flow logs enabled |

## Demo Scenarios

1. **Happy path** — Push to `main` → Stacks plan → Cost estimation → Sentinel green → Auto-apply → ArgoCD sync → App live
2. **Sentinel blocks** — PR with untagged resources → Policy fails → GitHub status red → Fix and re-push
3. **Cost governance** — Upsize instances → Cost limit exceeded → Admin review required
4. **Secrets rotation** — PKI cert auto-renews via VSO → DB creds rotate at 67% TTL → Zero-downtime rolling restart

## VCS-Driven Workflow

1. Developer pushes to `terraform/` on `main`
2. GitHub webhook notifies TFC
3. TFC queues a run for Stack `netlix-dev`
4. **Plan:** Stacks resolves components, runs parallel plans
5. **Cost estimation:** Calculates monthly delta
6. **Sentinel:** Evaluates all 6 policies
7. **Apply:** Auto-apply (dev) or manual confirm (staging)

## License

Private — HashiCorp internal demo platform.
