# Phase 1: Terraform Infrastructure - Detailed Implementation Plan

## Overview

This plan details the Terraform infrastructure setup for Katelynn's Photography website, building on patterns established in the `aws-projects` repository. This phase creates all AWS resources needed to support the Astro public portfolio and HTMX/FastAPI client portal.

## Current State Analysis

### Existing Terraform Patterns (from aws-projects)

Based on analysis of `/home/aw-jwalker/repos/aws-projects/`:

- **Backend**: S3 bucket `aw-jwalker-terraform-state` with DynamoDB locking (`terraform-state-lock`)
- **Region**: `us-east-2`
- **Profile**: `jw-dev` (with CI/CD override support)
- **Provider Version**: `~> 5.0`
- **Structure**: Flat per-project (no modules currently)
- **Tags**: `ManagedBy = "Terraform"` via default_tags

### Services NOT Yet in aws-projects (Must Create New)

- CloudFront
- Lambda
- API Gateway
- Cognito
- SES
- Route53 (hosted zone)
- ACM (SSL certificates)

## Desired End State

After completing this phase:

1. **S3 Buckets**:
   - `katelynns-portfolio-assets` - Public images served via CloudFront
   - `katelynns-client-albums` - Private client photos (presigned URL access only)
   - `katelynns-website-hosting` - Astro static site files

2. **CloudFront Distributions**:
   - Public distribution for portfolio website + images
   - Configured with proper caching for images (long TTL)

3. **Cognito User Pool**:
   - Email/password authentication
   - Admin-created accounts for clients
   - Password reset capability

4. **API Gateway**:
   - HTTP API (cheaper than REST API for this use case)
   - CORS configured for website domain
   - Ready for Lambda integration in Phase 2

5. **SES**:
   - Verified domain/email for sending
   - Ready for contact form emails

6. **Route53** (optional - depends on domain):
   - Hosted zone for custom domain
   - DNS records pointing to CloudFront

7. **ACM**:
   - SSL certificate for custom domain (must be in us-east-1 for CloudFront)

### Verification

- `terraform plan` shows no changes after apply
- CloudFront distribution accessible via generated URL
- S3 buckets exist with correct policies
- Cognito user pool accessible in AWS Console
- Can manually upload test image to S3 and access via CloudFront

## What We're NOT Doing

- Lambda function code (Phase 2)
- Astro frontend deployment (Phase 3)
- Client portal code (Phase 3)
- DNS cutover from Wix (Phase 4)
- DynamoDB for album metadata (may add later if needed)

---

## Implementation Approach

Following the aws-projects pattern, we'll create a new project directory within the katelynns-photography repo:

```
katelynns-photography/
├── terraform/
│   ├── main.tf              # Provider config + backend
│   ├── variables.tf         # All variable definitions
│   ├── outputs.tf           # Output values
│   ├── s3.tf                # S3 buckets
│   ├── cloudfront.tf        # CloudFront distributions
│   ├── cognito.tf           # User pool + client
│   ├── api-gateway.tf       # HTTP API
│   ├── ses.tf               # Email service
│   ├── acm.tf               # SSL certificates
│   ├── route53.tf           # DNS (optional)
│   └── terraform.tfvars     # Variable values (gitignored)
├── thoughts/
│   └── shared/
│       └── plans/
└── ...
```

---

## Phase 1.1: Project Setup

### Overview

Create the Terraform project structure and configure the backend.

### Changes Required:

#### 1. Create terraform directory structure

```bash
mkdir -p ~/repos/katelynns-photography/terraform
```

#### 2. Create main.tf

**File**: `terraform/main.tf`

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"

  backend "s3" {
    bucket         = "aw-jwalker-terraform-state"
    key            = "katelynns-photography/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  profile = var.aws_profile != "" ? var.aws_profile : null
  region  = "us-east-2"

  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Project   = "katelynns-photography"
    }
  }
}

# Secondary provider for ACM certificates (must be us-east-1 for CloudFront)
provider "aws" {
  alias   = "us_east_1"
  profile = var.aws_profile != "" ? var.aws_profile : null
  region  = "us-east-1"

  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Project   = "katelynns-photography"
    }
  }
}
```

#### 3. Create variables.tf

**File**: `terraform/variables.tf`

```hcl
variable "aws_profile" {
  description = "AWS profile to use (for local development only, leave empty for CI/CD)"
  type        = string
  default     = "jw-dev"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "katelynns-photography"
}

