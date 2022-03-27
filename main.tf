# route53 zone for simtooreal
data "aws_route53_zone" "zone_simtooreal" {
  name    = "simtooreal.com"
  private_zone = false
}

# route53 record for private EC2 instance so that no long ip addresses need to be remembered
resource "aws_route53_record" "record_private_simtooreal" {
  name    = "private.simtooreal.com"
  zone_id = data.aws_route53_zone.zone_simtooreal.id
  type    = "A"
  ttl     = 30

  records = [aws_instance.simtooreal_private.private_ip]
}

# route53 record for public EC2 instance so that no long ip addresses need to be remembered
resource "aws_route53_record" "record_public_simtooreal" {
  name    = "public.simtooreal.com"
  zone_id = data.aws_route53_zone.zone_simtooreal.id
  type    = "A"
  ttl     = 30

  records = [aws_instance.simtooreal_public.public_ip]
}

# simtooreal certificate managed by Terraform
resource "aws_acm_certificate" "simtooreal" {
  domain_name       = "*.simtooreal.com"
  validation_method = "DNS"
  subject_alternative_names = ["simtooreal.com"]

  tags = {
    Description = "simtooreal certificate managed by Terraform"
    Name        = "simtooreal"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# validation record for simtooreal cert
resource "aws_route53_record" "simtooreal_validation" {
  name    = sort(aws_acm_certificate.simtooreal.domain_validation_options[*].resource_record_name)[0]
  type    = sort(aws_acm_certificate.simtooreal.domain_validation_options[*].resource_record_type)[0]
  records = [sort(aws_acm_certificate.simtooreal.domain_validation_options[*].resource_record_value)[0]]
  zone_id = data.aws_route53_zone.zone_simtooreal.id
  ttl     = "300"
}

# cert for simtooreal
resource "aws_acm_certificate_validation" "simtooreal" {
  certificate_arn         = aws_acm_certificate.simtooreal.arn
  validation_record_fqdns = [aws_route53_record.simtooreal_validation.fqdn]
}

### IAM/ECR

# ecr for holding all images
resource "aws_ecr_repository" "simtooreal" {
  name                 = "simtooreal"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ecr admin role for simtooreal
resource "aws_iam_user" "simtooreal_ecr_admin" {
  name = "simtooreal_ecr_admin"

  tags = {
    tag-key = "simtooreal"
  }
}

# ecr admin policy for simtooreal
resource "aws_iam_user_policy" "simtooreal_ecr_admin" {
  name = "simtooreal_ecr_admin"
  user = aws_iam_user.simtooreal_ecr_admin.name

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "ecr:*",
            "Resource": "*"
        }
    ]
}
EOF
}

# instance profile for reading s3 from an EC2 instance
# which could be useful for a bastion or prepoluating instances with files
resource "aws_iam_instance_profile" "simtooreal_s3_public_read" {
  name     = "simtooreal_s3_public_read"
}

resource "aws_iam_instance_profile" "simtooreal_s3_private_read" {
  name     = "simtooreal_s3_private_read"
}

resource "aws_iam_role" "simtooreal_s3_read" {
  name = "simtooreal_s3_read"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

# role policy attachment for reading s3
resource "aws_iam_role_policy_attachment" "simtooreal_s3_public_read" {
  role       = aws_iam_role.simtooreal_s3_read.name
  policy_arn = aws_iam_policy.simtooreal_s3_public_read.arn
}

# role policy attachment for reading s3
resource "aws_iam_role_policy_attachment" "simtooreal_s3_private_read" {
  role       = aws_iam_role.simtooreal_s3_read.name
  policy_arn = aws_iam_policy.simtooreal_s3_private_read.arn
}

# IAM policy for reading s3 in simtooreal
resource "aws_iam_policy" "simtooreal_s3_public_read" {
  name               = "simtooreal_s3_public_read"
  description        = "Policy to allow S3 reading of bucket simtooreal-public"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "ssm:GetParametersByPath",
                "ssm:GetParameters",
                "ssm:GetParameter"
            ],
            "Resource": [
                "arn:aws:s3:::simtooreal-public/*",
                "arn:aws:ssm:${var.aws_region}:*:parameter/parameter/production/RAISIM_API_KEY"
            ]
        }
    ]
}
EOF
}

