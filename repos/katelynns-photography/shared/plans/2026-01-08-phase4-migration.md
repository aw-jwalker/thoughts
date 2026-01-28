# Phase 4: Migration from Wix to AWS - Detailed Implementation Plan

## Overview

This plan details the migration process from the existing Wix website to the new AWS infrastructure. This phase covers exporting content from Wix, organizing and uploading photos to S3, and performing the DNS cutover to transition traffic to the new site.

## Current State Analysis

### Existing Infrastructure (from Phases 1-3)

**Phase 1 Terraform Resources:**

- S3 Buckets:
  - `katelynns-photography-website` - Static site files (Astro)
  - `katelynns-photography-portfolio-assets` - Public portfolio images
  - `katelynns-photography-client-albums` - Private client albums
- CloudFront: Pending AWS account verification (blocker)
- Cognito User Pool: `us-east-2_bn71poxi6`
- API Gateway: `https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com`
- Route53/ACM: Skipped (domain_name is empty in tfvars)
- SES: Configuration set created (email identity mode)

**Phase 2 Backend:**

- Lambda functions deployed and operational
- Contact form, client portal, and admin API working
- API routes configured and tested

**Phase 3 Frontend:**

- Astro public site built and ready for deployment
- HTMX client portal integrated with Lambda
- All pages created (landing, portfolio, about, contact)
- Deployment scripts ready

### Current Wix Setup (Based on Master Plan)

- **Plan**: $900 for 2 years ($37.50/month)
- **Storage**: Over 100GB of photos
- **Features in use**:
  - Public photo galleries (portfolio showcase)
  - Private client downloads (authenticated access)
  - Contact/inquiry form
  - About/bio section

### Blockers Identified

1. **CloudFront**: Pending AWS account verification - cannot serve site via CDN until resolved
2. **Domain**: `domain_name` is empty in terraform.tfvars - Route53/ACM not deployed
3. **SES**: In sandbox mode - cannot send to non-verified emails

## Desired End State

After completing this phase:

1. **All content migrated from Wix to S3**
2. **Photos organized in correct bucket structure**
3. **Domain pointing to new AWS infrastructure**
4. **SSL certificate issued and working**
5. **Old Wix site deprecated (but kept temporarily as fallback)**

### Verification

- Website accessible via custom domain (HTTPS)
- All portfolio galleries display correctly
- Client albums accessible via presigned URLs
- Contact form sends emails successfully
- Page load time < 3 seconds
- No broken links or missing images

## What We're NOT Doing

- Migrating Wix email marketing data (future consideration)
- Preserving exact URL structure from Wix (no SEO value in this case)
- Automatic redirect setup on Wix (manual cancellation later)
- Payment processing setup (Phase 5 future enhancement)

---

## Implementation Approach

The migration is broken into four sub-phases:

1. **Phase 4.1**: Resolve blockers (CloudFront, domain configuration)
2. **Phase 4.2**: Export content from Wix
3. **Phase 4.3**: Upload and organize content in S3
4. **Phase 4.4**: DNS cutover and validation

---

## Phase 4.1: Resolve Blockers

### Overview

Before migration, we must resolve the AWS account verification and configure the custom domain.

### Changes Required:

#### 1. AWS CloudFront Verification

**Status**: Pending AWS support case resolution

**Action Required**:

- Check AWS Support Console for case status
- If resolved, re-run `terraform apply` to create CloudFront distribution
- If not resolved, follow up with AWS Support

```bash
# Check current terraform state
cd ~/repos/katelynns-photography/terraform
terraform plan
```

#### 2. Configure Custom Domain

**File**: `terraform/terraform.tfvars`

Update with actual domain:

```hcl
aws_profile    = "jw-dev"
project_name   = "katelynns-photography"
domain_name    = "katelynnsphotography.com"  # UPDATE THIS
admin_email    = "katelynn@example.com"      # UPDATE with real email
ses_from_email = "contact@katelynnsphotography.com"
```

#### 3. Apply Terraform with Domain Configuration

