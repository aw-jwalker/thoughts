# Media Library Folder Support Implementation Plan

**GitHub Issue:** #5 - Add folder support to S3 Media Library
**Parent Issue:** #3 - Portfolio S3 Media Library
**Status:** Draft

## Overview

Enhance the existing S3 media library to support folder-based organization for portfolio images. This allows admins to organize images into logical groups (e.g., "smith-wedding", "senior-portraits") and enables galleries to display all images from a folder rather than a single cover image.

## Current State Analysis

### What Exists Today

| Component              | Status  | Notes                                              |
| ---------------------- | ------- | -------------------------------------------------- |
| S3 Media Library       | Working | Flat structure under `images/` prefix              |
| Backend API            | Working | `GET /admin/media`, `POST /admin/media/upload-url` |
| Frontend Media Library | Working | Grid view with drag-and-drop upload                |
| Gallery Content        | Working | Single `image` field (cover only)                  |

### Key Files

- **Backend**: `backend/admin_api/handler.py` (lines 441-534)
- **Frontend JS**: `frontend/public/admin/s3-media-library.js`
- **CMS Config**: `frontend/public/admin/config.yml`
- **Gallery Schema**: `frontend/src/content/config.ts` (lines 60-69)
- **Portfolio Page**: `frontend/src/pages/portfolio.astro`

### Current S3 Structure

```
s3://katelynns-photography-portfolio-assets/
  images/
    a1b2c3d4-wedding-photo.jpg
    e5f6g7h8-landscape-sunset.png
    ...
```

## Desired End State

### New S3 Structure

```
s3://katelynns-photography-portfolio-assets/
  images/
    smith-wedding/
      IMG_001.jpg
      IMG_002.jpg
      ...
    senior-portraits-jane/
      photo-1.jpg
      photo-2.jpg
      ...
    misc/                    # Default folder for uncategorized images
      a1b2c3d4-photo.jpg
      ...
```

### New Gallery Content Schema

```markdown
---
title: Smith Wedding
image: https://...s3.../images/smith-wedding-cover.jpg # Cover image (selected via existing media library)
folder: smith-wedding # References S3 folder for full gallery
order: 1
featured: true
---
```

**Note:** The cover image is uploaded separately using the existing single-image media library functionality. The `folder` field references a folder of images that will be displayed on the gallery detail page.

### Verification Checklist

- [ ] Admin can create new folders in the media library UI
- [ ] Admin can navigate between folders (breadcrumb navigation)
- [ ] Admin can upload images to a specific folder
- [ ] Admin can drag-and-drop a local folder to upload all its contents
- [ ] Gallery content files can specify a `folder` field
- [ ] Portfolio gallery pages display all images from the referenced folder
- [ ] Images display correctly in lightbox/gallery view

## What We're NOT Doing

- Multi-level nested folders (only single level: `images/{folder}/`)
- Moving images between folders via UI (use AWS Console if needed)
- Deleting folders via UI
- Image reordering within folders (alphabetical by filename)
- Thumbnail generation (Astro handles responsive images)

## Implementation Approach

**Architecture Changes:**

```
Admin Browser (DecapCMS)
    │
    ├─► [GET /admin/media?folder=] → Lambda → List folders OR images in folder
    ├─► [POST /admin/media/folders] → Lambda → Create new folder
    ├─► [POST /admin/media/upload-url] → Lambda → Generate presigned URL (with folder param)
    │
    └─► [PUT presigned-url] → Direct S3 Upload (browser → S3)

Build Time (Astro)
    │
    └─► Gallery page reads `folder` from frontmatter
        └─► Fetch API lists images in folder → Render gallery grid
```

**Key Design Decisions:**

1. **Single-level folders only** - Keeps UI simple, covers 99% of use cases
2. **Folder slug reference** - Gallery content files reference folder slug, not individual URLs
3. **Build-time image loading** - Astro fetches folder contents at build time for static rendering
4. **Backward compatibility** - Existing `image` field still works for cover images

---

## Phase 1: Backend API Updates

### Overview

Modify the backend Lambda to support folder operations: listing folders, creating folders, and uploading to specific folders.

### Changes Required:

#### 1. Backend Lambda - Update list_media for folder support

**File**: `backend/admin_api/handler.py`

**Changes**: Modify `list_media()` to support folder listing and folder contents

Update imports (if not already present):

```python
from urllib.parse import unquote
```

Replace the existing `list_media` function (lines 441-482) with:

