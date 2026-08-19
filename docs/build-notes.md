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