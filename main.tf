provider "aws" {
  region = "us-east-1"
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get subnets but exclude unsupported AZ (us-east-1e)
data "aws_subnets" "supported" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Filter subnets by supported AZs
data "aws_subnet" "filtered" {
  for_each = toset(data.aws_subnets.supported.ids)

  id = each.value
}

locals {
  # Keep only subnets in supported AZs
  eks_subnet_ids = [
    for s in data.aws_subnet.filtered :
    s.id if contains(["us-east-1a", "us-east-1b", "us-east-1c"], s.availability_zone)
  ]
}

# IAM role for EKS cluster
resource "aws_iam_role" "cbz_eks_cluster_role" {
  name = "cbz-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cbz_eks_cluster_role_policy" {
  role       = aws_iam_role.cbz_eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Create EKS Cluster
resource "aws_eks_cluster" "my_cluster" {
  name     = "my-cluster"
  role_arn = aws_iam_role.cbz_eks_cluster_role.arn

  vpc_config {
    subnet_ids = local.eks_subnet_ids
  }

  depends_on = [aws_iam_role_policy_attachment.cbz_eks_cluster_role_policy]
}

# IAM role for worker nodes
resource "aws_iam_role" "cbz_eks_node_role" {
  name = "cbz-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cbz_eks_node_role_policy" {
  role       = aws_iam_role.cbz_eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Node group
resource "aws_eks_node_group" "my_node_group" {
  cluster_name    = aws_eks_cluster.my_cluster.name
  node_group_name = "my-node-group"
  node_role_arn   = aws_iam_role.cbz_eks_node_role.arn
  subnet_ids      = local.eks_subnet_ids
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  depends_on = [aws_eks_cluster.my_cluster]
}
