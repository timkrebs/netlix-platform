# ─── Vault Enterprise Helm release ─────────────────────────────────────────

locals {
  vault_namespace = kubernetes_namespace.vault.metadata[0].name
}

# ─── Encrypted StorageClass for Vault data (gp3 + KMS) ───────────────────

resource "kubernetes_storage_class" "vault_encrypted" {
  metadata {
    name = "gp3-encrypted"
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Retain"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

# Enterprise license stored as a Kubernetes Secret
resource "kubernetes_secret" "vault_license" {
  metadata {
    name      = "vault-ent-license"
    namespace = local.vault_namespace
  }

  data = {
    license = var.vault_ent_license
  }

  type = "Opaque"
}

resource "helm_release" "vault" {
  name       = "vault"
  namespace  = local.vault_namespace
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = var.vault_helm_version
  wait       = true
  timeout    = 600

  # Vault needs the TLS secret and license secret to exist before starting
  depends_on = [
    kubectl_manifest.vault_server_cert,
    kubernetes_secret.vault_license,
  ]

  # ── Global ──────────────────────────────────────────────────────────────
  set {
    name  = "global.enabled"
    value = "true"
  }

  # ── Server image ────────────────────────────────────────────────────────
  set {
    name  = "server.image.repository"
    value = "hashicorp/vault-enterprise"
  }
  set {
    name  = "server.image.tag"
    value = var.vault_image_tag
  }

  # ── Enterprise license ──────────────────────────────────────────────────
  set {
    name  = "server.enterpriseLicense.secretName"
    value = kubernetes_secret.vault_license.metadata[0].name
  }
  set {
    name  = "server.enterpriseLicense.secretKey"
    value = "license"
  }

  # ── HA mode with Raft ───────────────────────────────────────────────────
  set {
    name  = "server.ha.enabled"
    value = "true"
  }
  set {
    name  = "server.ha.replicas"
    value = tostring(var.vault_replicas)
  }
  set {
    name  = "server.ha.raft.enabled"
    value = "true"
  }
  set {
    name  = "server.ha.raft.setNodeId"
    value = "true"
  }

  # ── Raft + KMS seal configuration ──────────────────────────────────────
  set {
    name = "server.ha.raft.config"
    value = join("\n", concat(
      [
        "ui = true",
        "",
        "listener \"tcp\" {",
        "  tls_disable     = 0",
        "  address         = \"[::]:8200\"",
        "  cluster_address = \"[::]:8201\"",
        "  tls_cert_file   = \"/vault/userconfig/vault-server-tls/tls.crt\"",
        "  tls_key_file    = \"/vault/userconfig/vault-server-tls/tls.key\"",
        "  tls_client_ca_file = \"/vault/userconfig/vault-server-tls/ca.crt\"",
        "}",
        "",
        "storage \"raft\" {",
        "  path = \"/vault/data\"",
      ],
      # Generate retry_join blocks dynamically based on vault_replicas
      flatten([for i in range(var.vault_replicas) : [
        "  retry_join {",
        "    leader_api_addr         = \"https://vault-${i}.vault-internal:8200\"",
        "    leader_ca_cert_file     = \"/vault/userconfig/vault-server-tls/ca.crt\"",
        "    leader_client_cert_file = \"/vault/userconfig/vault-server-tls/tls.crt\"",
        "    leader_client_key_file  = \"/vault/userconfig/vault-server-tls/tls.key\"",
        "  }",
      ]]),
      [
        "}",
        "",
        "seal \"awskms\" {",
        "  region     = \"${var.aws_region}\"",
        "  kms_key_id = \"${aws_kms_key.vault_unseal.key_id}\"",
        "}",
        "",
        "service_registration \"kubernetes\" {}",
      ],
    ))
  }

  # ── TLS volume from cert-manager secret ─────────────────────────────────
  set {
    name  = "server.volumes[0].name"
    value = "vault-server-tls"
  }
  set {
    name  = "server.volumes[0].secret.secretName"
    value = "vault-server-tls"
  }
  set {
    name  = "server.volumeMounts[0].name"
    value = "vault-server-tls"
  }
  set {
    name  = "server.volumeMounts[0].mountPath"
    value = "/vault/userconfig/vault-server-tls"
  }
  set {
    name  = "server.volumeMounts[0].readOnly"
    value = "true"
  }

  # ── Environment variables ───────────────────────────────────────────────
  set {
    name  = "server.extraEnvironmentVars.VAULT_CACERT"
    value = "/vault/userconfig/vault-server-tls/ca.crt"
  }
  set {
    name  = "server.extraEnvironmentVars.VAULT_ADDR"
    value = "https://127.0.0.1:8200"
  }
  set {
    name  = "server.extraEnvironmentVars.VAULT_SKIP_VERIFY"
    value = "false"
  }

  # ── Service account with IRSA annotation ────────────────────────────────
  set {
    name  = "server.serviceAccount.create"
    value = "true"
  }
  set {
    name  = "server.serviceAccount.name"
    value = "vault"
  }
  set {
    name  = "server.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.vault_kms_irsa.iam_role_arn
  }

  # ── Data storage (encrypted gp3 via EBS CSI) ────────────────────────────
  set {
    name  = "server.dataStorage.enabled"
    value = "true"
  }
  set {
    name  = "server.dataStorage.size"
    value = "10Gi"
  }
  set {
    name  = "server.dataStorage.storageClass"
    value = kubernetes_storage_class.vault_encrypted.metadata[0].name
  }

  # ── Audit storage (encrypted gp3 via EBS CSI) ─────────────────────────
  set {
    name  = "server.auditStorage.enabled"
    value = "true"
  }
  set {
    name  = "server.auditStorage.size"
    value = "10Gi"
  }
  set {
    name  = "server.auditStorage.storageClass"
    value = kubernetes_storage_class.vault_encrypted.metadata[0].name
  }

  # ── Resources ───────────────────────────────────────────────────────────
  set {
    name  = "server.resources.requests.cpu"
    value = "250m"
  }
  set {
    name  = "server.resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "server.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "server.resources.limits.memory"
    value = "512Mi"
  }

  # ── Pod anti-affinity (soft — spread across nodes) ──────────────────────
  set {
    name = "server.affinity"
    value = yamlencode({
      podAntiAffinity = {
        preferredDuringSchedulingIgnoredDuringExecution = [
          {
            weight = 100
            podAffinityTerm = {
              labelSelector = {
                matchLabels = {
                  "app.kubernetes.io/name"     = "vault"
                  "app.kubernetes.io/instance" = "vault"
                  component                    = "server"
                }
              }
              topologyKey = "kubernetes.io/hostname"
            }
          }
        ]
      }
    })
  }

  # ── Service: ClusterIP (internal only — ALB Ingress handles external) ──
  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  # ── UI ──────────────────────────────────────────────────────────────────
  set {
    name  = "ui.enabled"
    value = "true"
  }
  set {
    name  = "ui.activeVaultPodOnly"
    value = "true"
  }

  # ── Ingress: ALB with ACM certificate (publicly trusted TLS) ──────────
  set {
    name  = "server.ingress.enabled"
    value = "true"
  }
  set {
    name  = "server.ingress.ingressClassName"
    value = "alb"
  }
  set {
    name  = "server.ingress.hosts[0].host"
    value = "vault.${var.environment}.${var.domain}"
  }
  set {
    name  = "server.ingress.hosts[0].paths[0]"
    value = "/"
  }
  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme"
    value = "internet-facing"
  }
  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type"
    value = "ip"
  }
  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/certificate-arn"
    value = var.certificate_arn
  }
  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/listen-ports"
    value = "[{\"HTTPS\":443}]"
    type  = "string"
  }
  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/ssl-redirect"
    value = "443"
    type  = "string"
  }
  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/backend-protocol"
    value = "HTTPS"
  }
  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/healthcheck-path"
    value = "/v1/sys/health?standbyok=true"
  }
  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/healthcheck-protocol"
    value = "HTTPS"
  }
  set {
    name  = "server.ingress.annotations.external-dns\\.alpha\\.kubernetes\\.io/hostname"
    value = "vault.${var.environment}.${var.domain}"
  }

  # ── Disable injector (using VSO instead) ────────────────────────────────
  set {
    name  = "injector.enabled"
    value = "false"
  }
}
