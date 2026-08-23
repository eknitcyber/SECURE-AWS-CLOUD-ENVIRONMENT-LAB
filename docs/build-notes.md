# Build Notes

## Project Goal

The goal of this project was to build a security-focused AWS environment using Terraform while developing a better understanding of how cloud infrastructure, networking, access control, monitoring, threat detection, and incident response work together.

The project followed this lifecycle:

BUILD → SECURE → MONITOR → TEST → DETECT → INVESTIGATE → REMEDIATE → DOCUMENT

Rather than simply deploying AWS resources, the project was designed to demonstrate why different security controls are used and how they work together.

The final architecture uses segmented networking, private application servers behind an Application Load Balancer, IAM-based administration, centralized logging and monitoring, GuardDuty threat detection, SNS alerting, AWS WAF protection, and automated infrastructure-as-code security checks.

A controlled security misconfiguration was introduced into the lab environment, investigated through AWS CloudTrail, and remediated through Terraform.

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

## ALB Security Group

The ALB accepts:

HTTP / TCP / 80 ← 0.0.0.0/0

The ALB is intentionally internet-facing because it is the public entry point to the application.

## Application Security Group

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

## Compute

Confirmed two t3.micro application instances are running across:

* us-east-1a
* us-east-1b

Both application servers use private addressing.

## Load Balancing

Confirmed both EC2 instances are registered with the target group and report healthy on port 80.

## Network Security

Confirmed the ALB and application servers use separate security groups.

The ALB accepts public HTTP traffic while the application security group accepts HTTP only from the ALB security group.

No public SSH rule exists.

## Private Networking

Confirmed the NAT Gateway is available and provides the private subnets with outbound connectivity.

The EC2 application servers remain without public IP addresses.

## Application

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

---

# Phase 4 - Centralized Logging and Security Monitoring

## Monitoring Goal

Added centralized logging and basic security monitoring to the environment so AWS activity can be recorded, retained, and used for detection.

Up to this point, the project focused mainly on building and securing the infrastructure. This phase adds visibility into activity occurring within the AWS account.

The monitoring flow is:

AWS API Activity → CloudTrail → S3 + CloudWatch Logs → Metric Filter → CloudWatch Alarm

This provides both an audit trail for investigation and a way to detect specific security-relevant activity.

## AWS CloudTrail

Created a multi-region AWS CloudTrail trail using Terraform.

Configured CloudTrail to:

* Record AWS management activity.
* Include global service events.
* Operate as a multi-region trail.
* Deliver logs to a dedicated S3 bucket.
* Send events to CloudWatch Logs for monitoring and detection.

Using a multi-region trail provides broader visibility than monitoring only the region where the main application infrastructure is deployed.

CloudTrail provides the audit layer for the environment by recording actions performed through the AWS Console, CLI, SDKs, and AWS APIs.

## Secure CloudTrail Log Storage

Created a dedicated S3 bucket for long-term CloudTrail log storage.

Configured the bucket with:

* Block Public Access enabled.
* Server-side encryption using Amazon S3 managed keys (SSE-S3).
* Bucket versioning enabled.
* A bucket policy allowing the CloudTrail service to deliver audit logs.

The bucket is not intended to serve public content. Its purpose is to preserve security and audit records, so public access is explicitly blocked.

Encryption protects stored log data at rest, while versioning provides additional protection against accidental modification or deletion of log objects.

## CloudTrail Log Validation

Verified that CloudTrail is actively delivering logs to the S3 bucket.

CloudTrail log objects were observed under the AWS logging structure:

AWSLogs/<account-id>/CloudTrail/<region>/<year>/<month>/<day>/

This confirmed that the trail was not only configured but was actively generating and storing audit records.

## CloudWatch Logs Integration

Created a dedicated CloudWatch Log Group for CloudTrail:

/aws/cloudtrail/secure-aws-terraform-lab

Configured a 30-day retention period for the log group.

An IAM role was created allowing CloudTrail to assume the required role and publish events into CloudWatch Logs.

S3 and CloudWatch serve different purposes in the logging design:

* S3 provides durable storage of the CloudTrail audit records.
* CloudWatch Logs makes the events available for monitoring, filtering, and detection.

This allows the same AWS activity to support both long-term investigation and near-real-time security monitoring.

## Unauthorized API Call Detection

