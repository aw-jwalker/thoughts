# Switch from CloudFront to AWS Amplify Hosting

## Overview

Replace CloudFront with AWS Amplify Hosting for the Astro static site. This bypasses the CloudFront verification blocker while providing equivalent functionality (HTTPS, CDN, custom domains). Additionally, implement GitHub Actions CI/CD pipelines for automated deployments to dev and prod environments.

## Current State Analysis

**Infrastructure (Terraform):**

- CloudFront distribution defined in `terraform/cloudfront.tf` - BLOCKED by AWS verification
- S3 buckets: `katelynns-photography-website`, `katelynns-photography-portfolio-assets`, `katelynns-photography-client-albums`
- Cognito, API Gateway, Lambda functions all working
- No custom domain configured yet (`domain_name = ""` in tfvars)

**Deployment:**

- Manual deployment via `scripts/deploy_frontend.sh` (builds Astro, syncs to S3, invalidates CloudFront)
- No GitHub Actions workflows exist

**Existing GitHub Actions Pattern (from aws-projects repo):**

- OIDC authentication with `aws-actions/configure-aws-credentials@v4`
- Role ARN stored in GitHub secrets (`AWS_ROLE_ARN`)
- OIDC provider already exists in jw-dev account (908027391776)

## Desired End State

1. **Amplify Hosting** replaces CloudFront for serving the Astro site
2. **GitHub Actions** automates build and deployment:
   - Push to `dev` branch → deploy to dev (jw-dev account)
   - Push to `main` branch → deploy to prod (jw-prod account)
3. **Portfolio images** served directly from S3 with public read access (no CDN needed for small traffic)
4. **HTTPS included** via Amplify's default domain (\*.amplifyapp.com)
5. **Custom domain** can be added later via Amplify domain association

### Verification:

- [x] Site accessible at Amplify URL with HTTPS
- [x] GitHub Actions deploys on push to dev/main
- [ ] API endpoints still work (contact form, client portal)
- [ ] Portfolio images load correctly

## What We're NOT Doing

- **Not using Amplify's built-in Git integration** - We want GitHub Actions for more control
- **Not setting up custom domain yet** - Will add after basic hosting works
- **Not changing Lambda/API Gateway/Cognito** - Those remain unchanged
- **Not implementing QA environment** - Starting with dev/prod only, can add later
- **Not migrating portfolio images to Amplify** - Keep in S3 with direct access

## Implementation Approach

1. Create Amplify app via Terraform (manual deployment mode, no Git connection)
2. Set up GitHub OIDC provider and IAM role for this repo (in both jw-dev and jw-prod)
3. Create GitHub Actions workflow that builds Astro and deploys to Amplify
4. Remove CloudFront resources from Terraform
5. Update S3 portfolio bucket to allow public read access
6. Test end-to-end deployment

---

## Phase 1: Terraform - Add Amplify Hosting

### Overview

Add AWS Amplify app resource to Terraform. Use manual deployment mode (not Git-connected) so GitHub Actions controls deployments.

### Changes Required:

#### 1. Create Amplify Terraform Configuration

**File**: `terraform/amplify.tf` (new file)

```hcl
# =============================================================================
# AWS Amplify Hosting (replaces CloudFront for static site)
# =============================================================================

resource "aws_amplify_app" "website" {
  name        = "${var.project_name}-website"
  description = "Photography portfolio website"

  # Manual deployment - GitHub Actions will deploy, not Amplify
  platform = "WEB"

  # Build spec not needed for manual deployment, but required by Amplify
  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        build:
          commands:
            - echo "Build handled by GitHub Actions"
      artifacts:
        baseDirectory: /
        files:
          - '**/*'
  EOT

  # Custom rewrite rules for SPA routing
  custom_rule {
    source = "/<*>"
    status = "404-200"
    target = "/index.html"
  }

  # Environment variables (available during Amplify builds, not used for manual deploy)
  environment_variables = {
    ENVIRONMENT = "production"
  }

  tags = {
    Name = "${var.project_name}-amplify"
  }
}

# Branch for production deployments
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.website.id
  branch_name = "main"

  description = "Production branch"
  stage       = "PRODUCTION"

  environment_variables = {
    ENVIRONMENT = "production"
  }
}

# Branch for development deployments (optional - can be in same or different account)
resource "aws_amplify_branch" "develop" {
  app_id      = aws_amplify_app.website.id
  branch_name = "develop"

  description = "Development branch"
  stage       = "DEVELOPMENT"

  environment_variables = {
    ENVIRONMENT = "development"
  }
}

# Domain association (conditional - only if domain is configured)
resource "aws_amplify_domain_association" "main" {
  count = var.domain_name != "" ? 1 : 0

  app_id      = aws_amplify_app.website.id
  domain_name = var.domain_name

  # Apex domain (example.com)
  sub_domain {
    branch_name = aws_amplify_branch.main.branch_name
    prefix      = ""
  }

  # www subdomain (www.example.com)
  sub_domain {
    branch_name = aws_amplify_branch.main.branch_name
    prefix      = "www"
  }
}
```

