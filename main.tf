locals {
  public_subnets_additional_tags = {
    "kubernetes.io/role/elb" : 1
  }

  private_subnets_additional_tags = {
    "kubernetes.io/role/internal-elb" : 1
  }
}


provider "aws" {
  region = var.region
}

locals {
  # The usage of the specific kubernetes.io/cluster/* resource tags below are required
  # for EKS and Kubernetes to discover and manage networking resources
  # https://www.terraform.io/docs/providers/aws/guides/eks-getting-started.html#base-vpc-networking
  tags = merge(var.tags, map("kubernetes.io/cluster/${var.id}", "shared"))

  # Unfortunately, most_recent (https://github.com/cloudposse/terraform-aws-eks-workers/blob/34a43c25624a6efb3ba5d2770a601d7cb3c0d391/main.tf#L141)
  # variable does not work as expected, if you are not going to use custom ami you should
  # enforce usage of eks_worker_ami_name_filter variable to set the right kubernetes version for EKS workers,
  # otherwise will be used the first version of Kubernetes supported by AWS (v1.11) for EKS workers but
  # EKS control plane will use the version specified by kubernetes_version variable.
  eks_worker_ami_name_filter = "amazon-eks-node-${var.kubernetes_version}*"
}

module "vpc" {
  source     = "./modules/vpc"
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  attributes = var.attributes
  cidr_block = "172.16.0.0/16"
  tags       = local.tags
}

module "subnets" {
  source               = "./modules/subnets"
  availability_zones   = var.availability_zones
  vpc_id               = module.vpc.vpc_id
  igw_id               = module.vpc.igw_id
  cidr_block           = module.vpc.vpc_cidr_block
  nat_gateway_enabled             = false
  nat_instance_enabled            = true
  public_subnets_additional_tags  = local.public_subnets_additional_tags
  private_subnets_additional_tags = local.private_subnets_additional_tags
}

module "eks_cluster" {
  source                       = "./modules/eks_cluster"
  namespace                    = var.namespace
  stage                        = var.stage
  name                         = var.name
  attributes                   = var.attributes
  tags                         = var.tags
  region                       = var.region
  vpc_id                       = module.vpc.vpc_id
  subnet_ids                   = concat(module.subnets.private_subnet_ids,module.subnets.public_subnet_ids)
  kubernetes_version           = var.kubernetes_version
  local_exec_interpreter       = var.local_exec_interpreter
  oidc_provider_enabled        = var.oidc_provider_enabled
  enabled_cluster_log_types    = var.enabled_cluster_log_types
  cluster_log_retention_period = var.cluster_log_retention_period
  workers_role_arns            = [module.eks_private_workers.workers_role_arn]
  workers_security_group_ids   = [module.eks_private_workers.security_group_id]
}

# Ensure ordering of resource creation to eliminate the race conditions when applying the Kubernetes Auth ConfigMap.
# Do not create Node Group before the EKS cluster is created and the `aws-auth` Kubernetes ConfigMap is applied.
# Otherwise, EKS will create the ConfigMap first and add the managed node role ARNs to it,
# and the kubernetes provider will throw an error that the ConfigMap already exists (because it can't update the map, only create it).
# If we create the ConfigMap first (to add additional roles/users/accounts), EKS will just update it by adding the managed node role ARNs.
data "null_data_source" "wait_for_cluster_and_kubernetes_configmap" {
  inputs = {
    cluster_name             = module.eks_cluster.eks_cluster_id
    kubernetes_config_map_id = module.eks_cluster.kubernetes_config_map_id
  }
}

module "eks_node_group" {
  source            = "./modules/eks_node_group"
  namespace         = var.namespace
  stage             = var.stage
  name              = var.name
  attributes        = var.attributes
  tags              = var.tags
  subnet_ids        = module.subnets.private_subnet_ids
  cluster_name      = data.null_data_source.wait_for_cluster_and_kubernetes_configmap.outputs["cluster_name"]
  instance_types    = var.instance_types
  desired_size      = var.desired_size
  min_size          = var.min_size
  max_size          = var.max_size
  kubernetes_labels = var.kubernetes_labels
  disk_size         = var.disk_size
}

 module "eks_private_workers" {
    source                             = "./modules/eks_workers"
    namespace                          = var.namespace
    stage                              = var.stage
    name                               = var.private_worker_name
    attributes                         = var.attributes
    tags                               = var.tags
    instance_type                      = var.instance_type
    eks_worker_ami_name_filter         = local.eks_worker_ami_name_filter
    vpc_id                             = module.vpc.vpc_id
    subnet_ids                         = module.subnets.private_subnet_ids
    health_check_type                  = var.health_check_type
    min_size                           = var.min_size
    max_size                           = var.max_size
    wait_for_capacity_timeout          = var.wait_for_capacity_timeout
    allowed_cidr_blocks                = ["0.0.0.0/0"]
    cluster_name                       = var.clusterid
    cluster_endpoint                   = module.eks_cluster.eks_cluster_endpoint
    cluster_certificate_authority_data = module.eks_cluster.eks_cluster_certificate_authority_data
    cluster_security_group_id          = module.eks_cluster.security_group_id

    # Auto-scaling policies and CloudWatch metric alarms
    autoscaling_policies_enabled           = var.autoscaling_policies_enabled
    cpu_utilization_high_threshold_percent = var.cpu_utilization_high_threshold_percent
    cpu_utilization_low_threshold_percent  = var.cpu_utilization_low_threshold_percent
  }


//module "rds_cluster_aurora_mysql_serverless" {
//  source               = "./modules/aws_rds_cluster"
//  namespace            = "eg"
//  stage                = "dev"
//  name                 = "mysql-db"
//  engine               = "aurora"
//  engine_mode          = "serverless"
//  cluster_family       = "aurora5.6"
//  cluster_size         = "0"
//  admin_user           = "admin1"
//  admin_password       = "Testing123"
//  db_name              = "test"
//  db_port              = "3306"
//  instance_type        = "db.t2.small"
//  vpc_id               = module.vpc.vpc_id
//  security_groups      = [module.eks_cluster.security_group_id]
//  subnets              = module.subnets.private_subnet_ids
//  enable_http_endpoint = true
//
//  scaling_configuration = [
//    {
//      auto_pause               = true
//      max_capacity             = 256
//      min_capacity             = 2
//      seconds_until_auto_pause = 300
//      timeout_action           = "ForceApplyCapacityChange"
//    }
//  ]
//}

module "ecr-repository" {
   source = "./modules/ecr"
   repository_name = "eks-demo/app"
   attach_lifecycle_policy = true
}

module "ecr-repository-2" {
   source = "./modules/ecr"
   repository_name = "eks-demo/app2"
   attach_lifecycle_policy = true
}

module "ecr-repository-3" {
   source = "./modules/ecr"
   repository_name = "eks-demo/db"
   attach_lifecycle_policy = true
}