Created a CloudWatch Logs metric filter to identify unsuccessful AWS API calls associated with authorization failures.

The filter monitors CloudTrail events for error codes including:

UnauthorizedOperation

and

AccessDenied

Matching events are converted into the custom CloudWatch metric:

SecurityMetrics / UnauthorizedAPICalls

This turns relevant CloudTrail log events into measurable security data that CloudWatch can evaluate.

## CloudWatch Security Alarm

Created a CloudWatch alarm for the UnauthorizedAPICalls metric.

The alarm is configured to evaluate the sum of detected unauthorized API calls over a five-minute period.

The threshold is:

UnauthorizedAPICalls >= 1

This means a single matching authorization failure within the evaluation period is enough to move the alarm into an alarm state.

Missing data is treated as non-breaching so the alarm does not generate an alert simply because no unauthorized activity has occurred.

At this stage, the alarm provides detection inside CloudWatch. Notification delivery will be added separately so security detections can generate external alerts.

## Infrastructure as Code

Implemented the Phase 4 monitoring infrastructure as a reusable Terraform module.

The monitoring module manages:

* CloudTrail.
* CloudTrail S3 storage.
* S3 public access controls.
* S3 encryption.
* S3 versioning.
* CloudTrail bucket permissions.
* CloudWatch Logs.
* CloudTrail-to-CloudWatch IAM permissions.
* CloudWatch metric filtering.
* CloudWatch security alarming.

Terraform deployed 11 new resources without modifying or destroying the existing network and application infrastructure.

## Phase 4 Validation

Verified that:

* The CloudTrail trail is actively logging.
* CloudTrail is configured as a multi-region trail.
* CloudTrail delivers events to both S3 and CloudWatch Logs.
* CloudTrail log files are present in the S3 bucket.
* Public access is blocked on the CloudTrail S3 bucket.
* S3 server-side encryption is enabled.
* S3 bucket versioning is enabled.
* The CloudWatch Log Group uses a defined retention period.
* The unauthorized API call metric filter is configured.
* Matching events generate the UnauthorizedAPICalls security metric.
* The CloudWatch alarm monitors that metric using the configured threshold.

## Phase 4 Outcome

The environment now has a centralized audit and monitoring layer.

Instead of relying only on the current configuration of AWS resources, activity within the environment is now recorded and can be evaluated for security-relevant behavior.

The monitoring path is:

AWS Activity → CloudTrail → S3

for retained audit evidence, and:

AWS Activity → CloudTrail → CloudWatch Logs → Metric Filter → Alarm

for security monitoring.

This establishes the visibility needed for later threat detection, alerting, controlled security testing, and incident investigation phases of the project.

---

# Phase 5 - Managed Threat Detection

## Threat Detection Goal

Added Amazon GuardDuty as the managed threat detection layer for the AWS environment.

Phase 4 established the ability to record AWS activity and detect specific events using CloudTrail, CloudWatch Logs, metric filters, and alarms. GuardDuty adds a different capability by continuously analyzing AWS data sources for activity that may indicate compromised credentials, reconnaissance, unauthorized behavior, or threats affecting AWS workloads.

This extends the security architecture from collecting and monitoring activity to actively looking for suspicious patterns.

## Amazon GuardDuty

Enabled Amazon GuardDuty using Terraform.

A GuardDuty detector was added to the existing monitoring module so threat detection remains part of the infrastructure-as-code configuration rather than being enabled manually through the AWS Console.

The detector is enabled in the same AWS region as the lab environment.

## Detection Approach

GuardDuty provides managed threat detection without requiring custom detection rules for every possible threat.

This complements the CloudWatch detection created in Phase 4.

The CloudWatch metric filter monitors for a specific condition that I defined:

CloudTrail → AccessDenied / UnauthorizedOperation → Metric → Alarm

GuardDuty provides broader managed analysis of AWS activity and generates findings when behavior matches known indicators or suspicious patterns.

Using both approaches provides two different types of visibility:

* CloudWatch provides custom detection for events I specifically choose to monitor.
* GuardDuty provides AWS-managed threat detection across supported telemetry sources.

This separation helped reinforce that centralized logging and threat detection are related but are not the same security control.

## Findings and Severity

GuardDuty findings are categorized by severity, allowing detected activity to be prioritized for investigation.