#### 2. Update Outputs

**File**: `terraform/outputs.tf`

Add after existing outputs:

```hcl
# =============================================================================
# Amplify Outputs
# =============================================================================
output "amplify_app_id" {
  description = "Amplify app ID"
  value       = aws_amplify_app.website.id
}

output "amplify_app_arn" {
  description = "Amplify app ARN"
  value       = aws_amplify_app.website.arn
}

output "amplify_default_domain" {
  description = "Amplify default domain"
  value       = aws_amplify_app.website.default_domain
}

output "amplify_main_branch_url" {
  description = "URL for main branch deployment"
  value       = "https://main.${aws_amplify_app.website.default_domain}"
}

output "amplify_develop_branch_url" {
  description = "URL for develop branch deployment"
  value       = "https://develop.${aws_amplify_app.website.default_domain}"
}
```

#### 3. Update Website URL Output

**File**: `terraform/outputs.tf`

Change the `website_url` output:

```hcl
output "website_url" {
  description = "Website URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://main.${aws_amplify_app.website.default_domain}"
}
```

#### 4. Make Portfolio Bucket Public (for direct image access)

**File**: `terraform/s3.tf`

Update the portfolio_assets bucket to allow public read:

```hcl
# Add this new resource after aws_s3_bucket.portfolio_assets
resource "aws_s3_bucket_public_access_block" "portfolio_assets_public" {
  bucket = aws_s3_bucket.portfolio_assets.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Update the bucket policy (replace existing CloudFront policy)
resource "aws_s3_bucket_policy" "portfolio_assets" {
  bucket = aws_s3_bucket.portfolio_assets.id

  # Wait for public access block to be applied
  depends_on = [aws_s3_bucket_public_access_block.portfolio_assets_public]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.portfolio_assets.arn}/*"
      }
    ]
  })
}
```

### Success Criteria:

#### Automated Verification:

```bash
cd terraform && terraform validate
cd terraform && terraform plan
```

- [x] Terraform validates without errors
- [x] Plan shows Amplify resources will be created
- [x] No errors related to Amplify resources

#### Manual Verification:

- [x] Review the terraform plan output for correctness
- [x] Confirm Amplify app, branches, and outputs look correct

**Implementation Note**: After completing this phase, run `terraform apply` and verify the Amplify app is created in the AWS console before proceeding.

---

## Phase 2: GitHub OIDC and IAM Role Setup

### Overview

Create IAM role for GitHub Actions to deploy to Amplify. This requires the OIDC provider (already exists in jw-dev) and a new role with Amplify permissions.

### Changes Required:

#### 1. Create GitHub Actions IAM Role Terraform

**File**: `terraform/github-actions-role.tf` (new file)

```hcl
# =============================================================================
# GitHub Actions OIDC and IAM Role
# =============================================================================

# Data source for existing OIDC provider (created once per account)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# If OIDC provider doesn't exist, create it (will be skipped if exists)
resource "aws_iam_openid_connect_provider" "github" {
  count = length(data.aws_iam_openid_connect_provider.github.arn) == 0 ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "github-actions-oidc"
  }
}

locals {
  oidc_provider_arn = length(data.aws_iam_openid_connect_provider.github.arn) > 0 ? data.aws_iam_openid_connect_provider.github.arn : aws_iam_openid_connect_provider.github[0].arn
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name        = "GitHubActions-${var.project_name}"
  description = "Role for GitHub Actions to deploy ${var.project_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:aw-jwalker/katelynns-photography:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "GitHubActions-${var.project_name}"
  }
}

# IAM Policy for Amplify deployments
resource "aws_iam_policy" "github_actions_amplify" {
  name        = "GitHubActions-${var.project_name}-Amplify"
  description = "Permissions for GitHub Actions to deploy to Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AmplifyDeployment"
        Effect = "Allow"
        Action = [
          "amplify:StartDeployment",
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:ListApps",
          "amplify:ListBranches",
          "amplify:CreateDeployment",
          "amplify:GetJob",
          "amplify:ListJobs"
        ]
        Resource = [
          aws_amplify_app.website.arn,
          "${aws_amplify_app.website.arn}/*"
        ]
      },
      {
        Sid    = "S3UploadArtifacts"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::amplify-*",
          "arn:aws:s3:::amplify-*/*"
        ]
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "github_actions_amplify" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_amplify.arn
}
```

