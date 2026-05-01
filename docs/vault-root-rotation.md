# Vault Root Token Rotation Runbook

One-time procedure to retire the initial root token used to bootstrap the
Vault cluster, replacing it with a non-root admin token for ongoing
Terraform operations.

## Why

[`terraform/workspaces/vault-cluster/providers.tf:35-39`](../terraform/workspaces/vault-cluster/providers.tf#L35-L39)
authenticates the Vault provider with `var.vault_root_token`. That token
is in HCP Terraform state, never rotated, and exists indefinitely with
unbounded capabilities. The Phase 5 enterprise-readiness audit flagged
this as the highest-impact Vault security finding.

After this rotation:

- The Vault provider authenticates as a non-root admin token managed by
  Terraform itself (`vault_token.tf_admin`).
- The original root token is revoked and unrecoverable.
- Future emergency root access goes through `vault operator generate-root`,
  which is quorum-gated by the recovery key holders and audit-logged.

## Prerequisites

- `vault` CLI installed locally
- `VAULT_ADDR` set to the cluster's external URL (e.g. `https://vault.dev.netlix.dev`)
- HCP Terraform admin access on the `netlix-vault-cluster-<env>` workspace
- Quorum of recovery-key holders available (enough to satisfy the threshold
  set at init — typically 3-of-5)
- The current root token (the one stored in HCP TF as `vault_root_token`),
  needed to perform the swap

## Procedure

### Step 1 — Confirm `vault_token.tf_admin` exists

The resource is added in [`terraform/workspaces/vault-cluster/admin-token.tf`](../terraform/workspaces/vault-cluster/admin-token.tf)
and is created automatically on the next apply after Phase 6.3 lands.
Verify state:

```bash
cd terraform/workspaces/vault-cluster
terraform state show vault_token.tf_admin | head -20
```

You should see `accessor`, `policies = ["admin-policy"]`, `renewable = true`,
and `ttl = 31536000` (1 year in seconds).

### Step 2 — Capture the new admin token

```bash
NEW_TOKEN=$(terraform output -raw tf_admin_token)
NEW_ACCESSOR=$(VAULT_TOKEN=$NEW_TOKEN vault token lookup -format=json | jq -r .data.accessor)
echo "Length: ${#NEW_TOKEN}"
echo "Accessor: $NEW_ACCESSOR"
```

The token is sensitive — never write it to disk, never paste into chat,
never put it in a non-HCP-managed file.

### Step 3 — Verify the new token works

Confirm it can perform the same operations as the root token without
actually committing the swap yet:

```bash
VAULT_TOKEN=$NEW_TOKEN vault token lookup
# expect: policies includes "admin-policy", display_name includes "tf_admin"

VAULT_TOKEN=$NEW_TOKEN vault auth list >/dev/null && echo "✓ auth list"
VAULT_TOKEN=$NEW_TOKEN vault secrets list >/dev/null && echo "✓ secrets list"
VAULT_TOKEN=$NEW_TOKEN vault policy list >/dev/null && echo "✓ policy list"
```

If any of these fail, the admin policy is missing capability — fix
[`terraform/workspaces/vault-cluster/auth.tf:15-76`](../terraform/workspaces/vault-cluster/auth.tf#L15-L76)
and re-apply before continuing.

### Step 4 — Swap the workspace variable in HCP Terraform

In the HCP Terraform UI:

1. Navigate to **netlix-vault-cluster-`<env>`** workspace
2. **Variables** tab
3. Locate `vault_root_token` (currently holds the original root)
4. Set new value to `$NEW_TOKEN` from Step 2 (mark as Sensitive)
5. Save

### Step 5 — Trigger a no-op apply to verify the swap

In HCP Terraform UI: **Actions → Start new run → Plan only**.

The plan should be empty (no resource changes). It runs the whole
state-refresh path with the new token, proving end-to-end auth works.
If the plan errors out with permission denied, **immediately revert
step 4** before proceeding — you still have the original root in case
of trouble.

### Step 6 — Issue a fresh root token via recovery keys

On a workstation with `vault` CLI:

```bash
# Initialize the generate-root flow — produces an OTP and a nonce.
vault operator generate-root -init
# Output:
#   Nonce       <nonce-uuid>
#   Started     true
#   Progress    0/3
#   Complete    false
#   OTP         <one-time-pad>
#   OTP Length  26

# SAVE the OTP locally — you'll need it to decode the final root.
```

Distribute the **nonce** (not the OTP) to recovery key holders via a
secure channel. Each holder runs:

```bash
vault operator generate-root -nonce=<nonce> <their-recovery-key-fragment>
```

After the threshold is met, Vault returns an `Encoded Token`. Decode it
locally with the OTP from the init step:

```bash
vault operator generate-root -decode=<encoded-token> -otp=<original-otp>
# Output: <new-root-token>
```

**Place the new root token in a sealed envelope or HSM**. Do not commit
it anywhere. It exists only as the break-glass credential for future
generate-root cycles.

### Step 7 — Revoke the OLD root token

You need the OLD root token's accessor. While still authenticated as
the old root:

```bash
VAULT_TOKEN=<old-root-token> vault token lookup
# Note the `accessor` field in output.
```

Then revoke it (use the new admin token to perform the revocation, so
the audit log shows who did it):

```bash
VAULT_TOKEN=$NEW_TOKEN vault token revoke -accessor <old-root-accessor>
```

### Step 8 — Verify in audit logs

```bash
# Check vault-cluster's Promtail-shipped audit logs in Grafana.
# Loki query (in Grafana → Explore):
#
#   {namespace="vault", container="vault", audit_type="response"}
#     | json
#     | request_path =~ "sys/generate-root.*|auth/token/revoke-accessor"
#
# Should show:
#   - 3+ entries for sys/generate-root/update (the recovery-key submissions)
#   - 1 entry for auth/token/revoke-accessor (Step 7)
```

In the **HashiCorp Vault Audit** Grafana dashboard, the events appear in
the live tail panel within ~30 s.

## Going forward

| When                             | Action                                                                                                                                                                          |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Quarterly                        | Run `terraform output -raw tf_admin_token \| VAULT_TOKEN=- vault token lookup` to confirm the TF admin token is healthy and TTL ≥ 6 months                                      |
| Annually                         | Rotate `vault_token.tf_admin` by tainting and re-applying (`terraform taint vault_token.tf_admin && terraform apply`), then repeat steps 2–7 with the new token                 |
| Emergency root needed            | `vault operator generate-root` (quorum-gated). Always one-shot; never store the resulting token long-term                                                                       |
| Compromise of the TF admin token | Run `VAULT_TOKEN=<new-root> vault token revoke -accessor <accessor>` (look up via `vault token lookup` first), taint the resource, apply to regenerate, then repeat steps 4–5   |

## What this commit does NOT do

- **Doesn't auto-revoke the original root.** That step is operator-driven
  by design — automating it inside Terraform creates a fail-stuck mode
  where a TF apply error halfway through could leave both tokens
  invalid, locking out the cluster.
- **Doesn't cross-cluster the rotation.** Each cluster (dev, staging,
  prod) goes through this runbook independently. The commit just
  makes the rotation possible — when to execute is up to the operator.
- **Doesn't change the user-facing auth methods.** The userpass admin
  user, JWT TFC auth, and Kubernetes auth roles are unaffected.
