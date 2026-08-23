module "vpc" {
  source = "../../modules/vpc"

  project_name = "secure-aws-terraform-lab"
  aws_region   = "us-east-1"

  vpc_cidr = "10.0.0.0/16"

  public_subnet_a_cidr  = "10.0.1.0/24"
  public_subnet_b_cidr  = "10.0.2.0/24"
  private_subnet_a_cidr = "10.0.11.0/24"
  private_subnet_b_cidr = "10.0.12.0/24"
}

module "iam" {
  source = "../../modules/iam"

  project_name = "secure-aws-terraform-lab"
}

module "compute" {
  source = "../../modules/compute"

  project_name          = "secure-aws-terraform-lab"
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  private_subnet_ids    = module.vpc.private_subnet_ids
  instance_profile_name = module.iam.instance_profile_name
}