The GuardDuty dashboard provides visibility into findings across severity levels including:

* Low
* Medium
* High
* Critical

At the time of validation, the environment had no active GuardDuty findings.

This is expected for the current state of the lab. GuardDuty is enabled so future suspicious activity can be surfaced as findings rather than requiring every event to be manually identified from raw logs.

## Infrastructure as Code

GuardDuty was enabled through the Terraform monitoring module using an aws_guardduty_detector resource.

Terraform deployment resulted in:

1 added, 0 changed, 0 destroyed

No existing network, compute, logging, or application resources needed to be modified to introduce the threat detection layer.

Keeping GuardDuty in Terraform also means its enabled state is documented alongside the rest of the security architecture and can be recreated during future deployments.

## Phase 5 Validation

Verified that:

* Amazon GuardDuty is enabled.
* The GuardDuty detector was created through Terraform.
* GuardDuty is actively monitoring the AWS environment.
* The GuardDuty dashboard is available for reviewing security findings.
* Findings can be categorized and prioritized by severity.
* GuardDuty can be suspended or disabled from its current active state.
* Existing infrastructure remained unchanged during deployment.

## Phase 5 Outcome

The environment now includes managed threat detection in addition to centralized logging and custom CloudWatch monitoring.

The security visibility built so far can be viewed as:

AWS Activity → CloudTrail → S3

for retained audit evidence,

AWS Activity → CloudTrail → CloudWatch → Metric Filter → Alarm

for custom event-based detection, and

AWS Telemetry → GuardDuty → Security Findings

for managed threat detection.

This gives the environment multiple layers of security visibility rather than relying on a single logging or detection mechanism.

The next step is to add an alerting path so important security detections can be delivered outside the AWS Console for review and response.

---

# Phase 6 - Security Alerting

## Alerting Goal

Extended the monitoring environment so security detections can generate notifications outside the AWS Console.

The previous monitoring phases provided centralized logging, custom detection, CloudWatch alarms, and GuardDuty threat detection. However, an alarm that only exists inside the AWS Console still requires someone to actively check it.

The goal of this phase was to create a notification path that can bring a detected event to my attention automatically.

## Amazon SNS

Created an Amazon SNS topic through Terraform named:

secure-aws-terraform-lab-security-alerts

The SNS topic acts as the notification layer between security monitoring services and the person responsible for reviewing an alert.

This separates detection from notification. CloudWatch determines when the monitored condition has been met, while SNS handles delivery of the resulting alert.

## CloudWatch Alarm Integration

Updated the existing unauthorized API call CloudWatch alarm to use the SNS topic as an alarm action.

The resulting detection and notification path is:

CloudTrail → CloudWatch Logs → Metric Filter → CloudWatch Alarm → SNS → Email

The alarm is configured to notify the SNS topic when it enters the ALARM state.

This means activity matching the existing AccessDenied or UnauthorizedOperation detection can result in an external notification rather than remaining visible only within CloudWatch.

## Email Subscription

Created an email subscription to the SNS security alerts topic.

The notification email address is provided to Terraform through a local terraform.tfvars file rather than being hardcoded into the Terraform module.

The local variable file is excluded from Git version control. This keeps the personal email address out of the public repository while still allowing Terraform to manage the SNS subscription.

The SNS email subscription was manually confirmed through the AWS confirmation email before it could receive notifications.

## Alert Validation

I wanted to verify the notification path itself rather than assuming that a configured SNS action meant alerts would successfully reach their destination.

The CloudWatch alarm was therefore placed into the ALARM state using the AWS CLI with a clearly identified test reason:

Phase 6 SNS notification test

This was a controlled notification test and did not require generating malicious traffic or intentionally causing unauthorized activity in the AWS environment.

The test produced the state transition:

OK → ALARM

CloudWatch invoked the configured SNS action and an alarm notification was successfully delivered to the confirmed email subscription.

The received notification included the alarm name, state change, reason for the state change, monitored metric, threshold information, and SNS alarm action.

This provided end-to-end confirmation that the alerting path was functioning.

## Security Design Decisions

I kept the detection and notification components separate.

CloudWatch remains responsible for evaluating the security metric, while SNS provides a reusable notification channel. This design means additional alarms can later send notifications through the same security alerts topic without requiring a separate email configuration for every detection.