#### 2. Add GitHub Actions Role Output

**File**: `terraform/outputs.tf`

Add:

```hcl
output "github_actions_role_arn" {
  description = "IAM Role ARN for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}
```

### Success Criteria:

#### Automated Verification:

```bash
cd terraform && terraform validate
cd terraform && terraform plan
```

- [x] Terraform validates without errors
- [x] Plan shows IAM role and policy will be created

#### Manual Verification:

- [x] After `terraform apply`, verify role exists in IAM console
- [x] Verify role has correct trust policy for GitHub OIDC

**Implementation Note**: After applying, note the `github_actions_role_arn` output - you'll need it for GitHub secrets.

---

## Phase 3: GitHub Actions Workflow

### Overview

Create GitHub Actions workflow to build the Astro site and deploy to Amplify. Supports dev (develop branch) and prod (main branch) deployments.

### Changes Required:

#### 1. Create GitHub Actions Workflow

**File**: `.github/workflows/deploy-website.yml` (new file)

```yaml
name: Deploy Website

on:
  push:
    branches:
      - main
      - develop
    paths:
      - "frontend/**"
      - ".github/workflows/deploy-website.yml"
  workflow_dispatch:
    inputs:
      environment:
        description: "Environment to deploy to"
        required: true
        type: choice
        options:
          - develop
          - main

env:
  AWS_REGION: us-east-2
  NODE_VERSION: "20"

permissions:
  contents: read
  id-token: write

jobs:
  build:
    name: Build Astro Site
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: "npm"
          cache-dependency-path: frontend/package-lock.json

      - name: Install Dependencies
        working-directory: frontend
        run: npm ci

      - name: Build Site
        working-directory: frontend
        run: npm run build

      - name: Upload Build Artifact
        uses: actions/upload-artifact@v4
        with:
          name: astro-build
          path: frontend/dist
          retention-days: 1

  deploy-dev:
    name: Deploy to Development
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/develop' || (github.event_name == 'workflow_dispatch' && github.event.inputs.environment == 'develop')
    environment: development

    steps:
      - name: Download Build Artifact
        uses: actions/download-artifact@v4
        with:
          name: astro-build
          path: dist

      - name: Configure AWS Credentials (Dev)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN_DEV }}
          aws-region: ${{ env.AWS_REGION }}
          role-session-name: GitHubActions-Deploy-Dev

      - name: Deploy to Amplify (Dev)
        run: |
          # Create deployment zip
          cd dist && zip -r ../deployment.zip . && cd ..

          # Get app ID and branch name
          APP_ID="${{ secrets.AMPLIFY_APP_ID_DEV }}"
          BRANCH_NAME="develop"

          # Create deployment
          DEPLOYMENT=$(aws amplify create-deployment \
            --app-id "$APP_ID" \
            --branch-name "$BRANCH_NAME" \
            --query '{jobId: jobId, zipUploadUrl: zipUploadUrl}' \
            --output json)

          JOB_ID=$(echo $DEPLOYMENT | jq -r '.jobId')
          UPLOAD_URL=$(echo $DEPLOYMENT | jq -r '.zipUploadUrl')

          echo "Job ID: $JOB_ID"

          # Upload zip to presigned URL
          curl -T deployment.zip "$UPLOAD_URL"

          # Start deployment
          aws amplify start-deployment \
            --app-id "$APP_ID" \
            --branch-name "$BRANCH_NAME" \
            --job-id "$JOB_ID"

          echo "Deployment started! Job ID: $JOB_ID"
          echo "View at: https://${BRANCH_NAME}.${{ secrets.AMPLIFY_DOMAIN_DEV }}"

  deploy-prod:
    name: Deploy to Production
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' || (github.event_name == 'workflow_dispatch' && github.event.inputs.environment == 'main')
    environment: production

    steps:
      - name: Download Build Artifact
        uses: actions/download-artifact@v4
        with:
          name: astro-build
          path: dist

      - name: Configure AWS Credentials (Prod)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN_PROD }}
          aws-region: ${{ env.AWS_REGION }}
          role-session-name: GitHubActions-Deploy-Prod

      - name: Deploy to Amplify (Prod)
        run: |
          # Create deployment zip
          cd dist && zip -r ../deployment.zip . && cd ..

          # Get app ID and branch name
          APP_ID="${{ secrets.AMPLIFY_APP_ID_PROD }}"
          BRANCH_NAME="main"

          # Create deployment
          DEPLOYMENT=$(aws amplify create-deployment \
            --app-id "$APP_ID" \
            --branch-name "$BRANCH_NAME" \
            --query '{jobId: jobId, zipUploadUrl: zipUploadUrl}' \
            --output json)

          JOB_ID=$(echo $DEPLOYMENT | jq -r '.jobId')
          UPLOAD_URL=$(echo $DEPLOYMENT | jq -r '.zipUploadUrl')

          echo "Job ID: $JOB_ID"

          # Upload zip to presigned URL
          curl -T deployment.zip "$UPLOAD_URL"

          # Start deployment
          aws amplify start-deployment \
            --app-id "$APP_ID" \
            --branch-name "$BRANCH_NAME" \
            --job-id "$JOB_ID"

          echo "Deployment started! Job ID: $JOB_ID"
          echo "View at: https://${BRANCH_NAME}.${{ secrets.AMPLIFY_DOMAIN_PROD }}"
```

