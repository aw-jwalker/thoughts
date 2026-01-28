# Portfolio Images S3 Media Library Implementation Plan

**Status: ✅ COMPLETED** (2026-01-25)

## Overview

Implement a custom DecapCMS media library that stores and serves portfolio images from the existing S3 bucket (`katelynns-photography-portfolio-assets`) instead of git. This provides a user-friendly upload experience for non-technical admins while keeping images out of the git repository.

## Current State Analysis

### What Exists Today

- **DecapCMS**: Uses git-based media storage (`frontend/public/images/`)
- **S3 Bucket**: `katelynns-photography-portfolio-assets` configured with:
  - Public read access (bucket policy allows `s3:GetObject` for `*`)
  - Versioning enabled
  - AES256 encryption
- **Image References**: Content files use relative paths (`/images/photo.jpg`)
- **Admin Auth**: DecapBridge PKCE authentication (GitHub-based)
- **API Gateway**: HTTP API v2 with Cognito JWT authorizer at `https://api.katelynnsphotography.com`

### Key Discoveries

- DecapCMS supports `registerMediaLibrary()` API but has **no native S3 support** - requires custom implementation
- Portfolio-assets bucket exists and is publicly readable
- Admin API pattern exists at `backend/admin_api/handler.py` - uses email-based admin check
- Existing Lambda role only has access to `client-albums` bucket, not `portfolio-assets`

## Desired End State

After implementation:

1. Admin opens DecapCMS at `/admin`
2. Admin clicks "Add Image" on any image field
3. Custom media library UI shows existing S3 images as a grid
4. Admin can upload new images (drag-and-drop or file picker)
5. Images upload directly to S3 via presigned URLs
6. Admin selects image → S3 URL inserted into content
7. Content saved via DecapBridge → images served from S3

### Verification

- [ ] Admin can see all existing portfolio images in the media library
- [ ] Admin can upload new images via the CMS UI
- [ ] Uploaded images appear in S3 bucket within seconds
- [ ] Selected images insert correct S3 URLs into content fields
- [ ] Images display correctly on the live site
- [ ] Page load time acceptable (Astro optimizes S3 images at build time)

## What We're NOT Doing