I also avoided committing the notification email address to GitHub by passing it through a Git-ignored Terraform variable file.

For testing, I changed the alarm state directly instead of creating suspicious AWS activity. This allowed the notification pipeline to be validated without weakening the environment or generating unnecessary security events.

## Phase 6 Validation

Verified that:

* The SNS security alerts topic was created through Terraform.
* The existing unauthorized API call alarm is connected to the SNS topic.
* The email endpoint is subscribed to the security alerts topic.
* The SNS subscription status is confirmed.
* Personal email information is not stored in the public Terraform configuration.
* CloudWatch alarm actions are enabled.
* The alarm sends notifications to the SNS topic when entering the ALARM state.
* A controlled alarm-state test successfully triggered SNS.
* The resulting CloudWatch alarm notification was successfully received by email.

## Phase 6 Outcome

The environment now has an external notification path for security monitoring.

The monitoring architecture has progressed from simply recording activity to detecting and communicating security events:

AWS Activity → CloudTrail → CloudWatch → Detection → Alarm → SNS → Email

Combined with GuardDuty, the environment now contains centralized audit logging, custom detection logic, managed threat detection, and external security alerting.

The most important result from this phase was verifying the complete notification chain rather than only confirming that the individual AWS resources existed.

The next phase will add AWS WAF to the application architecture so the project includes preventive controls at the public web layer in addition to its existing detection and monitoring controls.

---

# Phase 7 - Web Application Firewall Protection

## WAF Deployment

Added AWS WAF to provide an additional security layer in front of the public application entry point.

Created a regional AWS WAF Web ACL using Terraform and associated it with the existing Application Load Balancer.

The protected application path is now:

Internet → AWS WAF → Application Load Balancer → Private EC2 Instances

This allows HTTP requests to be inspected against security rules before they are forwarded through the load balancer to the private application tier.

## AWS Managed Rules

Configured the Web ACL with two AWS managed rule groups:

* AWSManagedRulesCommonRuleSet
* AWSManagedRulesKnownBadInputsRuleSet

The Common Rule Set provides general protection against common web application attack patterns and suspicious requests.

The Known Bad Inputs rule set adds protection against request patterns that AWS identifies as commonly associated with exploitation attempts or malicious input.

Using AWS managed rule groups provides a maintained baseline of application-layer protection without requiring every detection rule to be created manually.

## Web ACL Behavior

Configured the Web ACL with a default action of Allow.

Requests that do not match a blocking rule are therefore permitted to continue to the Application Load Balancer. Requests that match protections within the managed rule groups can be handled according to the AWS-managed rule actions.

This approach preserves normal application availability while applying security inspection to incoming traffic.

## Load Balancer Integration

Associated the Web ACL directly with the internet-facing Application Load Balancer.

The private EC2 instances remain inaccessible directly from the internet. WAF protects the public application entry point, while the existing security group design continues to restrict backend HTTP traffic to traffic originating from the ALB.

This creates multiple layers of network and application protection:

Internet → WAF inspection → ALB → Application Security Group → Private EC2

## Monitoring and Visibility

Enabled CloudWatch metrics and sampled requests for the Web ACL and its managed rule groups.

This provides visibility into WAF activity and creates a foundation for reviewing how incoming requests are evaluated by the configured protections.

## Design Decisions

* Used a regional Web ACL because the protected resource is an Application Load Balancer.
* Used AWS managed rule groups instead of manually maintaining a large collection of individual WAF rules.
* Applied WAF at the public ALB rather than directly exposing or modifying the private application servers.
* Retained the existing ALB and application security group separation so WAF complements the network controls rather than replacing them.
* Managed both the Web ACL and ALB association through Terraform so the security control remains part of the infrastructure-as-code configuration.

## Phase 7 Validation

Successfully verified:

* The regional Web ACL was created through Terraform.
* The Web ACL is associated with the application load balancer.
* The Web ACL default action is Allow.
* AWSManagedRulesCommonRuleSet is enabled.
* AWSManagedRulesKnownBadInputsRuleSet is enabled.
* CloudWatch metrics are enabled for WAF visibility.
* Sampled requests are enabled.
* The private application instances remain behind the Application Load Balancer.

## Phase 7 Outcome

The public application entry point now has application-layer filtering in addition to the network controls established in earlier phases.

