resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.0"
  wait             = true
  timeout          = 600

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }
  # Required for ALB ingress with backend-protocol HTTP. TLS terminates at
  # ALB (ACM cert); disabling server TLS avoids double-encryption and lets
  # ALB health checks work. In-cluster traffic is protected by VPC + network policies.
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  values = [yamlencode({
    configs = {
      cm = {
        "kustomize.buildOptions" = "--load-restrictor LoadRestrictionsNone"
      }
    }
    server = {
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        hostname         = "argocd.${var.environment}.${var.domain}"
        annotations = {
          "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
          "alb.ingress.kubernetes.io/target-type"      = "ip"
          "alb.ingress.kubernetes.io/certificate-arn"  = var.certificate_arn
          "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTPS\":443},{\"HTTP\":80}]"
          "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
          "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
          "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
          "external-dns.alpha.kubernetes.io/hostname"  = "argocd.${var.environment}.${var.domain}"
        }
      }
    }
  })]
}

# ArgoCD Application deployed separately — the Application CRD is installed
# by the Helm chart above, and needs time to register in the API server.
resource "kubectl_manifest" "argocd_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "netlix-app"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_target_revision
        path           = "app/manifests/overlays/${var.environment}"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.target_namespace
      }
      # - Deployment /spec/replicas: HPA owns this. Without ignoring, ArgoCD
      #   selfHeal reconciles back to the Git value every few seconds,
      #   killing HPA-spawned pods.
      # - Deployment vso.secrets.hashicorp.com/restartedAt annotation:
      #   VSO writes this to trigger pod restarts on cert rotation. Without
      #   ignoring, ArgoCD strips it as drift and a rollout-storm cycle
      #   starts (VSO reapplies → Argo reverts → ...).
      # - VaultPKISecret managedFieldsManagers=[vault-secrets-operator]:
      #   VSO defaults additional spec fields after creation; Argo treats
      #   them as drift and resyncs in a tight loop. Telling Argo to ignore
      #   any fields VSO manages breaks the loop.
      ignoreDifferences = [
        {
          group = "apps"
          kind  = "Deployment"
          jsonPointers = [
            "/spec/replicas",
            "/spec/template/metadata/annotations/vso.secrets.hashicorp.com~1restartedAt",
          ]
        },
        {
          group                 = "secrets.hashicorp.com"
          kind                  = "VaultPKISecret"
          managedFieldsManagers = ["vault-secrets-operator"]
        },
      ]
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
          # Don't revert replicas on sync either — belt + braces with
          # ignoreDifferences above.
          "RespectIgnoreDifferences=true",
        ]
      }
    }
  })

  depends_on = [helm_release.argocd]
}