variable "domain_name" {
  description = "Custom domain name (e.g., katelynnsphotography.com)"
  type        = string
  default     = ""  # Empty if not using custom domain yet
}

variable "admin_email" {
  description = "Admin email for notifications and SES"
  type        = string
}

variable "ses_from_email" {
  description = "Email address to send from (must be verified in SES)"
  type        = string
}
```

#### 4. Create terraform.tfvars (gitignored)

**File**: `terraform/terraform.tfvars`

```hcl
aws_profile    = "jw-dev"
project_name   = "katelynns-photography"
domain_name    = "katelynnsphotography.com"  # or "" if not ready
admin_email    = "your-email@example.com"
ses_from_email = "contact@katelynnsphotography.com"
```

#### 5. Update .gitignore

**File**: `.gitignore` (add to existing or create)

```gitignore
# Terraform
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
*.tfvars.json
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform init` completes successfully
- [x] `terraform validate` passes
- [x] `terraform plan` runs without errors

#### Manual Verification:

- [x] Backend state file created in S3 under `katelynns-photography/` key

---

## Phase 1.2: S3 Buckets

### Overview

Create three S3 buckets for portfolio assets, client albums, and static website hosting.

### Changes Required:

#### 1. Create s3.tf

**File**: `terraform/s3.tf`

```hcl
# =============================================================================
# S3 Bucket: Portfolio Assets (public images served via CloudFront)
# =============================================================================
resource "aws_s3_bucket" "portfolio_assets" {
  bucket = "${var.project_name}-portfolio-assets"

  tags = {
    Name    = "${var.project_name}-portfolio-assets"
    Purpose = "Public portfolio images"
  }
}

