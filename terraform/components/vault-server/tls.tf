# ─── cert-manager TLS for Vault server ─────────────────────────────────────
#
# Chain: SelfSigned Issuer → CA Certificate → CA Issuer → Server Certificate
# The vault namespace must exist before these resources are created.
# The Helm release creates the namespace, so these depend on it implicitly
# via the kubernetes_namespace data source.

resource "kubernetes_namespace" "vault" {
  metadata {
    name = "vault"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_manifest" "selfsigned_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "vault-selfsigned"
      namespace = kubernetes_namespace.vault.metadata[0].name
    }
    spec = {
      selfSigned = {}
    }
  }
}

resource "kubernetes_manifest" "vault_ca_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "vault-ca"
      namespace = kubernetes_namespace.vault.metadata[0].name
    }
    spec = {
      isCA       = true
      commonName = "Vault CA"
      secretName = "vault-ca"
      duration   = "87600h" # 10 years
      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }
      issuerRef = {
        name  = kubernetes_manifest.selfsigned_issuer.manifest.metadata.name
        kind  = "Issuer"
        group = "cert-manager.io"
      }
    }
  }
}

resource "kubernetes_manifest" "vault_ca_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "vault-ca-issuer"
      namespace = kubernetes_namespace.vault.metadata[0].name
    }
    spec = {
      ca = {
        secretName = "vault-ca"
      }
    }
  }

  depends_on = [kubernetes_manifest.vault_ca_cert]
}

resource "kubernetes_manifest" "vault_server_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "vault-server-tls"
      namespace = kubernetes_namespace.vault.metadata[0].name
    }
    spec = {
      secretName  = "vault-server-tls"
      duration    = "8760h" # 1 year
      renewBefore = "720h"  # 30 days before expiry
      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }
      commonName = "vault.vault.svc.cluster.local"
      dnsNames = [
        "vault.vault.svc.cluster.local",
        "vault.vault.svc",
        "vault.vault",
        "vault",
        "vault-active.vault.svc.cluster.local",
        "vault-standby.vault.svc.cluster.local",
        "vault-internal.vault.svc.cluster.local",
        "*.vault-internal",
        "*.vault-internal.vault.svc.cluster.local",
        "localhost",
      ]
      ipAddresses = ["127.0.0.1"]
      issuerRef = {
        name  = kubernetes_manifest.vault_ca_issuer.manifest.metadata.name
        kind  = "Issuer"
        group = "cert-manager.io"
      }
    }
  }
}