# IAM policy for reading s3 in simtooreal
resource "aws_iam_policy" "simtooreal_s3_private_read" {
  name               = "simtooreal_s3_private_read"
  description        = "Policy to allow S3 reading of bucket simtooreal-private and ssm"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "ssm:GetParametersByPath",
                "ssm:GetParameters",
                "ssm:GetParameter"
            ],
            "Resource": [
                "arn:aws:s3:::simtooreal-private/*",
                "arn:aws:ssm:${var.aws_region}:*:parameter/parameter/production/RAISIM_API_KEY"
            ]
        }
    ]
}
EOF
}

### Networking and subnets

# AWS VPC for simtooreal
resource "aws_vpc" "simtooreal" {
  cidr_block = "172.17.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Description = "Scalable AI platform"
    Environment = "production"
    Name        = "simtooreal"
  }
}

# Fetch Availability Zones in the current region
data "aws_availability_zones" "simtooreal" {
}

# Create var.az_count private subnets, each in a different AZ
resource "aws_subnet" "simtooreal_private" {
  count             = var.az_count
  cidr_block        = cidrsubnet(aws_vpc.simtooreal.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.simtooreal.names[count.index]
  vpc_id            = aws_vpc.simtooreal.id

  tags = {
    Description = "Scalable AI platform"
    Environment = "production"
  }
}

# Create var.az_count public subnets, each in a different AZ
resource "aws_subnet" "simtooreal_public" {
  count = var.az_count
  cidr_block = cidrsubnet(
    aws_vpc.simtooreal.cidr_block,
    8,
    var.az_count + count.index,
  )
  availability_zone       = data.aws_availability_zones.simtooreal.names[count.index]
  vpc_id                  = aws_vpc.simtooreal.id
  map_public_ip_on_launch = true

  tags = {
    Description = "simtooreal public subnet managed by Terraform"
    Environment = "production"
  }
}

# Create var.az_count rds subnets, each in a different AZ
resource "aws_subnet" "simtooreal_rds" {
  count = var.az_count
  cidr_block = cidrsubnet(
    aws_vpc.simtooreal.cidr_block,
    8,
    2 * var.az_count + 1 + count.index,
  )
  availability_zone = data.aws_availability_zones.simtooreal.names[count.index]
  vpc_id            = aws_vpc.simtooreal.id

  tags = {
    Description = "simtooreal RDS subnet managed by Terraform"
    Environment = "production"
  }
}

# IGW for the public subnet
resource "aws_internet_gateway" "simtooreal" {
  vpc_id = aws_vpc.simtooreal.id
}

# Route the public subnet traffic through the IGW
resource "aws_route" "simtooreal_internet_access" {
  route_table_id         = aws_vpc.simtooreal.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.simtooreal.id
}

# Create a NAT gateway with an EIP for each private subnet to get internet connectivity
resource "aws_eip" "simtooreal" {
  count      = var.az_count
  vpc        = true
  depends_on = [aws_internet_gateway.simtooreal]

  tags = {
    Description = "simtooreal gateway EIP managed by Terraform"
    Environment = "production"
  }
}

# NAT gateway for internet access
resource "aws_nat_gateway" "simtooreal" {
  count         = var.az_count
  subnet_id     = element(aws_subnet.simtooreal_public.*.id, count.index)
  allocation_id = element(aws_eip.simtooreal.*.id, count.index)

  tags = {
    Description = "simtooreal gateway NAT managed by Terraform"
    Environment = "production"
  }
}

# Create a new route table for the private subnets
# And make it route non-local traffic through the NAT gateway to the internet
resource "aws_route_table" "simtooreal_private" {
  count  = var.az_count
  vpc_id = aws_vpc.simtooreal.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.simtooreal.*.id, count.index)
  }

  tags = {
    Description = "simtooreal gateway NAT managed by Terraform"
    Environment = "production"
  }
}