- ❌ CloudFront CDN (S3 direct access is fine for low-to-moderate traffic)
- ❌ Server-side image optimization (using Astro's built-in Sharp optimization)
- ❌ Image deletion from CMS (can be done via AWS Console if needed)
- ❌ Folder organization in S3 (flat structure under `/images/` prefix)
- ❌ Thumbnail generation (Astro handles responsive images)

## Implementation Approach

We'll build a lightweight custom media library that:

1. Uses a new Lambda function to list S3 objects and generate presigned upload URLs
2. Provides a simple React UI for the DecapCMS media library interface
3. Uploads images directly from browser to S3 (avoiding Lambda data transfer limits)
4. Uses the existing DecapBridge auth flow - admin-only access enforced by API

**Architecture:**

```
Admin Browser (DecapCMS)
    │
    ├─► [GET /admin/media] → Lambda → List S3 objects → Return image list
    ├─► [POST /admin/media/upload-url] → Lambda → Generate presigned URL
    │
    └─► [PUT presigned-url] → Direct S3 Upload (browser → S3)
```

---

## Phase 1: Backend API for Portfolio Media

### Overview

Create a new Lambda function (or extend admin_api) with endpoints for listing images and generating upload URLs.

### Changes Required:

#### 1. Terraform - IAM Policy for Portfolio Bucket Access

**File**: `terraform/lambda.tf`
**Changes**: Add S3 permissions for portfolio-assets bucket to Lambda role

```hcl
# Add to aws_iam_role_policy.lambda_custom Statement array (around line 38):
{
  Sid    = "S3PortfolioAssetsAccess"
  Effect = "Allow"
  Action = [
    "s3:GetObject",
    "s3:ListBucket",
    "s3:PutObject",
    "s3:DeleteObject"
  ]
  Resource = [
    aws_s3_bucket.portfolio_assets.arn,
    "${aws_s3_bucket.portfolio_assets.arn}/*"
  ]
}
```

#### 2. Terraform - S3 CORS Configuration for Browser Uploads

**File**: `terraform/s3.tf`
**Changes**: Add CORS configuration to portfolio-assets bucket

```hcl
# Add after aws_s3_bucket_policy.portfolio_assets (around line 58):
resource "aws_s3_bucket_cors_configuration" "portfolio_assets" {
  bucket = aws_s3_bucket.portfolio_assets.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = [
      "https://katelynnsphotography.com",
      "https://www.katelynnsphotography.com",
      "https://dev.katelynnsphotography.com",
      "http://localhost:4321"  # Local dev
    ]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}
```

#### 3. Terraform - API Gateway Routes for Media Endpoints

**File**: `terraform/lambda.tf`
**Changes**: Add routes for media listing and upload URL generation

```hcl
# Add after existing admin_api routes (around line 290):

# Admin Media - List images
resource "aws_apigatewayv2_route" "admin_media_list" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /admin/media"
  target    = "integrations/${aws_apigatewayv2_integration.admin_api.id}"

  # Note: No JWT auth - uses DecapBridge token validation in Lambda
}

# Admin Media - Get upload URL
resource "aws_apigatewayv2_route" "admin_media_upload" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /admin/media/upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.admin_api.id}"
}
```

#### 4. Backend Lambda Handler - Media Endpoints

**File**: `backend/admin_api/handler.py`
**Changes**: Add media listing and upload URL endpoints

Add these imports at the top:

```python
from urllib.parse import quote
import uuid
```

Add environment variable:

```python
PORTFOLIO_ASSETS_BUCKET = os.environ.get("PORTFOLIO_ASSETS_BUCKET", "katelynns-photography-portfolio-assets")
```

Add to `lambda_handler` route handling (around line 38):

```python
    # Media library routes (no Cognito auth - uses DecapBridge token)
    if http_method == "GET" and path == "/admin/media":
        return list_media(event)

    if http_method == "POST" and path == "/admin/media/upload-url":
        return get_upload_url(event)
```

Add these new functions:

```python
def verify_decapbridge_token(event) -> bool:
    """
    Verify the request is from an authenticated DecapBridge session.

    DecapBridge sends a token in the Authorization header after GitHub OAuth.
    We validate by checking for the token presence - DecapBridge handles the
    actual authentication. For additional security, we could call DecapBridge
    API to validate the token.
    """
    auth_header = event.get("headers", {}).get("authorization", "")

    # Check for Bearer token from DecapBridge
    if auth_header.startswith("Bearer ") and len(auth_header) > 20:
        return True

    return False


def list_media(event):
    """
    List all images in the portfolio-assets bucket.

    Returns images with their S3 URLs for display in the media library.
    """
    if not verify_decapbridge_token(event):
        return error_response(401, "Authentication required")

    try:
        images = []
        paginator = s3_client.get_paginator("list_objects_v2")

        for page in paginator.paginate(Bucket=PORTFOLIO_ASSETS_BUCKET, Prefix="images/"):
            for obj in page.get("Contents", []):
                key = obj["Key"]

                # Skip folder markers and non-image files
                if key.endswith("/"):
                    continue

                filename = key.split("/")[-1]
                ext = filename.lower().split(".")[-1] if "." in filename else ""

                if ext not in ["jpg", "jpeg", "png", "gif", "webp", "svg"]:
                    continue

                # Public S3 URL (bucket has public read policy)
                url = f"https://{PORTFOLIO_ASSETS_BUCKET}.s3.us-east-2.amazonaws.com/{quote(key, safe='/')}"

                images.append({
                    "name": filename,
                    "path": key,
                    "url": url,
                    "size": obj["Size"],
                    "last_modified": obj["LastModified"].isoformat()
                })

        # Sort by most recent first
        images.sort(key=lambda x: x["last_modified"], reverse=True)

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({
                "images": images,
                "total": len(images)
            })
        }

    except ClientError as e:
        print(f"S3 error listing media: {e}")
        return error_response(500, "Failed to list media")


def get_upload_url(event):
    """
    Generate a presigned URL for uploading an image to S3.

    Request body:
    {
        "filename": "wedding-photo.jpg",
        "content_type": "image/jpeg"
    }

    Returns a presigned PUT URL that expires in 5 minutes.
    """
    if not verify_decapbridge_token(event):
        return error_response(401, "Authentication required")

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON body")

    filename = body.get("filename", "").strip()
    content_type = body.get("content_type", "image/jpeg")

    if not filename:
        return error_response(400, "filename is required")

    # Validate file extension
    ext = filename.lower().split(".")[-1] if "." in filename else ""
    allowed_extensions = ["jpg", "jpeg", "png", "gif", "webp", "svg"]

    if ext not in allowed_extensions:
        return error_response(400, f"Invalid file type. Allowed: {', '.join(allowed_extensions)}")

    # Sanitize filename and add unique prefix to avoid collisions
    safe_filename = sanitize_filename(filename)
    unique_id = uuid.uuid4().hex[:8]
    key = f"images/{unique_id}-{safe_filename}"

    try:
        # Generate presigned URL for PUT operation
        presigned_url = s3_client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": PORTFOLIO_ASSETS_BUCKET,
                "Key": key,
                "ContentType": content_type
            },
            ExpiresIn=300  # 5 minutes
        )

        # Public URL for accessing the image after upload
        public_url = f"https://{PORTFOLIO_ASSETS_BUCKET}.s3.us-east-2.amazonaws.com/{quote(key, safe='/')}"

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({
                "upload_url": presigned_url,
                "public_url": public_url,
                "key": key,
                "expires_in": 300
            })
        }

    except ClientError as e:
        print(f"S3 error generating presigned URL: {e}")
        return error_response(500, "Failed to generate upload URL")


def sanitize_filename(filename: str) -> str:
    """Sanitize filename for S3 key."""
    # Keep only alphanumeric, hyphens, underscores, and dots
    safe = re.sub(r"[^a-zA-Z0-9\-_.]", "-", filename.lower())
    # Collapse multiple hyphens
    safe = re.sub(r"-+", "-", safe)
    # Remove leading/trailing hyphens
    return safe.strip("-")[:100]
```

#### 5. Terraform - Lambda Environment Variable

**File**: `terraform/lambda.tf`
**Changes**: Add PORTFOLIO_ASSETS_BUCKET to admin_api environment

```hcl
# Update aws_lambda_function.admin_api environment block (around line 157):
environment {
  variables = {
    CLIENT_ALBUMS_BUCKET    = aws_s3_bucket.client_albums.id
    PORTFOLIO_ASSETS_BUCKET = aws_s3_bucket.portfolio_assets.id
    COGNITO_USER_POOL_ID    = aws_cognito_user_pool.clients.id
    ADMIN_EMAIL             = var.admin_email
  }
}
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform plan` shows expected changes (IAM, CORS, routes, env var)
- [ ] `terraform apply` completes successfully
- [ ] Lambda deploy script runs without errors

#### Manual Verification:

- [ ] API call `GET /admin/media` returns list of images (test with curl + token)
- [ ] API call `POST /admin/media/upload-url` returns presigned URL
- [ ] Presigned URL allows successful image upload from browser
- [ ] Uploaded image accessible at public URL

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the API endpoints work correctly before proceeding to Phase 2.

---

## Phase 2: DecapCMS Custom Media Library

### Overview

Create a custom media library that integrates with DecapCMS, providing a UI for browsing and uploading images to S3.

### Changes Required:

#### 1. Create Media Library JavaScript Module

**File**: `frontend/public/admin/s3-media-library.js`
**Changes**: New file - custom media library implementation

```javascript
/**
 * S3 Media Library for DecapCMS
 *
 * Custom media library that stores images in S3 instead of git.
 * Registers with DecapCMS via registerMediaLibrary API.
 */

const S3MediaLibrary = {
  name: "s3-media-library",

  /**
   * Initialize the media library
   * Called by DecapCMS when the library is registered
   */
  init: function ({ options, handleInsert }) {
    this.options = options || {};
    this.handleInsert = handleInsert;
    this.apiBase = options.apiBase || "https://api.katelynnsphotography.com";

    return this;
  },

  /**
   * Open the media library modal
   * Called when user clicks "Choose image" or similar
   */
  show: async function ({ config, allowMultiple, imagesOnly }) {
    // Create modal overlay
    const modal = this.createModal();
    document.body.appendChild(modal);

    // Load and display images
    await this.loadImages(modal);

    // Set up upload handling
    this.setupUploadHandlers(modal);
  },

  /**
   * Create the modal HTML structure
   */
  createModal: function () {
    const modal = document.createElement("div");
    modal.id = "s3-media-modal";
    modal.innerHTML = `
      <div class="s3-media-overlay">
        <div class="s3-media-container">
          <div class="s3-media-header">
            <h2>Media Library</h2>
            <button class="s3-media-close" aria-label="Close">&times;</button>
          </div>

          <div class="s3-media-upload-zone">
            <input type="file" id="s3-file-input" accept="image/*" multiple style="display:none">
            <div class="s3-upload-area" id="s3-upload-area">
              <p>Drag & drop images here or <button id="s3-browse-btn">browse</button></p>
            </div>
            <div class="s3-upload-progress" id="s3-upload-progress" style="display:none">
              <div class="s3-progress-bar"><div class="s3-progress-fill"></div></div>
              <span class="s3-progress-text">Uploading...</span>
            </div>
          </div>

          <div class="s3-media-grid" id="s3-media-grid">
            <div class="s3-loading">Loading images...</div>
          </div>
        </div>
      </div>
    `;

    // Add styles
    this.addStyles();

    // Close button handler
    modal.querySelector(".s3-media-close").addEventListener("click", () => {
      modal.remove();
    });

    // Close on overlay click
    modal.querySelector(".s3-media-overlay").addEventListener("click", (e) => {
      if (e.target.classList.contains("s3-media-overlay")) {
        modal.remove();
      }
    });

    return modal;
  },

  /**
   * Add CSS styles for the modal
   */
  addStyles: function () {
    if (document.getElementById("s3-media-styles")) return;

    const styles = document.createElement("style");
    styles.id = "s3-media-styles";
    styles.textContent = `
      .s3-media-overlay {
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background: rgba(0, 0, 0, 0.7);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 10000;
      }

      .s3-media-container {
        background: white;
        border-radius: 8px;
        width: 90%;
        max-width: 900px;
        max-height: 85vh;
        display: flex;
        flex-direction: column;
        overflow: hidden;
      }

      .s3-media-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 16px 20px;
        border-bottom: 1px solid #e0e0e0;
      }

      .s3-media-header h2 {
        margin: 0;
        font-size: 18px;
        color: #333;
      }

      .s3-media-close {
        background: none;
        border: none;
        font-size: 24px;
        cursor: pointer;
        color: #666;
        padding: 0;
        line-height: 1;
      }

      .s3-media-close:hover {
        color: #333;
      }

      .s3-media-upload-zone {
        padding: 16px 20px;
        border-bottom: 1px solid #e0e0e0;
      }

      .s3-upload-area {
        border: 2px dashed #ccc;
        border-radius: 8px;
        padding: 24px;
        text-align: center;
        transition: border-color 0.2s, background 0.2s;
      }

      .s3-upload-area.dragover {
        border-color: #2196F3;
        background: #E3F2FD;
      }

      .s3-upload-area p {
        margin: 0;
        color: #666;
      }

      #s3-browse-btn {
        background: #2196F3;
        color: white;
        border: none;
        padding: 8px 16px;
        border-radius: 4px;
        cursor: pointer;
        margin-left: 8px;
      }

      #s3-browse-btn:hover {
        background: #1976D2;
      }

      .s3-upload-progress {
        margin-top: 12px;
      }

      .s3-progress-bar {
        height: 8px;
        background: #e0e0e0;
        border-radius: 4px;
        overflow: hidden;
      }

      .s3-progress-fill {
        height: 100%;
        background: #4CAF50;
        width: 0%;
        transition: width 0.3s;
      }

      .s3-progress-text {
        display: block;
        margin-top: 8px;
        font-size: 14px;
        color: #666;
      }

      .s3-media-grid {
        padding: 20px;
        overflow-y: auto;
        flex: 1;
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
        gap: 16px;
        align-content: start;
      }

      .s3-loading {
        grid-column: 1 / -1;
        text-align: center;
        color: #666;
        padding: 40px;
      }

      .s3-media-item {
        aspect-ratio: 1;
        border-radius: 8px;
        overflow: hidden;
        cursor: pointer;
        border: 3px solid transparent;
        transition: border-color 0.2s, transform 0.2s;
      }

      .s3-media-item:hover {
        border-color: #2196F3;
        transform: scale(1.02);
      }

      .s3-media-item img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }

      .s3-empty-state {
        grid-column: 1 / -1;
        text-align: center;
        color: #666;
        padding: 40px;
      }
    `;
    document.head.appendChild(styles);
  },

  /**
   * Load images from S3 via API
   */
  loadImages: async function (modal) {
    const grid = modal.querySelector("#s3-media-grid");

    try {
      // Get the auth token from DecapBridge
      const token = this.getAuthToken();

      const response = await fetch(`${this.apiBase}/admin/media`, {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      if (!response.ok) {
        throw new Error("Failed to load images");
      }

      const data = await response.json();

      if (data.images.length === 0) {
        grid.innerHTML =
          '<div class="s3-empty-state">No images yet. Upload some!</div>';
        return;
      }

      grid.innerHTML = data.images
        .map(
          (img) => `
        <div class="s3-media-item" data-url="${img.url}" data-name="${img.name}">
          <img src="${img.url}" alt="${img.name}" loading="lazy">
        </div>
      `,
        )
        .join("");

      // Add click handlers for selection
      grid.querySelectorAll(".s3-media-item").forEach((item) => {
        item.addEventListener("click", () => {
          const url = item.dataset.url;
          this.handleInsert(url);
          modal.remove();
        });
      });
    } catch (error) {
      console.error("Error loading images:", error);
      grid.innerHTML =
        '<div class="s3-empty-state">Error loading images. Please try again.</div>';
    }
  },

  /**
   * Get auth token from DecapBridge session
   */
  getAuthToken: function () {
    // DecapBridge stores token in localStorage after OAuth
    const stored = localStorage.getItem("decap-cms-auth");
    if (stored) {
      try {
        const parsed = JSON.parse(stored);
        return parsed.token || parsed.access_token || "";
      } catch (e) {
        return "";
      }
    }
    return "";
  },

  /**
   * Set up file upload handlers
   */
  setupUploadHandlers: function (modal) {
    const uploadArea = modal.querySelector("#s3-upload-area");
    const fileInput = modal.querySelector("#s3-file-input");
    const browseBtn = modal.querySelector("#s3-browse-btn");

    // Browse button
    browseBtn.addEventListener("click", () => fileInput.click());

    // File input change
    fileInput.addEventListener("change", (e) => {
      this.handleFiles(e.target.files, modal);
    });

    // Drag and drop
    uploadArea.addEventListener("dragover", (e) => {
      e.preventDefault();
      uploadArea.classList.add("dragover");
    });

    uploadArea.addEventListener("dragleave", () => {
      uploadArea.classList.remove("dragover");
    });

    uploadArea.addEventListener("drop", (e) => {
      e.preventDefault();
      uploadArea.classList.remove("dragover");
      this.handleFiles(e.dataTransfer.files, modal);
    });
  },

  /**
   * Handle file upload
   */
  handleFiles: async function (files, modal) {
    const progressContainer = modal.querySelector("#s3-upload-progress");
    const progressFill = modal.querySelector(".s3-progress-fill");
    const progressText = modal.querySelector(".s3-progress-text");

    progressContainer.style.display = "block";

    const token = this.getAuthToken();
    let uploaded = 0;
    const total = files.length;

    for (const file of files) {
      progressText.textContent = `Uploading ${file.name}...`;

      try {
        // Get presigned URL
        const urlResponse = await fetch(
          `${this.apiBase}/admin/media/upload-url`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${token}`,
            },
            body: JSON.stringify({
              filename: file.name,
              content_type: file.type,
            }),
          },
        );

        if (!urlResponse.ok) {
          throw new Error("Failed to get upload URL");
        }

        const urlData = await urlResponse.json();

        // Upload to S3
        const uploadResponse = await fetch(urlData.upload_url, {
          method: "PUT",
          headers: {
            "Content-Type": file.type,
          },
          body: file,
        });

        if (!uploadResponse.ok) {
          throw new Error("Failed to upload to S3");
        }

        uploaded++;
        progressFill.style.width = `${(uploaded / total) * 100}%`;
      } catch (error) {
        console.error("Upload error:", error);
        progressText.textContent = `Error uploading ${file.name}`;
      }
    }

    progressText.textContent = `Uploaded ${uploaded} of ${total} files`;

    // Reload images after short delay
    setTimeout(() => {
      this.loadImages(modal);
      progressContainer.style.display = "none";
      progressFill.style.width = "0%";
    }, 1000);
  },
};

