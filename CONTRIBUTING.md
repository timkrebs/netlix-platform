# Contributing to Netlix Platform

This guide walks you through the branch-based GitOps workflow used in this project.
Every change flows through three long-lived branches before it reaches production.

## Branch Model

```
feature/xyz  or  fix/xyz          (your work)
        \                          
         \    PR + CI checks       
          \                        
           dev ──────────────────  (integration — auto-deploys to dev environment)
               \                   
                \  promotion PR    
                 \                 
                  staging ───────  (pre-release — auto-deploys to staging environment)
                         \         
                          \ promotion PR
                           \       
                            main   (production-ready code)
```

| Branch    | Purpose                        | Deploys to         | Who merges here          |
|-----------|--------------------------------|--------------------|--------------------------|
| `dev`     | Integration and daily work     | dev EKS cluster    | Any developer via PR     |
| `staging` | Pre-release validation         | staging EKS cluster| Promotion workflow only  |
| `main`    | Production-ready, tagged releases | (future prod)   | Promotion workflow only  |

## Prerequisites

- Git CLI and [GitHub CLI](https://cli.github.com/) (`gh`) installed
- Repository cloned: `git clone https://github.com/timkrebs/netlix-platform.git`
- Authenticated with GitHub: `gh auth login`

## Step-by-Step Workflow

### 1. Create a feature or fix branch

Always branch from `dev` — it is the integration branch and the default branch of this repo.

```bash
# Make sure your local dev is up to date
git checkout dev
git pull origin dev

# Create your branch
git checkout -b feature/add-health-dashboard
# or
git checkout -b fix/cors-header-missing
```

**Naming conventions:**
- `feature/<short-description>` — new functionality
- `fix/<short-description>` — bug fixes
- `chore/<short-description>` — maintenance, dependency updates, docs

### 2. Make your changes and push

```bash
# Work on your changes...
git add -A
git commit -m "feat: add health dashboard endpoint"

# Push your branch to the remote
git push -u origin feature/add-health-dashboard
```

### 3. Open a Pull Request targeting `dev`

```bash
gh pr create --base dev --title "feat: add health dashboard endpoint" --body "
## Summary
- Added /dashboard endpoint with cluster health metrics
- Integrated with existing /health and /ready probes

## Test plan
- [ ] go build passes
- [ ] Trivy scan clean
- [ ] Manual test against local server
"
```

Or use the GitHub web UI — make sure the base branch is **`dev`**, not `main`.

### 4. CI checks run automatically

When you open the PR, GitHub Actions runs these checks:

| Job                  | What it does                                  |
|----------------------|-----------------------------------------------|
| **Format check**     | `terraform fmt -check` on all components      |
| **Sentinel tests**   | Policy tests for all 6 Sentinel policies      |
| **Validate components** | `terraform validate` on each Terraform component |
| **Go build & vet**   | Compiles and vets the Go server code          |
| **Container image scan** | Builds the Docker image and scans with Trivy (fails on CRITICAL/HIGH CVEs) |

All required checks must pass before the PR can be merged.

### 5. Merge to `dev` — auto-deploy to dev environment

Once CI is green, merge the PR (squash or merge commit — your choice).

After merge, the **CD workflow** automatically:
1. Builds the Docker image from `app/server/`
2. Tags it as `dev-<commit-sha>` and pushes to GHCR
3. Scans the image with Trivy (fails the pipeline if vulnerabilities found)
4. Updates `app/overlays/dev/kustomization.yaml` with the new image tag
5. Commits the overlay change to the `dev` branch

**ArgoCD** detects the overlay change and auto-syncs the dev EKS cluster.

You can verify:
```bash
# Check the CD workflow run
gh run list --workflow=cd.yaml --branch=dev

# Check ArgoCD sync status (requires cluster access)
kubectl get application netlix-app -n argocd
```

### 6. Promote `dev` to `staging`

Once you've validated your changes in the dev environment, promote to staging.

**Using GitHub Actions UI:**
1. Go to **Actions** > **Promote** workflow
2. Click **Run workflow**
3. Select: `from: dev` / `to: staging`
4. Click **Run workflow**

**Using the CLI:**
```bash
gh workflow run promote.yaml -f from=dev -f to=staging
```

This creates a **promotion PR** from `dev` to `staging` with a summary of all commits being promoted. Review the PR, then merge it.

After merge, the CD workflow runs on the `staging` branch:
- Builds and tags the image as `staging-<commit-sha>`
- Updates `app/overlays/staging/kustomization.yaml`
- ArgoCD syncs the staging EKS cluster

### 7. Validate in staging

Staging is the pre-production environment. Run your validation:

```bash
# Smoke test the staging endpoint
curl https://app.staging.netlix.dev/health

# Check pod status
kubectl get pods -n consul --context staging
```

### 8. Promote `staging` to `main`

Once staging is validated, promote to main.

**Using GitHub Actions UI:**
1. Go to **Actions** > **Promote** workflow
2. Select: `from: staging` / `to: main`

**Using the CLI:**
```bash
gh workflow run promote.yaml -f from=staging -f to=main
```

Review and merge the promotion PR.

### 9. Tag a release

After merging to `main`, create a semantic version tag to trigger the release workflow:

```bash
git checkout main
git pull origin main
git tag -a v1.2.0 -m "release: v1.2.0 — health dashboard"
git push origin v1.2.0
```

The **Release workflow** builds the final production image, scans it with Trivy, and publishes it to GHCR with the version tag (e.g., `ghcr.io/timkrebs/netlix-platform/web:1.2.0`).

## Quick Reference

```
git checkout dev && git pull                  # Start from latest dev
git checkout -b feature/my-change             # Create branch
# ... make changes, commit, push ...
gh pr create --base dev                       # Open PR to dev
# ... CI passes, merge PR ...                 # CD auto-deploys to dev
gh workflow run promote.yaml -f from=dev -f to=staging   # Promote
# ... merge promotion PR ...                  # CD auto-deploys to staging
# ... validate staging ...
gh workflow run promote.yaml -f from=staging -f to=main  # Promote
# ... merge promotion PR ...
git tag -a v1.x.x -m "release: ..." && git push origin v1.x.x  # Release
```

## Rules

- **Never push directly to `staging` or `main`** — always use the promotion workflow
- **Never skip CI** — all checks must pass before merging
- **Always branch from `dev`** — it is the source of truth for active development
- **Pin image tags** — the CD workflow handles this automatically, never edit overlay image tags manually
- **One promotion at a time** — wait for the current promotion PR to merge before starting another

## Infrastructure Changes

If your change includes Terraform files (`terraform/`, `*.tfcomponent.hcl`, `*.tfdeploy.hcl`):
- CI validates all components and runs `terraform fmt` checks
- HCP Terraform Stacks will plan/apply infrastructure changes when the Stack detects file changes
- Test infrastructure changes in `dev` first before promoting

If your change is **app-only** (`app/server/**`), only the CD pipeline runs — no Terraform execution.

## Troubleshooting

**CI is failing on my PR:**
```bash
gh pr checks <pr-number>        # See which checks failed
gh run view <run-id> --log      # Read the full log
```

**CD didn't update the overlay:**
- Check that your change touched files in `app/server/**`
- The CD workflow only triggers on pushes to `dev` or `staging` branches

**ArgoCD isn't syncing:**
```bash
kubectl get application netlix-app -n argocd -o yaml | grep -A5 status
```

**Promotion workflow failed:**
- Ensure there are actual commits to promote (source branch must be ahead of target)
- Check the workflow run log: `gh run list --workflow=promote.yaml`