#### 2. Create develop branch (if it doesn't exist)

```bash
git checkout -b develop
git push -u origin develop
```

### Success Criteria:

#### Automated Verification:

- [x] Workflow file passes GitHub Actions syntax validation
- [x] `yamllint .github/workflows/deploy-website.yml` passes (if available)

#### Manual Verification:

- [x] GitHub Actions workflow appears in Actions tab
- [x] Manual workflow dispatch works
- [x] Deployment completes successfully
- [x] Site is accessible at Amplify URL

**Implementation Note**: After creating the workflow, you must add GitHub secrets before running:

- `AWS_ROLE_ARN_DEV` - IAM role ARN from jw-dev account
- `AWS_ROLE_ARN_PROD` - IAM role ARN from jw-prod account
- `AMPLIFY_APP_ID_DEV` - Amplify app ID from jw-dev account
- `AMPLIFY_APP_ID_PROD` - Amplify app ID from jw-prod account
- `AMPLIFY_DOMAIN_DEV` - Amplify default domain (e.g., `d1234abcd.amplifyapp.com`)
- `AMPLIFY_DOMAIN_PROD` - Amplify default domain for prod

---

## Phase 4: Remove CloudFront Resources

### Overview

Remove CloudFront distribution and related resources from Terraform since Amplify now handles hosting.

### Changes Required:

#### 1. Remove CloudFront Configuration

**File**: `terraform/cloudfront.tf`

Delete or comment out the entire file contents:

- `aws_cloudfront_origin_access_control.website`
- `aws_cloudfront_origin_access_control.portfolio`
- `aws_cloudfront_distribution.main`
- `aws_s3_bucket_policy.website` (will be replaced)

#### 2. Update S3 Website Bucket Policy

**File**: `terraform/s3.tf`

The website bucket no longer needs CloudFront access since Amplify hosts the site directly. Remove or simplify the bucket policy:

```hcl
# Website bucket doesn't need a policy anymore - Amplify hosts the content
# If you want to allow direct S3 access for debugging, add:
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyAllPublicAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [
          aws_s3_bucket.website.arn,
          "${aws_s3_bucket.website.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
```

#### 3. Remove CloudFront Outputs

**File**: `terraform/outputs.tf`

Remove or comment out:

```hcl
# output "cloudfront_distribution_id" { ... }
# output "cloudfront_domain_name" { ... }
```

#### 4. Update ACM Certificate Dependency

**File**: `terraform/acm.tf`

The ACM certificate was for CloudFront. Amplify manages its own certificates. If custom domain isn't configured, you can simplify or remove ACM resources. Keep them if you plan to add custom domain later.

### Success Criteria:

#### Automated Verification:

```bash
cd terraform && terraform validate
cd terraform && terraform plan
```

