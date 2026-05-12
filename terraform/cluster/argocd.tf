# ArgoCD installation + bootstrap of the app-of-apps pattern.
#
# What Terraform owns:
#   1. The argocd namespace
#   2. The Helm release for ArgoCD itself
#   3. The Kubernetes Secret containing GitHub App creds for ArgoCD's repo-server
#   4. The single root Application (app-of-apps)
#
# What Terraform does NOT own:
#   - The Kyverno install, Kyverno policies, sample-api workloads. These are
#     managed by ArgoCD from this repo's gitops/ directory. Once Terraform
#     bootstraps the root app, all further changes are git commits, not
#     terraform applies.

# ---------------------------------------------------------------------------
# Namespace for ArgoCD.
# ---------------------------------------------------------------------------
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "purpose"                      = "gitops-controller"
    }
  }
}

# ---------------------------------------------------------------------------
# ArgoCD Helm release. Minimal overrides — most defaults are fine for a lab.
# Notable overrides:
#   - Dex disabled: no SSO yet; admin password is the only login.
#   - server.service.type: ClusterIP (port-forward only, no public LB).
#   - configs.params.application.namespaces: lets Applications live outside
#     the argocd namespace if we ever want that. Empty default = argocd-only.
#   - notifications: disabled (lab, no need).
# ---------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      global = {
        domain = "argocd.local" # placeholder; only matters with ingress
      }

      dex = {
        enabled = false
      }

      server = {
        service = {
          type = "ClusterIP"
        }
      }

      notifications = {
        enabled = false
      }

      applicationSet = {
        enabled = true
      }

      configs = {
        params = {
          "applicationsetcontroller.policy" = "sync"
        }
        cm = {
          "application.instanceLabelKey" = "argocd.argoproj.io/instance"
        }
      }
    })
  ]

  depends_on = [
    kubernetes_secret.argocd_github_repo,
  ]
}

# ---------------------------------------------------------------------------
# Root app-of-apps, deployed via the argocd-apps Helm chart.
#
# Why a separate Helm release and not a kubernetes_manifest resource:
#   - The kubernetes_manifest provider does a plan-time GET against the
#     cluster's API to learn the Application CRD's schema. On the first
#     apply, the CRD doesn't exist yet — even with depends_on, the plan
#     fails with "no matches for kind Application in version argoproj.io/v1alpha1".
#   - The argocd-apps chart is the upstream-recommended way to bootstrap
#     Applications declaratively. It's a thin wrapper that installs the
#     Application resources via Helm templating, which doesn't suffer the
#     same plan-time schema discovery issue.
#   - The CRD was already installed by the main argo-cd release above,
#     so by the time this release applies, Helm's apply succeeds.
#
# Everything downstream of this root app — Kyverno, kyverno-policies,
# lab-policies, sample-api — is YAML in gitops/apps/ in this repo, picked
# up automatically by Argo CD's recursive directory scan.
# ---------------------------------------------------------------------------
resource "helm_release" "argocd_root_app" {
  name       = "argocd-root-app"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  # argocd-apps is versioned independently from the main argo-cd chart.
  # 2.0.4 is current as of writing.
  version   = var.argocd_apps_chart_version
  namespace = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      applications = [
        {
          name      = "root"
          namespace = "argocd"
          finalizers = [
            "resources-finalizer.argocd.argoproj.io",
          ]
          project = "default"
          sources = [
            {
              repoURL        = "https://github.com/${var.github_repo}"
              targetRevision = var.gitops_branch
              path           = "gitops/apps"
              directory = {
                recurse = false
              }
            }
          ]
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "argocd"
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
            syncOptions = [
              "CreateNamespace=true",
            ]
          }
        }
      ]
    })
  ]

  depends_on = [
    helm_release.argocd,
  ]
}

# ---------------------------------------------------------------------------
# ArgoCD repository credentials, fed by the GitHub App stored in shared KV.
# This Secret is what ArgoCD's repo-server reads to clone gitops/ from this repo.
#
# Naming follows the ArgoCD convention: the Secret must:
#   - live in the argocd namespace
#   - have label argocd.argoproj.io/secret-type=repository
#   - have data fields: url, githubAppID, githubAppInstallationID,
#     githubAppPrivateKey
# ---------------------------------------------------------------------------
resource "kubernetes_secret" "argocd_github_repo" {
  metadata {
    name      = "repo-github-${replace(var.github_repo, "/", "-")}"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
    annotations = {
      "managed-by" = "terraform"
    }
  }

  type = "Opaque"

  data = {
    type                    = "git"
    url                     = "https://github.com/${var.github_repo}"
    githubAppID             = data.azurerm_key_vault_secret.argocd_github_app_id.value
    githubAppInstallationID = data.azurerm_key_vault_secret.argocd_github_app_installation_id.value
    githubAppPrivateKey     = data.azurerm_key_vault_secret.argocd_github_app_private_key.value
  }

  # The secret must exist before the helm_release.argocd installs the root
  # Application that references it. The namespace is the only ordering
  # dependency on the k8s side (Helm release will install fine into an
  # existing namespace).
  depends_on = [kubernetes_namespace.argocd]
}
