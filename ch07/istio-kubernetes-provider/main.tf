# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.6.1"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.2.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.7.2"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.52.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "terraform_remote_state" "eks" {
  backend = "local"
  config = {
    path = "../../ch01/provision-eks-cluster/terraform.tfstate"
  }
}

# Retrieve EKS cluster configuration
data "aws_eks_cluster" "cluster" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.cluster.name]
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.cluster.name]
      command     = "aws"
    }
  }
}


module "istio-crds" {
  source = "./istio-crds"
}

module "istio" {
  source = "./istio"

  depends_on = [
    module.istio-crds
  ]
}