The security model has progressed from relying only on network segmentation and security groups to inspecting web requests before they reach the application infrastructure.

AWS WAF is managed through Terraform and attached directly to the Application Load Balancer, keeping the protection reproducible and version controlled.

---

# Phase 8 - Controlled Security Incident Simulation

## Objective
Simulate a realistic cloud security misconfiguration in a controlled environment so the change could be investigated and remediated using the security controls built throughout the project.

## Scenario
The application EC2 security group was originally configured to accept HTTP traffic on port 80 only from the Application Load Balancer security group.

To simulate a security incident, the Terraform configuration was temporarily modified to replace the restricted ALB source with:

- Protocol: TCP
- Port: 80
- Source: 0.0.0.0/0
- Description: TEMP INCIDENT - overly permissive HTTP

This intentionally exposed the application security group to HTTP traffic from any IPv4 address.

## Terraform Change
The controlled misconfiguration was introduced through Terraform rather than manually changing the AWS resource.

Before applying the change, terraform plan showed:

Plan: 0 to add, 1 to change, 0 to destroy.

The plan showed the existing ALB-only ingress rule being removed and replaced with the temporary 0.0.0.0/0 rule.

## Deployment
The Terraform change was applied to the AWS environment.

After deployment, the EC2 security group was inspected through the AWS Management Console.

The application security group showed:

- Type: HTTP
- Protocol: TCP
- Port: 80
- Source: 0.0.0.0/0
- Description: TEMP INCIDENT - overly permissive HTTP

This confirmed that the insecure configuration was active in the AWS environment.

## Security Impact
The intended architecture restricts application traffic so that EC2 instances receive HTTP requests only through the Application Load Balancer.

Changing the source to 0.0.0.0/0 removed that restriction and created an overly permissive network rule.

This represented a realistic cloud configuration incident involving excessive network exposure.

## Evidence
- 29-change-alb-security-group.png - Terraform plan showing the intentional security group modification
- 31-live-aws-config-with-insecure-state.png - AWS console confirming the insecure rule was active

## Result
A controlled security incident was successfully created using Terraform and verified in AWS.

The environment was intentionally left in the insecure state only long enough to perform the investigation in Phase 9 before remediation.

---

# Phase 9 - Incident Investigation

## Objective

Investigate the intentionally introduced security group misconfiguration using AWS CloudTrail and determine what changed, how the change occurred, and whether the existing monitoring controls detected it.

## Investigation

During Phase 8, the application security group was intentionally modified so HTTP traffic on port 80 was allowed from 0.0.0.0/0 instead of only from the Application Load Balancer security group.

AWS CloudTrail Event History was used to investigate the configuration change.

CloudTrail recorded an AuthorizeSecurityGroupIngress API event associated with the application security group.

The event showed:

- Event source: ec2.amazonaws.com

- Event name: AuthorizeSecurityGroupIngress

- AWS Region: us-east-1

- Protocol: TCP

- Port: 80

- Source CIDR: 0.0.0.0/0

- Description: TEMP INCIDENT - overly permissive HTTP

- The user agent showed that Terraform performed the change

This provided an audit trail showing both the configuration change and the method used to make it.

## Security Analysis

The CloudTrail event confirmed that an ingress rule allowing HTTP traffic from any IPv4 address had been successfully authorized.

The intended architecture restricts the application security group so HTTP traffic is accepted only from the Application Load Balancer security group.

Changing the source to 0.0.0.0/0 violated this restriction and created an unnecessarily broad network rule.

Although the EC2 instances remained in private subnets without public IP addresses, the security group configuration itself no longer followed the intended least-access design.

## Detection Analysis

The existing CloudWatch security alarm remained in the OK state during the incident.

The CloudWatch metric filter created earlier in the project specifically monitors AWS API calls that return authorization errors such as:

- AccessDenied

- UnauthorizedOperation

The security group modification was performed using valid AWS permissions and the API request succeeded. Because the action was authorized, it did not match the existing unauthorized API call detection.

This exposed an important limitation in the monitoring design: an action can be authorized by AWS while still creating an insecure configuration.

Monitoring only failed or unauthorized API calls is therefore not enough to detect every security-relevant infrastructure change.

## Investigation Findings

The investigation determined that:

- The application security group was modified.

- HTTP port 80 was opened to 0.0.0.0/0.

