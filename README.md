# Netlix Platform

**Netlix** is a production-grade reference architecture showcasing HashiCorp technologies in a real-world AWS deployment. It simulates a SaaS startup running its platform on Kubernetes, demonstrating the complete HCP Terraform Stacks workflow — from VCS-driven runs through Sentinel policy checks and cost estimation to automated multi-environment infrastructure provisioning — integrated with HCP Vault Dedicated for secrets management, dynamic database credentials, and PKI certificate issuance.

**Domain:** [netlix.dev](https://netlix.dev)

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Infrastructure as Code | HCP Terraform (Stacks) |
| Policy as Code | Sentinel |
| Secrets Management | HCP Vault Dedicated |
| Secrets Delivery | Vault Secrets Operator (VSO) |
| GitOps | ArgoCD |
| Container Orchestration | Amazon EKS |
| Database | Amazon RDS (PostgreSQL) |
| Observability | Datadog |
| CI/CD | GitHub Actions |

## Architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │               HCP Terraform Stack               │
                    │                                                 │
                    │  Variable Sets:                                 │
                    │    netlix-vault  (Vault admin token)            │
                    │    netlix-hcp    (HCP service principal)        │
                    │                                                 │
                    │  Identity Tokens:                               │
                    │    aws (OIDC workload identity — no static keys)│
                    │                                                 │
                    │  Components:           Dependency Graph:        │
                    │    dns             ──── Route53 + ACM           │
                    │    networking      ──── VPC + subnets + NAT     │
                    │    eks            ◄──── EKS + IRSA + KMS       │
                    │    hvn_peering    ◄──── HCP Vault ↔ VPC        │
                    │    rds            ◄──── PostgreSQL + KMS        │
                    │    vault_config   ◄──── PKI, K8s auth, DB, KV  │
                    │    vso            ◄──── Vault Secrets Operator  │
                    │    argocd         ◄──── GitOps delivery         │
                    │                                                 │
                    │  Deployments:                                   │
                    │    dev     (10.0.0.0/16, m6i.large, t4g.medium)│
                    │    staging (10.1.0.0/16, m6i.large, m6i.large) │
                    └─────────────────────────────────────────────────┘
```

## Repository Structure

```
netlix-platform/
├── variables.tfcomponent.hcl       # Stack-level input variables
├── providers.tfcomponent.hcl       # Provider configurations (OIDC, Vault, Helm, K8s)
├── components.tfcomponent.hcl      # 8 component definitions + dependency wiring
├── outputs.tfcomponent.hcl         # Stack outputs
├── deployments.tfdeploy.hcl        # dev + staging deployment configs
├── .terraform-version              # Terraform 1.14.5
│
├── terraform/components/
│   ├── networking/                 # VPC, subnets, NAT, flow logs
│   ├── dns/                        # Route53 hosted zone, ACM wildcard cert
│   ├── eks/                        # EKS cluster, IRSA, KMS encryption
│   ├── rds/                        # PostgreSQL, KMS, monitoring, perf insights
│   ├── hvn-peering/                # HCP Vault HVN ↔ AWS VPC peering
│   ├── vault-config/               # PKI CAs, K8s auth, DB engine, KV, policies
│   ├── vso/                        # Vault Secrets Operator (Helm)
│   └── argocd/                     # ArgoCD + GitOps Application
│
├── bootstrap/                      # One-time AWS OIDC trust setup
├── sentinel/                       # 6 Sentinel policies + test fixtures
│   ├── policies/
│   └── test/
├── app/                            # Kubernetes manifests
│   ├── web/                        # Web frontend (fake-service)
│   ├── api/                        # Backend API (fake-service)
│   └── mesh/                       # Consul intentions + proxy defaults
├── kubernetes/
│   ├── helm/                       # Helm values (Consul, osquery)
│   └── monitoring/                 # Datadog agent + setup
└── .github/workflows/              # CI, release, Sentinel tests
```

## Prerequisites

- [Terraform CLI](https://developer.hashicorp.com/terraform/install) >= 1.14.5
- [HCP Terraform](https://app.terraform.io) organization with Stacks enabled
- [HCP](https://portal.cloud.hashicorp.com) account with Vault Dedicated cluster
- AWS account with IAM permissions
- GitHub repository connected to HCP Terraform

## Getting Started

### Phase 0 — Bootstrap AWS OIDC Trust

This creates the IAM OIDC provider and roles that allow HCP Terraform Stacks to authenticate
to AWS without static credentials.

```bash
cd bootstrap
terraform init
terraform apply
```

This creates:
- IAM OIDC provider for `app.terraform.io`
- `tfc-netlix-dev` IAM role (scoped to dev Stack deployment)
- `tfc-netlix-staging` IAM role (scoped to staging Stack deployment)

### Phase 1 — HCP Terraform Setup

1. Create organization `tim-krebs-org` in HCP Terraform
2. Connect GitHub repository via the HCP Terraform GitHub App
3. Create **variable sets**:

   | Variable Set | Variables | Type |
   |-------------|-----------|------|
   | `netlix-vault` | `vault_token` | Terraform (sensitive) |
   | `netlix-hcp` | `hcp_client_id`, `hcp_client_secret` | Terraform (sensitive) |

4. Create **Stack** `netlix` with VCS connection pointing to this repository
5. Create **policy set** `netlix-sentinel` pointing to `sentinel/` path

### Phase 2 — Deploy

Push to `main` and HCP Terraform will:

1. **Plan:** Resolve all 8 components in dependency order, run parallel plans
2. **Cost estimation:** Calculate monthly cost delta
3. **Sentinel:** Evaluate all 6 policies against the plan
4. **Apply:** Deploy dev and staging environments

### Phase 3 — Application Deployment

Once infrastructure is up, apply Kubernetes manifests:

```bash
aws eks update-kubeconfig --region eu-central-1 --name netlix-dev

kubectl apply -f app/mesh/proxy-defaults.yaml
kubectl apply -f app/mesh/intentions.yaml
kubectl apply -f app/web/deployment.yaml
kubectl apply -f app/api/deployment.yaml
```

ArgoCD will sync additional applications from the [netlix-gitops](https://github.com/timkrebs/netlix-gitops) repository.

## Component Dependency Graph

```
dns                                    (no dependencies)
networking                             (no dependencies)
    ├── eks                            (needs VPC, subnets)
    │   ├── rds                        (needs VPC, subnets, EKS SG)
    │   ├── vault_config               (needs EKS endpoint, OIDC, RDS creds)
    │   │   └── vso                    (needs Vault addr, namespace, auth path)
    │   └── argocd                     (needs EKS via Helm provider)
    └── hvn_peering                    (needs VPC ID, route tables)
            └── rds                    (needs HVN CIDR for SG rules)
```

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

1. **Happy path** — Push to `main` → Stacks plan → Cost estimation → Sentinel green → Auto-apply → App live
2. **Sentinel blocks** — PR with untagged resources → Policy fails → GitHub status red → Fix and re-push
3. **Cost governance** — Upsize instances → Cost limit exceeded → Admin review required
4. **Secrets rotation** — PKI cert auto-renews via VSO → DB creds rotate at 67% TTL → Zero-downtime rolling restart
5. **Multi-environment** — dev and staging deploy from the same Stack with different inputs

## Credential Management

All credentials use OIDC workload identity or HCP Terraform variable sets — **no static keys in code**.

| Credential | Source | Delivery |
|-----------|--------|----------|
| AWS access | OIDC identity token | `assume_role_with_web_identity` |
| HCP service principal | Variable set `netlix-hcp` | Ephemeral store reference |
| Vault admin token | Variable set `netlix-vault` | Ephemeral store reference |
| GitHub PAT | Deployment input | Sensitive variable |
| DB credentials | Vault database engine | Dynamic secrets via VSO |
| TLS certificates | Vault PKI engine | Auto-rotated via VSO |

## License

Private — HashiCorp demo platform.
