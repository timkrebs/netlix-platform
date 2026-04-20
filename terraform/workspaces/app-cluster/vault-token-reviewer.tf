# Vault runs in a separate cluster (vault-cluster). For cross-cluster
# Kubernetes auth, Vault needs to call THIS cluster's API for TokenReview
# using a delegated reviewer SA.
#
# This file:
#   1. Creates a `vault-token-reviewer` ServiceAccount in vault-secrets-
#      operator-system.
#   2. Binds it to the built-in `system:auth-delegator` ClusterRole
#      (grants permission on the TokenReview API).
#   3. Provisions a long-lived service-account-token Secret (k8s 1.24+
#      stopped auto-creating these — the legacy Secret pattern is the
#      only way to get a non-expiring JWT for an external reviewer).
#
# The JWT is then passed to vault-config via the token_reviewer_jwt
# input, and Vault uses it to authenticate every TokenReview call.

# Namespace is owned by the VSO Helm release (see ../../components/vso),
# so we don't manage it here — just reference it by name.

resource "kubernetes_service_account" "vault_token_reviewer" {
  metadata {
    name      = "vault-token-reviewer"
    namespace = "vault-secrets-operator-system"
  }
}

resource "kubernetes_cluster_role_binding" "vault_token_reviewer" {
  metadata {
    name = "vault-token-reviewer-auth-delegator"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_token_reviewer.metadata[0].name
    namespace = kubernetes_service_account.vault_token_reviewer.metadata[0].namespace
  }
}

# Long-lived token via a Secret of type kubernetes.io/service-account-token.
# This is the documented k8s 1.24+ pattern for external services that
# need a non-expiring JWT (TokenRequest API tokens have max TTL).
resource "kubernetes_secret" "vault_token_reviewer" {
  metadata {
    name      = "vault-token-reviewer-token"
    namespace = kubernetes_service_account.vault_token_reviewer.metadata[0].namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.vault_token_reviewer.metadata[0].name
    }
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

locals {
  token_reviewer_jwt = kubernetes_secret.vault_token_reviewer.data["token"]
  app_cluster_ca     = base64decode(module.eks.cluster_ca_certificate)
  app_cluster_host   = module.eks.cluster_endpoint
}