```bash
cd ~/repos/katelynns-photography/terraform

# Review changes (will create Route53, ACM, update CloudFront)
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# Note the outputs - especially nameservers
terraform output route53_nameservers
```

#### 4. Update Domain Registrar Nameservers

After Route53 hosted zone is created, update the domain registrar (where the domain was purchased) with the AWS Route53 nameservers.

**Manual Steps**:

1. Log into domain registrar (GoDaddy, Namecheap, etc.)
2. Find DNS/Nameserver settings
3. Replace existing nameservers with Route53 nameservers from terraform output
4. Save changes (propagation takes 24-48 hours)

#### 5. SES Production Access (Optional but Recommended)

**Current State**: SES is in sandbox mode - can only send to verified emails.

**To Request Production Access**:

1. Go to AWS SES Console
2. Click "Request production access"
3. Fill out the form:
   - Use case: Transactional emails (contact form)
   - Expected volume: < 100 emails/month
   - Bounce/complaint handling: Will monitor CloudWatch

**Alternative**: Keep sandbox mode and verify `admin_email` address to receive contact form submissions.

```bash
# Verify admin email for sandbox mode
aws ses verify-email-identity \
    --email-address katelynn@example.com \
    --profile jw-dev \
    --region us-east-2
```

### Success Criteria:

#### Automated Verification:

- [ ] `terraform plan` shows no pending changes after apply
- [ ] `terraform output cloudfront_domain_name` returns a CloudFront URL
- [ ] `terraform output route53_nameservers` returns 4 nameservers
- [ ] `dig katelynnsphotography.com NS` shows Route53 nameservers (after propagation)

#### Manual Verification:

- [ ] CloudFront distribution status is "Deployed" in AWS Console
- [ ] ACM certificate status is "Issued" in us-east-1
- [ ] SES email identity verified (check email for verification link)

**Implementation Note**: DNS propagation can take 24-48 hours. Proceed to Phase 4.2 while waiting.

---

## Phase 4.2: Export Content from Wix

### Overview

Export all content from the Wix website including images, text content, and any client data.

### Changes Required:

#### 1. Create Local Export Directory Structure

```bash
mkdir -p ~/wix-export/{portfolio,client-albums,content,assets}
```

#### 2. Export Portfolio Images from Wix

