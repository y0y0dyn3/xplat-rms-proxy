variable "app_count" {}
variable "app_image" {}
variable "app_port" {}
variable "fargate_cpu" {}
variable "fargate_memory" {}
variable "stage" {}

variable "region" {
  type    = "string"
  default = "us-west-2"
}

# Configure the remote-state backend.
terraform {
  backend "s3" {
    encrypt = "True"
    acl     = "private"
  }
}

locals {
  production         = "${var.stage == "prod"}"
  base_network_stage = "${ local.production ? "prod" : "dev"}"
  domain_name        = "packages.security.rackspace.com"

  # Dev uses a wildcard cert and the dumb name is *.dev....
  acm_certificate_stage = "${local.production ? "" : "*.dev."}"
  acm_certificate_name  = "${local.acm_certificate_stage}${local.domain_name}"

  # Find the Route53 Hosted Zone
  domain_name_zone = "${local.production ? local.domain_name : format("dev.%s", local.domain_name)}"

  # What's the actual domain name
  domain_name_stage = "${local.production ? "" : var.stage == "dev" ? "dev." : format("%s.dev.", var.stage)}"
  fqdn              = "${local.domain_name_stage}packages.security.rackspace.com"
}

data "aws_caller_identity" "current" {}

# Add base-networking remote state
data "terraform_remote_state" base_network {
  backend = "s3"

  config {
    bucket = "${data.aws_caller_identity.current.account_id}-terraform"
    key    = "rms-proxy-base-network/${local.base_network_stage}/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "${var.region}"
}

# ALB Security group
resource "aws_security_group" "lb" {
  name        = "${var.stage}-rms-proxy-alb}"
  description = "controls access to the rms-proxy ALB"
  vpc_id      = "${data.terraform_remote_state.base_network.vpc_id}"

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create ECS Task
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.stage}-rms-proxy-tasks"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${data.terraform_remote_state.base_network.vpc_id}"

  ingress {
    protocol        = "tcp"
    from_port       = "80"
    to_port         = "${var.app_port}"
    security_groups = ["${aws_security_group.lb.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create ALB
resource "aws_lb" "main" {
  name               = "${var.stage}-rms-proxy-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = ["${data.terraform_remote_state.base_network.public_subnet_ids}"]
  security_groups    = ["${aws_security_group.lb.id}"]
}

resource "aws_lb_target_group" "app" {
  name        = "${var.stage}-rms-proxy"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "${data.terraform_remote_state.base_network.vpc_id}"
  target_type = "ip"
}

data "aws_acm_certificate" "ssl_cert" {
  domain      = "${local.acm_certificate_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}

# Route all traffic from the ALB to the Fargate target group
resource "aws_lb_listener" "https" {
  load_balancer_arn = "${aws_lb.main.id}"
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = "${data.aws_acm_certificate.ssl_cert.arn}"

  default_action {
    target_group_arn = "${aws_lb_target_group.app.id}"
    type             = "forward"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = "${aws_lb.main.id}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ECS - Fargate
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.stage}-rms-proxy"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.fargate_cpu}"
  memory                   = "${var.fargate_memory}"

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.fargate_cpu},
    "image": "${var.app_image}",
    "memory": ${var.fargate_memory},
    "name": "${var.stage}-rms-proxy",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${var.app_port},
        "hostPort": ${var.app_port}
      }
    ]
  }
]
DEFINITION
}

resource "aws_ecs_service" "main" {
  name            = "${var.stage}-rms-proxy-service"
  cluster         = "${data.terraform_remote_state.base_network.ecs_cluster_id}"
  task_definition = "${aws_ecs_task_definition.app.arn}"
  desired_count   = "${var.app_count}"
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = ["${aws_security_group.ecs_tasks.id}"]
    subnets         = ["${data.terraform_remote_state.base_network.private_subnet_ids}"]
  }

  load_balancer {
    target_group_arn = "${aws_lb_target_group.app.id}"
    container_name   = "${var.stage}-rms-proxy"
    container_port   = "${var.app_port}"
  }

  depends_on = [
    "aws_lb_listener.http",
    "aws_lb_listener.https",
  ]
}

# Fetch the Route53 Zone
data "aws_route53_zone" "packages" {
  name = "${local.domain_name_zone}"
}

# Point ALIAS record to ALB
resource "aws_route53_record" "packages" {
  zone_id = "${data.aws_route53_zone.packages.zone_id}"
  name    = "${local.fqdn}"
  type    = "A"

  alias {
    name                   = "${aws_lb.main.dns_name}"
    zone_id                = "${aws_lb.main.zone_id}"
    evaluate_target_health = true
  }
}
