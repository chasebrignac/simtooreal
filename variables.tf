terraform {
  backend "remote" {
    organization = "simtooreal"

    workspaces {
      name = "simtooreal"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# The major region is us-east-1
variable "aws_region" {
  description = "The AWS region"
  default     = "us-east-1"
}

# The number of AZs to cover for AZ fault tolerance
variable "az_count" {
  description = "Number of AZs to cover in a given AWS region"
  default     = "2"
}

# The database password should be passed in at terraform runtime by using -var
variable "db_password" {
  description = "Database password"
  default     = "$$${db_password}"
  sensitive   = true
}

# The aws secret should be passed in at terraform runtime by using -var
variable "aws_secret_access_key" {
  description = "AWS access key"
  default     = "$$${aws_secret_access_key}"
  sensitive   = true
}

# The database password should be passed in at terraform runtime by using -var
variable "aws_access_key_id" {
  description = "AWS key ID"
  default     = "$$${aws_access_key_id}"
  sensitive   = true
}