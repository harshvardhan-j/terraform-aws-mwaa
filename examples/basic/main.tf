#####################################################################################
# Terraform module examples are meant to show an _example_ on how to use a module
# per use-case. The code below should not be copied directly but referenced in order
# to build your own root module that invokes this module
#####################################################################################
provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
  account_id = data.aws_caller_identity.current.account_id
}

#-----------------------------------------------------------
# Create an S3 bucket and upload sample DAG 
#-----------------------------------------------------------

resource "aws_s3_bucket" "dags" {
  bucket = var.mwaas3bucket  
  tags = var.tags
}

resource "aws_s3_bucket_acl" "dags" {
  bucket = aws_s3_bucket.dags.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "dags" {
  bucket = aws_s3_bucket.dags.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "dags" {
  bucket = aws_s3_bucket.dags.id
  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

# Upload DAGS

resource "aws_s3_object" "object1" {
for_each = fileset("dags/", "*")
bucket = aws_s3_bucket.dags.id
key = "dags/${each.value}"
source = "dags/${each.value}"
etag = filemd5("dags/${each.value}")
}

# Upload plugins/requirements.txt

resource "aws_s3_object" "reqs" {
for_each = fileset("mwaa/", "*")
bucket = aws_s3_bucket.dags.id
key = "${each.value}"
source = "mwaa/${each.value}"
etag = filemd5("mwaa/${each.value}")
}

#-----------------------------------------------------------
# NOTE: MWAA Airflow environment takes minimum of 20 mins
#-----------------------------------------------------------
module "mwaa" {
  source = "../.."

  name                 = "basic-mwaa"
  airflow_version      = "2.2.2"
  environment_class    = "mw1.medium"
  source_bucket_arn    = "arn:aws:s3:::${var.mwaas3bucket}"
  dag_s3_path          = "dags"

  ## If uploading requirements.txt or plugins, you can enable these via these options
  #plugins_s3_path      = "plugins.zip"
  #requirements_s3_path = "requirements.txt"

  logging_configuration = {
    dag_processing_logs = {
      enabled   = true
      log_level = "INFO"
    }

    scheduler_logs = {
      enabled   = true
      log_level = "INFO"
    }

    task_logs = {
      enabled   = true
      log_level = "INFO"
    }

    webserver_logs = {
      enabled   = true
      log_level = "INFO"
    }

    worker_logs = {
      enabled   = true
      log_level = "INFO"
    }
  }

  airflow_configuration_options = {
    "core.load_default_connections" = "false"
    "core.load_examples" = "false"
    "webserver.dag_default_view" = "tree"
    "webserver.dag_orientation" = "TB"
  }

  min_workers        = 1
  max_workers        = 2
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  webserver_access_mode = "PUBLIC_ONLY"   # Choose the Private network option(PRIVATE_ONLY) if your Apache Airflow UI is only accessed within a corporate network, and you do not require access to public repositories for web server requirements installation
  source_cidr           = ["10.1.0.0/16"] # Add your IP address to access Airflow UI

  # create_security_group = true # change to to `false` to bring your sec group using `security_group_ids`
  # execution_role_arn = "<ENTER_YOUR_IAM_ROLE_ARN>" # Module creates a new IAM role if `execution_role_arn` is not specified

  tags = var.tags
}

#---------------------------------------------------------------
# Supporting Resources
#---------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = var.name
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = var.tags
}