```python
def list_media(event):
    """
    List folders or images in the portfolio-assets bucket.

    Query params:
    - folder: If provided, list images in that folder. If empty/missing, list all folders.

    Returns:
    - Without folder param: List of folders under images/
    - With folder param: List of images in images/{folder}/
    """
    if not verify_decapbridge_token(event):
        return error_response(401, "Authentication required")

    query_params = event.get("queryStringParameters") or {}
    folder = query_params.get("folder", "").strip()

    try:
        if folder:
            # List images in a specific folder
            return list_folder_images(folder)
        else:
            # List all folders
            return list_folders()
    except ClientError as e:
        print(f"S3 error listing media: {e}")
        return error_response(500, "Failed to list media")


def list_folders():
    """List all folders under images/ prefix."""
    folders = set()
    paginator = s3_client.get_paginator("list_objects_v2")

    # Use Delimiter to get "directories"
    for page in paginator.paginate(Bucket=PORTFOLIO_ASSETS_BUCKET, Prefix="images/", Delimiter="/"):
        # Get common prefixes (folders)
        for prefix in page.get("CommonPrefixes", []):
            folder_path = prefix["Prefix"]  # e.g., "images/smith-wedding/"
            folder_name = folder_path.replace("images/", "").rstrip("/")
            if folder_name:
                folders.add(folder_name)

    # Also check for any images directly in images/ (legacy flat structure)
    has_root_images = False
    for page in paginator.paginate(Bucket=PORTFOLIO_ASSETS_BUCKET, Prefix="images/", Delimiter="/"):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if key != "images/" and not key.endswith("/"):
                has_root_images = True
                break
        if has_root_images:
            break

    folder_list = sorted(list(folders))

    # Add "misc" pseudo-folder if there are root-level images
    if has_root_images and "misc" not in folder_list:
        folder_list.insert(0, "(root)")

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({
            "folders": folder_list,
            "total": len(folder_list)
        })
    }


def list_folder_images(folder: str):
    """List all images in a specific folder."""
    # Handle root-level images
    if folder == "(root)":
        prefix = "images/"
        is_root = True
    else:
        # Validate folder name
        if not re.match(r"^[a-z0-9][a-z0-9-]*[a-z0-9]$", folder) and folder != "(root)":
            return error_response(400, "Invalid folder name")
        prefix = f"images/{folder}/"
        is_root = False

    images = []
    paginator = s3_client.get_paginator("list_objects_v2")

    for page in paginator.paginate(Bucket=PORTFOLIO_ASSETS_BUCKET, Prefix=prefix, Delimiter="/" if is_root else ""):
        for obj in page.get("Contents", []):
            key = obj["Key"]

            # Skip folder markers
            if key.endswith("/"):
                continue

            # For root listing, skip items in subfolders
            if is_root:
                relative_path = key.replace("images/", "")
                if "/" in relative_path:
                    continue

            filename = key.split("/")[-1]
            ext = filename.lower().split(".")[-1] if "." in filename else ""

            if ext not in ["jpg", "jpeg", "png", "gif", "webp", "svg"]:
                continue

            url = f"https://{PORTFOLIO_ASSETS_BUCKET}.s3.us-east-2.amazonaws.com/{quote(key, safe='/')}"

            images.append({
                "name": filename,
                "path": key,
                "url": url,
                "size": obj["Size"],
                "last_modified": obj["LastModified"].isoformat()
            })

    # Sort by filename for consistent ordering
    images.sort(key=lambda x: x["name"].lower())

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({
            "folder": folder,
            "images": images,
            "total": len(images)
        })
    }
```

#### 2. Backend Lambda - Add create folder endpoint

**File**: `backend/admin_api/handler.py`

Add new route in `lambda_handler` (around line 57):

```python
    if http_method == "POST" and path == "/admin/media/folders":
        return create_folder(event)
```

Add new function after `list_folder_images`:

```python
def create_folder(event):
    """
    Create a new folder in the portfolio-assets bucket.

    Request body:
    {
        "name": "smith-wedding"
    }

    Creates an empty .keep file to ensure the folder exists in S3.
    """
    if not verify_decapbridge_token(event):
        return error_response(401, "Authentication required")

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON body")

    name = body.get("name", "").strip().lower()

    if not name:
        return error_response(400, "name is required")

    # Validate folder name (URL-safe slug)
    if not re.match(r"^[a-z0-9][a-z0-9-]*[a-z0-9]$", name) or len(name) < 2 or len(name) > 50:
        return error_response(400, "Folder name must be a URL-safe slug (lowercase letters, numbers, hyphens, 2-50 chars)")

    # Check if folder already exists
    prefix = f"images/{name}/"
    response = s3_client.list_objects_v2(Bucket=PORTFOLIO_ASSETS_BUCKET, Prefix=prefix, MaxKeys=1)
    if response.get("Contents"):
        return error_response(409, f"Folder '{name}' already exists")

    # Create folder with a .keep file (S3 doesn't have true folders)
    try:
        s3_client.put_object(
            Bucket=PORTFOLIO_ASSETS_BUCKET,
            Key=f"{prefix}.keep",
            Body=b"",
            ContentType="application/octet-stream"
        )

        return {
            "statusCode": 201,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({
                "message": "Folder created",
                "folder": name
            })
        }
    except ClientError as e:
        print(f"S3 error creating folder: {e}")
        return error_response(500, "Failed to create folder")
```

#### 3. Backend Lambda - Update get_upload_url for folder support

**File**: `backend/admin_api/handler.py`

Replace the existing `get_upload_url` function (lines 485-534) with:

