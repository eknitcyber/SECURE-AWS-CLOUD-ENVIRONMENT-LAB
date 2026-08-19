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