resource "kubernetes_namespace_v1" "datadog" {
  metadata {
    name = "datadog"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      environment                    = var.environment
    }
  }
}

resource "kubernetes_secret_v1" "datadog" {
  metadata {
    name      = "datadog-secret"
    namespace = kubernetes_namespace_v1.datadog.metadata[0].name
  }

  data = {
    "api-key" = var.datadog_api_key
  }
}

resource "helm_release" "datadog_operator" {
  name       = "datadog-operator"
  namespace  = kubernetes_namespace_v1.datadog.metadata[0].name
  repository = "https://helm.datadoghq.com"
  chart      = "datadog-operator"
  version    = "2.1.0"

  set {
    name  = "replicaCount"
    value = "1"
  }
}

resource "kubernetes_manifest" "datadog_agent" {
  manifest = {
    apiVersion = "datadoghq.com/v2alpha1"
    kind       = "DatadogAgent"
    metadata = {
      name      = "datadog"
      namespace = kubernetes_namespace_v1.datadog.metadata[0].name
    }
    spec = {
      global = {
        clusterName = var.cluster_name
        site        = var.datadog_site
        credentials = {
          apiSecret = {
            secretName = kubernetes_secret_v1.datadog.metadata[0].name
            keyName    = "api-key"
          }
        }
      }
      features = {
        clusterChecks = {
          enabled = true
        }
        orchestratorExplorer = {
          enabled = true
        }
        apm = {
          instrumentation = {
            enabled = true
            targets = [
              {
                name = "default-target"
                ddTraceVersions = {
                  java   = "1"
                  python = "4"
                  js     = "5"
                  php    = "1"
                  dotnet = "3"
                  ruby   = "2"
                }
              }
            ]
          }
        }
        logCollection = {
          enabled            = true
          containerCollectAll = true
        }
      }
    }
  }

  depends_on = [helm_release.datadog_operator]
}
