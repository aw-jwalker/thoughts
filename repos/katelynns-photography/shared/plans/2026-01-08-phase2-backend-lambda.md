# Phase 2: Backend Lambda Functions - Detailed Implementation Plan

## Overview

This plan details the Python Lambda functions and API Gateway integration for Katelynn's Photography website. Building on the Phase 1 infrastructure (S3, Cognito, API Gateway, SES), this phase creates the serverless backend using FastAPI + Mangum pattern as specified in the master plan.

## Current State Analysis

### Existing Infrastructure (from Phase 1)

Based on Phase 1 outputs:

- **API Gateway**: HTTP API `nbu6ndrpg2` at `https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com`
- **Cognito User Pool**: `us-east-2_bn71poxi6` with client ID `6a5h8p858dg9laj544ijvu9gro`
- **S3 Buckets**:
  - `katelynns-photography-website` - Static site files
  - `katelynns-photography-portfolio-assets` - Public portfolio images
  - `katelynns-photography-client-albums` - Private client albums
- **SES**: Configuration set `katelynns-photography-emails` (email identity mode)

### Phase 1 Blockers (Not Blocking Phase 2)

- CloudFront distribution pending AWS account verification
- Route53/ACM skipped (no domain configured)

These don't block Phase 2 - Lambda functions can be tested directly via API Gateway URL.

## Desired End State

After completing this phase:

1. **Lambda Functions**:
   - `contact-form-handler` - Receives form data, validates, sends email via SES
   - `client-portal` - FastAPI app handling albums listing and presigned URL generation (Mangum-wrapped)
   - `admin-api` - Admin operations for album management

2. **API Gateway Routes**:
   - `POST /contact` - Contact form submission (unauthenticated)
   - `GET /api/albums` - List client's albums (Cognito authenticated)
   - `GET /api/albums/{album_id}/download` - Get presigned download URL (Cognito authenticated)
   - `POST /admin/albums` - Create album (admin-only)

3. **IAM Roles**:
   - Lambda execution roles with least-privilege access to S3, SES, Cognito

### Verification

- `POST /contact` with valid data returns 200 and sends email
- Cognito-authenticated request to `/api/albums` returns user's albums
- Presigned URLs work for downloading client photos
- Admin can create new albums with S3 prefix

## What We're NOT Doing

- Astro frontend (Phase 3)
- HTMX client portal UI (Phase 3)
- DNS/domain configuration
- Payment processing
- DynamoDB for album metadata (using S3 prefixes/tags for simplicity)
- Image processing/thumbnails (future enhancement)

---

## Implementation Approach

Following the master plan's hybrid architecture:

- **FastAPI + Mangum** for the client portal (multiple routes in one Lambda)
- **Simple Python handlers** for contact form and admin API

### Directory Structure

```
katelynns-photography/
├── terraform/                    # Existing Phase 1 infra
│   ├── lambda.tf                 # NEW: Lambda resources
│   └── ...
├── backend/                      # NEW: Lambda function code
│   ├── contact_form/
│   │   ├── handler.py
│   │   └── requirements.txt
│   ├── client_portal/
│   │   ├── app/
│   │   │   ├── __init__.py
│   │   │   ├── main.py           # FastAPI app + Mangum handler
│   │   │   ├── routes/
│   │   │   │   ├── __init__.py
│   │   │   │   └── albums.py
│   │   │   └── services/
│   │   │       ├── __init__.py
│   │   │       ├── cognito.py
│   │   │       └── s3.py
│   │   └── requirements.txt
│   └── admin_api/
│       ├── handler.py
│       └── requirements.txt
├── scripts/
│   └── deploy_lambda.sh          # Build and deploy script
└── thoughts/
```

---

## Phase 2.1: Lambda Infrastructure (Terraform)

### Overview

Add Terraform resources for Lambda functions, IAM roles, and API Gateway integrations.

### Changes Required:

#### 1. Create lambda.tf

**File**: `terraform/lambda.tf`

