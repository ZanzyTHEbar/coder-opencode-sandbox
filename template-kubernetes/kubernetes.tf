resource "kubernetes_namespace_v1" "workspace" {
  metadata {
    name = local.namespace

    labels = {
      "app.kubernetes.io/name"       = "opencode-workspace"
      "app.kubernetes.io/managed-by" = "coder"
      "coder.com/workspace-id"       = data.coder_workspace.me.id
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
      }

      spec {
        service_account_name            = kubernetes_service_account_v1.workspace.metadata[0].name
        automount_service_account_token = false
        runtime_class_name              = var.runtime_class_name

        security_context {
          run_as_non_root = true
          run_as_user     = 1800
          run_as_group    = 1800
          fs_group        = 1800

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        init_container {
          name    = "fix-ownership"
          image   = var.opencode_image
          command = ["sh", "-c", "chown -R 1800:1800 /home/coder /home/coder/workspace 2>/dev/null; chmod 700 /home/coder/.opencode 2>/dev/null; true"]

          security_context {
            run_as_user                = 0
            run_as_group               = 0
            run_as_non_root            = false
            allow_privilege_escalation = false
            privileged                 = false

            capabilities {
              add = ["CHOWN"]
            }
          }

          volume_mount {
            name       = "home"
            mount_path = "/home/coder"
          }
        }

        container {
          name  = "opencode"
          image = var.opencode_image

          command = ["sh", "-lc", coder_agent.main.init_script]

          lifecycle {
            post_start {
              exec {
                command = [
                  "sh", "-c",
                  "mkdir -p /home/coder/.opencode /home/coder/workspace && nohup opencode web --hostname 127.0.0.1 --port 4096 --cwd /home/coder/workspace >/home/coder/.opencode/server.log 2>&1 &"
                ]
              }
            }
          }

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
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
      }
    }
  }
}