- [x] Terraform validates without errors
- [x] Plan shows CloudFront resources will be destroyed
- [x] No dangling references to CloudFront

#### Manual Verification:

- [x] After `terraform apply`, CloudFront distribution is removed
- [x] Site still works via Amplify URL
- [x] No errors in AWS console

**Implementation Note**: Run `terraform plan` first to review what will be destroyed. CloudFront deletion can take several minutes.

---

## Phase 5: Update Deployment Script

### Overview

Update the deployment script to use Amplify instead of S3/CloudFront, or deprecate it in favor of GitHub Actions.

### Changes Required:

#### 1. Update Deployment Script for Local Development

**File**: `scripts/deploy_frontend.sh`

```bash
#!/bin/bash
# Deploy frontend site to AWS Amplify
# Usage: ./scripts/deploy_frontend.sh [develop|main]
#
# For production deployments, prefer using GitHub Actions (push to main/develop)
# This script is for local/manual deployments when needed.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FRONTEND_DIR="$PROJECT_ROOT/frontend"

AWS_PROFILE="${AWS_PROFILE:-jw-dev}"
AWS_REGION="${AWS_REGION:-us-east-2}"
BRANCH_NAME="${1:-develop}"

# Get Amplify app ID from Terraform
AMPLIFY_APP_ID=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw amplify_app_id 2>/dev/null || echo "")

if [ -z "$AMPLIFY_APP_ID" ]; then
    echo "ERROR: Could not get Amplify app ID from Terraform"
    echo "Run 'terraform apply' first to create the Amplify app"
    exit 1
fi

echo "=========================================="
echo "Deploying Frontend Site to Amplify"
echo "=========================================="
echo "AWS Profile: $AWS_PROFILE"
echo "Amplify App ID: $AMPLIFY_APP_ID"
echo "Branch: $BRANCH_NAME"
echo ""

# Build frontend site
echo "Building frontend site..."
cd "$FRONTEND_DIR"
npm run build

# Create deployment zip
echo "Creating deployment package..."
cd dist
zip -r ../deployment.zip .
cd ..

# Create Amplify deployment
echo "Creating Amplify deployment..."
DEPLOYMENT=$(aws amplify create-deployment \
    --app-id "$AMPLIFY_APP_ID" \
    --branch-name "$BRANCH_NAME" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query '{jobId: jobId, zipUploadUrl: zipUploadUrl}' \
    --output json)

JOB_ID=$(echo $DEPLOYMENT | jq -r '.jobId')
UPLOAD_URL=$(echo $DEPLOYMENT | jq -r '.zipUploadUrl')

echo "Job ID: $JOB_ID"

# Upload zip to presigned URL
echo "Uploading deployment package..."
curl -T deployment.zip "$UPLOAD_URL"

# Start deployment
echo "Starting deployment..."
aws amplify start-deployment \
    --app-id "$AMPLIFY_APP_ID" \
    --branch-name "$BRANCH_NAME" \
    --job-id "$JOB_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"

# Clean up
rm -f deployment.zip

# Get the Amplify URL
AMPLIFY_DOMAIN=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw amplify_default_domain 2>/dev/null || echo "")

echo ""
echo "=========================================="
echo "Deployment Started!"
echo "=========================================="
echo "Job ID: $JOB_ID"
echo "Branch: $BRANCH_NAME"
if [ -n "$AMPLIFY_DOMAIN" ]; then
    echo "URL: https://${BRANCH_NAME}.${AMPLIFY_DOMAIN}"
fi
echo ""
echo "Check deployment status in AWS Amplify console"
```

### Success Criteria:

#### Automated Verification:

```bash
shellcheck scripts/deploy_frontend.sh
```

- [x] Script passes shellcheck (if available)
- [x] Script is executable (`chmod +x`)

#### Manual Verification:

- [x] Running `./scripts/deploy_frontend.sh dev` deploys successfully
- [x] Site is accessible at Amplify URL

---

## Phase 6: Configure GitHub Secrets

### Overview

Add required secrets to GitHub repository for the CI/CD pipeline.

### Changes Required:

#### 1. Add GitHub Repository Secrets

Navigate to: GitHub repo → Settings → Secrets and variables → Actions

**Required Secrets:**

