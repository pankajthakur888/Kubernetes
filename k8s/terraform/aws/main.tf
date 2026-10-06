# ==============================================================================
# Reference Terraform Architecture for Kubernetes HA on AWS
# Provisions VPC, Subnets, Security Groups, NLB, and EC2 instances.
# Bootstrapped by k8s.sh
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region" {
  default = "us-east-1"
}

variable "cluster_name" {
  default = "k8s-prod"
}

# Network Load Balancer (TCP port 6443 -> Control Plane Instances)
# EC2 Instances: 3 x Control Plane, 3 x Worker Nodes
# UserData runs: k8s.sh