# RDS route table for simtooreal
resource "aws_route_table" "simtooreal_rds" {
  count  = var.az_count
  vpc_id = aws_vpc.simtooreal.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.simtooreal.*.id, count.index)
  }

  tags = {
    Description = "simtooreal RDS route table managed by Terraform"
    Environment = "production"
  }
}

# Explicitely associate the newly created route tables to the private subnets (so they don't default to the main route table)
resource "aws_route_table_association" "simtooreal_private" {
  count          = var.az_count
  subnet_id      = element(aws_subnet.simtooreal_private.*.id, count.index)
  route_table_id = element(aws_route_table.simtooreal_private.*.id, count.index)
}

resource "aws_route_table_association" "rsimtooreal_rds" {
  count          = var.az_count
  subnet_id      = element(aws_subnet.simtooreal_rds.*.id, count.index)
  route_table_id = element(aws_route_table.simtooreal_rds.*.id, count.index)
}

### RDS

# subnet used by rds
resource "aws_db_subnet_group" "simtooreal" {
  name        = "simtooreal"
  description = "simtooreal RDS Subnet Group managed by Terraform"
  subnet_ids  = aws_subnet.simtooreal_rds.*.id
}

# Security Group for resources that want to access the database
resource "aws_security_group" "simtooreal_db_access" {
  vpc_id      = aws_vpc.simtooreal.id
  name        = "simtooreal_db_access"
  description = "simtooreal allow access to RDS, managed by Terraform"

  ingress {
    # TLS (change to whatever ports you need)
    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"

    # Please restrict your ingress to only necessary IPs and ports.
    # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
    cidr_blocks = [aws_vpc.simtooreal.cidr_block]
  }
}