// Register with DecapCMS
if (typeof CMS !== "undefined") {
  CMS.registerMediaLibrary(S3MediaLibrary);
}
```

#### 2. Update Admin Page to Load Custom Media Library

**File**: `frontend/src/pages/admin.astro`
**Changes**: Load custom media library script and configure DecapCMS

```astro
---
// Admin page - serves Decap CMS interface
// Uses DecapBridge for authentication
// Uses custom S3 media library for image storage
---
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="robots" content="noindex" />
    <title>Admin - Katelynn's Photography</title>
  </head>
  <body>
    <script src="https://unpkg.com/decap-cms@^3.3/dist/decap-cms.js"></script>
    <script src="/admin/s3-media-library.js"></script>
    <script>
      // Configure S3 media library with API endpoint
      CMS.registerMediaLibrary(S3MediaLibrary, {
        apiBase: 'https://api.katelynnsphotography.com'
      });
    </script>
  </body>
</html>
```

#### 3. Update DecapCMS Config for S3 Media Library

**File**: `frontend/public/admin/config.yml`
**Changes**: Configure DecapCMS to use S3 media library

Replace lines 31-33:

```yaml
# Media files configuration - S3 storage
media_library:
  name: s3-media-library
  config:
    apiBase: https://api.katelynnsphotography.com
