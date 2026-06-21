resource "kubernetes_namespace_v1" "workspace" {
  metadata {
    name = local.namespace

    labels = {
      "app.kubernetes.io/name"       = "opencode-workspace"
      "app.kubernetes.io/managed-by" = "coder"
      "coder.com/workspace-id"       = data.coder_workspace.me.id

      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_service_account_v1" "workspace" {
  metadata {
    name      = "opencode-workspace"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
  }

  automount_service_account_token = false
}

resource "kubernetes_persistent_volume_claim_v1" "home" {
  wait_until_bound = false

  metadata {
    name      = "home"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = var.home_storage_size
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "workspace" {
  wait_until_bound = false

  metadata {
    name      = "workspace"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = var.workspace_storage_size
      }
    }
  }
}

resource "kubernetes_deployment_v1" "opencode" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "opencode"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
    labels = {
      app = "opencode"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "opencode"
      }
    }

    template {
      metadata {
        labels = {
          app = "opencode"
        }

        annotations = var.vault_git_secret_path == "" ? {} : {
          "vault.hashicorp.com/agent-inject"                            = "true"
          "vault.hashicorp.com/agent-service-account-token-volume-name" = "vault-token"
          "vault.hashicorp.com/auth-config-audience"                    = "vault"
          "vault.hashicorp.com/role"                                    = var.vault_role
          "vault.hashicorp.com/agent-inject-secret-git"                 = var.vault_git_secret_path
        }
      }

      spec {
        service_account_name            = kubernetes_service_account_v1.workspace.metadata[0].name
        automount_service_account_token = false
        runtime_class_name              = var.runtime_class_name

        security_context {
          run_as_non_root = true
          run_as_user     = 1001
          run_as_group    = 1001
          fs_group        = 1001

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "opencode"
          image = var.opencode_image

          command = ["sh", "-lc", coder_agent.main.init_script]

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }

          env {
            name  = "HOME"
            value = "/home/coder"
          }

          env {
            name  = "LOGNAME"
            value = "coder"
          }

          env {
            name  = "USER"
            value = "coder"
          }

          port {
            name           = "opencode"
            container_port = 4096
          }

          resources {
            limits = {
              cpu               = var.cpu_limit
              memory            = var.memory_limit
              ephemeral-storage = var.ephemeral_storage_limit
            }

            requests = {
              cpu               = var.cpu_request
              memory            = var.memory_request
              ephemeral-storage = var.ephemeral_storage_request
            }
          }

          security_context {
            run_as_non_root            = true
            allow_privilege_escalation = false
            privileged                 = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "home"
            mount_path = "/home/coder"
          }

          volume_mount {
            name       = "workspace"
            mount_path = "/home/coder/workspace"
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }

        volume {
          name = "home"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.home.metadata[0].name
          }
        }

        volume {
          name = "workspace"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.workspace.metadata[0].name
          }
        }

        volume {
          name = "tmp"

          empty_dir {
            medium = "Memory"
          }
        }

        dynamic "volume" {
          for_each = var.vault_git_secret_path == "" ? [] : [1]

          content {
            name = "vault-token"

            projected {
              sources {
                service_account_token {
                  path               = "token"
                  audience           = "vault"
                  expiration_seconds = 3600
                }
              }
            }
          }
        }
      }
    }
  }
}