# database security group
resource "aws_security_group" "simtooreal_rds" {
  name        = "simtooreal_rds"
  description = "simtooreal RDS security group, managed by Terraform"
  vpc_id      = aws_vpc.simtooreal.id

  //allow traffic for TCP 5432
  ingress {
    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"

    # Please restrict your ingress to only necessary IPs and ports.
    # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
    security_groups = aws_security_group.simtooreal_private.*.id
  }

  // outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# public security group for load balancers and bastions
resource "aws_security_group" "simtooreal_public" {
  name        = "simtooreal_public"
  description = "simtooreal public security group managed by Terraform"
  vpc_id      = aws_vpc.simtooreal.id

  # allows ssh attempts from my IP address
  # you should change this to your IP address
  # or your corporate network
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["69.181.183.147/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### AWS instances

resource "aws_key_pair" "simtooreal" {
  key_name   = "simtooreal"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC60teZFO7BuQVwHSUewqOFGo7Iko16pF/vpio8p0K4PR29KG4oaKd4lRHx0WwX5NlLTxEI5xXQWAN9sRQMz60UDnURKnGbjiy+QI/mL3Ivkt4YV6gEfGYdVChJE6bYpnmUbPn8e27JcIJkBcDEATTEZEvSWi8xNhXWOr3I4m/Jc7OOOZAk7R9roqFlsNQrOCizc543PxCLLKafwFcDNUg+h8EOO3+PVZJziAllRTx53WxYbOUZ1tSXwaiJkXSLhVmSZQU6gXuzjlUe2ZAYwW9XzQj8xvPjFJIgizJthnbFxiAn6BygM+/4YdT+SjdpG1Y3NamXgBPQPKWFX8vBkwxVIGywDqpMVlI8L1DgbU4ISVmkHj+kG8t7iX9NF73fG9M414SBpIZSO7lsXz5rHqoz7VZe5DDl5piVV/thXwaAMMm1kerF1GlWcvUxsABv4yD2DnuqMVPz77dP1abOVpRTr7NcSvQCFv4vcMO+0CAGO/RIn3vYawjLvBFEeICsd35mnWF+PDg4QiSycJpUX9wFnZKsbI+pOEfexHqseuiS+PTOgROVonC7PUzYjFbxT3SRKRsiJxNxmRtbaEjWXZpsEFjDb/ifs9K06mqTF6MqFYXVs4AhTxDuhqQ9EOBg/LG+JUIj76o4cl7VkUJxhYyP9MNO1Ze6AVl7/xmzigsEFQ== chase.brignac@example.com"
}

# public facing instance through which maintenance work is done
# t3a.micro has enough memory to run a Duo bastion but t3a.nano will save money
resource "aws_instance" "simtooreal_public" {
  ami                         = "ami-0fa37863afb290840"
  instance_type               = "t3a.micro"
  subnet_id                   = aws_subnet.simtooreal_public[0].id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.simtooreal_s3_public_read.name
  vpc_security_group_ids      = [aws_security_group.simtooreal_public.id]
  key_name                    = aws_key_pair.simtooreal.key_name
  depends_on                  = [aws_s3_bucket_object.simtooreal_public]
  user_data                   = "#!/bin/bash\necho $USER\ncd /home/ubuntu\npwd\necho beginscript\nexport AWS_ACCESS_KEY_ID=${aws_ssm_parameter.simtooreal_aws_access_key_id.value}\nexport AWS_SECRET_ACCESS_KEY=${aws_ssm_parameter.simtooreal_secret_access_key.value}\necho $AWS_SECRET_ACCESS_KEY\necho $AWS_ACCESS_KEY_ID\nexport AWS_DEFAULT_REGION=us-east-1\nsudo apt-get update -y\nsudo apt-get install awscli -y\nsudo apt-get install awscli -y\naws s3 cp s3://simtooreal-public/bastion.tar.gz ./\napt-get remove docker docker-engine docker-ce docker.io\napt-get install -y apt-transport-https ca-certificates curl software-properties-common\ncurl -fsSL https://download.docker.com/linux/ubuntu/gpg  | apt-key add -\nadd-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable'\napt-get -y install docker-ce\nsystemctl start docker\napt-get install -y docker-compose\nsystemctl enable docker\ntar -zxvf bastion.tar.gz\ncd bastion/examples/compose\ndocker-compose up --build"
  # to troubleshoot your user_data logon to the instance and run this
  #cat /var/log/cloud-init-output.log

  root_block_device {
    volume_size = "20"
    volume_type = "standard"
  }

  # lifecycle {
  #   ignore_changes = [user_data]
  # }

  tags = {
    Name = "simtooreal_public"
  }
}

# private instance inside the private subnet
# reaching RDS is done through this instance
resource "aws_instance" "simtooreal_private" {
  ami           = "ami-0fa37863afb290840"
  instance_type = "t2.nano"
  subnet_id     = aws_subnet.simtooreal_private[0].id

  vpc_security_group_ids      = [aws_security_group.simtooreal_private.id]
  key_name                    = aws_key_pair.simtooreal.key_name
  iam_instance_profile        = aws_iam_instance_profile.simtooreal_s3_private_read.name
  depends_on                  = [aws_s3_bucket_object.simtooreal_private]
  user_data                   = "#!/bin/bash\necho $USER\ncd /home/ubuntu\npwd\necho beginscript\nsudo apt-get update -y\nsudo apt-get install awscli -y\necho $USER\napt-add-repository --yes --update ppa:ansible/ansible\napt -y install ansible\napt install postgresql-client-common\napt-get -y install postgresql\napt-get remove docker docker-engine docker-ce docker.io\napt-get install -y apt-transport-https ca-certificates curl software-properties-common\nexport AWS_ACCESS_KEY_ID=${aws_ssm_parameter.simtooreal_aws_access_key_id.value}\nexport AWS_SECRET_ACCESS_KEY=${aws_ssm_parameter.simtooreal_secret_access_key.value}\nexport AWS_DEFAULT_REGION=us-east-1\naws s3 cp s3://simtooreal-private/simtooreal.tar.gz ./\ntar -zxvf simtooreal.tar.gz\nmv simtooreal data\napt install python3-pip -y\napt-get install tmux"
  # to troubleshoot your user_data logon to the instance and run this
  #cat /var/log/cloud-init-output.log

  root_block_device { 
    volume_size = "50"
    volume_type = "standard"
  }

  # lifecycle {
  #   ignore_changes = [user_data]
  # }

  tags = {
    Name = "simtooreal_private"
  }
}

# Traffic to the private security group should only come from AWS services such as the ALB, DB, or elasticache
resource "aws_security_group" "simtooreal_private" {
  name        = "simtooreal_private"
  description = "Private security group managed by Terraform"
  vpc_id      = aws_vpc.simtooreal.id

  egress {
    protocol        = "tcp"
    from_port       = "5432"
    to_port         = "5432"
    security_groups = [aws_security_group.simtooreal_db_access.id]
  }

  ingress {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22

    # Please restrict your ingress to only necessary IPs and ports.
    # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
    cidr_blocks = [aws_vpc.simtooreal.cidr_block]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### S3

# simtooreal s3 bucket
resource "aws_s3_bucket" "simtooreal_public" {
  bucket = "simtooreal-public"
  acl    = "private"

  tags = {
    Name        = "simtooreal"
    Environment = "production"
  }
}

# simtooreal s3 bucket
resource "aws_s3_bucket" "simtooreal_private" {
  bucket = "simtooreal-private"
  acl    = "private"

  tags = {
    Name        = "simtooreal"
    Environment = "production"
  }
}

# bastion
resource "aws_s3_bucket_object" "simtooreal_public" {
  bucket = aws_s3_bucket.simtooreal_public.bucket
  key    = "bastion.tar.gz"
  source = "bastion.tar.gz"

  # The filemd5() function is available in Terraform 0.11.12 and later
  etag = filemd5("bastion.tar.gz")
}

# tar-ed up simtooreal directory without terraform files
resource "aws_s3_bucket_object" "simtooreal_private" {
  bucket = aws_s3_bucket.simtooreal_private.bucket
  key    = "simtooreal.tar.gz"
  source = "simtooreal.tar.gz"

  # The filemd5() function is available in Terraform 0.11.12 and later
  etag = filemd5("simtooreal.tar.gz")
}

### Systems Manager

# ssm parameter group for database endpoint
resource "aws_ssm_parameter" "openai_api_key" {
  name        = "/parameter/production/RAISIM_API_KEY"
  description = "Your OpenAI API Key"
  type        = "SecureString"
  value       = var.openai_api_key
  overwrite   = "true"

  tags = {
    Name        = "simtooreal"
    environment = "production"
  }
}

# ssm parameter group for user id password
resource "aws_ssm_parameter" "simtooreal_aws_access_key_id" {
  name        = "/parameter/production/AWS_ACCESS_KEY_ID"
  description = "The database password"
  type        = "SecureString"
  value       = var.aws_access_key_id
  overwrite   = "true"

  tags = {
    Name        = "simtooreal"
    environment = "production"
  }
}

# ssm parameter group for user secret endpoint
resource "aws_ssm_parameter" "simtooreal_secret_access_key" {
  name        = "/parameter/production/AWS_SECRET_ACCESS_KEY"
  description = "The database endpoint"
  type        = "SecureString"
  value       = var.aws_secret_access_key
  overwrite   = "true"

  tags = {
    Name        = "simtooreal"
    environment = "production"
  }
}


