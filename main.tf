terraform {
  required_providers {
    aws = ">= 3.0"
  }
}

provider "aws" {
  profile = var.profile
  region  = var.region
}

terraform {
  backend "s3" {
    bucket  = var.bucket_name                                       // Bucket where to SAVE Terraform State
    key     = "terraform/L7_ecs_with_instances/terraform.tfstate.*" // Object name in the bucket to SAVE Terraform State
    region  = "us-east-1"                                           // Region where bucket is created
    encrypt = true
  }
}
//=============================locals=======================================================
locals {
  av_zones = ["${data.aws_region.current.name}a", "${data.aws_region.current.name}b"]
}
//===============================vpc=========================================================
resource "aws_vpc" "vpc_ecs" {
  cidr_block       = var.vpc_cidr
  instance_tenancy = "default"

  tags = {
    Name = "vpc for ecs cluster"
  }
}
//=============================subnets public==================================================
resource "aws_subnet" "public_subnets" {
  vpc_id                  = aws_vpc.vpc_ecs.id
  count                   = length(local.av_zones)
  availability_zone       = local.av_zones[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  map_public_ip_on_launch = true
  tags = {
    Name   = "Public subnet-${count.index} in ${local.av_zones[count.index]}"
    vpc_id = aws_vpc.vpc_ecs.id
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc_ecs.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "public rt"
  }
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table_association" "rt_to_sub_public" {
  count          = length(aws_subnet.public_subnets[*].id)
  route_table_id = aws_route_table.public_rt.id
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
}

# resource "aws_subnet" "public_subnets" {
#   vpc_id = aws_vpc.vpc_ecs.id
#   for_each = {
#     1 = "${data.aws_region.current.name}a"
#     2 = "${data.aws_region.current.name}b"
#   }
#   availability_zone       = each.value
#   cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.key)
#   map_public_ip_on_launch = true
#   tags = {
#     Name   = "Public in ${each.value}"
#     vpc_id = aws_vpc.vpc_ecs.id
#   }
# }

//=====================================subnet private============================================
resource "aws_subnet" "privat_subnets" {
  vpc_id            = aws_vpc.vpc_ecs.id
  count             = length(local.av_zones)
  availability_zone = local.av_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 11)
  tags = {
    Name   = "Private subnet-${count.index} in ${local.av_zones[count.index]}"
    vpc_id = aws_vpc.vpc_ecs.id
  }
}

resource "aws_route_table" "privat_rt" {
  count  = length(aws_subnet.privat_subnets[*].id)
  vpc_id = aws_vpc.vpc_ecs.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_gw[count.index].id
  }
  tags = {
    Name = "privat rt ${count.index + 1}"
  }
}

resource "aws_route_table_association" "rt_to_sub_privat" {
  count          = length(aws_subnet.privat_subnets[*].id)
  route_table_id = aws_route_table.privat_rt[count.index].id
  subnet_id      = element(aws_subnet.privat_subnets[*].id, count.index)
}

//==========================network=======================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_ecs.id
  tags = {
    Name = "Internet gateway for ecs"
  }
}

resource "aws_eip" "eip" {
  count = length(local.av_zones)
  vpc   = true
  tags = {
    "Name" = "nat-gw ip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "nat_gw" {
  count         = length(aws_subnet.privat_subnets[*].id)
  allocation_id = aws_eip.eip[count.index].id
  subnet_id     = element(aws_subnet.public_subnets[*].id, count.index)
  tags = {
    Name = "nat-gw-${count.index + 1}"
  }
}

//=======================================ssh key=================================================================
# resource "tls_private_key" "key_algorithm" {
#   algorithm = "RSA"
#   rsa_bits  = 4096
# }

# resource "aws_key_pair" "generated_key" {
#   key_name   = local.key_name
#   public_key = tls_private_key.key_algorithm.public_key_openssh
# }

//=========================================security groups===============================================================
resource "aws_security_group" "sg_for_instances" {
  name   = "sg_for_instances"
  vpc_id = aws_vpc.vpc_ecs.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SecurityGroup ssh"
  }
}

