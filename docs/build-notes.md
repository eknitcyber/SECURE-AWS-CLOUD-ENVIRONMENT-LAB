# Build Notes

## Project Goal

The goal of this project is to build a security-focused AWS environment using Terraform while developing a better understanding of how cloud infrastructure, networking, access control, and security monitoring work together.

The project follows this lifecycle:

BUILD → SECURE → MONITOR → TEST → DETECT → INVESTIGATE → REMEDIATE → DOCUMENT

Rather than simply deploying AWS resources, I want the final environment to demonstrate why different security controls are used and how they work together.

The final architecture will use segmented networking, private application servers behind an Application Load Balancer, IAM-based administration, centralized logging and monitoring, threat detection, alerting, and infrastructure-as-code security controls.

Later in the project, I will perform a controlled security simulation and use AWS security telemetry to investigate the change and restore the secure configuration through Terraform.

---

# Phase 1 - Network Foundation

## What I Built

I started with the networking layer because every other resource in the environment depends on how the VPC is designed.

Using Terraform, I created a VPC in us-east-1 with the CIDR range:

10.0.0.0/16

I divided the network into four subnets across two Availability Zones:

* Public Subnet A: 10.0.1.0/24 in us-east-1a
* Public Subnet B: 10.0.2.0/24 in us-east-1b
* Private Subnet A: 10.0.11.0/24 in us-east-1a
* Private Subnet B: 10.0.12.0/24 in us-east-1b

I also created an Internet Gateway and a public route table containing a 0.0.0.0/0 route through the gateway. Both public subnets are associated with this route table.

The networking resources were organized into a reusable Terraform VPC module instead of placing all of the infrastructure directly in the development environment configuration.

## Why I Designed It This Way

The main purpose of the subnet design is to separate resources based on whether they actually need to be internet-facing.

The public subnets are intended for infrastructure that must communicate directly with the internet, such as the Application Load Balancer and NAT Gateway.

The private subnets are intended for application workloads that should not accept direct connections from internet users.

Using two Availability Zones also gives the environment a more realistic structure. Application resources can be distributed rather than placing the entire environment in a single AZ.

I initially kept the private networking simple and added outbound connectivity when the private application tier required it. This also helped limit unnecessary AWS costs during the earlier stages of the lab.

## What I Learned

This phase helped me better understand that the terms "public subnet" and "private subnet" are determined by network design rather than just a subnet name.

Routing, public IP assignment, Internet Gateway connectivity, and security controls all affect whether a resource is actually reachable from the internet.

I also gained experience organizing Terraform into modules and passing network information between modules instead of defining the entire environment in one large Terraform file.

---

# Phase 2 - Secure Compute and Administration

## What I Built

In Phase 2, I added the first EC2 workload and focused on how the instance would be administered securely.

The instance used:

* Amazon Linux 2023
* t3.micro
* A dynamically retrieved Amazon Linux AMI
* A dedicated IAM role
* An IAM instance profile
* IMDSv2
* AWS Systems Manager Session Manager

Instead of hardcoding an AMI ID, Terraform retrieves the current Amazon Linux 2023 AMI through AWS Systems Manager Parameter Store.

This makes the configuration less dependent on a specific regional AMI identifier.

## IAM and Instance Credentials

I created a dedicated IAM role for the EC2 workload and associated it with the instance through an IAM instance profile.

The role uses AmazonSSMManagedInstanceCore to provide the permissions required for Systems Manager.

Using an IAM role means the instance can receive temporary AWS credentials when required rather than storing access keys directly on the server.

This helped reinforce the difference between giving a workload an AWS identity and manually placing credentials on that workload.

## Administration Without Public SSH

A major security decision in this phase was to use AWS Systems Manager Session Manager instead of SSH for administration.

I successfully established an interactive shell on the EC2 instance through Session Manager without:

* Opening TCP port 22
* Assigning an inbound SSH security group rule
* Creating an SSH key pair
* Managing a private SSH key

The administration path is therefore:

Administrator → AWS/IAM → Systems Manager → EC2

instead of exposing an SSH service directly to the internet.

This reduces the number of publicly reachable services and makes administrative access dependent on AWS IAM authorization.

## IMDSv2

I also configured the EC2 instance to require Instance Metadata Service Version 2.

Because EC2 workloads can obtain temporary IAM role credentials through the instance metadata service, protecting access to that metadata is an important part of securing the instance.

Requiring IMDSv2 provides stronger metadata access controls than allowing the older metadata service behavior.

## What I Learned

The biggest takeaway from this phase was that secure administration does not require opening a traditional remote-management port to the internet.

Session Manager combines AWS IAM and Systems Manager to provide administrative access while allowing the EC2 security group to remain closed to SSH.

I also developed a better understanding of how IAM roles allow AWS workloads to receive temporary permissions without embedding permanent credentials into applications or servers.

---

# Phase 3 - Private Application Tier and Load Balancing

## Architecture Evolution

Phase 3 expanded the environment from an individual EC2 workload into a multi-tier application architecture.

The application traffic flow is now:

Internet → Application Load Balancer → Private EC2 Instances

The Application Load Balancer is the public entry point. The application servers themselves remain inside private subnets.

This separation allows the infrastructure to expose the application without exposing the EC2 instances directly.

## Private Application Instances

I updated the Terraform compute module to deploy two application instances:

* Application Instance A in Private Subnet A and us-east-1a
* Application Instance B in Private Subnet B and us-east-1b

