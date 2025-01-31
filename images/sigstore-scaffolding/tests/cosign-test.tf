resource "kubernetes_job_v1" "keyless_sign_verify" {
  depends_on = [helm_release.scaffold]

  metadata {
    name      = "keyless-sign-verify"
    namespace = "tuf-${random_pet.suffix.id}" // To mount the tuf root secret
  }

  spec {
    template {
      metadata {}
      spec {
        init_container {
          name        = "copy-tuf-root"
          image       = "cgr.dev/chainguard/wolfi-base:latest"
          working_dir = "/workspace"
          command     = ["/bin/sh", "-c"]
          args = [<<EOF
          set -ex
          ls /tuf-root/
          cp /tuf-root/root /workspace/root.json
          EOF
          ]
          volume_mount {
            name       = "workspace"
            mount_path = "/workspace"
          }
          volume_mount {
            name       = "tuf-root"
            mount_path = "/tuf-root"
          }
        }

        init_container {
          name        = "initialize"
          image       = data.oci_string.images["cosign-cli"].id
          working_dir = "/workspace"
          args = [
            "initialize",
            "--mirror", "http://tuf-server.tuf-${random_pet.suffix.id}.svc",
            "--root", "./root.json",
          ]
          volume_mount {
            name       = "workspace"
            mount_path = "/workspace"
          }
          volume_mount {
            name       = "tuf-config"
            mount_path = "/home/nonroot/.sigstore"
          }
        }

        init_container {
          name        = "sign"
          image       = data.oci_string.images["cosign-cli"].id
          working_dir = "/workspace"
          args = [
            "sign-blob", "/etc/os-release",
            "--fulcio-url", "http://fulcio-server.fulcio-${random_pet.suffix.id}.svc",
            "--rekor-url", "http://rekor-server.rekor-${random_pet.suffix.id}.svc",
            "--output-certificate", "cert.pem",
            "--output-signature", "sig",
            "--yes",
            "--identity-token", "/var/sigstore/token/oidc-token",
          ]
          volume_mount {
            name       = "workspace"
            mount_path = "/workspace"
          }
          volume_mount {
            name       = "oidc-token"
            mount_path = "/var/sigstore/token"
          }
          volume_mount {
            name       = "tuf-config"
            mount_path = "/home/nonroot/.sigstore"
          }
        }

        container {
          name        = "verify"
          image       = data.oci_string.images["cosign-cli"].id
          working_dir = "/workspace"
          args = [
            "verify-blob", "/etc/os-release",
            "--rekor-url", "http://rekor-server.rekor-${random_pet.suffix.id}.svc",
            "--certificate", "cert.pem",
            "--signature", "sig",
            "--certificate-oidc-issuer", "https://kubernetes.default.svc",
            "--certificate-identity", "https://kubernetes.io/namespaces/tuf-${random_pet.suffix.id}/serviceaccounts/default",
          ]
          volume_mount {
            name       = "workspace"
            mount_path = "/workspace"
          }
          volume_mount {
            name       = "tuf-config"
            mount_path = "/home/nonroot/.sigstore"
          }
        }

        volume {
          name = "workspace"
          empty_dir {}
        }
        volume {
          name = "oidc-token"
          projected {
            sources {
              service_account_token {
                path               = "oidc-token"
                expiration_seconds = 600
                audience           = "sigstore"
              }
            }
          }
        }
        volume {
          name = "tuf-root"
          secret {
            secret_name = "tuf-root"
          }
        }
        volume {
          name = "tuf-config"
          empty_dir {}
        }
        restart_policy = "Never"
      }
    }
  }

  wait_for_completion = true
}