```hcl
# =============================================================================
# IAM Role for Lambda Functions
# =============================================================================
resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-role"
  }
}

# Basic Lambda execution policy (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for S3, SES, Cognito access
resource "aws_iam_role_policy" "lambda_custom" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ClientAlbumsAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.client_albums.arn,
          "${aws_s3_bucket.client_albums.arn}/*"
        ]
      },
      {
        Sid    = "SESEmailSend"
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ses:FromAddress" = var.ses_from_email
          }
        }
      },
      {
        Sid    = "CognitoAccess"
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminCreateUser",
          "cognito-idp:ListUsers"
        ]
        Resource = aws_cognito_user_pool.clients.arn
      }
    ]
  })
}

# =============================================================================
# Lambda Function: Contact Form
# =============================================================================
resource "aws_lambda_function" "contact_form" {
  function_name = "${var.project_name}-contact-form"
  description   = "Handles contact form submissions"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 10
  memory_size   = 128

  # Placeholder - will be updated by deploy script
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      SES_FROM_EMAIL    = var.ses_from_email
      ADMIN_EMAIL       = var.admin_email
      ENVIRONMENT       = "production"
    }
  }

  tags = {
    Name = "${var.project_name}-contact-form"
  }
}

# =============================================================================
# Lambda Function: Client Portal (FastAPI + Mangum)
# =============================================================================
resource "aws_lambda_function" "client_portal" {
  function_name = "${var.project_name}-client-portal"
  description   = "Client portal API (albums, downloads)"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "app.main.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  # Placeholder - will be updated by deploy script
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      CLIENT_ALBUMS_BUCKET = aws_s3_bucket.client_albums.id
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.clients.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.web.id
      AWS_REGION_NAME      = "us-east-2"
      PRESIGNED_URL_EXPIRY = "3600"  # 1 hour
    }
  }

  tags = {
    Name = "${var.project_name}-client-portal"
  }
}

# =============================================================================
# Lambda Function: Admin API
# =============================================================================
resource "aws_lambda_function" "admin_api" {
  function_name = "${var.project_name}-admin-api"
  description   = "Admin API for album management"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  # Placeholder - will be updated by deploy script
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      CLIENT_ALBUMS_BUCKET = aws_s3_bucket.client_albums.id
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.clients.id
      ADMIN_EMAIL          = var.admin_email
    }
  }

  tags = {
    Name = "${var.project_name}-admin-api"
  }
}

# Placeholder zip for initial deployment
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/placeholder.zip"

  source {
    content  = "def lambda_handler(event, context): return {'statusCode': 200, 'body': 'placeholder'}"
    filename = "handler.py"
  }
}

# =============================================================================
# API Gateway Lambda Integrations
# =============================================================================

# Contact Form Integration
resource "aws_apigatewayv2_integration" "contact_form" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.contact_form.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "contact_form" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /contact"
  target    = "integrations/${aws_apigatewayv2_integration.contact_form.id}"
}

resource "aws_lambda_permission" "contact_form" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact_form.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# Client Portal Integration (catch-all for /api/*)
resource "aws_apigatewayv2_integration" "client_portal" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.client_portal.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "client_portal_albums" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /api/albums"
  target    = "integrations/${aws_apigatewayv2_integration.client_portal.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "client_portal_download" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /api/albums/{album_id}/download"
  target    = "integrations/${aws_apigatewayv2_integration.client_portal.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "client_portal" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.client_portal.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# Admin API Integration
resource "aws_apigatewayv2_integration" "admin_api" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.admin_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "admin_albums" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /admin/albums"
  target    = "integrations/${aws_apigatewayv2_integration.admin_api.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "admin_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.admin_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# =============================================================================
# Cognito JWT Authorizer for API Gateway
# =============================================================================
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.project_name}-cognito-authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.web.id]
    issuer   = "https://cognito-idp.us-east-2.amazonaws.com/${aws_cognito_user_pool.clients.id}"
  }
}
```

#### 2. Update outputs.tf (add Lambda outputs)

**File**: `terraform/outputs.tf` (additions)

```hcl
# =============================================================================
# Lambda Outputs
# =============================================================================
output "lambda_contact_form_arn" {
  description = "Contact form Lambda ARN"
  value       = aws_lambda_function.contact_form.arn
}

output "lambda_client_portal_arn" {
  description = "Client portal Lambda ARN"
  value       = aws_lambda_function.client_portal.arn
}

output "lambda_admin_api_arn" {
  description = "Admin API Lambda ARN"
  value       = aws_lambda_function.admin_api.arn
}
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform validate` passes
- [x] `terraform plan` shows Lambda resources to create
- [x] `terraform apply` succeeds

#### Manual Verification:

- [x] Lambda functions visible in AWS Console
- [x] API Gateway routes visible and linked to Lambda
- [x] JWT authorizer configured with Cognito

**Implementation Note**: After this phase, Lambda functions contain placeholder code. Phase 2.2 implements actual handlers.

---

## Phase 2.2: Contact Form Handler

### Overview

Implement the contact form Lambda function that receives form submissions and sends emails via SES.

### Changes Required:

#### 1. Create backend directory structure

```bash
mkdir -p backend/contact_form
```

#### 2. Create handler.py

**File**: `backend/contact_form/handler.py`

