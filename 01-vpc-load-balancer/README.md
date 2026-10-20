# VPC + Application Load Balancer + Auto Scaling (Terraform)

This project provisions a self-contained, internet-facing web tier on AWS using
Terraform. It creates a VPC with public and private subnets across two
Availability Zones, an Application Load Balancer (ALB) in the public subnets,
and an Auto Scaling Group (ASG) of EC2 instances in the private subnets.

Each EC2 instance runs a small Python "echo" HTTP server, so hitting the ALB
returns a response showing **which instance answered** — a simple way to verify
that load balancing and the network path work end-to-end.

## Architecture

```
                          Internet
                              │
                              ▼
                   ┌────────────────────┐
                   │  Internet Gateway  │
                   └─────────┬──────────┘
                             │  (public route table: 0.0.0.0/0 → IGW)
              ┌──────────────┴───────────────┐
              │        Public subnets         │
              │   10.10.1.0/24 (eu-1a)        │
              │   10.10.2.0/24 (eu-1b)        │
              │   ┌───────────────────────┐   │
              │   │  Application LB (ALB) │   │  <- alb_sg: 80 from 0.0.0.0/0
              │   └───────────┬───────────┘   │
              └───────────────┼───────────────┘
                              │  listener :80 → target group
              ┌───────────────┼───────────────┐
              │        Private subnets        │
              │   10.10.11.0/24 (eu-1a)       │
              │   10.10.12.0/24 (eu-1b)       │
              │   ┌───────────────────────┐   │
              │   │  ASG (EC2 instances)  │   │  <- instance_sg: 80 from alb_sg
              │   │  Python echo server   │   │
              │   └───────────────────────┘   │
              └───────────────────────────────┘
```

- **No NAT gateway.** The instances do not need outbound internet access — the
  echo server is written inline in `user_data` and uses only built-in tools, so
  there is nothing to download at boot. This keeps the design simple and avoids
  NAT gateway costs.
- **Instances are private.** They have no public IP and are reachable only
  through the ALB. Traffic from the internet reaches the ALB (public subnets),
  and the ALB reaches the instances over the VPC (private subnets).

## Resources created

| File | Resources |
|---|---|
| `network.tf` | VPC, 2 public + 2 private subnets, Internet Gateway, public route table + associations |
| `security.tf` | ALB security group, instance security group |
| `loadbalancer.tf` | Target group, Application Load Balancer, HTTP listener |
| `compute.tf` | Launch template (AL2023 + echo server), Auto Scaling Group, ALB attachment |
| `scaling.tf` | Scale-up / scale-down policies, CPU high/low CloudWatch alarms |
| `data.tf` | SSM lookup for the latest Amazon Linux 2023 AMI |
| `locals.tf` | Single source of truth for VPC CIDR, subnet CIDRs, and AZs |

## Scaling behavior

The ASG starts with **1** instance (`desired_capacity = 1`), scaling between
**1 and 3**:

- **Scale up** when average CPU ≥ 70% for 2 × 60s periods.
- **Scale down** (one instance at a time) when average CPU ≤ 30% for 5 × 60s periods.

## Files

```
.
├── versions.tf        # Terraform + provider version constraints, AWS provider
├── data.tf            # Data sources (AMIs)
├── network.tf         # VPC, subnets, IGW, route tables
├── security.tf        # Security groups
├── loadbalancer.tf    # ALB, target group, listener
├── compute.tf         # Launch template, ASG, target group attachment
├── scaling.tf         # Autoscaling policies + CloudWatch alarms
├── variables.tf       # Input variables
├── terraform.tfvars   # Variable values for this environment
└── outputs.tf         # Outputs (ALB DNS name)
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `instance_type` | EC2 instance type | `c5.large` |
| `instance_name` | Value of the EC2 instance's `Name` tag | `learn-terraform` |

Values are set in `terraform.tfvars`.

## Outputs

| Name | Description |
|---|---|
| `alb_dns_name` | Public DNS name of the Application Load Balancer |

## Usage

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Once applied, wait ~1–2 minutes for the target to become healthy, then test:

```bash
curl http://$(terraform output -raw alb_dns_name)/
```

Curl a few times — the `Hello from <hostname>` line changes as different
instances respond, confirming load balancing works.

## Testing notes

- Targets report **unhealthy** for the first ~30–60s while the health check
  catches up. This is normal.
- **`curl` hangs** → security group misconfigured.
- **`curl` returns `503`** → target group empty or targets still unhealthy
  (check that the echo server is running on port 80 on the instances).

## Teardown

```bash
terraform destroy
```

## Cleaning up / cost

The design is intentionally minimal to keep costs low (no NAT gateway). Main
cost drivers are the ALB and the EC2 instances. Remember to `destroy` when done
if you are only learning.
