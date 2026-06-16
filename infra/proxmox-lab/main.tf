terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.78.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.35.0"
    }

    external = {
      source  = "hashicorp/external"
      version = ">= 2.3.0"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://127.0.0.1:8006/"
  api_token = "terraform@pve!terraform=${var.proxmox_token_secret}"
  insecure  = true
}

provider "kubernetes" {
  config_path = "/root/.kube/config"
}