```python
"""
Contact Form Handler

Receives contact form submissions, validates input, and sends email via SES.
"""
import json
import os
import re
import boto3
from botocore.exceptions import ClientError

# Initialize SES client
ses_client = boto3.client("ses", region_name="us-east-2")

# Environment variables
SES_FROM_EMAIL = os.environ.get("SES_FROM_EMAIL", "noreply@example.com")
ADMIN_EMAIL = os.environ.get("ADMIN_EMAIL", "admin@example.com")


def validate_email(email: str) -> bool:
    """Basic email validation."""
    pattern = r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    return bool(re.match(pattern, email))


def sanitize_input(text: str, max_length: int = 1000) -> str:
    """Sanitize input text to prevent injection."""
    if not text:
        return ""
    # Strip HTML tags and limit length
    clean = re.sub(r"<[^>]+>", "", text)
    return clean[:max_length].strip()


def lambda_handler(event, context):
    """
    Handle contact form submission.

    Expected body (JSON):
    {
        "name": "John Doe",
        "email": "john@example.com",
        "phone": "555-1234" (optional),
        "message": "I'd like to book a session...",
        "inquiry_type": "wedding" | "portrait" | "event" | "other"
    }
    """
    # Parse request body
    try:
        if event.get("body"):
            body = json.loads(event["body"])
        else:
            return error_response(400, "Missing request body")
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON in request body")

    # Extract and validate fields
    name = sanitize_input(body.get("name", ""), 100)
    email = body.get("email", "").strip().lower()
    phone = sanitize_input(body.get("phone", ""), 20)
    message = sanitize_input(body.get("message", ""), 2000)
    inquiry_type = sanitize_input(body.get("inquiry_type", "general"), 50)

    # Validation
    errors = []
    if not name or len(name) < 2:
        errors.append("Name is required (minimum 2 characters)")
    if not validate_email(email):
        errors.append("Valid email address is required")
    if not message or len(message) < 10:
        errors.append("Message is required (minimum 10 characters)")

    if errors:
        return error_response(400, "Validation failed", {"errors": errors})

    # Build email content
    subject = f"New Photography Inquiry: {inquiry_type.title()} - {name}"

    email_body_text = f"""
New contact form submission from your photography website:

Name: {name}
Email: {email}
Phone: {phone or 'Not provided'}
Inquiry Type: {inquiry_type.title()}

Message:
{message}

---
This email was sent from your website contact form.
    """.strip()

    email_body_html = f"""
<html>
<head></head>
<body>
    <h2>New Photography Inquiry</h2>
    <p><strong>Name:</strong> {name}</p>
    <p><strong>Email:</strong> <a href="mailto:{email}">{email}</a></p>
    <p><strong>Phone:</strong> {phone or 'Not provided'}</p>
    <p><strong>Inquiry Type:</strong> {inquiry_type.title()}</p>
    <hr>
    <h3>Message:</h3>
    <p>{message.replace(chr(10), '<br>')}</p>
    <hr>
    <p><em>This email was sent from your website contact form.</em></p>
</body>
</html>
    """.strip()

    # Send email via SES
    try:
        ses_client.send_email(
            Source=SES_FROM_EMAIL,
            Destination={
                "ToAddresses": [ADMIN_EMAIL]
            },
            Message={
                "Subject": {"Data": subject, "Charset": "UTF-8"},
                "Body": {
                    "Text": {"Data": email_body_text, "Charset": "UTF-8"},
                    "Html": {"Data": email_body_html, "Charset": "UTF-8"}
                }
            },
            ReplyToAddresses=[email]  # Allow direct reply to sender
        )
    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        print(f"SES error: {error_code} - {e.response['Error']['Message']}")

        if error_code == "MessageRejected":
            # SES sandbox mode - email not verified
            return error_response(
                500,
                "Unable to send email. Please try again later or contact us directly."
            )
        return error_response(500, "Failed to send email")

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        },
        "body": json.dumps({
            "success": True,
            "message": "Thank you for your inquiry! We'll get back to you soon."
        })
    }


def error_response(status_code: int, message: str, details: dict = None):
    """Generate error response."""
    body = {"success": False, "error": message}
    if details:
        body.update(details)

    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        },
        "body": json.dumps(body)
    }
```

#### 3. Create requirements.txt

**File**: `backend/contact_form/requirements.txt`

```
boto3>=1.34.0
```

### Success Criteria:

#### Automated Verification:

- [x] Python syntax valid: `python -m py_compile backend/contact_form/handler.py`
- [x] No import errors when running locally with mocked boto3

#### Manual Verification:

- [x] Deploy to Lambda and test via API Gateway
- [ ] Valid form submission returns 200 and email received (SES sandbox - requires verified email)
- [x] Invalid submission returns 400 with specific error messages
- [x] Missing fields handled gracefully

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation that the email was received before proceeding.

---

## Phase 2.3: Client Portal (FastAPI + Mangum)

### Overview

Implement the client portal FastAPI application for authenticated album access and photo downloads.

### Changes Required:

#### 1. Create client portal directory structure

```bash
mkdir -p backend/client_portal/app/routes backend/client_portal/app/services
touch backend/client_portal/app/__init__.py
touch backend/client_portal/app/routes/__init__.py
touch backend/client_portal/app/services/__init__.py
```

#### 2. Create main.py (FastAPI app + Mangum handler)

**File**: `backend/client_portal/app/main.py`

```python
"""
Client Portal API

FastAPI application for authenticated client access to photo albums.
Wrapped with Mangum for AWS Lambda deployment.
"""
import os
from fastapi import FastAPI, HTTPException, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from mangum import Mangum

from .routes import albums
from .services.cognito import get_current_user

# Initialize FastAPI
app = FastAPI(
    title="Katelynn's Photography Client Portal",
    description="API for clients to access their photo albums",
    version="1.0.0",
    root_path="/api"  # Important for API Gateway path stripping
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Will be restricted in production via API Gateway
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Include routers
app.include_router(albums.router, tags=["albums"])


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "client-portal"}


@app.get("/me")
async def get_user_info(user: dict = Depends(get_current_user)):
    """Get current user information."""
    return {
        "email": user.get("email"),
        "name": user.get("name"),
        "sub": user.get("sub")
    }


# Mangum handler for Lambda
handler = Mangum(app, lifespan="off")
```

#### 3. Create albums router

**File**: `backend/client_portal/app/routes/albums.py`