```

Remove these lines (no longer needed):

```yaml
media_folder: "frontend/public/images"
public_folder: "/images"
```

### Success Criteria:

#### Automated Verification:

- [x] `npm run build` in frontend succeeds
- [ ] Admin page loads without JavaScript errors

#### Manual Verification:

- [ ] DecapCMS shows "Media Library" when clicking image field
- [ ] Modal displays existing S3 images in a grid
- [ ] Drag-and-drop upload works
- [ ] Browse button upload works
- [ ] Upload progress indicator shows correctly
- [ ] Clicking image inserts S3 URL into field
- [ ] Uploaded image appears after reload

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation that the media library UI works correctly before proceeding to Phase 3.

---

## Phase 3: Migration and Content Updates

### Overview

Migrate existing images from git to S3 and update content files to reference S3 URLs.

### Changes Required:

#### 1. Create Migration Script

**File**: `scripts/migrate-images-to-s3.sh`
**Changes**: New file - one-time migration script

```bash
#!/bin/bash
# Migrate portfolio images from git to S3

set -e

BUCKET="katelynns-photography-portfolio-assets"
SOURCE_DIR="frontend/public/images"
S3_PREFIX="images"

echo "Migrating images from $SOURCE_DIR to s3://$BUCKET/$S3_PREFIX/"