- The change was successfully authorized by AWS.

- Terraform was used to perform the modification.

- CloudTrail recorded the configuration change.

- The existing unauthorized API alarm did not detect the event.

- The insecure configuration violated the intended ALB-only access model.

- Additional detection controls would be required to automatically alert on successful but risky security group changes.

## Evidence

- 29-change-alb-security-group.png - Terraform plan showing the intentional insecure configuration

- 30-cloudtrail-security-group-incident.png - CloudTrail record of the security group modification

- 31-live-aws-config-with-insecure-state.png - AWS console showing the insecure rule active

## Result

CloudTrail provided the audit evidence needed to reconstruct and understand the security event.

The investigation identified what changed, which resource was affected, how the change was performed, and why the existing CloudWatch alarm did not detect it.

This phase demonstrated the difference between logging an event and detecting a security condition. CloudTrail successfully recorded the activity, but the existing detection logic was not designed to identify authorized configuration changes.

The findings from the investigation provided the information needed to remediate the security group through Terraform in Phase 10.

---

# Phase 10 - Terraform Remediation and Recovery

## Objective

Remediate the security group misconfiguration identified during the incident investigation and restore the application tier to its intended secure configuration using Terraform.

The goal was to correct the issue through infrastructure as code rather than manually changing the security group through the AWS Management Console.

## Remediation

The temporary security group rule introduced during Phase 8 allowed HTTP traffic on port 80 from 0.0.0.0/0.

The Terraform configuration was changed back to the original secure design.

The application security group was restored to:

- Protocol: TCP

- Port: 80

- Source: Application Load Balancer security group

- Description: Allow HTTP only from ALB

This removed the overly permissive internet-wide source and restored the intended relationship between the public load-balancing tier and the private application tier.

## Terraform Remediation

Before applying the remediation, terraform plan showed:

Plan: 0 to add, 1 to change, 0 to destroy.

The plan showed that Terraform would remove the temporary 0.0.0.0/0 ingress configuration and restore the Application Load Balancer security group as the only permitted source for HTTP traffic.

The remediation was then applied through Terraform.

No manual security group modification was performed through the AWS Console.

## Security Validation

After the Terraform apply completed, the application security group was inspected through the AWS Management Console.

The inbound configuration showed:

- Type: HTTP

- Protocol: TCP

- Port: 80

- Source: Application Load Balancer security group

- Description: Allow HTTP only from ALB

The temporary 0.0.0.0/0 rule was no longer present.

This confirmed that the application tier had returned to its intended network security configuration.

## Terraform State Validation

A final terraform plan was executed after remediation.

Terraform reported:

No changes. Your infrastructure matches the configuration.

This confirmed that the deployed AWS infrastructure and the Terraform configuration were synchronized again after the incident.

## Remediation Approach

Using Terraform for the remediation preserved infrastructure as code as the authoritative definition of the environment.

Manually fixing the security group in AWS could have corrected the immediate issue, but the insecure configuration would still have existed in the Terraform code and could have been redeployed later.

Correcting the Terraform configuration first ensured that both the deployed resource and the infrastructure definition returned to the secure state.

## Security Outcome

The intended traffic path was restored to:

Internet → AWS WAF → Application Load Balancer → Private EC2 Instances

The application security group once again accepts HTTP traffic only from the Application Load Balancer security group.

The controlled incident demonstrated that a security configuration could be changed, investigated through CloudTrail, analyzed against existing monitoring controls, and remediated through infrastructure as code.

## Evidence

- 30-cloudtrail-security-group-incident.png - CloudTrail evidence used during the investigation

- 31-live-aws-config-with-insecure-state.png - Application security group before remediation

- 32-security-group-remediated.png - Application security group after Terraform remediation

## Phase 10 Outcome

The controlled incident lifecycle was completed successfully.

The project demonstrated:

BUILD → SECURE → MONITOR → TEST → DETECT → INVESTIGATE → REMEDIATE

The insecure security group configuration was identified through CloudTrail investigation and corrected through Terraform.

The final terraform plan confirmed that no configuration drift remained and that the environment had returned to its intended secure baseline.

---

# Phase 11 - CI/CD Security Pipeline

## Objective

Implement an automated CI/CD security pipeline for the Terraform infrastructure so configuration quality and security checks run automatically whenever infrastructure code is pushed to the main branch or submitted through a pull request.