```python
def get_upload_url(event):
    """
    Generate a presigned URL for uploading an image to S3.

    Request body:
    {
        "filename": "wedding-photo.jpg",
        "content_type": "image/jpeg",
        "folder": "smith-wedding"  // Optional - defaults to root images/
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
    folder = body.get("folder", "").strip().lower()

    if not filename:
        return error_response(400, "filename is required")

    # Validate file extension
    ext = filename.lower().split(".")[-1] if "." in filename else ""
    allowed_extensions = ["jpg", "jpeg", "png", "gif", "webp", "svg"]

    if ext not in allowed_extensions:
        return error_response(400, f"Invalid file type. Allowed: {', '.join(allowed_extensions)}")

    # Validate folder if provided
    if folder and folder != "(root)":
        if not re.match(r"^[a-z0-9][a-z0-9-]*[a-z0-9]$", folder):
            return error_response(400, "Invalid folder name")

    # Sanitize filename
    safe = re.sub(r"[^a-zA-Z0-9\-_.]", "-", filename.lower())
    safe = re.sub(r"-+", "-", safe).strip("-")[:100]

    # Build S3 key
    if folder and folder != "(root)":
        key = f"images/{folder}/{safe}"
    else:
        # Root level - add unique prefix to avoid collisions
        unique_id = uuid.uuid4().hex[:8]
        key = f"images/{unique_id}-{safe}"

    try:
        presigned_url = s3_client.generate_presigned_url(
            "put_object",
            Params={"Bucket": PORTFOLIO_ASSETS_BUCKET, "Key": key, "ContentType": content_type},
            ExpiresIn=300
        )

        public_url = f"https://{PORTFOLIO_ASSETS_BUCKET}.s3.us-east-2.amazonaws.com/{quote(key, safe='/')}"

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({
                "upload_url": presigned_url,
                "public_url": public_url,
                "key": key,
                "folder": folder or "(root)",
                "expires_in": 300
            })
        }

    except ClientError as e:
        print(f"S3 error generating presigned URL: {e}")
        return error_response(500, "Failed to generate upload URL")
```

#### 4. Backend Lambda - Add public folder listing endpoint

**File**: `backend/admin_api/handler.py`

Add route for public (build-time) access:

```python
    # Public endpoint for build-time folder image listing (no auth required)
    if http_method == "GET" and path.startswith("/media/folders/") and path.endswith("/images"):
        folder = path.replace("/media/folders/", "").replace("/images", "")
        return list_folder_images_public(folder)
```

Add the public function:

```python
def list_folder_images_public(folder: str):
    """
    Public endpoint to list images in a folder.
    Used by Astro at build time to render gallery pages.

    No authentication required - folder contents are public anyway.
    """
    if not folder:
        return error_response(400, "Folder name required")

    # Validate folder name
    if not re.match(r"^[a-z0-9][a-z0-9-]*[a-z0-9]$", folder):
        return error_response(400, "Invalid folder name")

    prefix = f"images/{folder}/"
    images = []

    try:
        paginator = s3_client.get_paginator("list_objects_v2")

        for page in paginator.paginate(Bucket=PORTFOLIO_ASSETS_BUCKET, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]

                if key.endswith("/") or key.endswith(".keep"):
                    continue

                filename = key.split("/")[-1]
                ext = filename.lower().split(".")[-1] if "." in filename else ""

                if ext not in ["jpg", "jpeg", "png", "gif", "webp", "svg"]:
                    continue

                url = f"https://{PORTFOLIO_ASSETS_BUCKET}.s3.us-east-2.amazonaws.com/{quote(key, safe='/')}"

                images.append({
                    "name": filename,
                    "url": url
                })

        # Sort alphabetically by filename
        images.sort(key=lambda x: x["name"].lower())

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "public, max-age=300"  # 5 min cache for builds
            },
            "body": json.dumps({
                "folder": folder,
                "images": images,
                "total": len(images)
            })
        }

    except ClientError as e:
        print(f"S3 error listing folder images: {e}")
        return error_response(500, "Failed to list folder images")
```

#### 5. Terraform - Add API Gateway route for folder creation

**File**: `terraform/api-gateway.tf`

Add after existing media routes:

```hcl
# Admin Media - Create folder
resource "aws_apigatewayv2_route" "admin_media_create_folder" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /admin/media/folders"
  target    = "integrations/${aws_apigatewayv2_integration.admin_api.id}"
}

# Public endpoint - List folder images (for Astro build)
resource "aws_apigatewayv2_route" "media_folder_images" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /media/folders/{folder}/images"
  target    = "integrations/${aws_apigatewayv2_integration.admin_api.id}"
}
```

### Success Criteria:

#### Automated Verification:

- [x] `terraform plan` shows new route additions (syntax validated)
- [ ] `terraform apply` completes successfully
- [ ] Lambda deploy script runs without errors

#### Manual Verification:

- [ ] `GET /admin/media` returns list of folders (with auth token)
- [ ] `GET /admin/media?folder=test` returns images in folder (with auth token)
- [ ] `POST /admin/media/folders` creates new folder (with auth token)
- [ ] `POST /admin/media/upload-url` with folder param returns correct S3 key
- [ ] `GET /media/folders/{folder}/images` returns images (no auth required)

**Implementation Note**: After completing this phase, pause for manual testing of API endpoints before proceeding to Phase 2.

---

## Phase 2: Frontend Media Library UI

### Overview

Update the S3 media library JavaScript to support folder navigation, folder creation, and folder-based uploads.

### Changes Required:

#### 1. Update Media Library JavaScript

