# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get all subnets in the VPC
data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Look up details for each subnet
data "aws_subnet" "details" {
  for_each = toset(data.aws_subnets.all.ids)
  id       = each.value
}

# Keep only subnets in supported AZs (exclude us-east-1e)
locals {
  eks_subnets = [
    for s in data.aws_subnet.details :
    s.id if contains(["us-east-1a", "us-east-1b", "us-east-1c"], s.availability_zone)
  ]
}

# Use filtered subnets for EKS control plane
resource "aws_eks_cluster" "my_cluster" {
  name     = "my-cluster"
  role_arn = aws_iam_role.cbz_eks_cluster_role.arn

  vpc_config {
    subnet_ids = local.eks_subnets
  }

  depends_on = [aws_iam_role_policy_attachment.cbz_eks_cluster_role_policy]
}

# Worker node group (can use the same filtered subnets)
resource "aws_eks_node_group" "example" {
  cluster_name    = aws_eks_cluster.my_cluster.name
  node_group_name = "example-node-group"
  node_role_arn   = aws_iam_role.cbz_eks_node_group_role.arn
  subnet_ids      = local.eks_subnets

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t2.medium"]

  depends_on = [aws_eks_cluster.my_cluster]
}
