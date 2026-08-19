# Build Notes

## Phase 1 - VPC Networking

### Infrastructure
- Deployed AWS infrastructure using Terraform.
- Created a VPC with CIDR `10.0.0.0/16`.
- Deployed resources in `us-east-1`.

### Network Segmentation
- Public Subnet A: `10.0.1.0/24` - `us-east-1a`
- Public Subnet B: `10.0.2.0/24` - `us-east-1b`
- Private Subnet A: `10.0.11.0/24` - `us-east-1a`
- Private Subnet B: `10.0.12.0/24` - `us-east-1b`

### Routing
- Attached an Internet Gateway to the VPC.
- Created a public route table with a `0.0.0.0/0` route through the Internet Gateway.
- Associated both public subnets with the public route table.
- Private subnets currently have no direct route to the Internet.

### Infrastructure as Code
- Implemented the network as a reusable Terraform VPC module.
- Terraform successfully provisioned 9 AWS resources.
- Infrastructure configuration is version controlled with Git/GitHub.

### Design Decisions
- Resources are distributed across two Availability Zones.
- Public and private workloads are separated into dedicated subnets.
- A NAT Gateway was intentionally omitted at this stage to minimize lab costs.


## Phase 2 - Secure Compute and Administration

### Compute
- Provisioned an Amazon EC2 instance using Terraform.
- Deployed Amazon Linux 2023 on a `t3.micro` instance.
- Retrieved the current Amazon Linux AMI dynamically from AWS Systems Manager Parameter Store.
- Enforced IMDSv2 for EC2 instance metadata access.

### IAM
- Created a dedicated IAM role for the EC2 workload.
- Attached `AmazonSSMManagedInstanceCore`.
- Associated the role with EC2 through an IAM instance profile.
- Avoided embedding AWS credentials or access keys on the instance.

### Network Security
- Created a dedicated application security group.
- Configured zero inbound security group rules.
- Did not expose SSH (TCP/22) to the Internet.
- Allowed outbound connectivity for required AWS service communication.

### Secure Administration
- Configured AWS Systems Manager Session Manager for administrative access.
- Successfully established an interactive shell without SSH.
- No SSH key pair is required for instance administration.

### Security Decisions
- Eliminated public SSH exposure to reduce the remote administration attack surface.
- Used IAM-based Session Manager access instead of long-lived SSH credentials.
- Required IMDSv2 to improve protection of instance metadata credentials.