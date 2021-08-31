output "current_region" {
  value = data.aws_region.current.name
}

output "availability_zones" {
  value = data.aws_availability_zones.available.names
}

output "current_account_id" {
  value = data.aws_caller_identity.current.account_id
}
output "current_id" {
  value = data.aws_caller_identity.current.id
}

output "vpc" {
  value = aws_vpc.vpc_ecs
}

# output "aws_key_pair"{
#   value=aws_key_pair.generated_key.public_key
# }

output "aws_lb_external" {
  value = aws_lb.lb
}

output "backet" {
  value = data.aws_s3_bucket.selected
}