**File**: `frontend/public/admin/s3-media-library.js`

Replace the entire file with:

```javascript
/**
 * S3 Media Library for DecapCMS
 *
 * Custom media library that stores images in S3 with folder support.
 * Uses a class-based approach to ensure proper 'this' binding.
 */

class S3MediaLibraryClass {
  constructor() {
    this.name = "s3-media-library";
    this.options = {};
    this.handleInsert = null;
    this.apiBase = "https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com";
    this.currentFolder = null; // null = folder list view

    // Bind all methods
    this.init = this.init.bind(this);
    this.show = this.show.bind(this);
    this.createModal = this.createModal.bind(this);
    this.addStyles = this.addStyles.bind(this);
    this.loadFolders = this.loadFolders.bind(this);
    this.loadFolderImages = this.loadFolderImages.bind(this);
    this.getAuthToken = this.getAuthToken.bind(this);
    this.setupUploadHandlers = this.setupUploadHandlers.bind(this);
    this.handleFiles = this.handleFiles.bind(this);
    this.createFolder = this.createFolder.bind(this);
    this.navigateToFolder = this.navigateToFolder.bind(this);
    this.navigateBack = this.navigateBack.bind(this);
  }

  init({ options, handleInsert }) {
    this.options = options || {};
    this.handleInsert = handleInsert;
    this.apiBase =
      (options && options.apiBase) ||
      "https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com";
    return this;
  }

  async show({ config, allowMultiple, imagesOnly }) {
    this.currentFolder = null;
    const modal = this.createModal();
    document.body.appendChild(modal);
    await this.loadFolders(modal);
    this.setupUploadHandlers(modal);
  }

  createModal() {
    const modal = document.createElement("div");
    modal.id = "s3-media-modal";
    modal.innerHTML = `
      <div class="s3-media-overlay">
        <div class="s3-media-container">
          <div class="s3-media-header">
            <div class="s3-media-breadcrumb">
              <span class="s3-breadcrumb-root" id="s3-breadcrumb-root">Media Library</span>
              <span class="s3-breadcrumb-separator" id="s3-breadcrumb-sep" style="display:none"> / </span>
              <span class="s3-breadcrumb-folder" id="s3-breadcrumb-folder"></span>
            </div>
            <button class="s3-media-close" aria-label="Close">&times;</button>
          </div>

          <div class="s3-media-toolbar" id="s3-media-toolbar">
            <button class="s3-toolbar-btn" id="s3-create-folder-btn">+ New Folder</button>
          </div>

          <div class="s3-media-upload-zone" id="s3-upload-zone" style="display:none">
            <input type="file" id="s3-file-input" accept="image/*" multiple style="display:none">
            <input type="file" id="s3-folder-input" webkitdirectory multiple style="display:none">
            <div class="s3-upload-area" id="s3-upload-area">
              <p>Drag & drop images or a folder here, or
                <button id="s3-browse-btn">browse files</button>
                <button id="s3-browse-folder-btn">browse folder</button>
              </p>
            </div>
            <div class="s3-upload-progress" id="s3-upload-progress" style="display:none">
              <div class="s3-progress-bar"><div class="s3-progress-fill"></div></div>
              <span class="s3-progress-text">Uploading...</span>
            </div>
          </div>

          <div class="s3-media-grid" id="s3-media-grid">
            <div class="s3-loading">Loading...</div>
          </div>
        </div>
      </div>
    `;

    this.addStyles();

    // Close handlers
    modal
      .querySelector(".s3-media-close")
      .addEventListener("click", () => modal.remove());
    modal.querySelector(".s3-media-overlay").addEventListener("click", (e) => {
      if (e.target.classList.contains("s3-media-overlay")) modal.remove();
    });

    // Breadcrumb navigation
    modal.querySelector("#s3-breadcrumb-root").addEventListener("click", () => {
      if (this.currentFolder) this.navigateBack(modal);
    });

    // Create folder button
    modal
      .querySelector("#s3-create-folder-btn")
      .addEventListener("click", () => {
        this.createFolder(modal);
      });

    return modal;
  }

  addStyles() {
    if (document.getElementById("s3-media-styles")) return;

    const styles = document.createElement("style");
    styles.id = "s3-media-styles";
    styles.textContent = `
      .s3-media-overlay {
        position: fixed;
        top: 0; left: 0; right: 0; bottom: 0;
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

      .s3-media-breadcrumb {
        font-size: 18px;
        color: #333;
      }

      .s3-breadcrumb-root {
        cursor: pointer;
        color: #2196F3;
      }

      .s3-breadcrumb-root:hover {
        text-decoration: underline;
      }

      .s3-breadcrumb-separator {
        color: #999;
        margin: 0 8px;
      }

      .s3-breadcrumb-folder {
        font-weight: 600;
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

      .s3-media-toolbar {
        padding: 12px 20px;
        border-bottom: 1px solid #e0e0e0;
        display: flex;
        gap: 12px;
      }

      .s3-toolbar-btn {
        background: #f5f5f5;
        border: 1px solid #ddd;
        padding: 8px 16px;
        border-radius: 4px;
        cursor: pointer;
        font-size: 14px;
      }

      .s3-toolbar-btn:hover {
        background: #e0e0e0;
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

      .s3-upload-area p { margin: 0; color: #666; }

      #s3-browse-btn, #s3-browse-folder-btn {
        background: #2196F3;
        color: white;
        border: none;
        padding: 8px 16px;
        border-radius: 4px;
        cursor: pointer;
        margin-left: 8px;
      }

      #s3-browse-btn:hover, #s3-browse-folder-btn:hover {
        background: #1976D2;
      }

      #s3-browse-folder-btn {
        background: #4CAF50;
      }

      #s3-browse-folder-btn:hover {
        background: #388E3C;
      }

      .s3-upload-progress { margin-top: 12px; }

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

      .s3-loading, .s3-empty-state {
        grid-column: 1 / -1;
        text-align: center;
        color: #666;
        padding: 40px;
      }

      .s3-folder-item {
        aspect-ratio: 1;
        border-radius: 8px;
        background: #f5f5f5;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        cursor: pointer;
        border: 3px solid transparent;
        transition: border-color 0.2s, background 0.2s;
      }

      .s3-folder-item:hover {
        border-color: #2196F3;
        background: #e3f2fd;
      }

      .s3-folder-icon {
        font-size: 48px;
        margin-bottom: 8px;
      }

      .s3-folder-name {
        font-size: 14px;
        color: #333;
        text-align: center;
        padding: 0 8px;
        word-break: break-word;
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
    `;
    document.head.appendChild(styles);
  }

  async loadFolders(modal) {
    const grid = modal.querySelector("#s3-media-grid");
    const uploadZone = modal.querySelector("#s3-upload-zone");
    const toolbar = modal.querySelector("#s3-media-toolbar");
    const breadcrumbSep = modal.querySelector("#s3-breadcrumb-sep");
    const breadcrumbFolder = modal.querySelector("#s3-breadcrumb-folder");
    const breadcrumbRoot = modal.querySelector("#s3-breadcrumb-root");

    // Update UI for folder list view
    this.currentFolder = null;
    uploadZone.style.display = "none";
    toolbar.style.display = "flex";
    breadcrumbSep.style.display = "none";
    breadcrumbFolder.textContent = "";
    breadcrumbRoot.style.cursor = "default";
    breadcrumbRoot.style.color = "#333";

    grid.innerHTML = '<div class="s3-loading">Loading folders...</div>';

    try {
      const token = this.getAuthToken();
      const response = await fetch(`${this.apiBase}/admin/media`, {
        headers: { Authorization: `Bearer ${token}` },
      });

      if (!response.ok) throw new Error("Failed to load folders");

      const data = await response.json();

      if (!data.folders || data.folders.length === 0) {
        grid.innerHTML =
          '<div class="s3-empty-state">No folders yet. Create one to get started!</div>';
        return;
      }

      grid.innerHTML = data.folders
        .map(
          (folder) => `
          <div class="s3-folder-item" data-folder="${folder}">
            <span class="s3-folder-icon">📁</span>
            <span class="s3-folder-name">${folder === "(root)" ? "Uncategorized" : folder}</span>
          </div>
        `,
        )
        .join("");

      // Add click handlers for folders
      grid.querySelectorAll(".s3-folder-item").forEach((item) => {
        item.addEventListener("click", () => {
          this.navigateToFolder(modal, item.dataset.folder);
        });
      });
    } catch (error) {
      console.error("Error loading folders:", error);
      grid.innerHTML =
        '<div class="s3-empty-state">Error loading folders. Please try again.</div>';
    }
  }

  async loadFolderImages(modal, folder) {
    const grid = modal.querySelector("#s3-media-grid");
    const uploadZone = modal.querySelector("#s3-upload-zone");
    const toolbar = modal.querySelector("#s3-media-toolbar");
    const breadcrumbSep = modal.querySelector("#s3-breadcrumb-sep");
    const breadcrumbFolder = modal.querySelector("#s3-breadcrumb-folder");
    const breadcrumbRoot = modal.querySelector("#s3-breadcrumb-root");
    const handleInsert = this.handleInsert;

    // Update UI for image list view
    this.currentFolder = folder;
    uploadZone.style.display = "block";
    toolbar.style.display = "none";
    breadcrumbSep.style.display = "inline";
    breadcrumbFolder.textContent =
      folder === "(root)" ? "Uncategorized" : folder;
    breadcrumbRoot.style.cursor = "pointer";
    breadcrumbRoot.style.color = "#2196F3";

    grid.innerHTML = '<div class="s3-loading">Loading images...</div>';

    try {
      const token = this.getAuthToken();
      const response = await fetch(
        `${this.apiBase}/admin/media?folder=${encodeURIComponent(folder)}`,
        {
          headers: { Authorization: `Bearer ${token}` },
        },
      );

      if (!response.ok) throw new Error("Failed to load images");

      const data = await response.json();

      if (!data.images || data.images.length === 0) {
        grid.innerHTML =
          '<div class="s3-empty-state">No images in this folder. Upload some!</div>';
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

      // Add click handlers for image selection
      grid.querySelectorAll(".s3-media-item").forEach((item) => {
        item.addEventListener("click", () => {
          handleInsert(item.dataset.url);
          modal.remove();
        });
      });
    } catch (error) {
      console.error("Error loading images:", error);
      grid.innerHTML =
        '<div class="s3-empty-state">Error loading images. Please try again.</div>';
    }
  }

  navigateToFolder(modal, folder) {
    this.loadFolderImages(modal, folder);
  }

  navigateBack(modal) {
    this.loadFolders(modal);
  }

  async createFolder(modal) {
    const name = prompt(
      "Enter folder name (lowercase letters, numbers, hyphens):",
    );
    if (!name) return;

    const sanitized = name.toLowerCase().trim();
    if (
      !/^[a-z0-9][a-z0-9-]*[a-z0-9]$/.test(sanitized) ||
      sanitized.length < 2
    ) {
      alert(
        "Invalid folder name. Use lowercase letters, numbers, and hyphens (min 2 chars).",
      );
      return;
    }

    try {
      const token = this.getAuthToken();
      const response = await fetch(`${this.apiBase}/admin/media/folders`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ name: sanitized }),
      });

      if (!response.ok) {
        const error = await response.json();
        alert(error.error || "Failed to create folder");
        return;
      }

      // Navigate to the new folder
      this.navigateToFolder(modal, sanitized);
    } catch (error) {
      console.error("Error creating folder:", error);
      alert("Failed to create folder. Please try again.");
    }
  }

  getAuthToken() {
    const userInfo = localStorage.getItem("decap-cms-user");
    const hasSession = sessionStorage.getItem("decap-cms-auth");

    if (userInfo && hasSession) {
      try {
        const parsed = JSON.parse(userInfo);
        return parsed.login || "";
      } catch (e) {
        return "";
      }
    }
    return "";
  }

  setupUploadHandlers(modal) {
    const uploadArea = modal.querySelector("#s3-upload-area");
    const fileInput = modal.querySelector("#s3-file-input");
    const folderInput = modal.querySelector("#s3-folder-input");
    const browseBtn = modal.querySelector("#s3-browse-btn");
    const browseFolderBtn = modal.querySelector("#s3-browse-folder-btn");

    browseBtn.addEventListener("click", () => fileInput.click());
    browseFolderBtn.addEventListener("click", () => folderInput.click());

    fileInput.addEventListener("change", (e) => {
      this.handleFiles(Array.from(e.target.files), modal);
    });

    folderInput.addEventListener("change", (e) => {
      this.handleFiles(Array.from(e.target.files), modal);
    });

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

      // Handle both files and folders from drag-and-drop
      const items = e.dataTransfer.items;
      const files = [];

      const processEntry = async (entry) => {
        if (entry.isFile) {
          return new Promise((resolve) => {
            entry.file((file) => {
              files.push(file);
              resolve();
            });
          });
        } else if (entry.isDirectory) {
          const reader = entry.createReader();
          return new Promise((resolve) => {
            reader.readEntries(async (entries) => {
              for (const subEntry of entries) {
                await processEntry(subEntry);
              }
              resolve();
            });
          });
        }
      };

      const promises = [];
      for (let i = 0; i < items.length; i++) {
        const entry = items[i].webkitGetAsEntry();
        if (entry) {
          promises.push(processEntry(entry));
        }
      }

      Promise.all(promises).then(() => {
        if (files.length > 0) {
          this.handleFiles(files, modal);
        }
      });
    });
  }

  async handleFiles(files, modal) {
    if (!this.currentFolder) {
      alert("Please select a folder first");
      return;
    }

    const progressContainer = modal.querySelector("#s3-upload-progress");
    const progressFill = modal.querySelector(".s3-progress-fill");
    const progressText = modal.querySelector(".s3-progress-text");

    // Filter to only image files
    const imageFiles = files.filter((file) => {
      const ext = file.name.toLowerCase().split(".").pop();
      return ["jpg", "jpeg", "png", "gif", "webp", "svg"].includes(ext);
    });

    if (imageFiles.length === 0) {
      alert("No valid image files found");
      return;
    }

    progressContainer.style.display = "block";

    const token = this.getAuthToken();
    let uploaded = 0;
    const total = imageFiles.length;

    for (const file of imageFiles) {
      progressText.textContent = `Uploading ${file.name} (${uploaded + 1}/${total})...`;

      try {
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
              folder: this.currentFolder,
            }),
          },
        );

        if (!urlResponse.ok) throw new Error("Failed to get upload URL");

        const urlData = await urlResponse.json();

        const uploadResponse = await fetch(urlData.upload_url, {
          method: "PUT",
          headers: { "Content-Type": file.type },
          body: file,
        });

        if (!uploadResponse.ok) throw new Error("Failed to upload to S3");

        uploaded++;
        progressFill.style.width = `${(uploaded / total) * 100}%`;
      } catch (error) {
        console.error("Upload error:", error);
        progressText.textContent = `Error uploading ${file.name}`;
      }
    }

    progressText.textContent = `Uploaded ${uploaded} of ${total} files`;

    setTimeout(() => {
      this.loadFolderImages(modal, this.currentFolder);
      progressContainer.style.display = "none";
      progressFill.style.width = "0%";
    }, 1000);
  }
}

window.S3MediaLibrary = new S3MediaLibraryClass();
```

### Success Criteria:

#### Automated Verification:

- [x] `npm run build` in frontend succeeds
- [ ] No JavaScript errors in browser console on admin page

#### Manual Verification:

- [ ] Media library shows folder list on open
- [ ] Clicking a folder shows images inside
- [ ] Breadcrumb navigation works (back to folder list)
- [ ] "New Folder" button creates folder with prompt
- [ ] Upload zone appears only when inside a folder
- [ ] File browse upload works
- [ ] Folder browse upload works
- [ ] Drag-and-drop folder upload works
- [ ] Selecting an image inserts the URL

**Implementation Note**: After completing this phase, pause for manual testing of the media library UI before proceeding to Phase 3.

---

## Phase 3: Gallery Schema and Page Updates

### Overview

Update the gallery content schema to support folder references and modify the portfolio page to render all images from a folder.

### Changes Required:

#### 1. Update Gallery Content Schema

**File**: `frontend/src/content/config.ts`

Update the galleries schema (around line 60):

```typescript
const galleries = defineCollection({
  type: "content",
  schema: z.object({
    title: z.string(),
    image: z.string().optional(), // Cover image (optional, can auto-select from folder)
    folder: z.string().optional(), // S3 folder slug for full gallery
    order: z.number(),
    featured: z.boolean().default(false),
  }),
});
```

#### 2. Update DecapCMS Config for Gallery Folder Field

**File**: `frontend/public/admin/config.yml`

Update the galleries collection fields (around line 164):

```yaml
# Galleries
- name: "galleries"
  label: "Wedding Galleries"
  folder: "frontend/src/content/galleries"
  create: true
  slug: "{{slug}}"
  fields:
    - { label: "Title", name: "title", widget: "string" }
    - {
        label: "Cover Image",
        name: "image",
        widget: "image",
        required: false,
        hint: "Optional cover image. If not set, first image from folder will be used.",
      }
    - {
        label: "Image Folder",
        name: "folder",
        widget: "string",
        required: false,
        hint: "S3 folder name (e.g., smith-wedding). Leave empty for single-image galleries.",
      }
    - {
        label: "Display Order",
        name: "order",
        widget: "number",
        value_type: "int",
      }
    - {
        label: "Featured on Homepage",
        name: "featured",
        widget: "boolean",
        default: false,
      }
```

#### 3. Create Gallery Detail Page

**File**: `frontend/src/pages/portfolio/[slug].astro` (new file)

```astro
---
import Layout from "../../layouts/Layout.astro";
import { getCollection } from "astro:content";
import Gallery from "../../components/Gallery.astro";

export async function getStaticPaths() {
  const galleries = await getCollection("galleries");
  return galleries.map((gallery) => ({
    params: { slug: gallery.slug },
    props: { gallery },
  }));
}

const { gallery } = Astro.props;

// Fetch images from S3 folder if specified
let images: { url: string; name: string }[] = [];

if (gallery.data.folder) {
  const apiBase = import.meta.env.PUBLIC_API_BASE || "https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com";

  try {
    const response = await fetch(`${apiBase}/media/folders/${gallery.data.folder}/images`);
    if (response.ok) {
      const data = await response.json();
      images = data.images || [];
    }
  } catch (error) {
    console.error(`Failed to load images for folder ${gallery.data.folder}:`, error);
  }
}

// Use cover image or first folder image
const coverImage = gallery.data.image || (images.length > 0 ? images[0].url : null);
---

<Layout title={`${gallery.data.title} | Katelynn's Photography`}>
  <main class="pt-24 pb-16">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <!-- Header -->
      <div class="mb-12 text-center">
        <a href="/portfolio" class="text-primary-600 hover:text-primary-700 mb-4 inline-block">
          &larr; Back to Portfolio
        </a>
        <h1 class="text-4xl font-serif text-primary-800 mb-4">{gallery.data.title}</h1>
        {images.length > 0 && (
          <p class="text-primary-600">{images.length} photos</p>
        )}
      </div>

      <!-- Gallery Grid -->
      {images.length > 0 ? (
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          {images.map((image, index) => (
            <div
              class="group relative aspect-square bg-primary-100 rounded-lg overflow-hidden cursor-pointer gallery-item"
              data-index={index}
              data-url={image.url}
            >
              <img
                src={image.url}
                alt={image.name}
                class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
                loading="lazy"
              />
            </div>
          ))}
        </div>
      ) : gallery.data.image ? (
        <!-- Single image gallery (legacy) -->
        <div class="max-w-2xl mx-auto">
          <img
            src={gallery.data.image}
            alt={gallery.data.title}
            class="w-full rounded-lg"
          />
        </div>
      ) : (
        <p class="text-center text-primary-600">No images available for this gallery.</p>
      )}
    </div>
  </main>

  <!-- Lightbox -->
  <div id="lightbox" class="fixed inset-0 bg-black/90 z-50 hidden items-center justify-center">
    <button id="lightbox-close" class="absolute top-4 right-4 text-white text-4xl hover:text-primary-300">&times;</button>
    <button id="lightbox-prev" class="absolute left-4 text-white text-4xl hover:text-primary-300">&larr;</button>
    <button id="lightbox-next" class="absolute right-4 text-white text-4xl hover:text-primary-300">&rarr;</button>
    <img id="lightbox-img" class="max-h-[90vh] max-w-[90vw] object-contain" />
  </div>

  <script define:vars={{ images }}>
    const galleryItems = document.querySelectorAll('.gallery-item');
    const lightbox = document.getElementById('lightbox');
    const lightboxImg = document.getElementById('lightbox-img');
    const closeBtn = document.getElementById('lightbox-close');
    const prevBtn = document.getElementById('lightbox-prev');
    const nextBtn = document.getElementById('lightbox-next');

    let currentIndex = 0;

    function showImage(index) {
      if (index < 0) index = images.length - 1;
      if (index >= images.length) index = 0;
      currentIndex = index;
      lightboxImg.src = images[index].url;
    }

    galleryItems.forEach((item) => {
      item.addEventListener('click', () => {
        currentIndex = parseInt(item.dataset.index);
        showImage(currentIndex);
        lightbox.classList.remove('hidden');
        lightbox.classList.add('flex');
      });
    });

    closeBtn.addEventListener('click', () => {
      lightbox.classList.add('hidden');
      lightbox.classList.remove('flex');
    });

    prevBtn.addEventListener('click', () => showImage(currentIndex - 1));
    nextBtn.addEventListener('click', () => showImage(currentIndex + 1));

    document.addEventListener('keydown', (e) => {
      if (lightbox.classList.contains('hidden')) return;
      if (e.key === 'Escape') closeBtn.click();
      if (e.key === 'ArrowLeft') prevBtn.click();
      if (e.key === 'ArrowRight') nextBtn.click();
    });

    lightbox.addEventListener('click', (e) => {
      if (e.target === lightbox) closeBtn.click();
    });
  </script>
</Layout>
```

#### 4. Update Portfolio Listing Page

**File**: `frontend/src/pages/portfolio.astro`

Add links to gallery detail pages:

Find the gallery card section and update to link to detail pages:

```astro
{sortedGalleries.map((gallery) => (
  <a
    href={`/portfolio/${gallery.slug}`}
    class="group block relative aspect-[4/5] bg-primary-100 rounded-lg overflow-hidden"
  >
    <img
      src={gallery.data.image}
      alt={gallery.data.title}
      class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
      loading="lazy"
    />
    <div class="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300">
      <div class="absolute bottom-0 left-0 right-0 p-6">
        <h3 class="text-white font-serif text-xl">{gallery.data.title}</h3>
        <span class="text-white/80 text-sm">View Gallery &rarr;</span>
      </div>
    </div>
  </a>
))}
```

#### 5. Add Environment Variable

**File**: `frontend/.env.example` (create if doesn't exist)

```
PUBLIC_API_BASE=https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com
```

### Success Criteria:

#### Automated Verification:

- [x] `npm run build` succeeds
- [x] TypeScript type checking passes
- [x] All gallery pages generate correctly

#### Manual Verification:

- [ ] Portfolio page shows gallery cards with links
- [ ] Clicking gallery card opens detail page
- [ ] Detail page shows all images from S3 folder
- [ ] Lightbox navigation works (click, arrows, escape)
- [ ] Galleries without folders still work (single image display)

**Implementation Note**: After completing this phase, verify the full workflow end-to-end before marking the implementation complete.

---

## Testing Strategy

### Unit Tests:

- Lambda handler tests for folder operations
- Test folder name validation
- Test image listing with and without folders

### Integration Tests:

- API Gateway → Lambda → S3 flow for folders
- Presigned URL upload to folders
- Build-time folder image fetching

### Manual Testing Steps:

1. Log into DecapCMS as admin
2. Open media library
3. Create a new folder (e.g., "test-wedding")
4. Upload multiple images to the folder
5. Create a new gallery with `folder: test-wedding`
6. Build the site (`npm run build`)
7. Navigate to the gallery detail page
8. Verify all images display
9. Test lightbox navigation

## Migration Notes

### Existing Galleries

Existing galleries with `image` field will continue to work. To convert to folder-based:

1. Create folder in media library
2. Upload all gallery images to folder
3. Edit gallery content file:
   - Keep `image` for cover (or remove to use first folder image)
   - Add `folder: folder-name`
4. Rebuild site

### Backward Compatibility

- `image` field remains supported for cover images
- Galleries without `folder` field display single image (legacy behavior)
- No changes required for existing galleries

## Performance Considerations

- **Build-time fetching**: Images loaded at build time, not runtime
- **S3 caching**: Public folder endpoint has 5-minute cache header
- **Lazy loading**: Gallery images use `loading="lazy"`
- **Image optimization**: Astro can process S3 images if needed

## Cost Impact

Minimal additional cost:

- S3 requests: ~$0.01 more for folder operations
- No additional storage (images already in S3)
- Lambda: Negligible increase

## References

- Parent issue: GitHub #3 (Portfolio S3 Media Library)
- Master plan: `thoughts/shared/plans/2026-01-17-s3-media-management-master-plan.md`
- Original plan: `thoughts/shared/plans/2026-01-17-portfolio-s3-media-library.md`
- Backend handler: `backend/admin_api/handler.py`
- Media library JS: `frontend/public/admin/s3-media-library.js`
