resource "kubernetes_network_policy_v1" "default_deny" {
  metadata {
    name      = "default-deny"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy_v1" "allow_dns" {
  metadata {
    name      = "allow-dns"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      ports {
        port     = "53"
        protocol = "UDP"
      }

      ports {
        port     = "53"
        protocol = "TCP"
      }

      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }

        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "allow_public_egress" {
  metadata {
    name      = "allow-public-egress"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      dynamic "ports" {
        for_each = toset(var.allowed_public_egress_ports)

        content {
          port     = tostring(ports.value)
          protocol = "TCP"
        }
      }

      to {
        ip_block {
          cidr   = "0.0.0.0/0"
          except = var.internal_egress_block_cidrs
        }
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "allow_coder" {
  metadata {
    name      = "allow-coder"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      ports {
        port     = "80"
        protocol = "TCP"
      }

      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "coder"
          }
        }
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "allow_vault" {
  count = var.vault_git_secret_path == "" ? 0 : 1

  metadata {
    name      = "allow-vault"
    namespace = kubernetes_namespace_v1.workspace.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      ports {
        port     = tostring(var.vault_port)
        protocol = "TCP"
      }

      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.vault_namespace
          }
        }
      }
    }
  }
}