resource "aws_security_group" "sg_for_lb" {
  name   = "sg_for_lb"
  vpc_id = aws_vpc.vpc_ecs.id

  dynamic "ingress" {
    for_each = ["80", "8080", "443"]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SecurityGroup lb"
  }
}

//=========================================instance===============================================================
resource "aws_launch_configuration" "lanch_conf" {
  name_prefix   = "terraform-lc-"
  image_id      = data.aws_ami.latest_amazon_linux2.id
  instance_type = "t2.micro"
  key_name      = "aws_ec2_key"
  # key_name        = local.key_name1
  security_groups      = [aws_security_group.sg_for_instances.id, aws_security_group.sg_for_lb.id]
  iam_instance_profile = aws_iam_instance_profile.instance_profile.id
  user_data            = data.template_file.userdata.rendered
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ag_for_ecs" {
  name = "ag"
  # availability_zones   = local.av_zones
  vpc_zone_identifier  = aws_subnet.privat_subnets[*].id
  launch_configuration = aws_launch_configuration.lanch_conf.name
  min_size             = 1
  max_size             = 5
  desired_capacity     = 3
  lifecycle {
    create_before_destroy = true
  }
}

//==============================================ecs cluster=========================================
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs_cluster-1"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

//====================================================iam===========================================
resource "aws_iam_role" "instance_role" {
  name               = "ecs-container-instance-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TrustEC2",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ec2_container_service_policy_attachment" {
  role       = aws_iam_role.instance_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  role       = aws_iam_role.instance_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "iam_profile"
  role = aws_iam_role.instance_role.id
}

//==========================================ecs tasks and services==============================================
resource "aws_ecs_service" "ecs_service1" {
  name            = "test-service1"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.hello_world_task.arn
  desired_count   = 2

  load_balancer {
    target_group_arn = aws_lb_target_group.port80.arn
    container_name   = "hello-world"
    container_port   = 80
  }

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in [${local.av_zones[0]}, ${local.av_zones[1]}]"
  }
  depends_on = [aws_alb_listener.alb_l_80]
}

resource "aws_ecs_task_definition" "hello_world_task" {
  family                = "tests"
  container_definitions = <<EOF
[
  {
    "name": "hello-world",
    "image": "tutum/hello-world",
    "memoryReservation": 256,
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 80
      }
    ]
  }
]
EOF
}
//========
resource "aws_ecs_service" "ecs_service2" {
  name            = "test-service2"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.nginx_task.arn
  desired_count   = 1

  load_balancer {
    target_group_arn = aws_lb_target_group.port8080.arn
    container_name   = "nginx"
    container_port   = 80
  }

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in [${local.av_zones[0]}, ${local.av_zones[1]}]"
  }
  depends_on = [aws_alb_listener.alb_l_8080]
}

resource "aws_ecs_task_definition" "nginx_task" {
  family                = "nginx"
  container_definitions = <<EOF
[
  {
    "name": "nginx",
    "image": "nginx:latest",
    "memoryReservation": 256,
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 8080
      }
    ]
  }
]
EOF
}

//==============================
resource "aws_lb_target_group" "port80" {
  name       = "lb-tg80"
  port       = 80
  protocol   = "HTTP"
  vpc_id     = aws_vpc.vpc_ecs.id
  depends_on = [aws_lb.lb]
}

resource "aws_lb_target_group" "port8080" {
  name       = "lb-tg8080"
  port       = 8080
  protocol   = "HTTP"
  vpc_id     = aws_vpc.vpc_ecs.id
  depends_on = [aws_lb.lb]

}

resource "aws_lb" "lb" {
  name               = "lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg_for_lb.id]
  subnets            = aws_subnet.public_subnets[*].id
  subnet_mapping {
    subnet_id = aws_subnet.privat_subnets[0].id
  }
  subnet_mapping {
    subnet_id = aws_subnet.privat_subnets[1].id
  }
  # access_logs {
  #   bucket  = data.aws_s3_bucket.selected.arn
  #   prefix  = "test-lb"
  #   enabled = true
  # }
}

resource "aws_alb_listener" "alb_l_80" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.port80.arn
  }
}

resource "aws_alb_listener" "alb_l_8080" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.port8080.arn
  }
}