The pipeline was implemented using GitHub Actions.

## GitHub Actions Workflow

A GitHub Actions workflow was created at:

.github/workflows/terraform-security.yml

The workflow was configured to execute automatically on:

- Pushes to the main branch

- Pull requests

This provides automated validation of Terraform changes before they are accepted into the infrastructure codebase.

## Automated Terraform Checks

The pipeline performs several automated checks against the Terraform configuration.

The workflow includes:

- Terraform Format Check

- Terraform Init

- Terraform Validate

- TFLint

- Checkov

Each tool provides a different layer of infrastructure validation and security analysis.

## Terraform Format Check

Terraform fmt is used to verify that the Terraform configuration follows standardized formatting.

During the initial CI run, the format check identified formatting issues in the compute and monitoring modules.

The affected files were reformatted locally using Terraform and committed back to the repository.

This demonstrated that the CI pipeline could detect configuration-quality issues automatically.

## Terraform Validation

Terraform init is executed with the backend disabled so the CI environment can initialize the Terraform configuration without accessing the live Terraform state.

Terraform validate then checks the configuration for syntax and internal consistency.

The validation completed successfully without requiring AWS credentials or deploying infrastructure.

## TFLint

TFLint was integrated into the pipeline to perform Terraform-specific linting.

The initial workflow configuration exposed a compatibility issue with the installed TFLint version because positional directory arguments were no longer supported.

The workflow was corrected to use the supported chdir configuration.

After the correction, TFLint completed successfully.

## Checkov Security Scanning

Checkov was integrated to perform static security analysis against the Terraform infrastructure.

The scan identified multiple infrastructure-hardening recommendations, including controls related to:

- HTTPS and TLS

- EC2 storage encryption

- Application Load Balancer security settings

- Security group ingress and egress

- Logging and monitoring

- Additional production-hardening controls

The findings were reviewed rather than automatically modifying the infrastructure solely to satisfy the scanner.

## Risk-Based Finding Review

One Checkov recommendation identified encryption of the EC2 root volumes.

The proposed Terraform change was tested with terraform plan before deployment.

Terraform showed that enabling the setting on the existing instances would require replacement of the EC2 resources and their target group attachments.

Because this would unnecessarily destroy and recreate working infrastructure late in the project, the change was not applied.

The Terraform configuration was restored and terraform plan confirmed that no infrastructure changes remained.

This demonstrated the importance of reviewing automated security recommendations based on operational impact rather than applying scanner recommendations blindly.

## Checkov CI Behavior

Checkov remained enabled so security findings continue to be visible during automated scans.

The workflow was configured with soft-fail behavior so documented or lab-specific findings do not prevent the entire CI pipeline from completing successfully.

This preserves visibility into security recommendations while allowing intentional design decisions and future hardening opportunities to be evaluated separately.

## Pipeline Validation

After correcting the formatting and TFLint issues, the GitHub Actions workflow completed successfully.

The final automated pipeline successfully executed:

Terraform Format Check → Terraform Init → Terraform Validate → TFLint → Checkov

The complete GitHub Actions job finished successfully, demonstrating that Terraform changes can now be automatically checked whenever the workflow is triggered.

## Security Benefit

The CI/CD pipeline introduces automated security and configuration analysis into the infrastructure development lifecycle.

Instead of relying entirely on manual review, Terraform changes can now be automatically evaluated for:

- Formatting problems

- Invalid Terraform configuration

- Terraform linting issues

- Infrastructure security weaknesses

The pipeline performs analysis only and does not automatically deploy infrastructure or require AWS credentials.

## Evidence

- 33-github-actions-security-workflow.png - GitHub Actions workflow configuration showing the automated Terraform validation, TFLint, and Checkov stages

- 34-github-actions-security-pipeline-success.png - Successful GitHub Actions job showing all Terraform, TFLint, and Checkov stages completing successfully

## Phase 11 Outcome

An automated infrastructure security pipeline was successfully integrated into the project using GitHub Actions.

The pipeline validates Terraform configuration, performs linting, runs static infrastructure security analysis, and provides repeatable security feedback for future code changes.

The implementation also demonstrated a practical DevSecOps workflow by detecting real formatting and configuration issues during development, correcting the pipeline, reviewing security findings, and validating the final automated process.

---