```python
"""
Albums Router

Handles album listing and download URL generation.
"""
import os
from typing import Optional
from fastapi import APIRouter, HTTPException, Depends, Path, Query
from pydantic import BaseModel

from ..services.cognito import get_current_user
from ..services.s3 import S3Service

router = APIRouter()
s3_service = S3Service()


class Album(BaseModel):
    """Album response model."""
    id: str
    name: str
    photo_count: int
    created_at: Optional[str] = None


class AlbumListResponse(BaseModel):
    """Album list response."""
    albums: list[Album]
    total: int


class DownloadResponse(BaseModel):
    """Download URL response."""
    album_id: str
    download_url: str
    expires_in: int
    file_count: int


@router.get("/albums", response_model=AlbumListResponse)
async def list_albums(user: dict = Depends(get_current_user)):
    """
    List all albums available to the authenticated user.

    Albums are organized by user email prefix in S3:
    s3://bucket/albums/{user_email}/album_name/
    """
    user_email = user.get("email")
    if not user_email:
        raise HTTPException(status_code=401, detail="User email not found in token")

    try:
        albums = s3_service.list_user_albums(user_email)
        return AlbumListResponse(
            albums=albums,
            total=len(albums)
        )
    except Exception as e:
        print(f"Error listing albums for {user_email}: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve albums")


@router.get("/albums/{album_id}", response_model=Album)
async def get_album(
    album_id: str = Path(..., description="Album identifier"),
    user: dict = Depends(get_current_user)
):
    """Get details of a specific album."""
    user_email = user.get("email")

    try:
        album = s3_service.get_album_details(user_email, album_id)
        if not album:
            raise HTTPException(status_code=404, detail="Album not found")
        return album
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error getting album {album_id} for {user_email}: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve album")


@router.get("/albums/{album_id}/download", response_model=DownloadResponse)
async def get_download_url(
    album_id: str = Path(..., description="Album identifier"),
    file_name: Optional[str] = Query(None, description="Specific file to download"),
    user: dict = Depends(get_current_user)
):
    """
    Get presigned URL(s) for downloading album photos.

    If file_name is provided, returns URL for that specific file.
    Otherwise, returns URL for a zip of all photos (if available).
    """
    user_email = user.get("email")

    try:
        # Verify user has access to this album
        album = s3_service.get_album_details(user_email, album_id)
        if not album:
            raise HTTPException(status_code=404, detail="Album not found")

        if file_name:
            # Single file download
            url, expires = s3_service.generate_presigned_url(
                user_email, album_id, file_name
            )
        else:
            # Generate URLs for all files in album
            url, expires, file_count = s3_service.generate_album_download_urls(
                user_email, album_id
            )

        return DownloadResponse(
            album_id=album_id,
            download_url=url,
            expires_in=expires,
            file_count=album.photo_count if not file_name else 1
        )
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error generating download URL for {album_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate download URL")


@router.get("/albums/{album_id}/files")
async def list_album_files(
    album_id: str = Path(..., description="Album identifier"),
    user: dict = Depends(get_current_user)
):
    """List all files in an album with individual download URLs."""
    user_email = user.get("email")

    try:
        album = s3_service.get_album_details(user_email, album_id)
        if not album:
            raise HTTPException(status_code=404, detail="Album not found")

        files = s3_service.list_album_files(user_email, album_id)
        return {
            "album_id": album_id,
            "files": files,
            "total": len(files)
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error listing files for {album_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to list album files")
```

#### 4. Create Cognito service

**File**: `backend/client_portal/app/services/cognito.py`

```python
"""
Cognito Authentication Service

Handles JWT token verification for API Gateway Cognito authorizer.
"""
import os
from typing import Optional
from fastapi import HTTPException, Request


def get_current_user(request: Request) -> dict:
    """
    Extract user information from API Gateway request context.

    When using JWT authorizer, API Gateway validates the token and adds
    the claims to the request context. We just need to extract them.
    """
    # API Gateway v2 (HTTP API) puts JWT claims in requestContext.authorizer.jwt.claims
    request_context = request.scope.get("aws.context", {})

    # For local testing / direct Lambda invocation
    if not request_context:
        # Check if running in Lambda with API Gateway event
        event = request.scope.get("aws.event", {})
        if event:
            authorizer = event.get("requestContext", {}).get("authorizer", {})
            jwt_claims = authorizer.get("jwt", {}).get("claims", {})

            if jwt_claims:
                return {
                    "sub": jwt_claims.get("sub"),
                    "email": jwt_claims.get("email"),
                    "name": jwt_claims.get("name"),
                    "cognito_username": jwt_claims.get("cognito:username")
                }

    # Fallback: Check request headers for testing
    # In production, this would be validated by API Gateway
    auth_header = request.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        # For local dev/testing only - API Gateway handles real validation
        # This is just to allow the endpoint to be called during development
        return {
            "sub": "test-user",
            "email": "test@example.com",
            "name": "Test User"
        }

    raise HTTPException(
        status_code=401,
        detail="Authentication required",
        headers={"WWW-Authenticate": "Bearer"}
    )
```

#### 5. Create S3 service

**File**: `backend/client_portal/app/services/s3.py`