resource "aws_s3_bucket_versioning" "portfolio_assets" {
  bucket = aws_s3_bucket.portfolio_assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "portfolio_assets" {
  bucket = aws_s3_bucket.portfolio_assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block direct public access - CloudFront will access via OAC
resource "aws_s3_bucket_public_access_block" "portfolio_assets" {
  bucket = aws_s3_bucket.portfolio_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# S3 Bucket: Client Albums (private, accessed via presigned URLs)
# =============================================================================
resource "aws_s3_bucket" "client_albums" {
  bucket = "${var.project_name}-client-albums"

  tags = {
    Name    = "${var.project_name}-client-albums"
    Purpose = "Private client photo albums"
  }
}

resource "aws_s3_bucket_versioning" "client_albums" {
  bucket = aws_s3_bucket.client_albums.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "client_albums" {
  bucket = aws_s3_bucket.client_albums.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "client_albums" {
  bucket = aws_s3_bucket.client_albums.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule: Move old client albums to cheaper storage after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "client_albums" {
  bucket = aws_s3_bucket.client_albums.id

  rule {
    id     = "archive-old-albums"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER_IR"
    }
  }
}

# =============================================================================
# S3 Bucket: Website Hosting (Astro static files)
# =============================================================================
resource "aws_s3_bucket" "website" {
  bucket = "${var.project_name}-website"

  tags = {
    Name    = "${var.project_name}-website"
    Purpose = "Static website hosting (Astro)"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform plan` shows 3 buckets to create
- [x] `terraform apply` succeeds
- [x] `aws s3 ls | grep katelynns` shows all 3 buckets

#### Manual Verification:

- [ ] Buckets visible in AWS Console with correct settings
- [ ] Public access blocked on all buckets

---

## Phase 1.3: CloudFront Distribution

### Overview

Create CloudFront distribution to serve the website and portfolio images with caching.

### Changes Required:

#### 1. Create cloudfront.tf

**File**: `terraform/cloudfront.tf`

```hcl
# =============================================================================
# CloudFront Origin Access Control (replaces OAI)
# =============================================================================
resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${var.project_name}-website-oac"
  description                       = "OAC for website S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "portfolio" {
  name                              = "${var.project_name}-portfolio-oac"
  description                       = "OAC for portfolio assets S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# =============================================================================
# CloudFront Distribution
# =============================================================================
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${var.project_name} website distribution"
  price_class         = "PriceClass_100"  # US, Canada, Europe only (cheapest)

  # Custom domain aliases (only if domain is configured)
  aliases = var.domain_name != "" ? [var.domain_name, "www.${var.domain_name}"] : []

  # Origin 1: Website static files
  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "S3-website"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  # Origin 2: Portfolio images
  origin {
    domain_name              = aws_s3_bucket.portfolio_assets.bucket_regional_domain_name
    origin_id                = "S3-portfolio"
    origin_access_control_id = aws_cloudfront_origin_access_control.portfolio.id
  }

  # Default behavior: Website files
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-website"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600      # 1 hour
    max_ttl     = 86400     # 24 hours
    compress    = true
  }

  # Behavior for portfolio images (longer cache)
  ordered_cache_behavior {
    path_pattern           = "/images/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-portfolio"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 86400       # 1 day minimum
    default_ttl = 604800      # 7 days
    max_ttl     = 2592000     # 30 days
    compress    = true
  }

  # Custom error responses for SPA routing
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  # SSL Certificate
  viewer_certificate {
    # Use ACM certificate if custom domain, otherwise CloudFront default
    acm_certificate_arn            = var.domain_name != "" ? aws_acm_certificate.main[0].arn : null
    cloudfront_default_certificate = var.domain_name == ""
    ssl_support_method             = var.domain_name != "" ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${var.project_name}-distribution"
  }

  depends_on = [aws_acm_certificate_validation.main]
}

# =============================================================================
# S3 Bucket Policies for CloudFront Access
# =============================================================================
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "portfolio_assets" {
  bucket = aws_s3_bucket.portfolio_assets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.portfolio_assets.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform plan` shows CloudFront resources
- [ ] `terraform apply` succeeds - **BLOCKED: AWS account requires verification for CloudFront. Support case opened.**

#### Manual Verification:

- [ ] CloudFront distribution status is "Deployed"
- [ ] Can access distribution URL in browser (will show error until content uploaded)

---

## Phase 1.4: ACM Certificate (for custom domain)

### Overview

Create SSL certificate for custom domain. Must be in us-east-1 for CloudFront.

### Changes Required:

#### 1. Create acm.tf

**File**: `terraform/acm.tf`

```hcl
# =============================================================================
# ACM Certificate (must be in us-east-1 for CloudFront)
# =============================================================================
resource "aws_acm_certificate" "main" {
  count = var.domain_name != "" ? 1 : 0

  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "www.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-certificate"
  }
}

# DNS validation records (created in Route53)
resource "aws_route53_record" "acm_validation" {
  for_each = var.domain_name != "" ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main[0].zone_id
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "main" {
  count = var.domain_name != "" ? 1 : 0

  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.main[0].arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform plan` shows ACM resources (if domain_name set) - **SKIPPED: domain_name is empty**
- [x] `terraform apply` succeeds - **SKIPPED: domain_name is empty**

#### Manual Verification:

- [ ] Certificate status is "Issued" in ACM console (us-east-1)

---

## Phase 1.5: Route53 DNS

### Overview

Create hosted zone and DNS records for custom domain.

### Changes Required:

#### 1. Create route53.tf

**File**: `terraform/route53.tf`

```hcl
# =============================================================================
# Route53 Hosted Zone (only if custom domain configured)
# =============================================================================
resource "aws_route53_zone" "main" {
  count = var.domain_name != "" ? 1 : 0
  name  = var.domain_name

  tags = {
    Name = "${var.project_name}-zone"
  }
}

# A record for apex domain -> CloudFront
resource "aws_route53_record" "apex" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# A record for www -> CloudFront
resource "aws_route53_record" "www" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = aws_route53_zone.main[0].zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform plan` shows Route53 resources (if domain_name set) - **SKIPPED: domain_name is empty**
- [x] `terraform apply` succeeds - **SKIPPED: domain_name is empty**

#### Manual Verification:

- [ ] Hosted zone visible in Route53 console
- [ ] NS records shown (must update domain registrar)

**Important**: After creating the hosted zone, you must update your domain registrar's nameservers to point to the Route53 nameservers shown in the outputs.

---

## Phase 1.6: Cognito User Pool

### Overview

Create Cognito user pool for client authentication.

### Changes Required:

#### 1. Create cognito.tf

**File**: `terraform/cognito.tf`

```hcl
# =============================================================================
# Cognito User Pool
# =============================================================================
resource "aws_cognito_user_pool" "clients" {
  name = "${var.project_name}-clients"

  # Username configuration
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Email configuration (use Cognito default for now, can switch to SES later)
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Admin create user config (clients don't self-register)
  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_subject = "Your Katelynn's Photography Gallery Access"
      email_message = "Hello! Your gallery is ready. Username: {username}, Temporary password: {####}. Visit our website to view your photos."
      sms_message   = "Your temporary password is {####}"
    }
  }

  # Schema attributes
  schema {
    name                     = "name"
    attribute_data_type      = "String"
    mutable                  = true
    required                 = false
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  tags = {
    Name = "${var.project_name}-user-pool"
  }
}

# =============================================================================
# Cognito User Pool Client (for web app)
# =============================================================================
resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.project_name}-web-client"
  user_pool_id = aws_cognito_user_pool.clients.id

  # No client secret (public client for browser)
  generate_secret = false

  # Auth flows
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  # Token validity
  access_token_validity  = 1   # hours
  id_token_validity      = 1   # hours
  refresh_token_validity = 30  # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Prevent user existence errors (security)
  prevent_user_existence_errors = "ENABLED"
}

# =============================================================================
# Cognito User Pool Domain (for hosted UI if needed)
# =============================================================================
resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.project_name
  user_pool_id = aws_cognito_user_pool.clients.id
}
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform plan` shows Cognito resources
- [x] `terraform apply` succeeds

#### Manual Verification:

- [ ] User pool visible in Cognito console
- [ ] Can manually create a test user via console
- [ ] Hosted UI accessible at `https://katelynns-photography.auth.us-east-2.amazoncognito.com`

---

## Phase 1.7: SES Email Service

### Overview

Configure SES for sending contact form emails.

### Changes Required:

#### 1. Create ses.tf

**File**: `terraform/ses.tf`

```hcl
# =============================================================================
# SES Email Identity (domain or email address)
# =============================================================================

# Option 1: Verify domain (preferred, allows any @domain.com address)
resource "aws_ses_domain_identity" "main" {
  count  = var.domain_name != "" ? 1 : 0
  domain = var.domain_name
}

# DNS records for domain verification
resource "aws_route53_record" "ses_verification" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = aws_route53_zone.main[0].zone_id
  name    = "_amazonses.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.main[0].verification_token]
}

# Wait for domain verification
resource "aws_ses_domain_identity_verification" "main" {
  count  = var.domain_name != "" ? 1 : 0
  domain = aws_ses_domain_identity.main[0].id

  depends_on = [aws_route53_record.ses_verification]
}

# DKIM records for better deliverability
resource "aws_ses_domain_dkim" "main" {
  count  = var.domain_name != "" ? 1 : 0
  domain = aws_ses_domain_identity.main[0].domain
}

resource "aws_route53_record" "ses_dkim" {
  count   = var.domain_name != "" ? 3 : 0
  zone_id = aws_route53_zone.main[0].zone_id
  name    = "${aws_ses_domain_dkim.main[0].dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.main[0].dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# Option 2: Verify single email address (if no custom domain yet)
resource "aws_ses_email_identity" "admin" {
  count = var.domain_name == "" ? 1 : 0
  email = var.admin_email
}

# =============================================================================
# SES Configuration Set (for tracking)
# =============================================================================
resource "aws_ses_configuration_set" "main" {
  name = "${var.project_name}-emails"
}
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform plan` shows SES resources
- [x] `terraform apply` succeeds

#### Manual Verification:

- [ ] Domain/email identity shows "Verified" in SES console
- [ ] DKIM status is "Enabled" (if using domain)
- [ ] Can send test email from SES console

**Note**: SES starts in sandbox mode. To send to non-verified addresses, you must request production access from AWS. Currently using email identity (your-email@example.com) since domain_name is empty - update terraform.tfvars with real email.

---

## Phase 1.8: API Gateway (Infrastructure Only)

### Overview

Create HTTP API for Lambda functions (actual Lambda integration in Phase 2).

### Changes Required:

#### 1. Create api-gateway.tf

**File**: `terraform/api-gateway.tf`

```hcl
# =============================================================================
# HTTP API (v2 - cheaper than REST API)
# =============================================================================
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  description   = "API for ${var.project_name}"

  cors_configuration {
    allow_origins = var.domain_name != "" ? [
      "https://${var.domain_name}",
      "https://www.${var.domain_name}"
    ] : ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 3600
  }

  tags = {
    Name = "${var.project_name}-api"
  }
}

# Default stage (auto-deploy)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  tags = {
    Name = "${var.project_name}-api-default"
  }
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-api-logs"
  }
}
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform plan` shows API Gateway resources
- [x] `terraform apply` succeeds

#### Manual Verification:

- [ ] API visible in API Gateway console
- [ ] API endpoint URL accessible (will return error until routes configured): `https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com`

---

## Phase 1.9: Outputs

### Overview

Define all output values for use in other phases.

### Changes Required:

#### 1. Create outputs.tf

**File**: `terraform/outputs.tf`

```hcl
# =============================================================================
# S3 Outputs
# =============================================================================
output "s3_website_bucket" {
  description = "S3 bucket for website files"
  value       = aws_s3_bucket.website.id
}

output "s3_portfolio_bucket" {
  description = "S3 bucket for portfolio images"
  value       = aws_s3_bucket.portfolio_assets.id
}

output "s3_client_albums_bucket" {
  description = "S3 bucket for client albums"
  value       = aws_s3_bucket.client_albums.id
}

# =============================================================================
# CloudFront Outputs
# =============================================================================
output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "website_url" {
  description = "Website URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.main.domain_name}"
}

# =============================================================================
# Cognito Outputs
# =============================================================================
output "cognito_user_pool_id" {
  description = "Cognito user pool ID"
  value       = aws_cognito_user_pool.clients.id
}

output "cognito_user_pool_client_id" {
  description = "Cognito user pool client ID"
  value       = aws_cognito_user_pool_client.web.id
}

output "cognito_domain" {
  description = "Cognito hosted UI domain"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.us-east-2.amazoncognito.com"
}

# =============================================================================
# API Gateway Outputs
# =============================================================================
output "api_gateway_url" {
  description = "API Gateway invoke URL"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_apigatewayv2_api.main.id
}

# =============================================================================
# Route53 Outputs (if using custom domain)
# =============================================================================
output "route53_nameservers" {
  description = "Route53 nameservers (update your registrar with these)"
  value       = var.domain_name != "" ? aws_route53_zone.main[0].name_servers : []
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = var.domain_name != "" ? aws_route53_zone.main[0].zone_id : ""
}
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform plan` completes successfully
- [x] `terraform apply` shows all outputs (partial - CloudFront outputs pending)
- [x] `terraform output` displays all values

**Current outputs:**

```
api_gateway_id              = "nbu6ndrpg2"
api_gateway_url             = "https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com"
cognito_domain              = "https://katelynns-photography.auth.us-east-2.amazoncognito.com"
cognito_user_pool_client_id = "6a5h8p858dg9laj544ijvu9gro"
cognito_user_pool_id        = "us-east-2_bn71poxi6"
s3_client_albums_bucket     = "katelynns-photography-client-albums"
s3_portfolio_bucket         = "katelynns-photography-portfolio-assets"
s3_website_bucket           = "katelynns-photography-website"
```

---

## Testing Strategy

### After Full Phase 1 Completion:

1. **Verify all resources exist**:

   ```bash
   terraform output
   ```

2. **Test CloudFront**:
   - Upload test index.html to website bucket
   - Access CloudFront URL

   ```bash
   echo "<h1>Hello World</h1>" > index.html
   aws s3 cp index.html s3://katelynns-photography-website/
   # Visit CloudFront URL
   ```

3. **Test Cognito**:
   - Create test user in console
   - Verify email received

4. **Test API Gateway**:
   - Access API endpoint (should return error, no routes yet)

---

## References

- Master plan: `thoughts/shared/plans/2026-01-08-build-website-master-plan.md`
- AWS Projects patterns: `/home/aw-jwalker/repos/aws-projects/`
- Terraform backend: `s3://aw-jwalker-terraform-state/katelynns-photography/`
