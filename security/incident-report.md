# Security Incident Report - Overly Permissive Security Group

## Executive Summary

A controlled cloud security incident was conducted within the AWS lab environment to demonstrate the investigation and remediation of an infrastructure misconfiguration.

The application EC2 security group was intentionally modified through Terraform to allow HTTP traffic on TCP port 80 from 0.0.0.0/0 instead of restricting traffic to the Application Load Balancer security group.

AWS CloudTrail was used to investigate the change and identify the API activity responsible for the modification. The incident also demonstrated a limitation in the existing CloudWatch detection logic because the configuration change was authorized and therefore did not trigger the unauthorized API activity alarm.

The insecure configuration was subsequently removed through Terraform and the original ALB-only security group rule was restored.

## Incident Type

Cloud infrastructure misconfiguration resulting in excessive network exposure.

## Affected Resource

The application-tier EC2 security group protecting the private EC2 instances.

## Intended Configuration

The intended architecture permits HTTP traffic to the application instances only through the Application Load Balancer.

Expected traffic path:

Internet → AWS WAF → Application Load Balancer → Private EC2 Instances

The application security group should therefore accept:

- Protocol: TCP

- Port: 80

- Source: Application Load Balancer security group

## Security Event

For the controlled simulation, the Terraform configuration was temporarily changed to allow:

- Protocol: TCP

- Port: 80

- Source: 0.0.0.0/0

- Description: TEMP INCIDENT - overly permissive HTTP

The change was applied through Terraform and verified in the AWS Management Console.

## Detection

AWS CloudTrail recorded the infrastructure modification as an EC2 API event.

The investigation identified:

- Event source: ec2.amazonaws.com

- Event name: AuthorizeSecurityGroupIngress

- AWS Region: us-east-1

- Protocol: TCP

- Port: 80

- Source CIDR: 0.0.0.0/0

- Terraform identified in the user agent

This provided an audit trail showing what changed and how the change was performed.

## Detection Gap

The existing CloudWatch security alarm monitored API activity containing authorization failures such as:

- AccessDenied

- UnauthorizedOperation

The security group modification was performed with valid AWS permissions and the API request succeeded.

Because the activity was authorized, it did not match the existing unauthorized API call metric filter.

This demonstrated an important distinction between logging and detection. CloudTrail successfully recorded the event, but the existing detection rule was not designed to identify successful but risky configuration changes.

## Security Impact

The change violated the intended network access model by allowing the application security group to accept HTTP traffic from any IPv4 address instead of only from the Application Load Balancer.

The EC2 instances remained deployed in private subnets without public IP addresses, which reduced direct internet exposure. However, the security group itself was still unnecessarily permissive and no longer followed the intended least-access design.

## Root Cause

The incident was intentionally introduced through a Terraform configuration change as part of the controlled security exercise.

In a real environment, a similar condition could result from:

- Incorrect Infrastructure as Code changes

- Excessive IAM permissions

- Inadequate peer review

- Manual configuration changes

- Missing preventative policy controls

- Insufficient detection of security group modifications

## Investigation

CloudTrail Event History was reviewed to reconstruct the security event.

The recorded API activity confirmed that the security group ingress rule had been modified successfully and that Terraform performed the change.

The live AWS configuration was then compared with the intended Terraform architecture to confirm the security impact.

## Remediation

The insecure 0.0.0.0/0 ingress configuration was removed from Terraform.

The original rule was restored so that HTTP traffic on port 80 was accepted only from the Application Load Balancer security group.

The remediation was performed through Terraform rather than manually modifying the AWS resource.

This ensured that both the deployed infrastructure and its Infrastructure as Code definition returned to the intended secure configuration.

## Validation

After remediation:

- The application security group was inspected in AWS.

- The 0.0.0.0/0 HTTP rule was no longer present.

- The Application Load Balancer security group was restored as the HTTP source.

- A final terraform plan reported no changes.

This confirmed that the AWS environment and Terraform configuration were synchronized with the secure baseline.

## Preventative Improvements

Several controls could improve detection or prevention of similar incidents in a production environment:

- Alerting on security group ingress modifications

- AWS Config rules for overly permissive security groups

- Infrastructure security scanning during CI/CD

- Pull request review requirements for Terraform changes

- Least-privilege IAM permissions

- Policy-as-code controls preventing prohibited CIDR ranges

- Continuous configuration monitoring

The project subsequently integrated TFLint and Checkov into GitHub Actions to provide automated analysis of future Terraform changes.

## Lessons Learned

CloudTrail logging provides critical forensic evidence, but logging alone does not guarantee that risky activity will generate an alert.

Authorized infrastructure changes can still create security vulnerabilities.

Infrastructure as Code provides an effective remediation mechanism because the secure configuration can be restored through the same controlled deployment process used to manage the environment.

Automated CI/CD security scanning provides another layer of defense by identifying potential infrastructure weaknesses before deployment.

## Evidence

- docs/screenshots/29-change-alb-security-group.png - Terraform plan introducing the controlled misconfiguration

- docs/screenshots/30-cloudtrail-security-group-incident.png - CloudTrail evidence of the security group modification

- docs/screenshots/31-live-aws-config-with-insecure-state.png - AWS configuration showing the insecure rule

- docs/screenshots/32-security-group-remediated.png - Restored application security group after remediation

---