```python
"""
S3 Service

Handles S3 operations for client albums including listing and presigned URL generation.
"""
import os
from datetime import datetime
from typing import Optional, Tuple, List
import boto3
from botocore.exceptions import ClientError

from ..routes.albums import Album


class S3Service:
    """Service for S3 album operations."""

    def __init__(self):
        self.bucket = os.environ.get("CLIENT_ALBUMS_BUCKET", "katelynns-photography-client-albums")
        self.region = os.environ.get("AWS_REGION_NAME", "us-east-2")
        self.presigned_expiry = int(os.environ.get("PRESIGNED_URL_EXPIRY", "3600"))
        self.s3_client = boto3.client("s3", region_name=self.region)

    def _get_user_prefix(self, user_email: str) -> str:
        """
        Get S3 prefix for user's albums.

        Structure: albums/{sanitized_email}/
        """
        # Sanitize email for use as S3 prefix
        safe_email = user_email.lower().replace("@", "_at_").replace(".", "_")
        return f"albums/{safe_email}/"

    def list_user_albums(self, user_email: str) -> List[Album]:
        """
        List all albums for a user.

        Albums are identified by "folders" (common prefixes) under the user's prefix.
        """
        prefix = self._get_user_prefix(user_email)
        albums = []

        try:
            # List "folders" (common prefixes) under user's directory
            paginator = self.s3_client.get_paginator("list_objects_v2")

            for page in paginator.paginate(Bucket=self.bucket, Prefix=prefix, Delimiter="/"):
                for common_prefix in page.get("CommonPrefixes", []):
                    album_prefix = common_prefix["Prefix"]
                    album_name = album_prefix.rstrip("/").split("/")[-1]

                    # Count photos in album
                    photo_count = self._count_objects(album_prefix)

                    # Get album creation date (earliest object)
                    created_at = self._get_album_created_date(album_prefix)

                    albums.append(Album(
                        id=album_name,
                        name=album_name.replace("-", " ").replace("_", " ").title(),
                        photo_count=photo_count,
                        created_at=created_at
                    ))

            return albums

        except ClientError as e:
            print(f"Error listing albums: {e}")
            raise

    def _count_objects(self, prefix: str) -> int:
        """Count objects under a prefix."""
        count = 0
        paginator = self.s3_client.get_paginator("list_objects_v2")

        for page in paginator.paginate(Bucket=self.bucket, Prefix=prefix):
            count += len([
                obj for obj in page.get("Contents", [])
                if not obj["Key"].endswith("/")  # Exclude "folder" markers
            ])

        return count

    def _get_album_created_date(self, prefix: str) -> Optional[str]:
        """Get the earliest LastModified date for objects in album."""
        try:
            response = self.s3_client.list_objects_v2(
                Bucket=self.bucket,
                Prefix=prefix,
                MaxKeys=1
            )

            contents = response.get("Contents", [])
            if contents:
                return contents[0]["LastModified"].isoformat()
            return None

        except ClientError:
            return None

    def get_album_details(self, user_email: str, album_id: str) -> Optional[Album]:
        """Get details for a specific album."""
        prefix = self._get_user_prefix(user_email)
        album_prefix = f"{prefix}{album_id}/"

        # Verify album exists
        response = self.s3_client.list_objects_v2(
            Bucket=self.bucket,
            Prefix=album_prefix,
            MaxKeys=1
        )

        if not response.get("Contents"):
            return None

        photo_count = self._count_objects(album_prefix)
        created_at = self._get_album_created_date(album_prefix)

        return Album(
            id=album_id,
            name=album_id.replace("-", " ").replace("_", " ").title(),
            photo_count=photo_count,
            created_at=created_at
        )

    def list_album_files(self, user_email: str, album_id: str) -> List[dict]:
        """List all files in an album with presigned URLs."""
        prefix = self._get_user_prefix(user_email)
        album_prefix = f"{prefix}{album_id}/"
        files = []

        paginator = self.s3_client.get_paginator("list_objects_v2")

        for page in paginator.paginate(Bucket=self.bucket, Prefix=album_prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                if key.endswith("/"):
                    continue  # Skip folder markers

                file_name = key.split("/")[-1]
                url = self.s3_client.generate_presigned_url(
                    "get_object",
                    Params={"Bucket": self.bucket, "Key": key},
                    ExpiresIn=self.presigned_expiry
                )

                files.append({
                    "name": file_name,
                    "size": obj["Size"],
                    "last_modified": obj["LastModified"].isoformat(),
                    "download_url": url
                })

        return files

    def generate_presigned_url(
        self,
        user_email: str,
        album_id: str,
        file_name: str
    ) -> Tuple[str, int]:
        """Generate presigned URL for a specific file."""
        prefix = self._get_user_prefix(user_email)
        key = f"{prefix}{album_id}/{file_name}"

        # Verify file exists
        try:
            self.s3_client.head_object(Bucket=self.bucket, Key=key)
        except ClientError as e:
            if e.response["Error"]["Code"] == "404":
                raise ValueError(f"File not found: {file_name}")
            raise

        url = self.s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": key},
            ExpiresIn=self.presigned_expiry
        )

        return url, self.presigned_expiry

    def generate_album_download_urls(
        self,
        user_email: str,
        album_id: str
    ) -> Tuple[str, int, int]:
        """
        Generate download access for all files in album.

        Returns the first file's URL as a starting point.
        For bulk downloads, the frontend should use list_album_files.
        """
        files = self.list_album_files(user_email, album_id)

        if not files:
            raise ValueError("Album is empty")

        # Return first file URL - frontend handles batch downloads
        return files[0]["download_url"], self.presigned_expiry, len(files)
```

