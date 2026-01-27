# Photography Website Migration: Wix to AWS

## Current Situation

**Current Wix Plan**: $900 for 2 years = **$37.50/month**

**Required Features**:

- Public photo galleries (portfolio showcase)
- Private client downloads (authenticated access)
- Contact/inquiry form
- About/bio section
- Future: Payment processing (not immediate)

**Storage Needs**: Over 100GB of photos

## Research Summary

### Wix Pricing Reference

Based on [Wix Pricing Plans](https://www.wix.com/plans):

- **Light Plan**: $17/month - Portfolio without e-commerce
- **Core Plan**: $29/month - With e-commerce for selling prints
- **Business Plan**: $36/month - Advanced e-commerce features
- **Additional costs**: Custom domain (~$15/year), professional email (~$6/month)

### AWS Alternative Architecture

#### Option 1: CloudFront Flat-Rate + S3 + Amplify (Recommended for Simplicity)

**Components:**

1. **AWS Amplify Hosting** - React frontend hosting with CI/CD
   - [Amplify Pricing](https://aws.amazon.com/amplify/pricing/): Free tier (5GB storage, 1000 build minutes)
   - After free tier: ~$0.51-5/month for low-traffic sites

2. **CloudFront Flat-Rate Plan** - CDN with bundled services
   - [CloudFront Pricing](https://aws.amazon.com/cloudfront/pricing/)
   - **Free tier**: $0/month (1M requests, 100GB transfer, includes WAF, DDoS protection)
   - **Pro tier**: $15/month (10M requests, 50TB transfer)

3. **S3 Standard Storage** - Photo storage
   - ~$0.023/GB/month
   - Example: 50GB of photos = ~$1.15/month

4. **Lambda + API Gateway** - Serverless backend
   - Free tier: 1M requests/month, 400,000 GB-seconds compute
   - Likely $0 for a photography portfolio

5. **Amazon SES** - Contact form emails
   - $0.10 per 1,000 emails (effectively free for contact form)

6. **Amazon Cognito** - Client authentication for private galleries
   - Free tier: 50,000 monthly active users
   - Likely $0 for photography clients

7. **Route 53** - DNS hosting
   - $0.50/month per hosted zone + $0.40 per million queries

8. **S3 Presigned URLs** - Secure client photo downloads
   - [Presigned URL Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html)
   - Time-limited secure access to photos without public buckets

#### Estimated Monthly Costs (AWS) - Your Use Case

Based on 150GB storage and moderate client download traffic:

| Service              | Monthly Cost     | Notes                                     |
| -------------------- | ---------------- | ----------------------------------------- |
| S3 Storage (150GB)   | ~$3.45           | $0.023/GB standard storage                |
| CloudFront           | $0-15            | Free tier or Pro if high download traffic |
| Amplify Hosting      | ~$1-5            | React frontend with CI/CD                 |
| Lambda + API Gateway | $0               | Free tier (1M requests/month)             |
| Cognito              | $0               | Free tier (50K MAU)                       |
| Route 53             | ~$0.50           | DNS hosting                               |
| SES                  | ~$0              | Contact form emails only                  |
| **TOTAL**            | **~$5-25/month** | Depending on download traffic             |

**Savings vs Wix**: $12.50-32.50/month = **$150-390/year**

### Feature Mapping: Wix to AWS

| Wix Feature            | AWS Equivalent                                  |
| ---------------------- | ----------------------------------------------- |
| Website hosting        | Amplify Hosting (React)                         |
| Photo galleries        | S3 + CloudFront + React gallery component       |
| Client photo downloads | S3 presigned URLs + Cognito auth                |
| Contact form           | Lambda + API Gateway + SES                      |
| Custom domain          | Route 53                                        |
| SSL/HTTPS              | CloudFront (included)                           |
| CDN                    | CloudFront (included)                           |
| DDoS protection        | CloudFront + AWS Shield (included in flat-rate) |

### Software Licensing (All Free)

| Tool         | License                                                                       | Commercial Use       |
| ------------ | ----------------------------------------------------------------------------- | -------------------- |
| Astro        | [MIT](https://github.com/withastro/astro/blob/main/LICENSE)                   | Yes, free            |
| HTMX         | [Zero-Clause BSD](https://github.com/bigskysoftware/htmx/blob/master/LICENSE) | Yes, no restrictions |
| Flask        | BSD                                                                           | Yes, free            |
| FastAPI      | MIT                                                                           | Yes, free            |
| React        | MIT                                                                           | Yes, free            |
| Tailwind CSS | MIT                                                                           | Yes, free            |

**No licensing costs** - all recommended tools are open source.

### Pros of AWS Migration

1. **Cost savings**: Potentially $10-30/month savings
2. **Full control**: Own your infrastructure, no vendor lock-in
3. **Scalability**: Pay only for what you use
4. **Your skills**: Already experienced with AWS, Terraform, React, Python
5. **Professional growth**: Adds to your portfolio
6. **Data ownership**: Photos stay in your S3 buckets
7. **No software licenses**: All tools are free/open source

### Cons of AWS Migration

1. **Development time**: Need to build React frontend, Lambda backend
2. **Maintenance**: You handle updates, security patches
3. **Learning curve**: Cognito, presigned URLs, etc.
4. **No drag-and-drop**: Code-based changes only
5. **Email marketing**: Would need separate solution (Mailchimp, etc.)

---

## Final Decision

**Hybrid Architecture:**

- **Astro** - Public portfolio site (galleries, about, contact form)
- **HTMX + Python** - Client portal (login, album downloads)

**Why this approach:**

1. Astro excels at image-heavy content (built-in optimization)
2. HTMX + Python lets you explore HTMX while using your Python skills
3. Easy to swap the client portal later if HTMX doesn't suit you
4. Both deploy cleanly to AWS (S3/CloudFront + Lambda)

**Estimated Savings**: $150-390/year vs Wix

---

## Implementation Plan

### Progress Summary (Updated 2026-01-09)

| Phase                   | Status         | Completion |
| ----------------------- | -------------- | ---------- |
| Phase 1: Infrastructure | 🟡 Partial     | 80%        |
| Phase 2: Backend        | ✅ Complete    | 95%        |
| Phase 3: Frontend       | ✅ Complete    | 95%        |
| Phase 4: Migration      | ❌ Not Started | 0%         |

**Key Blockers:**

- ⛔ CloudFront distribution pending AWS account verification (support case opened)
- ⚠️ Custom domain not configured in terraform.tfvars
- ⚠️ SES in sandbox mode (can only send to verified emails)

**What's Working:**

- ✅ S3 buckets created (website, portfolio-assets, client-albums)
- ✅ Cognito user pool and client configured
- ✅ API Gateway with routes deployed
- ✅ Lambda functions deployed (contact-form, client-portal, admin-api)
- ✅ Astro public site built and ready
- ✅ HTMX client portal templates created
- ✅ Deployment scripts ready

**Remaining Tasks:**

1. Resolve CloudFront AWS verification blocker
2. Configure custom domain in terraform.tfvars
3. Run `terraform apply` to create CloudFront, Route53, ACM
4. Deploy Astro site to S3 (`./scripts/deploy_astro.sh`)
5. Export content from Wix
6. Upload photos to S3
7. Update domain registrar nameservers
8. Validate migration

**Terraform Outputs (Current):**

```
api_gateway_url             = "https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com"
cognito_user_pool_id        = "us-east-2_bn71poxi6"
cognito_user_pool_client_id = "6a5h8p858dg9laj544ijvu9gro"
s3_website_bucket           = "katelynns-photography-website"
s3_portfolio_bucket         = "katelynns-photography-portfolio-assets"
s3_client_albums_bucket     = "katelynns-photography-client-albums"
```

---

### Phase 1: Infrastructure (Terraform) — 🟡 80% Complete

**Sub-Phase Status:**

- ✅ 1.1 Project Setup - Backend, providers configured
- ✅ 1.2 S3 Buckets - 3 buckets created (website, portfolio-assets, client-albums)
- ⛔ 1.3 CloudFront - BLOCKED (AWS account verification pending)
- ⏭️ 1.4 ACM Certificate - Skipped (domain_name empty in tfvars)
- ⏭️ 1.5 Route53 DNS - Skipped (domain_name empty in tfvars)
- ✅ 1.6 Cognito User Pool - Created with client app
- ✅ 1.7 SES Email - Configuration set created (sandbox mode)
- ✅ 1.8 API Gateway - HTTP API with routes deployed
- ✅ 1.9 Outputs - Complete

Create a Terraform project with the following modules:

```
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
└── modules/
    ├── s3/              # Photo storage buckets
    ├── cloudfront/      # CDN distributions
    ├── cognito/         # Client authentication
    ├── lambda/          # Backend functions
    ├── api-gateway/     # REST API
    ├── ses/             # Email service
    └── route53/         # DNS
```

**S3 Buckets:**

- `portfolio-gallery` - Public bucket for portfolio images
- `client-albums` - Private bucket for client downloads

**CloudFront Distributions:**

- Public distribution for portfolio (caching optimized for images)
- Private distribution with signed URLs for client downloads

**Cognito User Pool:**

- Email/password authentication for clients
- Admin creates client accounts after sessions
- Password reset flow

### Phase 2: Backend (Python/Lambda) — ✅ 95% Complete

**Sub-Phase Status:**

- ✅ 2.1 Lambda Terraform - IAM roles, functions, API routes configured
- ✅ 2.2 Contact Form - Deployed (SES sandbox limits apply)
- ✅ 2.3 Client Portal - FastAPI + Mangum deployed
- ✅ 2.4 Admin API - Album management endpoints deployed
- ✅ 2.5 Deployment Script - `scripts/deploy_lambda.sh` working
- 🟡 2.6 Integration Testing - Needs end-to-end SES test with verified email

**Lambda Functions:**

1. `contact-form-handler` - Receives form data, sends email via SES
2. `generate-presigned-url` - Creates time-limited download URLs for authenticated clients
3. `list-client-albums` - Returns albums available for logged-in client
4. `admin-create-album` - Allows you to create new client albums

**API Gateway Endpoints:**

- `POST /contact` - Contact form submission
- `GET /albums` - List client's available albums (authenticated)
- `GET /albums/{id}/download` - Get presigned download URL (authenticated)
- `POST /admin/albums` - Create new album (admin only)

### Phase 3: Frontend (Hybrid Approach) — ✅ 95% Complete

**Sub-Phase Status:**

- ✅ 3.1 Astro Project Setup - Initialized with Tailwind CSS
- ✅ 3.2 Base Layout & Navigation - Layout.astro, Navigation.astro, Footer.astro
- ✅ 3.3 Landing Page - Hero, featured work, CTA sections
- ✅ 3.4 Portfolio Gallery - Filterable gallery with lightbox
- ✅ 3.5 About & Contact Pages - Form submits to Lambda backend
- ✅ 3.6 Deployment Script - `scripts/deploy_astro.sh` ready
- ✅ 3.7-3.10 HTMX Client Portal - Templates + routes created
- ⏳ Deployment - Waiting on CloudFront (can deploy to S3 directly)

#### Part A: Astro - Public Portfolio Site

[Astro](https://astro.build/) handles the public-facing portfolio:

- **Built-in image optimization**: Auto WebP conversion, responsive sizing, lazy loading
- **Zero JavaScript by default**: Fast page loads for image-heavy galleries
- **Photography templates**: Start from [Capture](https://astro.build/themes/details/capture-portfolio-template-for-photographer/) or [Foliograph](https://astro.build/themes/details/foliograph-photography-portfolio-template/)
- **Deploys to S3/CloudFront**

```
astro-portfolio/
├── src/
│   ├── pages/
│   │   ├── index.astro        # Landing page with featured work
│   │   ├── portfolio.astro    # Gallery showcase
│   │   ├── about.astro        # Bio and business info
│   │   └── contact.astro      # Inquiry form (posts to Lambda)
│   ├── components/
│   │   ├── Gallery.astro      # Masonry photo grid
│   │   ├── Lightbox.astro     # Full-screen viewer
│   │   ├── ContactForm.astro  # Form component
│   │   └── Navigation.astro   # Header/footer
│   └── layouts/
│       └── Layout.astro       # Base template
├── public/                    # Static assets
├── astro.config.mjs
└── package.json
```

#### Part B: HTMX + FastAPI + Mangum - Client Portal

[HTMX](https://htmx.org/) + [FastAPI](https://fastapi.tiangolo.com/) + [Mangum](https://mangum.io/) for the authenticated client area:

- **FastAPI**: Modern Python web framework, async support, automatic OpenAPI docs
- **Mangum**: ASGI adapter for AWS Lambda (wraps FastAPI for Lambda/API Gateway)
- **HTMX**: Server-side rendering with minimal JS (~14KB)
- **Jinja2**: Template rendering for HTML responses
- **Easy to swap**: If HTMX doesn't work out, easy to replace

**Resources**: [Mangum docs](https://mangum.io/), [FastAPI on Lambda guide](https://www.eliasbrange.dev/posts/deploy-fastapi-on-aws-part-1-lambda-api-gateway/)

```
client-portal/
├── app/
│   ├── main.py                # FastAPI app + Mangum handler
│   ├── templates/
│   │   ├── base.html          # Base template with HTMX script
│   │   ├── login.html         # Client login form
│   │   ├── albums.html        # Album list (HTMX-powered)
│   │   └── album_detail.html  # Individual album with download links
│   ├── routes/
│   │   ├── auth.py            # Login/logout handlers
│   │   └── albums.py          # Album listing, download URL generation
│   └── services/
│       ├── cognito.py         # Cognito authentication
│       └── s3.py              # Presigned URL generation
├── static/
│   └── css/
│       └── tailwind.css       # Tailwind styles
├── requirements.txt           # fastapi, mangum, jinja2, boto3, python-jose
└── template.yaml              # SAM template for Lambda deployment
```

**Example main.py with Mangum:**

```python
from fastapi import FastAPI
from fastapi.templating import Jinja2Templates
from mangum import Mangum

app = FastAPI()
templates = Jinja2Templates(directory="templates")

# ... routes ...

# Lambda handler
handler = Mangum(app)
```

**Client portal flow:**

1. Client visits `/client` → redirected to login
2. Logs in with Cognito credentials (you create accounts for them)
3. Sees their available albums (fetched from DynamoDB or S3 prefix)
4. Clicks download → gets presigned S3 URL → downloads photos

### Phase 4: Migration — ❌ Not Started

**Sub-Phase Status:**

- ❌ 4.1 Resolve Blockers - CloudFront verification, domain configuration
- ❌ 4.2 Export from Wix - Manual download of all content
- ❌ 4.3 Upload to S3 - Scripts ready (`upload_portfolio.sh`, `upload_client_albums.sh`)
- ❌ 4.4 DNS Cutover - Update nameservers, validate migration

**Dependencies:**

- Requires CloudFront verification (Phase 1.3)
- Requires domain name in terraform.tfvars (Phase 1.4-1.5)

1. **Export Wix content:**
   - Download all images from Wix media manager
   - Export text content (about, descriptions)
   - Note current URL structure for redirects

2. **Upload to S3:**
   - Organize photos into portfolio vs client albums
   - Use AWS CLI: `aws s3 sync ./photos s3://bucket-name/`
   - Set appropriate metadata (content-type, cache headers)

3. **DNS Cutover:**
   - Update Route 53 to point to CloudFront
   - Keep Wix active briefly for fallback
   - Verify SSL certificate provisioned

### Phase 5: Verification

- [ ] All portfolio galleries load correctly
- [ ] Images are served via CloudFront (check headers)
- [ ] Client login works (test account creation)
- [ ] Client can view and download their albums
- [ ] Presigned URLs expire correctly
- [ ] Contact form sends emails to your inbox
- [ ] Mobile responsive design works
- [ ] Page load performance acceptable (<3s)
- [ ] SEO basics (meta tags, sitemap)

---

## Future Enhancements (Optional)

- **Payment processing**: Add Stripe for selling prints/downloads
- **Email marketing**: Integrate with Mailchimp or use SES campaigns
- **Booking system**: Add Calendly embed or custom booking
- **Admin dashboard**: React admin panel for managing albums