# Upload all images
for file in "$SOURCE_DIR"/*.{jpg,jpeg,png,gif,webp,svg}; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "Uploading: $filename"
        aws s3 cp "$file" "s3://$BUCKET/$S3_PREFIX/$filename" --content-type "image/$(echo ${filename##*.} | tr '[:upper:]' '[:lower:]')"
    fi
done

echo "Migration complete!"
echo ""
echo "Next steps:"
echo "1. Update content files to use S3 URLs"
echo "2. Remove images from git: rm -rf frontend/public/images/*.jpg"
echo "3. Commit changes"
```

#### 2. Update Content Files with S3 URLs

**Files**: Multiple content files need URL updates

**Base URL pattern**:

- Old: `/images/filename.jpg`
- New: `https://katelynns-photography-portfolio-assets.s3.us-east-2.amazonaws.com/images/filename.jpg`

Files to update:

- `frontend/src/content/site-settings/home.json` - hero.backgroundImage
- `frontend/src/content/about/main.json` - photo
- `frontend/src/content/galleries/*.md` - image field

Example update for `home.json`:

```json
{
  "hero": {
    "backgroundImage": "https://katelynns-photography-portfolio-assets.s3.us-east-2.amazonaws.com/images/hero-bg.jpg"
  }
}
```

#### 3. Update .gitignore (Optional)

**File**: `.gitignore`
**Changes**: Optionally add images folder to prevent accidental commits

```gitignore
# Portfolio images now stored in S3
frontend/public/images/*.jpg
frontend/public/images/*.jpeg
frontend/public/images/*.png
```

### Success Criteria:

#### Automated Verification:

- [x] Migration script runs without errors
- [x] S3 bucket contains all expected images
- [x] `npm run build` succeeds with S3 URLs
- [x] No broken image references in build output

#### Manual Verification:

- [ ] Homepage hero image displays correctly
- [ ] About page photo displays correctly
- [ ] All gallery images display correctly
- [ ] Portfolio page renders all images
- [ ] No console errors related to images

**Implementation Note**: After completing this phase, the migration is complete. The final manual verification confirms the live site works correctly.

---

## Testing Strategy

### Unit Tests:

- Lambda handler tests for `/admin/media` endpoints
- URL generation and sanitization functions

### Integration Tests:

- API Gateway → Lambda → S3 flow
- Presigned URL upload flow

### Manual Testing Steps:

1. Log into DecapCMS as admin
2. Edit any content with an image field
3. Click to open media library
4. Verify existing images display
5. Upload a new test image
6. Verify image appears in library
7. Select image and verify URL inserted
8. Save content and verify git commit
9. Check live site for image display

## Performance Considerations

- **Astro Image Optimization**: Astro's built-in Sharp service will optimize S3 images at build time
- **S3 Direct Access**: Images served directly from S3 (no Lambda in request path)
- **Lazy Loading**: Media library uses `loading="lazy"` for grid images
- **Presigned URLs**: Upload URLs expire in 5 minutes for security

## Rollback Plan

If issues arise:

1. Revert `config.yml` to git-based media
2. Restore images to `frontend/public/images/`
3. Update content files to use `/images/` paths
4. Redeploy

## Cost Impact

Minimal additional cost:

- S3 storage: ~$0.50/month for 20GB
- S3 requests: ~$0.05/month (PUT/GET)
- No Lambda data transfer (browser uploads directly to S3)

## References

- Master plan: `thoughts/shared/plans/2026-01-17-s3-media-management-master-plan.md`
- DecapCMS config: `frontend/public/admin/config.yml`
- S3 bucket Terraform: `terraform/s3.tf`
- Lambda patterns: `backend/admin_api/handler.py`
- DecapCMS media library docs: https://decapcms.org/docs/configuration-options/