#### 6. Create requirements.txt

**File**: `backend/client_portal/requirements.txt`

```
fastapi>=0.109.0
mangum>=0.17.0
pydantic>=2.0.0
boto3>=1.34.0
python-jose[cryptography]>=3.3.0
```

### Success Criteria:

#### Automated Verification:

- [x] Python syntax valid for all files
- [x] `pip install -r requirements.txt` succeeds
- [x] FastAPI app imports without errors: `python -c "from app.main import app"`

#### Manual Verification:

- [x] Deploy to Lambda
- [x] Test `/api/health` returns healthy status
- [x] Authenticated request to `/api/albums` returns user's albums
- [x] `/api/albums/{id}/files` returns list with presigned URLs
- [x] Presigned URLs work in browser (direct download)

**Implementation Note**: After completing this phase, pause for manual testing of the authenticated flow end-to-end.

---

## Phase 2.4: Admin API

### Overview

Implement admin-only API for creating albums and managing client access.

### Changes Required:

#### 1. Create admin API directory

```bash
mkdir -p backend/admin_api
```

#### 2. Create handler.py

**File**: `backend/admin_api/handler.py`

```python
"""
Admin API Handler

Admin-only operations for album management.
Requires admin Cognito group membership.
"""
import json
import os
import re
import boto3
from botocore.exceptions import ClientError

# Initialize AWS clients
s3_client = boto3.client("s3", region_name="us-east-2")
cognito_client = boto3.client("cognito-idp", region_name="us-east-2")

# Environment variables
CLIENT_ALBUMS_BUCKET = os.environ.get("CLIENT_ALBUMS_BUCKET", "katelynns-photography-client-albums")
COGNITO_USER_POOL_ID = os.environ.get("COGNITO_USER_POOL_ID")
ADMIN_EMAIL = os.environ.get("ADMIN_EMAIL")


def lambda_handler(event, context):
    """
    Handle admin API requests.

    Routes:
    - POST /admin/albums - Create new album for a client
    """
    http_method = event.get("requestContext", {}).get("http", {}).get("method", "")
    path = event.get("requestContext", {}).get("http", {}).get("path", "")

    # Verify admin access
    if not is_admin(event):
        return error_response(403, "Admin access required")

    # Route handling
    if http_method == "POST" and path == "/admin/albums":
        return create_album(event)

    return error_response(404, "Not found")


def is_admin(event) -> bool:
    """
    Check if the authenticated user is an admin.

    For simplicity, we check if the user's email matches ADMIN_EMAIL.
    In production, you might use Cognito groups.
    """
    authorizer = event.get("requestContext", {}).get("authorizer", {})
    claims = authorizer.get("jwt", {}).get("claims", {})

    user_email = claims.get("email", "").lower()

    # Check against admin email
    if ADMIN_EMAIL and user_email == ADMIN_EMAIL.lower():
        return True

    # Check for admin group (if using Cognito groups)
    groups = claims.get("cognito:groups", [])
    if isinstance(groups, str):
        groups = [groups]

    return "admin" in [g.lower() for g in groups]


def create_album(event):
    """
    Create a new album for a client.

    Request body:
    {
        "client_email": "client@example.com",
        "album_name": "Wedding Photos 2024",
        "create_user": true  // Optional: create Cognito user if not exists
    }

    This creates an S3 "folder" structure for the client and optionally
    creates their Cognito account.
    """
    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON body")

    client_email = body.get("client_email", "").strip().lower()
    album_name = body.get("album_name", "").strip()
    create_user = body.get("create_user", False)

    # Validation
    if not client_email or not is_valid_email(client_email):
        return error_response(400, "Valid client_email is required")

    if not album_name or len(album_name) < 2:
        return error_response(400, "album_name is required (min 2 characters)")

    # Sanitize album name for S3 key
    safe_album_name = sanitize_album_name(album_name)
    safe_email = client_email.replace("@", "_at_").replace(".", "_")

    # Create S3 "folder" structure
    album_prefix = f"albums/{safe_email}/{safe_album_name}/"

    try:
        # Create placeholder object to establish the "folder"
        s3_client.put_object(
            Bucket=CLIENT_ALBUMS_BUCKET,
            Key=f"{album_prefix}.keep",
            Body=b"",
            ContentType="application/octet-stream",
            Metadata={
                "album-name": album_name,
                "client-email": client_email
            }
        )
    except ClientError as e:
        print(f"S3 error creating album: {e}")
        return error_response(500, "Failed to create album in S3")

    # Optionally create Cognito user
    user_created = False
    temp_password = None

    if create_user and COGNITO_USER_POOL_ID:
        user_created, temp_password = create_cognito_user(client_email)

    return {
        "statusCode": 201,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        },
        "body": json.dumps({
            "success": True,
            "album": {
                "name": album_name,
                "id": safe_album_name,
                "client_email": client_email,
                "s3_prefix": album_prefix
            },
            "user_created": user_created,
            "message": f"Album '{album_name}' created for {client_email}"
                + (f". User invited with temporary password." if user_created else "")
        })
    }


def create_cognito_user(email: str) -> tuple[bool, str]:
    """
    Create a Cognito user for the client.

    Returns (created: bool, temp_password: str or None)
    """
    try:
        # Check if user already exists
        try:
            cognito_client.admin_get_user(
                UserPoolId=COGNITO_USER_POOL_ID,
                Username=email
            )
            # User exists
            return False, None
        except cognito_client.exceptions.UserNotFoundException:
            pass  # User doesn't exist, create them

        # Create user with temporary password
        cognito_client.admin_create_user(
            UserPoolId=COGNITO_USER_POOL_ID,
            Username=email,
            UserAttributes=[
                {"Name": "email", "Value": email},
                {"Name": "email_verified", "Value": "true"}
            ],
            DesiredDeliveryMediums=["EMAIL"]
        )

        return True, None  # Password sent via email by Cognito

    except ClientError as e:
        print(f"Cognito error creating user: {e}")
        return False, None


def sanitize_album_name(name: str) -> str:
    """Sanitize album name for use as S3 key."""
    # Replace spaces and special chars with hyphens
    safe = re.sub(r"[^a-zA-Z0-9\-_]", "-", name.lower())
    # Collapse multiple hyphens
    safe = re.sub(r"-+", "-", safe)
    # Remove leading/trailing hyphens
    return safe.strip("-")[:100]


def is_valid_email(email: str) -> bool:
    """Basic email validation."""
    pattern = r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    return bool(re.match(pattern, email))


def error_response(status_code: int, message: str):
    """Generate error response."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        },
        "body": json.dumps({
            "success": False,
            "error": message
        })
    }
```