**Manual Steps** (Wix doesn't have bulk export):

1. **Log into Wix Dashboard**
2. **Go to Media Manager**
3. **Download portfolio images**:
   - Select all portfolio/gallery images
   - Click "Download" or right-click > Save
   - Save to `~/wix-export/portfolio/`
4. **Organize by category** (if applicable):
   ```bash
   mkdir -p ~/wix-export/portfolio/{wedding,portrait,event}
   # Manually sort images into categories
   ```

#### 3. Export Client Album Images

**Manual Steps**:

1. **In Wix Media Manager**, locate client folders
2. **Download each client's photos**:
   - Create folder per client: `~/wix-export/client-albums/clientname-date/`
   - Download all photos for that client
3. **Document client access**:
   - Note which clients have accounts
   - Export client email list for Cognito recreation

**Create Client Manifest**:

**File**: `~/wix-export/client-albums/manifest.json`

```json
{
  "clients": [
    {
      "email": "client1@example.com",
      "name": "John & Jane Smith",
      "albums": [
        {
          "name": "Smith Wedding 2024",
          "folder": "smith-wedding-2024",
          "photo_count": 150,
          "date": "2024-06-15"
        }
      ]
    },
    {
      "email": "client2@example.com",
      "name": "The Johnson Family",
      "albums": [
        {
          "name": "Johnson Family Portrait",
          "folder": "johnson-family-portrait",
          "photo_count": 45,
          "date": "2024-09-20"
        }
      ]
    }
  ]
}
```

#### 4. Export Text Content

**Manual Steps**:

1. **About Page Content**:
   - Copy text from Wix about page
   - Save to `~/wix-export/content/about.txt`

2. **Any other static content**:
   - Bio, testimonials, pricing info
   - Save to appropriate files in `~/wix-export/content/`

3. **Export Site Assets**:
   - Logo files
   - Favicon
   - Any custom graphics
   - Save to `~/wix-export/assets/`

#### 5. Create Export Verification Script

**File**: `scripts/verify_export.sh`

```bash
#!/bin/bash
# Verify Wix export completeness
# Usage: ./scripts/verify_export.sh ~/wix-export

set -e

EXPORT_DIR="${1:-$HOME/wix-export}"

echo "=========================================="
echo "Wix Export Verification"
echo "=========================================="
echo "Export directory: $EXPORT_DIR"
echo ""

# Check directory structure
echo "Checking directory structure..."
for dir in portfolio client-albums content assets; do
    if [ -d "$EXPORT_DIR/$dir" ]; then
        count=$(find "$EXPORT_DIR/$dir" -type f | wc -l)
        echo "  [OK] $dir/ - $count files"
    else
        echo "  [MISSING] $dir/"
    fi
done

echo ""

# Count portfolio images
echo "Portfolio images by category:"
for category in wedding portrait event; do
    if [ -d "$EXPORT_DIR/portfolio/$category" ]; then
        count=$(find "$EXPORT_DIR/portfolio/$category" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) | wc -l)
        echo "  - $category: $count images"
    fi
done

echo ""

# Count client albums
echo "Client albums:"
if [ -d "$EXPORT_DIR/client-albums" ]; then
    for album in "$EXPORT_DIR/client-albums"/*/; do
        if [ -d "$album" ]; then
            name=$(basename "$album")
            count=$(find "$album" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) | wc -l)
            echo "  - $name: $count images"
        fi
    done
fi

echo ""

# Calculate total size
total_size=$(du -sh "$EXPORT_DIR" 2>/dev/null | cut -f1)
echo "Total export size: $total_size"

echo ""

# Check for manifest
if [ -f "$EXPORT_DIR/client-albums/manifest.json" ]; then
    echo "[OK] Client manifest found"
else
    echo "[WARNING] Client manifest not found"
fi

echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
```

Make executable:

```bash
chmod +x scripts/verify_export.sh
```

### Success Criteria:

#### Automated Verification:

- [ ] `./scripts/verify_export.sh` completes without errors
- [ ] Total export size roughly matches Wix storage (100GB+)

#### Manual Verification:

- [ ] All portfolio categories have images
- [ ] All client albums exported with correct folder structure
- [ ] Client manifest has all client information
- [ ] Logo and asset files exported
- [ ] Text content saved for reference

**Implementation Note**: This is a manual process that may take several hours depending on the amount of content.

---

## Phase 4.3: Upload Content to S3

### Overview

Upload exported content to the appropriate S3 buckets with correct organization and metadata.

### Changes Required:

#### 1. Create Upload Script for Portfolio Images

**File**: `scripts/upload_portfolio.sh`

```bash
#!/bin/bash
# Upload portfolio images to S3
# Usage: ./scripts/upload_portfolio.sh ~/wix-export/portfolio

set -e

SOURCE_DIR="${1:-$HOME/wix-export/portfolio}"
S3_BUCKET="katelynns-photography-portfolio-assets"
AWS_PROFILE="${AWS_PROFILE:-jw-dev}"
AWS_REGION="${AWS_REGION:-us-east-2}"

echo "=========================================="
echo "Portfolio Upload"
echo "=========================================="
echo "Source: $SOURCE_DIR"
echo "Bucket: $S3_BUCKET"
echo "Profile: $AWS_PROFILE"
echo ""

# Check if source exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory not found: $SOURCE_DIR"
    exit 1
fi

# Upload with appropriate content-type and cache headers
echo "Uploading images..."

# Upload JPG/JPEG files
aws s3 sync "$SOURCE_DIR" "s3://$S3_BUCKET/images/" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --exclude "*" \
    --include "*.jpg" \
    --include "*.jpeg" \
    --include "*.JPG" \
    --include "*.JPEG" \
    --content-type "image/jpeg" \
    --cache-control "public, max-age=31536000, immutable" \
    --metadata "source=wix-migration"

# Upload PNG files
aws s3 sync "$SOURCE_DIR" "s3://$S3_BUCKET/images/" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --exclude "*" \
    --include "*.png" \
    --include "*.PNG" \
    --content-type "image/png" \
    --cache-control "public, max-age=31536000, immutable" \
    --metadata "source=wix-migration"

# Upload WebP files
aws s3 sync "$SOURCE_DIR" "s3://$S3_BUCKET/images/" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --exclude "*" \
    --include "*.webp" \
    --include "*.WEBP" \
    --content-type "image/webp" \
    --cache-control "public, max-age=31536000, immutable" \
    --metadata "source=wix-migration"

echo ""

# Verify upload
echo "Verifying upload..."
total_uploaded=$(aws s3 ls "s3://$S3_BUCKET/images/" --recursive --profile "$AWS_PROFILE" --region "$AWS_REGION" | wc -l)
total_source=$(find "$SOURCE_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" -o -name "*.JPG" -o -name "*.JPEG" -o -name "*.PNG" -o -name "*.WEBP" \) | wc -l)

echo "Source files: $total_source"
echo "Uploaded files: $total_uploaded"

if [ "$total_uploaded" -eq "$total_source" ]; then
    echo "[OK] All files uploaded successfully"
else
    echo "[WARNING] File count mismatch - verify manually"
fi

echo ""
echo "=========================================="
echo "Portfolio Upload Complete"
echo "=========================================="
echo "Images available at: s3://$S3_BUCKET/images/"
```

#### 2. Create Upload Script for Client Albums

**File**: `scripts/upload_client_albums.sh`

```bash
#!/bin/bash
# Upload client albums to S3
# Usage: ./scripts/upload_client_albums.sh ~/wix-export/client-albums

set -e

SOURCE_DIR="${1:-$HOME/wix-export/client-albums}"
S3_BUCKET="katelynns-photography-client-albums"
AWS_PROFILE="${AWS_PROFILE:-jw-dev}"
AWS_REGION="${AWS_REGION:-us-east-2}"

echo "=========================================="
echo "Client Albums Upload"
echo "=========================================="
echo "Source: $SOURCE_DIR"
echo "Bucket: $S3_BUCKET"
echo "Profile: $AWS_PROFILE"
echo ""

# Check if source exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory not found: $SOURCE_DIR"
    exit 1
fi

# Check for manifest
MANIFEST="$SOURCE_DIR/manifest.json"
if [ ! -f "$MANIFEST" ]; then
    echo "Warning: No manifest.json found. Uploading all folders."
    echo ""
fi

# Process each client album folder
for album_dir in "$SOURCE_DIR"/*/; do
    if [ -d "$album_dir" ]; then
        album_name=$(basename "$album_dir")

        # Skip if it's not a directory or is the manifest
        if [ "$album_name" == "manifest.json" ]; then
            continue
        fi

        echo "Processing album: $album_name"

        # The S3 structure should be: albums/{sanitized_email}/{album_name}/
        # For migration, we'll use a placeholder email structure
        # The admin will need to associate these with actual client emails later

        # Upload to a staging area first
        aws s3 sync "$album_dir" "s3://$S3_BUCKET/staging/$album_name/" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --exclude "*.json" \
            --cache-control "private, max-age=86400" \
            --metadata "source=wix-migration,status=pending-assignment"

        # Count uploaded
        count=$(aws s3 ls "s3://$S3_BUCKET/staging/$album_name/" --recursive --profile "$AWS_PROFILE" --region "$AWS_REGION" | wc -l)
        echo "  Uploaded: $count files"
        echo ""
    fi
done

# Upload manifest
if [ -f "$MANIFEST" ]; then
    echo "Uploading manifest..."
    aws s3 cp "$MANIFEST" "s3://$S3_BUCKET/staging/manifest.json" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --content-type "application/json"
    echo "Manifest uploaded"
fi

echo ""
echo "=========================================="
echo "Client Albums Upload Complete"
echo "=========================================="
echo ""
echo "IMPORTANT: Client albums are in staging area."
echo "Use the assign_album.sh script to move them to"
echo "the correct client email prefix structure."
echo ""
echo "Staging location: s3://$S3_BUCKET/staging/"
```

#### 3. Create Script to Assign Albums to Clients

**File**: `scripts/assign_album.sh`

```bash
#!/bin/bash
# Assign a staged album to a client email
# This creates the proper S3 structure and optionally creates the Cognito user
# Usage: ./scripts/assign_album.sh <album_name> <client_email> [--create-user]

set -e

ALBUM_NAME="$1"
CLIENT_EMAIL="$2"
CREATE_USER="$3"

S3_BUCKET="katelynns-photography-client-albums"
COGNITO_USER_POOL_ID="us-east-2_bn71poxi6"
AWS_PROFILE="${AWS_PROFILE:-jw-dev}"
AWS_REGION="${AWS_REGION:-us-east-2}"

if [ -z "$ALBUM_NAME" ] || [ -z "$CLIENT_EMAIL" ]; then
    echo "Usage: ./scripts/assign_album.sh <album_name> <client_email> [--create-user]"
    echo ""
    echo "Example:"
    echo "  ./scripts/assign_album.sh smith-wedding-2024 john@example.com --create-user"
    exit 1
fi

# Sanitize email for S3 path
SAFE_EMAIL=$(echo "$CLIENT_EMAIL" | tr '[:upper:]' '[:lower:]' | sed 's/@/_at_/g; s/\./_/g')
TARGET_PREFIX="albums/$SAFE_EMAIL/$ALBUM_NAME"

echo "=========================================="
echo "Assign Album to Client"
echo "=========================================="
echo "Album: $ALBUM_NAME"
echo "Client: $CLIENT_EMAIL"
echo "S3 Path: s3://$S3_BUCKET/$TARGET_PREFIX/"
echo ""

# Check if staging album exists
echo "Checking staging area..."
staging_count=$(aws s3 ls "s3://$S3_BUCKET/staging/$ALBUM_NAME/" --recursive --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null | wc -l)

if [ "$staging_count" -eq 0 ]; then
    echo "Error: Album not found in staging: $ALBUM_NAME"
    exit 1
fi

echo "Found $staging_count files in staging"

# Copy from staging to client prefix
echo ""
echo "Copying to client prefix..."
aws s3 sync "s3://$S3_BUCKET/staging/$ALBUM_NAME/" "s3://$S3_BUCKET/$TARGET_PREFIX/" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --metadata-directive REPLACE \
    --metadata "client-email=$CLIENT_EMAIL,assigned-date=$(date -I)"

# Verify copy
target_count=$(aws s3 ls "s3://$S3_BUCKET/$TARGET_PREFIX/" --recursive --profile "$AWS_PROFILE" --region "$AWS_REGION" | wc -l)
echo "Copied $target_count files to client prefix"

# Optionally create Cognito user
if [ "$CREATE_USER" == "--create-user" ]; then
    echo ""
    echo "Creating Cognito user..."

    # Check if user exists
    user_exists=$(aws cognito-idp admin-get-user \
        --user-pool-id "$COGNITO_USER_POOL_ID" \
        --username "$CLIENT_EMAIL" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>&1 || echo "NOT_FOUND")

    if echo "$user_exists" | grep -q "UserNotFoundException"; then
        # Create user
        aws cognito-idp admin-create-user \
            --user-pool-id "$COGNITO_USER_POOL_ID" \
            --username "$CLIENT_EMAIL" \
            --user-attributes \
                Name=email,Value="$CLIENT_EMAIL" \
                Name=email_verified,Value=true \
            --desired-delivery-mediums EMAIL \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION"

        echo "User created. Invitation email sent to $CLIENT_EMAIL"
    else
        echo "User already exists in Cognito"
    fi
fi

# Optionally remove from staging
echo ""
read -p "Remove album from staging? (y/N): " confirm
if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
    aws s3 rm "s3://$S3_BUCKET/staging/$ALBUM_NAME/" --recursive \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"
    echo "Staging album removed"
fi

echo ""
echo "=========================================="
echo "Album Assignment Complete"
echo "=========================================="
echo ""
echo "Client can now access their album at:"
echo "https://[your-domain]/client"
echo ""
echo "Login: $CLIENT_EMAIL"
echo "Album: $ALBUM_NAME"
```

#### 4. Deploy Astro Site to S3

```bash
# Build and deploy Astro site
./scripts/deploy_astro.sh
```

Make scripts executable:

```bash
chmod +x scripts/upload_portfolio.sh
chmod +x scripts/upload_client_albums.sh
chmod +x scripts/assign_album.sh
```

### Success Criteria:

#### Automated Verification:

- [ ] `./scripts/upload_portfolio.sh` completes successfully
- [ ] `./scripts/upload_client_albums.sh` completes successfully
- [ ] `aws s3 ls s3://katelynns-photography-portfolio-assets/images/ --profile jw-dev` shows uploaded images
- [ ] `aws s3 ls s3://katelynns-photography-client-albums/staging/ --profile jw-dev` shows staged albums
- [ ] Astro site deployed to `katelynns-photography-website` bucket

#### Manual Verification:

- [ ] Portfolio images accessible via CloudFront URL (once deployed)
- [ ] At least one client album assigned and accessible
- [ ] Test client can log in and see their album
- [ ] Presigned URLs work for photo downloads

**Implementation Note**: After uploading, use the assign_album.sh script for each client in the manifest.

---

## Phase 4.4: DNS Cutover and Validation

### Overview

Perform the final DNS cutover to point the domain to AWS infrastructure.

### Pre-Cutover Checklist

Before proceeding with DNS cutover, verify:

- [ ] CloudFront distribution is "Deployed" status
- [ ] ACM certificate is "Issued" status
- [ ] Route53 nameservers updated at registrar (from Phase 4.1)
- [ ] DNS propagation complete (`dig katelynnsphotography.com` returns Route53 nameservers)
- [ ] All portfolio images uploaded to S3
- [ ] Astro site deployed to S3
- [ ] At least one test client account working
- [ ] Contact form tested and working

### Changes Required:

#### 1. Verify SSL Certificate Status

```bash
# Check ACM certificate in us-east-1
aws acm list-certificates \
    --profile jw-dev \
    --region us-east-1 \
    --query 'CertificateSummaryList[?DomainName==`katelynnsphotography.com`]'
```

#### 2. Verify CloudFront Distribution

```bash
cd ~/repos/katelynns-photography/terraform

# Get CloudFront details
terraform output cloudfront_distribution_id
terraform output cloudfront_domain_name

# Check distribution status
aws cloudfront get-distribution \
    --id $(terraform output -raw cloudfront_distribution_id) \
    --profile jw-dev \
    --query 'Distribution.Status'
```

#### 3. Test Site via CloudFront URL

Before DNS cutover, test the site via the CloudFront URL:

```bash
# Get CloudFront URL
CF_URL=$(cd ~/repos/katelynns-photography/terraform && terraform output -raw cloudfront_domain_name)

# Test main pages
curl -I "https://$CF_URL/"
curl -I "https://$CF_URL/portfolio"
curl -I "https://$CF_URL/about"
curl -I "https://$CF_URL/contact"

# Test images
curl -I "https://$CF_URL/images/wedding/sample.jpg"
```

#### 4. Verify DNS Records in Route53

```bash
# Check Route53 records
aws route53 list-resource-record-sets \
    --hosted-zone-id $(cd ~/repos/katelynns-photography/terraform && terraform output -raw route53_zone_id) \
    --profile jw-dev \
    --query 'ResourceRecordSets[?Type==`A`]'
```

#### 5. Test Domain Resolution

```bash
# Test DNS resolution (should point to CloudFront)
dig katelynnsphotography.com A
dig www.katelynnsphotography.com A

# Test HTTPS
curl -I https://katelynnsphotography.com
curl -I https://www.katelynnsphotography.com
```

#### 6. Create Validation Script

**File**: `scripts/validate_migration.sh`

```bash
#!/bin/bash
# Validate complete migration
# Usage: ./scripts/validate_migration.sh [domain]

set -e

DOMAIN="${1:-katelynnsphotography.com}"
AWS_PROFILE="${AWS_PROFILE:-jw-dev}"

echo "=========================================="
echo "Migration Validation"
echo "=========================================="
echo "Domain: $DOMAIN"
echo ""

# Test homepage
echo "Testing homepage..."
status=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/")
if [ "$status" == "200" ]; then
    echo "  [OK] Homepage returns 200"
else
    echo "  [FAIL] Homepage returns $status"
fi

# Test portfolio
echo "Testing portfolio..."
status=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/portfolio")
if [ "$status" == "200" ]; then
    echo "  [OK] Portfolio returns 200"
else
    echo "  [FAIL] Portfolio returns $status"
fi

# Test about
echo "Testing about..."
status=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/about")
if [ "$status" == "200" ]; then
    echo "  [OK] About returns 200"
else
    echo "  [FAIL] About returns $status"
fi

# Test contact
echo "Testing contact..."
status=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/contact")
if [ "$status" == "200" ]; then
    echo "  [OK] Contact returns 200"
else
    echo "  [FAIL] Contact returns $status"
fi

# Test client portal
echo "Testing client portal..."
status=$(curl -s -o /dev/null -w "%{http_code}" "https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com/client")
if [ "$status" == "200" ]; then
    echo "  [OK] Client portal returns 200"
else
    echo "  [FAIL] Client portal returns $status"
fi

# Test API health
echo "Testing API health..."
status=$(curl -s -o /dev/null -w "%{http_code}" "https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com/health")
if [ "$status" == "200" ]; then
    echo "  [OK] API health returns 200"
else
    echo "  [FAIL] API health returns $status"
fi

# Test SSL certificate
echo ""
echo "Testing SSL certificate..."
ssl_info=$(echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
if [ -n "$ssl_info" ]; then
    echo "  [OK] SSL certificate valid"
    echo "$ssl_info" | sed 's/^/       /'
else
    echo "  [FAIL] SSL certificate issue"
fi

# Test CloudFront headers
echo ""
echo "Testing CloudFront headers..."
cf_header=$(curl -s -I "https://$DOMAIN/" | grep -i "x-cache" || echo "")
if [ -n "$cf_header" ]; then
    echo "  [OK] CloudFront serving content"
    echo "       $cf_header"
else
    echo "  [WARNING] CloudFront headers not found"
fi

echo ""
echo "=========================================="
echo "Validation Complete"
echo "=========================================="
```

Make executable:

```bash
chmod +x scripts/validate_migration.sh
```

#### 7. Post-Cutover Actions

After successful validation:

1. **Monitor for issues**:
   - Check CloudWatch logs for errors
   - Monitor CloudFront cache hit ratio
   - Watch for any 404/500 errors

2. **Notify clients**:
   - Send email to existing clients with new login URL
   - Provide any necessary instructions

3. **Keep Wix as fallback** (for 1-2 weeks):
   - Don't cancel Wix subscription immediately
   - Keep it available in case of issues
   - Cancel after confident migration is stable

4. **Update any external links**:
   - Social media profiles
   - Business listings
   - Email signatures

### Success Criteria:

#### Automated Verification:

- [ ] `./scripts/validate_migration.sh` passes all checks
- [ ] SSL certificate valid (not expired)
- [ ] CloudFront serving content (X-Cache header present)

#### Manual Verification:

- [ ] All pages load correctly via custom domain
- [ ] Contact form submits successfully
- [ ] Client login works
- [ ] Photo downloads work
- [ ] Mobile experience is good
- [ ] No broken images or links
- [ ] Page load time < 3 seconds

**Implementation Note**: Keep Wix subscription active for 1-2 weeks after cutover as a safety net.

---

## Testing Strategy

### Pre-Migration Testing

Before starting migration:

1. **Test via CloudFront URL**:
   - All Astro pages load
   - Images load from portfolio bucket
   - Contact form works

2. **Test client portal**:
   - Login flow works
   - Albums display correctly
   - Downloads work

### Post-Migration Testing

After DNS cutover:

1. **Full site walkthrough**:
   - Visit every page
   - Check all images
   - Test all interactive elements

2. **Client flow testing**:
   - Create test client account
   - Upload test album
   - Verify download flow

3. **Performance testing**:
   - Run Lighthouse audit
   - Check load times
   - Verify caching headers

### Manual Testing Checklist

- [ ] Homepage loads with hero image
- [ ] Portfolio gallery displays and filters work
- [ ] Lightbox opens and navigates
- [ ] About page content displays correctly
- [ ] Contact form submits and sends email
- [ ] Client login page loads
- [ ] Client can log in with credentials
- [ ] Client sees their albums
- [ ] Client can download photos
- [ ] Mobile navigation works
- [ ] All images have alt text
- [ ] SSL certificate shows as valid in browser
- [ ] No console errors in browser dev tools

---

## Rollback Plan

If issues are discovered after DNS cutover:

### Quick Rollback (DNS)

1. **Revert nameservers at registrar**:
   - Log into domain registrar
   - Change nameservers back to previous values (note these before migration!)
   - DNS will start resolving to old site within minutes to hours

### Alternative: CloudFront Disable

1. **Disable CloudFront distribution**:
   ```bash
   aws cloudfront update-distribution \
       --id <distribution-id> \
       --if-match <etag> \
       --distribution-config '{"Enabled": false, ...}'
   ```

### Data Rollback

If S3 data is corrupted:

1. **S3 versioning is enabled** - can restore previous versions
2. **Re-upload from local export** - `~/wix-export/` should still exist

### Document Pre-Migration State

Before migration, document:

- Current registrar nameservers
- Current Wix site URL structure
- Any custom DNS records

---

## Timeline Estimate

| Sub-Phase            | Duration  | Dependencies                          |
| -------------------- | --------- | ------------------------------------- |
| 4.1 Resolve Blockers | 1-3 days  | AWS Support response, DNS propagation |
| 4.2 Export from Wix  | 2-4 hours | Manual process                        |
| 4.3 Upload to S3     | 1-4 hours | Depends on internet speed, 100GB+     |
| 4.4 DNS Cutover      | 1-2 hours | Validation and monitoring             |

**Total**: 2-5 days (mostly waiting for DNS propagation and AWS verification)

---

## Cost Considerations

### Migration Costs

- **S3 Upload**: ~$0.005 per 1,000 requests + data transfer
- **Data Transfer IN**: Free
- **Storage**: ~$3.45/month for 150GB

### Ongoing Costs After Migration

Based on master plan estimates:

- S3 Storage (150GB): ~$3.45/month
- CloudFront: $0-15/month (depends on traffic)
- Lambda/API Gateway: ~$0 (free tier)
- Route53: ~$0.50/month
- **Total**: ~$5-25/month

**Savings vs Wix**: $12.50-32.50/month

---

## References

- Master plan: `thoughts/shared/plans/2026-01-08-build-website-master-plan.md`
- Phase 1 plan: `thoughts/shared/plans/2026-01-08-phase1-terraform-infrastructure.md`
- Phase 2 plan: `thoughts/shared/plans/2026-01-08-phase2-backend-lambda.md`
- Phase 3 plan: `thoughts/shared/plans/2026-01-08-phase3-frontend-hybrid.md`
- AWS S3 CLI: https://docs.aws.amazon.com/cli/latest/reference/s3/
- Route53 DNS: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/

---

## Summary

Phase 4 migrates the photography website from Wix to AWS:

1. **Phase 4.1**: Resolve CloudFront blocker and configure custom domain
2. **Phase 4.2**: Export all content from Wix (manual process)
3. **Phase 4.3**: Upload and organize content in S3 buckets
4. **Phase 4.4**: DNS cutover and comprehensive validation

**Key Scripts Created**:

- [x] `scripts/verify_export.sh` - Verify Wix export completeness
- [x] `scripts/upload_portfolio.sh` - Upload portfolio images to S3
- [x] `scripts/upload_client_albums.sh` - Upload client albums to staging
- [x] `scripts/assign_album.sh` - Assign albums to client emails
- [x] `scripts/validate_migration.sh` - Validate complete migration

**Prerequisites**:

- Phases 1-3 complete
- AWS CloudFront verification resolved
- Custom domain available
- Wix admin access for export