Both instances:

* Run Amazon Linux 2023
* Use t3.micro
* Have no public IP address
* Require IMDSv2
* Use the IAM instance profile created for the application workload
* Run a simple Apache web application

Placing the instances in separate Availability Zones also allows the load balancer to distribute requests across two independent backend instances.

## Application Load Balancer

I created an internet-facing Application Load Balancer across both public subnets.

The Terraform configuration also creates:

* An HTTP listener on TCP port 80
* An application target group
* HTTP health checks against /
* Target registrations for both private EC2 instances

Both application instances report Healthy in the target group.

The ALB gives users one public application endpoint while keeping the individual application servers private.

## Security Group Segmentation

I separated the load-balancing and application layers using two security groups.

### ALB Security Group

The ALB accepts:

HTTP / TCP / 80 ← 0.0.0.0/0

The ALB is intentionally internet-facing because it is the public entry point to the application.

### Application Security Group

The private EC2 instances accept:

HTTP / TCP / 80 ← ALB Security Group

The source of the application rule is another security group rather than 0.0.0.0/0.

This means an internet client can reach the ALB, but the same client cannot use the security group configuration to connect directly to the application instances.

The intended inbound path is:

Internet → ALB Security Group → Application Security Group → EC2

SSH remains closed to the internet, with administrative access handled through Systems Manager.

## Application Deployment

I configured EC2 user data through Terraform to install and start Apache automatically when the instances are created.

The startup configuration:

* Installs Apache HTTP Server
* Enables Apache at startup
* Starts the service
* Creates a simple Secure AWS Terraform Lab page
* Displays the hostname of the backend instance

Including the hostname makes the application useful for testing the load balancer.

By refreshing the same ALB address and receiving different backend hostnames, I can see that requests are reaching different EC2 instances without directly connecting to either server.

## Private Outbound Connectivity

Although the application servers should not be publicly reachable, they still require controlled outbound connectivity for tasks such as downloading operating-system packages and updates.

I added a NAT Gateway to support this requirement.

The VPC module now includes:

* An Elastic IP for NAT
* One NAT Gateway in Public Subnet A
* A private route table
* A 0.0.0.0/0 route through the NAT Gateway
* Route table associations for both private subnets

The private outbound path is:

Private EC2 → Private Route Table → NAT Gateway → Internet Gateway → Internet

This design helped clarify the difference between inbound exposure and outbound connectivity.

The EC2 instances can initiate connections to external services when necessary, but they still do not have public IP addresses and cannot receive unsolicited inbound internet connections through the NAT Gateway.

## NAT Gateway Design Decision

For this lab, I deployed one NAT Gateway instead of one NAT Gateway per Availability Zone.

This was a deliberate cost decision.

A production environment with stronger availability requirements could deploy a NAT Gateway in each Availability Zone and route each private subnet through its local NAT Gateway.

For this temporary lab environment, I accepted the reduced NAT redundancy in exchange for lower AWS costs.

Understanding that tradeoff was useful because architecture decisions are not only about what is technically possible. Cost, availability requirements, and the purpose of the environment also influence the design.

## Validation

I verified the final Phase 3 environment at multiple layers rather than relying only on a successful Terraform deployment.

### Compute

Confirmed two t3.micro application instances are running across:

* us-east-1a
* us-east-1b

Both application servers use private addressing.

### Load Balancing

Confirmed both EC2 instances are registered with the target group and report healthy on port 80.

### Network Security

Confirmed the ALB and application servers use separate security groups.

The ALB accepts public HTTP traffic while the application security group accepts HTTP only from the ALB security group.

No public SSH rule exists.

### Private Networking

Confirmed the NAT Gateway is available and provides the private subnets with outbound connectivity.

The EC2 application servers remain without public IP addresses.

### Application

I accessed the application through the ALB DNS name rather than connecting directly to an EC2 instance.

Repeated requests displayed hostnames from both private subnet ranges:

* 10.0.11.x
* 10.0.12.x

This confirmed that the same public ALB endpoint was successfully forwarding requests to application servers in both private subnets.

## What I Learned

Phase 3 helped connect several AWS networking concepts that are easy to understand individually but more useful when viewed as one architecture.

The ALB, security groups, private subnets, route tables, NAT Gateway, Internet Gateway, and EC2 instances each solve a different part of the problem.

The ALB provides controlled inbound application access.

The application security group restricts which resource can communicate with the application servers.

The private subnets prevent the application instances from being directly internet-facing.

The NAT Gateway provides outbound connectivity without assigning public IP addresses to the application servers.

Using all of these together creates a much stronger design than simply launching an EC2 instance with a public IP and opening port 80.

I also gained a better understanding of why security controls should be layered. A private subnet, security group, IAM role, IMDSv2 requirement, and Session Manager each address different risks rather than relying on one control to secure the entire workload.

## Phase 3 Outcome

At the end of Phase 3, the application architecture is:

Internet → Application Load Balancer → Private EC2 A / Private EC2 B

Administrative access follows:

Administrator → IAM / Systems Manager → Private EC2

Private outbound connectivity follows:

Private EC2 → NAT Gateway → Internet Gateway → Internet

The application servers are not directly exposed to internet clients, SSH is not publicly available, and the Application Load Balancer provides the controlled public entry point.

The environment now provides a foundation for the next stages of the project, where I will add logging, monitoring, threat detection, alerting, WAF protection, and eventually a controlled security incident and Terraform-based remediation.