#### 3. Create requirements.txt

**File**: `backend/admin_api/requirements.txt`

```
boto3>=1.34.0
```

### Success Criteria:

#### Automated Verification:

- [x] Python syntax valid: `python -m py_compile backend/admin_api/handler.py`
- [x] No import errors

#### Manual Verification:

- [x] Deploy to Lambda
- [x] Non-admin user gets 403 Forbidden
- [x] Admin can create album successfully
- [x] Album S3 prefix created with .keep file
- [ ] Cognito user created when `create_user: true` (not tested - user already existed)

---

## Phase 2.5: Deployment Script

### Overview

Create deployment script to package and deploy Lambda functions.

### Changes Required:

#### 1. Create deploy script

**File**: `scripts/deploy_lambda.sh`

```bash
#!/bin/bash
# Deploy Lambda functions for Katelynn's Photography
# Usage: ./scripts/deploy_lambda.sh [function_name]
# If no function name provided, deploys all functions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_ROOT/backend"
BUILD_DIR="$PROJECT_ROOT/.build"

AWS_PROFILE="${AWS_PROFILE:-jw-dev}"
AWS_REGION="${AWS_REGION:-us-east-2}"

# Function names (must match Terraform)
FUNCTIONS=(
    "katelynns-photography-contact-form:contact_form"
    "katelynns-photography-client-portal:client_portal"
    "katelynns-photography-admin-api:admin_api"
)

echo "AWS Profile: $AWS_PROFILE"
echo "AWS Region: $AWS_REGION"
echo ""

deploy_function() {
    local lambda_name=$1
    local source_dir=$2
    local zip_file="$BUILD_DIR/${source_dir}.zip"

    echo "=========================================="
    echo "Deploying: $lambda_name"
    echo "Source: $BACKEND_DIR/$source_dir"
    echo "=========================================="

    # Clean and create build directory
    rm -rf "$BUILD_DIR/$source_dir"
    mkdir -p "$BUILD_DIR/$source_dir"

    # Copy source files
    cp -r "$BACKEND_DIR/$source_dir/"* "$BUILD_DIR/$source_dir/"

    # Install dependencies
    if [ -f "$BUILD_DIR/$source_dir/requirements.txt" ]; then
        echo "Installing dependencies..."
        pip install -r "$BUILD_DIR/$source_dir/requirements.txt" \
            -t "$BUILD_DIR/$source_dir/" \
            --platform manylinux2014_x86_64 \
            --only-binary=:all: \
            --upgrade \
            --quiet
    fi

    # Create zip
    echo "Creating deployment package..."
    cd "$BUILD_DIR/$source_dir"
    rm -f "$zip_file"
    zip -r "$zip_file" . -x "*.pyc" -x "__pycache__/*" -x "*.dist-info/*" > /dev/null
    cd "$PROJECT_ROOT"

    # Get zip size
    local size=$(du -h "$zip_file" | cut -f1)
    echo "Package size: $size"

    # Deploy to Lambda
    echo "Updating Lambda function..."
    aws lambda update-function-code \
        --function-name "$lambda_name" \
        --zip-file "fileb://$zip_file" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --output text \
        --query 'FunctionArn'

    echo "Deployed successfully!"
    echo ""
}

# Main
mkdir -p "$BUILD_DIR"

if [ -n "$1" ]; then
    # Deploy single function
    for func in "${FUNCTIONS[@]}"; do
        lambda_name="${func%%:*}"
        source_dir="${func##*:}"
        if [ "$source_dir" == "$1" ] || [ "$lambda_name" == "$1" ]; then
            deploy_function "$lambda_name" "$source_dir"
            exit 0
        fi
    done
    echo "Unknown function: $1"
    echo "Available functions:"
    for func in "${FUNCTIONS[@]}"; do
        echo "  - ${func##*:}"
    done
    exit 1
else
    # Deploy all functions
    for func in "${FUNCTIONS[@]}"; do
        lambda_name="${func%%:*}"
        source_dir="${func##*:}"
        deploy_function "$lambda_name" "$source_dir"
    done
fi

echo "=========================================="
echo "All deployments complete!"
echo "=========================================="
```