| Secret Name           | Value                                                                   | Source                                               |
| --------------------- | ----------------------------------------------------------------------- | ---------------------------------------------------- |
| `AWS_ROLE_ARN_DEV`    | `arn:aws:iam::908027391776:role/GitHubActions-katelynns-photography`    | Terraform output: `github_actions_role_arn` (jw-dev) |
| `AWS_ROLE_ARN_PROD`   | `arn:aws:iam::PROD_ACCOUNT_ID:role/GitHubActions-katelynns-photography` | Terraform output from jw-prod                        |
| `AMPLIFY_APP_ID_DEV`  | `d1234567890`                                                           | Terraform output: `amplify_app_id` (jw-dev)          |
| `AMPLIFY_APP_ID_PROD` | `d0987654321`                                                           | Terraform output from jw-prod                        |
| `AMPLIFY_DOMAIN_DEV`  | `d1234567890.amplifyapp.com`                                            | Terraform output: `amplify_default_domain` (jw-dev)  |
| `AMPLIFY_DOMAIN_PROD` | `d0987654321.amplifyapp.com`                                            | Terraform output from jw-prod                        |

#### 2. Create GitHub Environments

Navigate to: GitHub repo → Settings → Environments

Create two environments:

- **development** - No protection rules needed
- **production** - Optionally add required reviewers for manual approval

### Success Criteria:

#### Manual Verification:

- [x] All 6 secrets are configured in GitHub (dev secrets only for now)
- [x] Both environments (development, production) are created
- [x] Workflow runs successfully when manually triggered

---

## Phase 7: End-to-End Testing

### Overview

Verify the complete deployment pipeline works from code push to live site.

### Test Cases:

#### 1. Development Deployment

```bash
# Create and push to develop branch
git checkout -b develop
# Make a small change to frontend/src/pages/index.astro
git add .
git commit -m "test: verify dev deployment pipeline"
git push -u origin develop
```

Expected: GitHub Actions deploys to dev Amplify

#### 2. Production Deployment

```bash
git checkout main
git merge develop
git push origin main
```

Expected: GitHub Actions deploys to prod Amplify

#### 3. Manual Workflow Trigger

- Go to Actions tab
- Select "Deploy Website" workflow
- Click "Run workflow"
- Select environment (develop or main)

Expected: Deployment completes successfully

### Success Criteria:

#### Manual Verification:

- [x] Dev site accessible at `https://dev.djexy32ybwpz7.amplifyapp.com`
- [x] Prod site accessible at `https://main.djexy32ybwpz7.amplifyapp.com`
- [x] All pages load correctly (/, /portfolio, /about, /contact)
- [ ] Contact form submits successfully (test with API)
- [ ] Portfolio images load from S3
- [x] HTTPS works (certificate valid)
- [ ] No console errors in browser

---

## Testing Strategy

### Unit Tests:

- Astro build succeeds locally: `cd frontend && npm run build`
- Terraform validates: `cd terraform && terraform validate`

### Integration Tests:

- GitHub Actions workflow completes without errors
- Amplify deployment succeeds
- Site is accessible via HTTPS

### Manual Testing Steps:

1. Visit the Amplify URL
2. Navigate through all pages
3. Test contact form submission
4. View portfolio gallery
5. Check browser console for errors
6. Test on mobile device

## Rollback Plan

If issues arise after deployment:

1. **Quick rollback**: Amplify keeps previous deployments - use AWS console to redeploy previous version
2. **Git rollback**: Revert the commit and push, triggering a new deployment
3. **Full rollback**: Re-enable CloudFront by uncommenting `cloudfront.tf` and running `terraform apply`

## Migration Notes

**Before migration:**

- Ensure you have AWS SSO sessions active for both jw-dev and jw-prod
- Run `terraform apply` in jw-dev first to test
- Note all terraform output values for GitHub secrets

**During migration:**

- Site will have brief downtime when switching from CloudFront to Amplify
- DNS changes (if custom domain) can take up to 48 hours to propagate

**After migration:**

- Monitor CloudWatch logs for any errors
- Check Amplify deployment history for failed deployments
- Remove any unused S3 objects from the website bucket

## References

- Master plan: `thoughts/shared/plans/2026-01-08-build-website-master-plan.md`
- AWS Amplify Terraform docs: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/amplify_app
- AWS Amplify deployment guide: https://docs.aws.amazon.com/amplify/latest/userguide/deploy-website-from-s3.html
- GitHub Actions OIDC: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
- Existing GitHub Actions pattern: `~/repos/aws-projects/.github/workflows/deploy-postgresql-timescaledb.yml`
