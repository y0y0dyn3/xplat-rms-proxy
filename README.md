# RMS Packages Proxy

Proxies HTTPS requests to various vendor agent packages through one location.

## Architecture
* Public Subnet(s)
  * Internet Gateway for incoming requests.
  * AWS ALB listening on HTTP (with HTTPS redirect) and HTTPS.
  * Security Group on ALB allows 80/443 Ingress and all Egress.
* Private Subnet(s)
  * No Internet Gateway - no implicit external access.
  * Fargate ECS service set to target group for the HTTPS listener on ALB.
  * Security Group for Fargate service only allows Ingress traffic from ALB and all Egress.
  * NAT Gateways with EIPs to route egress traffic from Fargate service to internet.

## Services
* `services/rms-proxy` - ALB, security groups, Fargate service and task, and DNS configuration. This can be deployed per user for testing purposes. Users will get their own ALB, Fargate service, task, and DNS record. `rms-proxy-base-network` must be run on the account first before running this.
* `services/rms-proxy-base-network` - VPC, subnets, route tables, EIPs, NAT Gateways, and ECS cluster configuration. This should only be run per account (dev/prod) and NOT per user.

## Endpoints
* user stages: https://<github_username>.dev.packages.security.rackspace.com
* dev stage: https://dev.packages.security.rackspace.com
* prod stage: https://packages.security.rackspace.com