#### 2. Make executable

```bash
chmod +x scripts/deploy_lambda.sh
```

### Success Criteria:

#### Automated Verification:

- [x] Script is executable
- [x] Script syntax is valid: `bash -n scripts/deploy_lambda.sh`

#### Manual Verification:

- [x] `./scripts/deploy_lambda.sh contact_form` deploys successfully
- [x] `./scripts/deploy_lambda.sh` deploys all functions
- [x] Lambda code updated in AWS Console

---

## Phase 2.6: Integration Testing

### Overview

End-to-end testing of all backend functionality.

### Test Scenarios:

#### 1. Contact Form Testing

```bash
# Test valid submission
curl -X POST https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com/contact \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test User",
    "email": "test@example.com",
    "message": "This is a test inquiry from API testing.",
    "inquiry_type": "portrait"
  }'

# Test validation errors
curl -X POST https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com/contact \
  -H "Content-Type: application/json" \
  -d '{"name": "A"}'
```

#### 2. Client Portal Testing

```bash
# Get Cognito token (manual step - use AWS Console or CLI)
# aws cognito-idp admin-initiate-auth ...

# Test albums endpoint
curl -X GET https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com/api/albums \
  -H "Authorization: Bearer $COGNITO_TOKEN"

# Test health endpoint (no auth required for health)
curl https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com/api/health
```

#### 3. Admin API Testing

```bash
# Create album (requires admin Cognito token)
curl -X POST https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com/admin/albums \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "client_email": "client@example.com",
    "album_name": "Wedding Photos 2024",
    "create_user": true
  }'
```

### Success Criteria:

#### Manual Verification:

- [ ] Contact form submission sends email to admin (SES sandbox - requires verified email)
- [x] Authenticated user can list their albums
- [x] Presigned URLs allow file download
- [x] Admin can create new albums
- [ ] New client receives Cognito invitation email (not tested)
- [x] Non-admin users cannot access admin endpoints
- [x] Invalid tokens return 401 Unauthorized
- [x] All error responses include helpful messages

---

## Testing Strategy

### Unit Tests (Future Enhancement)

For each Lambda function:

- Mock boto3 clients
- Test validation logic
- Test error handling
- Test response formatting

### Integration Tests

See Phase 2.6 for curl-based integration testing.

### Manual Testing Checklist

1. **Contact Form Flow**:
   - [ ] Submit with valid data → email received
   - [ ] Submit with invalid email → 400 error
   - [ ] Submit with missing required fields → 400 error with field list

2. **Client Portal Flow**:
   - [ ] Create test user in Cognito (admin console)
   - [ ] Upload test photos to their S3 prefix
   - [ ] Login and get token
   - [ ] List albums → sees their album
   - [ ] Get album files → sees files with download URLs
   - [ ] Download file via presigned URL → file downloads

3. **Admin Flow**:
   - [ ] Create album for new client with `create_user: true`
   - [ ] Client receives Cognito invitation email
   - [ ] Client can login and see their album

---

## Performance Considerations

- **Lambda Cold Starts**: First invocation may take 1-2 seconds. FastAPI app is larger (~256MB memory allocation helps).
- **S3 Listing**: Pagination handles large albums. Consider caching if performance issues arise.
- **Presigned URL Expiry**: 1 hour default. Adjust via environment variable if needed.

---

## Security Notes

- **Input Validation**: All user input is sanitized before use in S3 keys or emails.
- **Cognito JWT**: API Gateway validates tokens before Lambda invocation.
- **Presigned URLs**: Time-limited (1 hour), specific to authenticated user's albums.
- **Admin Check**: Based on email match or Cognito group membership.
- **S3 Bucket Policy**: Only Lambda role can access client albums bucket.

---

## Rollback Plan

If issues arise:

1. Lambda functions can be rolled back via AWS Console (versions)
2. Terraform can destroy/recreate resources: `terraform destroy -target=aws_lambda_function.contact_form`
3. API Gateway routes can be disabled individually

---

## References

- Master plan: `thoughts/shared/plans/2026-01-08-build-website-master-plan.md`
- Phase 1 plan: `thoughts/shared/plans/2026-01-08-phase1-terraform-infrastructure.md`
- Phase 1 outputs:
  - API Gateway: `https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com`
  - Cognito User Pool: `us-east-2_bn71poxi6`
  - Client ID: `6a5h8p858dg9laj544ijvu9gro`
  - S3 Buckets: `katelynns-photography-*`
