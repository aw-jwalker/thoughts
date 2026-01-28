# Client Albums Multi-Client Assignment Implementation Plan

**Status: ✅ COMPLETED** (2026-01-25)

## Overview

Redesign the client albums system to support multi-client album assignment with expiration dates. This replaces the current single-client design (where S3 paths embed user email) with a database-driven approach where albums are stored independently and assigned to one or more clients with configurable expiration.

## Current State Analysis

### What Exists Today

| Component     | Status  | Location                                                           |
| ------------- | ------- | ------------------------------------------------------------------ |
| S3 Bucket     | Working | `terraform/s3.tf:63-119` - `katelynns-photography-client-albums`   |
| Cognito Auth  | Working | JWT validation in `backend/client_portal/app/services/cognito.py`  |
| Album API     | Working | `backend/client_portal/app/routes/albums.py` - list, get, download |
| Admin API     | Limited | `backend/admin_api/handler.py` - creates albums under email prefix |
| Client Portal | Working | `frontend/src/pages/client/` - login, dashboard, album viewer      |

### Current S3 Structure (Single-Client)

```
s3://katelynns-photography-client-albums/
  albums/
    john_at_example_com/
      smith-wedding-2026/
        IMG_001.jpg
        IMG_002.jpg
```

**Problem**: Album is tied to single client email in path. Same album for multiple clients requires duplicate storage.

### Key Discoveries

- `S3Service._get_user_prefix()` (`s3.py:30-38`) embeds email in all S3 paths
- `list_user_albums()` (`s3.py:40-76`) lists albums by S3 prefix, not database
- No expiration checking exists anywhere
- No DynamoDB infrastructure exists

## Desired End State

After implementation:

1. **Albums stored independently**: `albums/{album_id}/photos/IMG_001.jpg`
2. **Assignments in DynamoDB**: Maps albums to clients with expiration dates
3. **Access controlled by database**: Client can only access assigned, non-expired albums
4. **Admin workflow**:
   - Upload photos via CLI: `aws s3 sync ./photos s3://bucket/albums/{album_id}/photos/`
   - Optionally create `metadata.json` (for Lightroom workflow)
   - Register album: `POST /admin/albums/{album_id}/register` (reads metadata.json if exists)
   - Assign to client: `POST /admin/albums/{album_id}/assign` with client email + expiry
5. **Client sees**: Only their assigned albums, with expiration dates displayed
6. **ZIP downloads**: Generated on first request, cached 30 days, 6-hour presigned URLs

### Verification Checklist

- [ ] Admin can upload album via CLI to new S3 structure
- [ ] Admin can register album via API (with or without metadata.json)
- [ ] Admin can assign album to multiple clients with different expiration dates
- [ ] Client sees only their assigned, non-expired albums
- [ ] Client sees expiration date on dashboard and album view
- [ ] Expired albums return 403 Forbidden (hidden from list)
- [ ] Client can download individual photos (1-hour URLs)
- [ ] Client can download full album as ZIP (6-hour URLs)
- [ ] ZIP is generated on first request and cached
- [ ] ZIP auto-deletes after 30 days (lifecycle policy)

## What We're NOT Doing

- ❌ Migrating existing albums (fresh start with new structure)
- ❌ Lightroom integration (separate plan - but structure supports it)
- ❌ Web-based admin UI for uploads (CLI + API for now)
- ❌ Email notifications for expiration warnings
- ❌ Client-initiated access extension requests
- ❌ Thumbnail generation (using full-size images with lazy loading)
- ❌ Async ZIP generation for very large albums (MVP accepts 500 photo limit)

## Known Limitations

| Limitation                                               | Impact                          | Future Solution                      |
| -------------------------------------------------------- | ------------------------------- | ------------------------------------ |
| ZIP generation may timeout for albums >500 photos / >5GB | Large wedding albums could fail | Async generation with Step Functions |
| No web UI for admin uploads                              | Must use CLI                    | Future admin dashboard               |
| No automatic expiration notifications                    | Clients may miss deadline       | Email reminders via SES              |

## Lightroom Extensibility Notes

This design explicitly supports future Lightroom integration:

1. **S3 structure is upload-agnostic**: `albums/{album_id}/photos/` works for CLI, Lightroom, or web upload
2. **Optional metadata.json**: Lightroom can write `albums/{album_id}/metadata.json` with album info
3. **Registration reads metadata.json**: API can auto-populate album name/date from the file
4. **Album ID can be human-readable slug**: Lightroom publish service can use album name as ID
5. **DynamoDB is authoritative**: metadata.json is just a handoff mechanism, not runtime data

**Lightroom workflow (future):**

```
1. Lightroom syncs photos to albums/{album_id}/photos/
2. Lightroom creates albums/{album_id}/metadata.json
3. Admin calls POST /admin/albums/{album_id}/register
4. API reads metadata.json, creates DynamoDB record
5. Admin assigns to clients via API
```

---

## Phase 1: DynamoDB Infrastructure

### Overview

Create three DynamoDB tables: Album (metadata), User (client info), and User_Album (join table for access). This design is appropriate for the expected scale (~100-500 albums max).

### Design Rationale

At this scale (professional photographer doing 20-100 shoots/year):

- **Scan operations are fine**: <500 items scans in <100ms, costs fractions of a cent
- **Three tables is clear**: Normalized design with proper relationships
- **Easy to extend**: Add fields anytime without schema changes
- **Simple queries**: FilterExpression works for any ad-hoc query

**Table Naming Convention:** Singular names (Album, User, User_Album)

### Changes Required:

#### 1. Create DynamoDB Terraform Configuration

**File**: `terraform/dynamodb.tf` (NEW FILE)

```hcl
# ============================================================
# DynamoDB Tables for Client Albums
# ============================================================
# Three-table design for simplicity at expected scale (<500 albums)
# Scan operations are acceptable and cost-effective at this scale
# Table names are singular: Album, User, User_Album

# ------------------------------------------------------------
# Album Table - One row per album
# ------------------------------------------------------------
resource "aws_dynamodb_table" "album" {
  name         = "${var.project_name}-album"
  billing_mode = "PAY_PER_REQUEST"  # On-demand pricing
  hash_key     = "album_id"

  attribute {
    name = "album_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-album"
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# User Table - Client information (supplements Cognito)
# ------------------------------------------------------------
resource "aws_dynamodb_table" "user" {
  name         = "${var.project_name}-user"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "email"

  attribute {
    name = "email"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-user"
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# User_Album Table - Join table mapping users to albums
# ------------------------------------------------------------
resource "aws_dynamodb_table" "user_album" {
  name         = "${var.project_name}-user-album"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "album_id"
  range_key    = "email"

  attribute {
    name = "album_id"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  # GSI for "list all albums for a user" query
  # This is the one index worth having - makes client dashboard O(1)
  global_secondary_index {
    name            = "email-index"
    hash_key        = "email"
    range_key       = "album_id"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-user-album"
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# Outputs for Lambda environment variables
# ------------------------------------------------------------
output "album_table_name" {
  value = aws_dynamodb_table.album.name
}

output "album_table_arn" {
  value = aws_dynamodb_table.album.arn
}

output "user_table_name" {
  value = aws_dynamodb_table.user.name
}

output "user_table_arn" {
  value = aws_dynamodb_table.user.arn
}

output "user_album_table_name" {
  value = aws_dynamodb_table.user_album.name
}

output "user_album_table_arn" {
  value = aws_dynamodb_table.user_album.arn
}
```

**Data Model:**

```
Album Table (PK: album_id)
─────────────────────────────────────────────────────────────────────────────
album_id        | name              | event_date | photo_count | shoot_type | location     | ...
smith-wed-2026  | Smith Wedding     | 2026-01-15 | 247         | wedding    | Denver, CO   |
jones-port-2026 | Jones Portraits   | 2026-02-20 | 45          | portrait   | Studio       |

User Table (PK: email)
─────────────────────────────────────────────────────────────────────────────
email                  | first_name | last_name | phone        | created_at
john@example.com       | John       | Smith     | 303-555-1234 | 2026-01-17T10:00:00Z
jane@example.com       | Jane       | Smith     | 303-555-5678 | 2026-01-17T10:00:00Z
mary@example.com       | Mary       | Jones     | null         | 2026-02-21T10:00:00Z

User_Album Table (PK: album_id, SK: email, GSI: email)
─────────────────────────────────────────────────────────────────────────────
album_id        | email                  | expires_at           | assigned_at
smith-wed-2026  | john@example.com       | 2026-07-15T00:00:00Z | 2026-01-17T10:00:00Z
smith-wed-2026  | jane@example.com       | 2026-07-15T00:00:00Z | 2026-01-17T10:00:00Z
jones-port-2026 | mary@example.com       | 2026-08-20T00:00:00Z | 2026-02-21T10:00:00Z
```

**Query Patterns (all work with Scan + FilterExpression at this scale):**

```python
# Get single album
album_table.get_item(Key={"album_id": "smith-wed-2026"})

# List all albums (admin)
album_table.scan()

# Filter albums by year
album_table.scan(
    FilterExpression="begins_with(event_date, :year)",
    ExpressionAttributeValues={":year": "2026"}
)

# Filter by shoot type
album_table.scan(
    FilterExpression="shoot_type = :type",
    ExpressionAttributeValues={":type": "wedding"}
)

# Get user info
user_table.get_item(Key={"email": "john@example.com"})

# List all users (admin)
user_table.scan()

# Get user's albums (uses GSI - fast)
user_album_table.query(
    IndexName="email-index",
    KeyConditionExpression="email = :email",
    ExpressionAttributeValues={":email": "john@example.com"}
)

# Get album's users
user_album_table.query(
    KeyConditionExpression="album_id = :id",
    ExpressionAttributeValues={":id": "smith-wed-2026"}
)

# Check specific user-album access
user_album_table.get_item(
    Key={"album_id": "smith-wed-2026", "email": "john@example.com"}
)
```

#### 2. Update Lambda IAM Policy for DynamoDB

**File**: `terraform/lambda.tf`
**Location**: Add to `aws_iam_role_policy.lambda_custom` Statement array (around line 52)

```hcl
    # Add after S3ClientAlbumsAccess statement:
    {
      Sid    = "DynamoDBAccess"
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ]
      Resource = [
        aws_dynamodb_table.album.arn,
        aws_dynamodb_table.user.arn,
        aws_dynamodb_table.user_album.arn,
        "${aws_dynamodb_table.user_album.arn}/index/*"
      ]
    }
```

#### 3. Add Lambda Environment Variables

**File**: `terraform/lambda.tf`
**Location**: Update `aws_lambda_function.client_portal` environment block (around line 126)

```hcl
environment {
  variables = {
    CLIENT_ALBUMS_BUCKET   = aws_s3_bucket.client_albums.id
    COGNITO_USER_POOL_ID   = aws_cognito_user_pool.clients.id
    COGNITO_CLIENT_ID      = aws_cognito_user_pool_client.web.id
    AWS_REGION_NAME        = "us-east-2"
    PRESIGNED_URL_EXPIRY   = "3600"      # 1 hour for photo browsing
    ZIP_URL_EXPIRY         = "21600"     # 6 hours for ZIP downloads
    ALBUM_TABLE_NAME       = aws_dynamodb_table.album.name
    USER_TABLE_NAME        = aws_dynamodb_table.user.name
    USER_ALBUM_TABLE_NAME  = aws_dynamodb_table.user_album.name
  }
}
```

**Location**: Update `aws_lambda_function.admin_api` environment block (around line 157)

```hcl
environment {
  variables = {
    CLIENT_ALBUMS_BUCKET   = aws_s3_bucket.client_albums.id
    COGNITO_USER_POOL_ID   = aws_cognito_user_pool.clients.id
    ADMIN_EMAIL            = var.admin_email
    ALBUM_TABLE_NAME       = aws_dynamodb_table.album.name
    USER_TABLE_NAME        = aws_dynamodb_table.user.name
    USER_ALBUM_TABLE_NAME  = aws_dynamodb_table.user_album.name
  }
}
```

### Success Criteria:

#### Automated Verification:

- [ ] `terraform plan` shows three DynamoDB tables creation (Album, User, User_Album)
- [ ] `terraform plan` shows IAM policy updates
- [ ] `terraform plan` shows Lambda environment variable updates
- [ ] `terraform apply` completes successfully

#### Manual Verification:

- [ ] All three DynamoDB tables visible in AWS Console
- [ ] User_Album table has GSI on email
- [ ] Point-in-time recovery enabled on all tables

**Implementation Note**: After completing this phase, run `terraform apply` and verify the tables exist before proceeding.

---

## Phase 2: S3 Structure Updates

### Overview

Update S3 bucket configuration for new album structure and add lifecycle rules for ZIP cleanup.

### Changes Required:

#### 1. Add S3 Lifecycle Rule for ZIP Cleanup

**File**: `terraform/s3.tf`
**Location**: Add to `aws_s3_bucket_lifecycle_configuration.client_albums` (after line 119)

```hcl
  # Add this rule to the existing lifecycle configuration:
  rule {
    id     = "delete-old-zips"
    status = "Enabled"

    filter {
      prefix = "zips/"
    }

    expiration {
      days = 30  # Auto-delete ZIPs after 30 days
    }
  }
```

#### 2. Document New S3 Structure

The new structure will be:

```
s3://katelynns-photography-client-albums/
  albums/
    {album-id}/
      metadata.json       # OPTIONAL - for Lightroom workflow
      photos/
        IMG_001.jpg
        IMG_002.jpg
        ...
  zips/
    {album-id}.zip        # Generated on first download request
```

**metadata.json format (optional):**

```json
{
  "name": "Smith Wedding 2026",
  "event_date": "2026-01-15",
  "shoot_type": "wedding",
  "location": "Denver, CO",
  "notes": "Outdoor ceremony at Red Rocks"
}
```

**Notes:**

- Album IDs should be URL-safe slugs (e.g., `smith-wedding-2026`)
- Photos go under `photos/` subdirectory
- `metadata.json` is optional - used as input during registration
- ZIPs stored in separate `zips/` prefix for lifecycle management
- DynamoDB is authoritative for all runtime queries

### Success Criteria:

#### Automated Verification:

- [ ] `terraform plan` shows lifecycle rule addition
- [ ] `terraform apply` completes successfully

#### Manual Verification:

- [ ] Lifecycle rule visible in S3 Console
- [ ] Test upload to new structure works: `aws s3 cp test.jpg s3://bucket/albums/test-album/photos/`

---

## Phase 3: Backend DynamoDB Service

### Overview

Create a new DynamoDB service class for Album, User, and User_Album operations using the three-table design.

### Changes Required:

#### 1. Create DynamoDB Service

**File**: `backend/client_portal/app/services/dynamodb.py` (NEW FILE)

```python
"""
DynamoDB Service

Handles Album, User, and User_Album operations.
Uses three-table design optimized for small scale (<500 albums).
Table names are singular: Album, User, User_Album.
"""
import os
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
import boto3
from botocore.exceptions import ClientError


class DynamoDBService:
    """Service for DynamoDB operations."""

    def __init__(self):
        self.region = os.environ.get("AWS_REGION_NAME", "us-east-2")
        self.album_table_name = os.environ.get(
            "ALBUM_TABLE_NAME", "katelynns-photography-album"
        )
        self.user_table_name = os.environ.get(
            "USER_TABLE_NAME", "katelynns-photography-user"
        )
        self.user_album_table_name = os.environ.get(
            "USER_ALBUM_TABLE_NAME", "katelynns-photography-user-album"
        )

        self.dynamodb = boto3.resource("dynamodb", region_name=self.region)
        self.album_table = self.dynamodb.Table(self.album_table_name)
        self.user_table = self.dynamodb.Table(self.user_table_name)
        self.user_album_table = self.dynamodb.Table(self.user_album_table_name)

    # ==================== Album Operations ====================

    def create_album(
        self,
        album_id: str,
        name: str,
        event_date: Optional[str] = None,
        photo_count: int = 0,
        created_by: Optional[str] = None,
        **extra_fields
    ) -> Dict[str, Any]:
        """
        Create album metadata record.

        Args:
            album_id: Unique album identifier (URL-safe slug)
            name: Human-readable album name
            event_date: Event date (ISO format, e.g., "2026-01-15")
            photo_count: Number of photos in album
            created_by: Admin email who created the album
            **extra_fields: Any additional fields (shoot_type, location, notes, etc.)
        """
        now = datetime.now(timezone.utc).isoformat()

        item = {
            "album_id": album_id,
            "name": name,
            "event_date": event_date,
            "photo_count": photo_count,
            "created_at": now,
            "created_by": created_by,
            "zip_generated_at": None,
            **extra_fields  # Allow arbitrary additional fields
        }

        # Remove None values
        item = {k: v for k, v in item.items() if v is not None}

        self.album_table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(album_id)"  # Prevent overwrite
        )

        return item

    def get_album(self, album_id: str) -> Optional[Dict[str, Any]]:
        """Get album metadata by ID."""
        try:
            response = self.album_table.get_item(Key={"album_id": album_id})
            return response.get("Item")
        except ClientError:
            return None

    def update_album(self, album_id: str, **fields) -> None:
        """
        Update album fields.

        Example: update_album("smith-wed", photo_count=250, location="Denver")
        """
        if not fields:
            return

        update_expr_parts = []
        expr_attr_values = {}

        for key, value in fields.items():
            update_expr_parts.append(f"{key} = :{key}")
            expr_attr_values[f":{key}"] = value

        self.album_table.update_item(
            Key={"album_id": album_id},
            UpdateExpression="SET " + ", ".join(update_expr_parts),
            ExpressionAttributeValues=expr_attr_values
        )

    def list_all_albums(self) -> List[Dict[str, Any]]:
        """
        List all albums (admin use).

        Note: Uses Scan - acceptable at expected scale (<500 albums).
        """
        response = self.album_table.scan()
        items = response.get("Items", [])

        # Handle pagination for larger tables
        while "LastEvaluatedKey" in response:
            response = self.album_table.scan(
                ExclusiveStartKey=response["LastEvaluatedKey"]
            )
            items.extend(response.get("Items", []))

        return items

    def query_albums(self, **filters) -> List[Dict[str, Any]]:
        """
        Query albums with filters.

        Example: query_albums(shoot_type="wedding", event_date__begins_with="2026")

        Note: Uses Scan with FilterExpression - acceptable at this scale.
        """
        filter_parts = []
        expr_attr_values = {}
        expr_attr_names = {}

        for key, value in filters.items():
            if "__begins_with" in key:
                attr = key.replace("__begins_with", "")
                filter_parts.append(f"begins_with(#{attr}, :{attr})")
                expr_attr_names[f"#{attr}"] = attr
                expr_attr_values[f":{attr}"] = value
            else:
                filter_parts.append(f"#{key} = :{key}")
                expr_attr_names[f"#{key}"] = key
                expr_attr_values[f":{key}"] = value

        scan_kwargs = {}
        if filter_parts:
            scan_kwargs["FilterExpression"] = " AND ".join(filter_parts)
            scan_kwargs["ExpressionAttributeValues"] = expr_attr_values
            scan_kwargs["ExpressionAttributeNames"] = expr_attr_names

        response = self.album_table.scan(**scan_kwargs)
        return response.get("Items", [])

    def delete_album(self, album_id: str) -> bool:
        """Delete an album (admin use)."""
        try:
            self.album_table.delete_item(Key={"album_id": album_id})
            return True
        except ClientError:
            return False

    # ==================== User Operations ====================

    def create_user(
        self,
        email: str,
        first_name: Optional[str] = None,
        last_name: Optional[str] = None,
        phone: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Create or update user record.

        Args:
            email: User's email address (primary key)
            first_name: User's first name
            last_name: User's last name
            phone: User's phone number
        """
        now = datetime.now(timezone.utc).isoformat()
        email_lower = email.lower()

        item = {
            "email": email_lower,
            "first_name": first_name,
            "last_name": last_name,
            "phone": phone,
            "created_at": now,
        }

        # Remove None values
        item = {k: v for k, v in item.items() if v is not None}

        self.user_table.put_item(Item=item)
        return item

    def get_user(self, email: str) -> Optional[Dict[str, Any]]:
        """Get user by email."""
        email_lower = email.lower()
        try:
            response = self.user_table.get_item(Key={"email": email_lower})
            return response.get("Item")
        except ClientError:
            return None

    def update_user(self, email: str, **fields) -> None:
        """
        Update user fields.

        Example: update_user("john@example.com", phone="303-555-1234")
        """
        if not fields:
            return

        email_lower = email.lower()
        update_expr_parts = []
        expr_attr_values = {}

        for key, value in fields.items():
            update_expr_parts.append(f"{key} = :{key}")
            expr_attr_values[f":{key}"] = value

        self.user_table.update_item(
            Key={"email": email_lower},
            UpdateExpression="SET " + ", ".join(update_expr_parts),
            ExpressionAttributeValues=expr_attr_values
        )

    def list_all_users(self) -> List[Dict[str, Any]]:
        """List all users (admin use)."""
        response = self.user_table.scan()
        items = response.get("Items", [])

        while "LastEvaluatedKey" in response:
            response = self.user_table.scan(
                ExclusiveStartKey=response["LastEvaluatedKey"]
            )
            items.extend(response.get("Items", []))

        return items

    def get_or_create_user(
        self,
        email: str,
        first_name: Optional[str] = None,
        last_name: Optional[str] = None,
        phone: Optional[str] = None
    ) -> Dict[str, Any]:
        """Get existing user or create new one."""
        existing = self.get_user(email)
        if existing:
            return existing
        return self.create_user(email, first_name, last_name, phone)

    # ==================== User_Album (Assignment) Operations ====================

    def assign_album_to_user(
        self,
        album_id: str,
        email: str,
        expires_at: str
    ) -> Dict[str, Any]:
        """
        Assign an album to a user with expiration.

        Args:
            album_id: Album to assign
            email: User's email address
            expires_at: Expiration datetime (ISO format)
        """
        now = datetime.now(timezone.utc).isoformat()
        email_lower = email.lower()

        item = {
            "album_id": album_id,
            "email": email_lower,
            "assigned_at": now,
            "expires_at": expires_at,
        }

        self.user_album_table.put_item(Item=item)
        return item

    def get_user_album(
        self, album_id: str, email: str
    ) -> Optional[Dict[str, Any]]:
        """Get a specific user-album assignment."""
        email_lower = email.lower()
        try:
            response = self.user_album_table.get_item(
                Key={"album_id": album_id, "email": email_lower}
            )
            return response.get("Item")
        except ClientError:
            return None

    def list_user_albums(self, email: str) -> List[Dict[str, Any]]:
        """
        List all albums assigned to a user.

        Uses GSI for efficient query.
        Returns assignment records (call get_album() for full metadata).
        """
        email_lower = email.lower()

        response = self.user_album_table.query(
            IndexName="email-index",
            KeyConditionExpression="email = :email",
            ExpressionAttributeValues={":email": email_lower}
        )

        return response.get("Items", [])

    def list_album_users(self, album_id: str) -> List[Dict[str, Any]]:
        """List all users assigned to an album."""
        response = self.user_album_table.query(
            KeyConditionExpression="album_id = :id",
            ExpressionAttributeValues={":id": album_id}
        )
        return response.get("Items", [])

    def revoke_user_album(self, album_id: str, email: str) -> bool:
        """Remove a user's access to an album."""
        email_lower = email.lower()
        try:
            self.user_album_table.delete_item(
                Key={"album_id": album_id, "email": email_lower}
            )
            return True
        except ClientError:
            return False

    # ==================== Access Validation ====================

    def check_user_access(
        self, album_id: str, email: str
    ) -> tuple[bool, Optional[str], Optional[str]]:
        """
        Check if a user has valid (non-expired) access to an album.

        Returns:
            (has_access, expires_at, error_message)
        """
        assignment = self.get_user_album(album_id, email)

        if not assignment:
            return (False, None, "Album not found or not assigned to you")

        expires_at = assignment.get("expires_at")
        if expires_at:
            expiry_dt = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
            if datetime.now(timezone.utc) > expiry_dt:
                return (False, expires_at, "Album access has expired")

        return (True, expires_at, None)
```

#### 2. Update Models

**File**: `backend/client_portal/app/models.py`
**Changes**: Add new models for assignments and update Album model

```python
"""
Data Models

Pydantic models for request/response validation.
"""
from typing import Optional, List, Dict, Any
from pydantic import BaseModel


class Album(BaseModel):
    """Album information."""
    id: str
    name: str
    photo_count: int
    created_at: Optional[str] = None
    event_date: Optional[str] = None
    expires_at: Optional[str] = None      # Per-client expiration (from assignment)
    # Additional fields can be added dynamically


class AlbumListResponse(BaseModel):
    """Response for album list endpoint."""
    albums: List[Album]
    total: int


class AlbumFile(BaseModel):
    """File information with download URL."""
    name: str
    size: int
    last_modified: str
    download_url: str


class DownloadResponse(BaseModel):
    """Response for download URL endpoint."""
    album_id: str
    download_url: str
    expires_in: int
    file_count: int


class User(BaseModel):
    """User information."""
    email: str
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone: Optional[str] = None
    created_at: Optional[str] = None


class UserAlbum(BaseModel):
    """User-album assignment record."""
    album_id: str
    email: str
    assigned_at: str
    expires_at: str


# ==================== Admin Request Models ====================

class CreateAlbumRequest(BaseModel):
    """Request to create/register a new album."""
    album_id: str                          # URL-safe slug
    name: Optional[str] = None             # If not provided, read from metadata.json
    event_date: Optional[str] = None
    shoot_type: Optional[str] = None       # wedding, portrait, event, etc.
    location: Optional[str] = None
    notes: Optional[str] = None


class AssignAlbumRequest(BaseModel):
    """Request to assign album to a user."""
    email: str
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone: Optional[str] = None
    expires_at: Optional[str] = None       # ISO datetime
    expires_in_days: Optional[int] = None  # Alternative: days from now
    create_cognito_user: bool = False      # Create Cognito user if doesn't exist
```

### Success Criteria:

#### Automated Verification:

- [ ] Python syntax valid (no import errors)
- [ ] Models can be instantiated
- [ ] DynamoDB service methods don't raise on import

#### Manual Verification:

- [ ] N/A - tested in Phase 4

---

## Phase 4: Update Album Routes with Database Access

### Overview

Rewrite the album routes to use DynamoDB for access control and expiration checking.

### Changes Required:

#### 1. Update S3 Service for New Structure

**File**: `backend/client_portal/app/services/s3.py`
**Changes**: Modify to work with new S3 structure, add 6-hour ZIP URL expiry

Replace the entire file with:

```python
"""
S3 Service

Handles S3 operations for client albums including listing and presigned URL generation.
Updated for multi-client album structure.
"""
import os
import io
import json
import zipfile
from typing import Optional, Tuple, List, Dict, Any
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError


class S3Service:
    """Service for S3 album operations."""

    def __init__(self):
        self.bucket = os.environ.get(
            "CLIENT_ALBUMS_BUCKET", "katelynns-photography-client-albums"
        )
        self.region = os.environ.get("AWS_REGION_NAME", "us-east-2")

        # Different expiry times for different use cases
        self.photo_url_expiry = int(os.environ.get("PRESIGNED_URL_EXPIRY", "3600"))  # 1 hour
        self.zip_url_expiry = int(os.environ.get("ZIP_URL_EXPIRY", "21600"))  # 6 hours

        self.s3_client = boto3.client(
            "s3",
            region_name=self.region,
            config=Config(s3={"addressing_style": "virtual"})
        )

    def _get_album_prefix(self, album_id: str) -> str:
        """Get S3 prefix for album photos."""
        return f"albums/{album_id}/photos/"

    def _get_metadata_key(self, album_id: str) -> str:
        """Get S3 key for album metadata.json."""
        return f"albums/{album_id}/metadata.json"

    def _get_zip_key(self, album_id: str) -> str:
        """Get S3 key for album ZIP file."""
        return f"zips/{album_id}.zip"

    # ==================== Metadata Operations ====================

    def get_metadata_json(self, album_id: str) -> Optional[Dict[str, Any]]:
        """
        Read metadata.json from S3 if it exists.

        Used during album registration to auto-populate fields.
        Returns None if file doesn't exist.
        """
        key = self._get_metadata_key(album_id)
        try:
            response = self.s3_client.get_object(Bucket=self.bucket, Key=key)
            content = response["Body"].read().decode("utf-8")
            return json.loads(content)
        except ClientError as e:
            if e.response["Error"]["Code"] == "NoSuchKey":
                return None
            raise
        except json.JSONDecodeError:
            return None

    # ==================== Photo Operations ====================

    def count_album_photos(self, album_id: str) -> int:
        """Count photos in an album."""
        prefix = self._get_album_prefix(album_id)
        count = 0
        paginator = self.s3_client.get_paginator("list_objects_v2")

        for page in paginator.paginate(Bucket=self.bucket, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                if not key.endswith("/") and not key.endswith(".keep"):
                    count += 1

        return count

    def album_exists_in_s3(self, album_id: str) -> bool:
        """Check if album has any photos in S3."""
        prefix = self._get_album_prefix(album_id)
        response = self.s3_client.list_objects_v2(
            Bucket=self.bucket,
            Prefix=prefix,
            MaxKeys=1
        )
        return len(response.get("Contents", [])) > 0

    def list_album_files(self, album_id: str) -> List[Dict[str, Any]]:
        """List all files in an album with presigned URLs (1-hour expiry)."""
        prefix = self._get_album_prefix(album_id)
        files = []

        paginator = self.s3_client.get_paginator("list_objects_v2")

        for page in paginator.paginate(Bucket=self.bucket, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                if key.endswith("/"):
                    continue

                file_name = key.split("/")[-1]
                if file_name == ".keep":
                    continue

                url = self.s3_client.generate_presigned_url(
                    "get_object",
                    Params={"Bucket": self.bucket, "Key": key},
                    ExpiresIn=self.photo_url_expiry
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
        album_id: str,
        file_name: str
    ) -> Tuple[str, int]:
        """Generate presigned URL for a specific photo (1-hour expiry)."""
        key = f"{self._get_album_prefix(album_id)}{file_name}"

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
            ExpiresIn=self.photo_url_expiry
        )

        return url, self.photo_url_expiry

    # ==================== ZIP Operations ====================

    def zip_exists(self, album_id: str) -> bool:
        """Check if ZIP file already exists."""
        key = self._get_zip_key(album_id)
        try:
            self.s3_client.head_object(Bucket=self.bucket, Key=key)
            return True
        except ClientError:
            return False

    def generate_zip(self, album_id: str) -> str:
        """
        Generate ZIP file for album and upload to S3.

        WARNING: May timeout for albums >500 photos or >5GB.
        Returns the S3 key of the generated ZIP.
        """
        prefix = self._get_album_prefix(album_id)
        zip_key = self._get_zip_key(album_id)

        # Create ZIP in memory
        zip_buffer = io.BytesIO()

        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
            paginator = self.s3_client.get_paginator("list_objects_v2")

            for page in paginator.paginate(Bucket=self.bucket, Prefix=prefix):
                for obj in page.get("Contents", []):
                    key = obj["Key"]
                    if key.endswith("/") or key.endswith(".keep"):
                        continue

                    file_name = key.split("/")[-1]

                    # Download file content
                    response = self.s3_client.get_object(Bucket=self.bucket, Key=key)
                    file_content = response["Body"].read()

                    # Add to ZIP
                    zf.writestr(file_name, file_content)

        # Upload ZIP to S3
        zip_buffer.seek(0)
        self.s3_client.put_object(
            Bucket=self.bucket,
            Key=zip_key,
            Body=zip_buffer.getvalue(),
            ContentType="application/zip"
        )

        return zip_key

    def get_zip_download_url(self, album_id: str) -> Tuple[str, int]:
        """Get presigned URL for ZIP download (6-hour expiry for large downloads)."""
        zip_key = self._get_zip_key(album_id)

        url = self.s3_client.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": self.bucket,
                "Key": zip_key,
                "ResponseContentDisposition": f'attachment; filename="{album_id}.zip"'
            },
            ExpiresIn=self.zip_url_expiry  # 6 hours for large downloads
        )

        return url, self.zip_url_expiry
```

#### 2. Update Album Routes

**File**: `backend/client_portal/app/routes/albums.py`
**Changes**: Use DynamoDB for access control, add expiration checking

Replace entire file with:

```python
"""
Albums Router

Handles album listing and download URL generation.
Updated for multi-client album assignments with expiration.
"""
from typing import Optional
from fastapi import APIRouter, HTTPException, Depends, Path, Query

from ..models import Album, AlbumListResponse, DownloadResponse
from ..services.cognito import get_current_user
from ..services.s3 import S3Service
from ..services.dynamodb import DynamoDBService

router = APIRouter()
s3_service = S3Service()
db_service = DynamoDBService()


def _check_album_access(album_id: str, user_email: str) -> dict:
    """
    Check if user has valid access to album.
    Raises HTTPException if access denied.
    Returns assignment info if valid.
    """
    has_access, expires_at, error = db_service.check_user_access(album_id, user_email)

    if not has_access:
        if "expired" in (error or "").lower():
            raise HTTPException(status_code=403, detail=error)
        raise HTTPException(status_code=404, detail="Album not found")

    return {"expires_at": expires_at}


@router.get("/albums", response_model=AlbumListResponse)
async def list_albums(user: dict = Depends(get_current_user)):
    """
    List all albums assigned to the authenticated user.

    Only returns non-expired albums (expired albums are hidden).
    """
    user_email = user.get("email")
    if not user_email:
        raise HTTPException(status_code=401, detail="User email not found in token")

    try:
        # Get all assignments for this user (uses GSI - fast)
        assignments = db_service.list_user_albums(user_email)

        albums = []
        for assignment in assignments:
            album_id = assignment.get("album_id")
            expires_at = assignment.get("expires_at")

            # Check if expired (skip expired albums - don't show them)
            has_access, _, _ = db_service.check_user_access(album_id, user_email)
            if not has_access:
                continue

            # Get album metadata
            album_data = db_service.get_album(album_id)
            if not album_data:
                continue

            albums.append(Album(
                id=album_id,
                name=album_data.get("name", album_id),
                photo_count=album_data.get("photo_count", 0),
                created_at=album_data.get("created_at"),
                event_date=album_data.get("event_date"),
                expires_at=expires_at
            ))

        # Sort by event_date descending (most recent first)
        albums.sort(key=lambda a: a.event_date or "", reverse=True)

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

    # Check access (raises if denied)
    access_info = _check_album_access(album_id, user_email)

    try:
        album_data = db_service.get_album(album_id)
        if not album_data:
            raise HTTPException(status_code=404, detail="Album not found")

        return Album(
            id=album_id,
            name=album_data.get("name", album_id),
            photo_count=album_data.get("photo_count", 0),
            created_at=album_data.get("created_at"),
            event_date=album_data.get("event_date"),
            expires_at=access_info.get("expires_at")
        )
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
    Get presigned URL for downloading.

    If file_name is provided: returns 1-hour URL for that specific file.
    Otherwise: returns 6-hour URL for ZIP of all photos (generates if needed).
    """
    user_email = user.get("email")

    # Check access (raises if denied)
    _check_album_access(album_id, user_email)

    try:
        if file_name:
            # Single file download (1-hour URL)
            url, expires = s3_service.generate_presigned_url(album_id, file_name)
            file_count = 1
        else:
            # ZIP download (6-hour URL)
            # Generate ZIP if it doesn't exist
            if not s3_service.zip_exists(album_id):
                s3_service.generate_zip(album_id)
                db_service.update_album(album_id, zip_generated_at=__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat())

            url, expires = s3_service.get_zip_download_url(album_id)

            # Get file count from album metadata
            album_data = db_service.get_album(album_id)
            file_count = album_data.get("photo_count", 0) if album_data else 0

        return DownloadResponse(
            album_id=album_id,
            download_url=url,
            expires_in=expires,
            file_count=file_count
        )
    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
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

    # Check access (raises if denied)
    access_info = _check_album_access(album_id, user_email)

    try:
        files = s3_service.list_album_files(album_id)
        return {
            "album_id": album_id,
            "files": files,
            "total": len(files),
            "expires_at": access_info.get("expires_at")
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error listing files for {album_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to list album files")
```

### Success Criteria:

#### Automated Verification:

- [ ] Python syntax valid
- [ ] Lambda package can be built: `cd backend/client_portal && pip install -r requirements.txt`

#### Manual Verification:

- [ ] API returns 404 for album not assigned to user
- [ ] API returns 403 for expired album
- [ ] API returns album list with expiration dates
- [ ] ZIP is generated on first download request
- [ ] Photo URLs expire in 1 hour
- [ ] ZIP URLs expire in 6 hours

**Implementation Note**: After completing this phase, deploy Lambda and test with manually created DynamoDB records before proceeding.

---

## Phase 5: Admin API Updates

### Overview

Add endpoints for registering albums (with metadata.json support) and assigning them to clients.

### Changes Required:

#### 1. Update Admin API Handler

**File**: `backend/admin_api/handler.py`
**Changes**: Add album registration and assignment endpoints with metadata.json support

Add these imports at the top:

```python
from datetime import datetime, timezone, timedelta
import json
```

Add environment variables:

```python
ALBUM_TABLE_NAME = os.environ.get("ALBUM_TABLE_NAME", "katelynns-photography-album")
USER_TABLE_NAME = os.environ.get("USER_TABLE_NAME", "katelynns-photography-user")
USER_ALBUM_TABLE_NAME = os.environ.get("USER_ALBUM_TABLE_NAME", "katelynns-photography-user-album")
```

Add DynamoDB setup (after s3_client):

```python
dynamodb = boto3.resource("dynamodb", region_name="us-east-2")
album_table = dynamodb.Table(ALBUM_TABLE_NAME)
user_table = dynamodb.Table(USER_TABLE_NAME)
user_album_table = dynamodb.Table(USER_ALBUM_TABLE_NAME)
```

Add to `lambda_handler` route handling:

```python
    # Album management routes
    if http_method == "POST" and path == "/admin/albums":
        return register_album(event)

    if http_method == "GET" and path == "/admin/albums":
        return list_all_albums(event)

    if http_method == "POST" and path.startswith("/admin/albums/") and path.endswith("/assign"):
        album_id = path.split("/")[3]  # /admin/albums/{album_id}/assign
        return assign_album(event, album_id)

    if http_method == "GET" and path.startswith("/admin/albums/") and path.endswith("/users"):
        album_id = path.split("/")[3]
        return list_album_users(event, album_id)

    if http_method == "DELETE" and "/assign/" in path:
        # /admin/albums/{album_id}/assign/{email}
        parts = path.split("/")
        album_id = parts[3]
        email = parts[5]
        return revoke_user_album(event, album_id, email)
```

Add these new functions:

```python
def _read_metadata_json(album_id: str) -> dict:
    """Read metadata.json from S3 if it exists."""
    key = f"albums/{album_id}/metadata.json"
    try:
        response = s3_client.get_object(Bucket=CLIENT_ALBUMS_BUCKET, Key=key)
        content = response["Body"].read().decode("utf-8")
        return json.loads(content)
    except ClientError as e:
        if e.response["Error"]["Code"] == "NoSuchKey":
            return {}
        raise
    except json.JSONDecodeError:
        return {}


def register_album(event):
    """
    Register a new album in DynamoDB.

    If metadata.json exists in S3, uses it for defaults.
    API parameters override metadata.json values.

    Assumes photos have already been uploaded to S3 at:
    albums/{album_id}/photos/

    Request body:
    {
        "album_id": "smith-wedding-2026",
        "name": "Smith Wedding 2026",      // Optional if metadata.json exists
        "event_date": "2026-01-15",        // Optional
        "shoot_type": "wedding",           // Optional
        "location": "Denver, CO",          // Optional
        "notes": "Outdoor ceremony"        // Optional
    }
    """
    if not is_admin(event):
        return error_response(403, "Admin access required")

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON body")

    album_id = body.get("album_id", "").strip()

    if not album_id:
        return error_response(400, "album_id is required")

    # Validate album_id format (URL-safe slug)
    if not re.match(r"^[a-z0-9][a-z0-9-]*[a-z0-9]$", album_id) or len(album_id) > 100:
        return error_response(400, "album_id must be a URL-safe slug (lowercase, hyphens, 2-100 chars)")

    # Check if album already exists
    existing = album_table.get_item(Key={"album_id": album_id}).get("Item")
    if existing:
        return error_response(409, f"Album '{album_id}' already exists")

    # Read metadata.json from S3 (if exists) as defaults
    s3_metadata = _read_metadata_json(album_id)

    # API params override metadata.json
    name = body.get("name") or s3_metadata.get("name") or album_id.replace("-", " ").title()
    event_date = body.get("event_date") or s3_metadata.get("event_date")
    shoot_type = body.get("shoot_type") or s3_metadata.get("shoot_type")
    location = body.get("location") or s3_metadata.get("location")
    notes = body.get("notes") or s3_metadata.get("notes")

    # Count photos in S3
    prefix = f"albums/{album_id}/photos/"
    photo_count = 0
    paginator = s3_client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=CLIENT_ALBUMS_BUCKET, Prefix=prefix):
        for obj in page.get("Contents", []):
            if not obj["Key"].endswith("/") and not obj["Key"].endswith(".keep"):
                photo_count += 1

    if photo_count == 0:
        return error_response(400, f"No photos found at s3://{CLIENT_ALBUMS_BUCKET}/{prefix}")

    # Get admin email from token
    claims = event.get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {})
    admin_email = claims.get("email", "unknown")

    now = datetime.now(timezone.utc).isoformat()

    # Create album record
    item = {
        "album_id": album_id,
        "name": name,
        "photo_count": photo_count,
        "created_at": now,
        "created_by": admin_email,
        "zip_generated_at": None,
    }

    # Add optional fields if provided
    if event_date:
        item["event_date"] = event_date
    if shoot_type:
        item["shoot_type"] = shoot_type
    if location:
        item["location"] = location
    if notes:
        item["notes"] = notes

    album_table.put_item(Item=item)

    return {
        "statusCode": 201,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({
            "message": "Album registered",
            "album": item,
            "metadata_json_found": bool(s3_metadata)
        })
    }


def list_all_albums(event):
    """List all albums (admin use)."""
    if not is_admin(event):
        return error_response(403, "Admin access required")

    response = album_table.scan()
    albums = response.get("Items", [])

    # Sort by created_at descending
    albums.sort(key=lambda a: a.get("created_at", ""), reverse=True)

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({
            "albums": albums,
            "total": len(albums)
        })
    }


def assign_album(event, album_id: str):
    """
    Assign an album to a user.

    Request body:
    {
        "email": "john.doe@example.com",
        "first_name": "John",                  // Optional
        "last_name": "Doe",                    // Optional
        "phone": "303-555-1234",               // Optional
        "expires_at": "2026-07-15T00:00:00Z",  // OR
        "expires_in_days": 180,
        "create_cognito_user": true            // Optional: create Cognito user
    }
    """
    if not is_admin(event):
        return error_response(403, "Admin access required")

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON body")

    email = body.get("email", "").strip().lower()
    first_name = body.get("first_name", "").strip() or None
    last_name = body.get("last_name", "").strip() or None
    phone = body.get("phone", "").strip() or None
    expires_at = body.get("expires_at")
    expires_in_days = body.get("expires_in_days")
    create_cognito_user = body.get("create_cognito_user", False)

    if not email:
        return error_response(400, "email is required")

    # Validate email format
    if not re.match(r"^[^@]+@[^@]+\.[^@]+$", email):
        return error_response(400, "Invalid email format")

    # Check album exists
    album = album_table.get_item(Key={"album_id": album_id}).get("Item")
    if not album:
        return error_response(404, f"Album '{album_id}' not found. Register it first with POST /admin/albums")

    # Calculate expiration
    if expires_at:
        try:
            datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
        except ValueError:
            return error_response(400, "Invalid expires_at format (use ISO 8601)")
    elif expires_in_days:
        expires_dt = datetime.now(timezone.utc) + timedelta(days=int(expires_in_days))
        expires_at = expires_dt.isoformat()
    else:
        return error_response(400, "Either expires_at or expires_in_days is required")

    now = datetime.now(timezone.utc).isoformat()

    # Create or update User record in DynamoDB
    existing_user = user_table.get_item(Key={"email": email}).get("Item")
    if not existing_user:
        user_item = {
            "email": email,
            "created_at": now,
        }
        if first_name:
            user_item["first_name"] = first_name
        if last_name:
            user_item["last_name"] = last_name
        if phone:
            user_item["phone"] = phone
        user_table.put_item(Item=user_item)
    elif first_name or last_name or phone:
        # Update existing user if new info provided
        update_parts = []
        expr_values = {}
        if first_name:
            update_parts.append("first_name = :fn")
            expr_values[":fn"] = first_name
        if last_name:
            update_parts.append("last_name = :ln")
            expr_values[":ln"] = last_name
        if phone:
            update_parts.append("phone = :ph")
            expr_values[":ph"] = phone
        if update_parts:
            user_table.update_item(
                Key={"email": email},
                UpdateExpression="SET " + ", ".join(update_parts),
                ExpressionAttributeValues=expr_values
            )

    # Create Cognito user if requested
    if create_cognito_user:
        try:
            user_attrs = [
                {"Name": "email", "Value": email},
                {"Name": "email_verified", "Value": "true"}
            ]
            if first_name:
                user_attrs.append({"Name": "given_name", "Value": first_name})
            if last_name:
                user_attrs.append({"Name": "family_name", "Value": last_name})
            if phone:
                user_attrs.append({"Name": "phone_number", "Value": phone})

            cognito_client.admin_create_user(
                UserPoolId=COGNITO_USER_POOL_ID,
                Username=email,
                UserAttributes=user_attrs,
                DesiredDeliveryMediums=["EMAIL"]
            )
        except cognito_client.exceptions.UsernameExistsException:
            pass  # User already exists
        except Exception as e:
            print(f"Error creating Cognito user: {e}")
            # Continue anyway - DynamoDB user was created

    # Create User_Album assignment record
    assignment_item = {
        "album_id": album_id,
        "email": email,
        "assigned_at": now,
        "expires_at": expires_at,
    }

    user_album_table.put_item(Item=assignment_item)

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({
            "message": "Album assigned to user",
            "assignment": assignment_item
        })
    }


def list_album_users(event, album_id: str):
    """List all users assigned to an album."""
    if not is_admin(event):
        return error_response(403, "Admin access required")

    response = user_album_table.query(
        KeyConditionExpression="album_id = :id",
        ExpressionAttributeValues={":id": album_id}
    )

    assignments = response.get("Items", [])

    # Enrich with user info
    enriched = []
    for assignment in assignments:
        user = user_table.get_item(Key={"email": assignment["email"]}).get("Item", {})
        enriched.append({
            **assignment,
            "first_name": user.get("first_name"),
            "last_name": user.get("last_name"),
            "phone": user.get("phone"),
        })

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({
            "album_id": album_id,
            "users": enriched,
            "total": len(enriched)
        })
    }


def revoke_user_album(event, album_id: str, email: str):
    """Remove a user's access to an album."""
    if not is_admin(event):
        return error_response(403, "Admin access required")

    email = email.lower()

    user_album_table.delete_item(
        Key={"album_id": album_id, "email": email}
    )

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({
            "message": "Access revoked",
            "album_id": album_id,
            "email": email
        })
    }
```

#### 2. Add API Gateway Routes for Admin Endpoints

**File**: `terraform/lambda.tf`
**Location**: Add after existing admin routes (around line 290)

```hcl
# Admin - List all albums
resource "aws_apigatewayv2_route" "admin_albums_list" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /admin/albums"
  target             = "integrations/${aws_apigatewayv2_integration.admin_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Admin - Assign album to user
resource "aws_apigatewayv2_route" "admin_album_assign" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /admin/albums/{album_id}/assign"
  target             = "integrations/${aws_apigatewayv2_integration.admin_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Admin - List album users
resource "aws_apigatewayv2_route" "admin_album_users" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /admin/albums/{album_id}/users"
  target             = "integrations/${aws_apigatewayv2_integration.admin_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Admin - Revoke user album access
resource "aws_apigatewayv2_route" "admin_album_revoke" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "DELETE /admin/albums/{album_id}/assign/{email}"
  target             = "integrations/${aws_apigatewayv2_integration.admin_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}
```

### Success Criteria:

#### Automated Verification:

- [ ] `terraform plan` shows new API routes
- [ ] Lambda deploy succeeds
- [ ] Python syntax valid

#### Manual Verification:

- [ ] `POST /admin/albums` registers album (reads metadata.json if present)
- [ ] `GET /admin/albums` lists all albums
- [ ] `POST /admin/albums/{id}/assign` creates User record and User_Album assignment
- [ ] `GET /admin/albums/{id}/users` lists users with enriched info (name, phone)
- [ ] `DELETE /admin/albums/{id}/assign/{email}` removes User_Album record

**Implementation Note**: After this phase, you can test the full admin workflow. Create test data before testing client portal.

---

## Phase 6: Frontend Updates

### Overview

Update the client portal frontend to display expiration dates and add ZIP download button.

### Changes Required:

#### 1. Update API Types

**File**: `frontend/src/lib/api.ts`
**Changes**: Add expires_at to Album interface, add ZIP download function

Update the Album interface:

```typescript
export interface Album {
  id: string;
  name: string;
  photo_count: number;
  created_at: string | null;
  event_date?: string | null;
  expires_at?: string | null;
}
```

Add new function for ZIP download:

```typescript
/**
 * Get download URL for album ZIP (6-hour expiry)
 */
export async function getAlbumZipUrl(albumId: string): Promise<{
  album_id: string;
  download_url: string;
  expires_in: number;
  file_count: number;
}> {
  return apiRequest(`/albums/${albumId}/download`);
}
```

#### 2. Update Dashboard with Expiration Display

**File**: `frontend/src/pages/client/dashboard.astro`
**Changes**: Show expiration date on album cards

In the `showAlbums` function, update the album card HTML:

```typescript
function showAlbums(albums: Album[]) {
  loadingEl.classList.add("hidden");
  errorEl.classList.add("hidden");
  emptyEl.classList.add("hidden");
  albumsGridEl.classList.remove("hidden");

  albumsGridEl.innerHTML = albums
    .map((album) => {
      const expiresAt = album.expires_at ? new Date(album.expires_at) : null;
      const now = new Date();
      const daysUntilExpiry = expiresAt
        ? Math.ceil(
            (expiresAt.getTime() - now.getTime()) / (1000 * 60 * 60 * 24),
          )
        : null;

      let expiryClass = "";
      let expiryText = "";

      if (daysUntilExpiry !== null) {
        if (daysUntilExpiry <= 0) {
          expiryClass = "bg-red-100 text-red-800";
          expiryText = "Expired";
        } else if (daysUntilExpiry <= 7) {
          expiryClass = "bg-yellow-100 text-yellow-800";
          expiryText = `Expires in ${daysUntilExpiry} day${daysUntilExpiry !== 1 ? "s" : ""}`;
        } else if (daysUntilExpiry <= 30) {
          expiryClass = "bg-blue-100 text-blue-800";
          expiryText = `Expires ${expiresAt.toLocaleDateString()}`;
        } else {
          expiryClass = "bg-green-100 text-green-800";
          expiryText = `Access until ${expiresAt.toLocaleDateString()}`;
        }
      }

      return `
      <a href="/client/albums/${album.id}" class="group">
        <div class="bg-white rounded-sm shadow-md overflow-hidden hover:shadow-lg transition-shadow">
          <div class="aspect-[4/3] bg-primary-100 flex items-center justify-center">
            <svg class="w-16 h-16 text-primary-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
          </div>
          <div class="p-4">
            <h2 class="font-serif text-lg text-primary-900 group-hover:text-accent transition-colors">
              ${album.name}
            </h2>
            <p class="text-sm text-primary-600 mt-1">
              ${album.photo_count} photo${album.photo_count !== 1 ? "s" : ""}
            </p>
            ${
              expiryText
                ? `
              <span class="inline-block mt-2 px-2 py-1 text-xs rounded ${expiryClass}">
                ${expiryText}
              </span>
            `
                : ""
            }
          </div>
        </div>
      </a>
    `;
    })
    .join("");
}
```

#### 3. Update Album Viewer with ZIP Download

**File**: `frontend/src/pages/client/albums/[...id].astro`
**Changes**: Add "Download All" button and expiration display

Add after the header section (around line 25):

```html
<!-- Download controls -->
<div class="flex items-center gap-4 mb-6">
  <button
    id="download-all-btn"
    class="bg-accent text-white px-4 py-2 rounded-sm hover:bg-accent-dark transition-colors flex items-center gap-2"
  >
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
      />
    </svg>
    <span id="download-btn-text">Download All</span>
  </button>

  <span id="expiry-badge" class="hidden px-3 py-1 text-sm rounded"></span>
</div>
```

Add to the script section:

```typescript
import { getAlbumZipUrl } from "../../../lib/api";

const downloadAllBtn = document.getElementById(
  "download-all-btn",
) as HTMLButtonElement;
const downloadBtnText = document.getElementById(
  "download-btn-text",
) as HTMLSpanElement;
const expiryBadge = document.getElementById("expiry-badge") as HTMLSpanElement;

// Update showPhotos to also show expiry badge
function showPhotos(album: Album, files: AlbumFile[]) {
  // ... existing photo display code ...

  // Show expiry badge
  if (album.expires_at) {
    const expiresAt = new Date(album.expires_at);
    const now = new Date();
    const daysUntilExpiry = Math.ceil(
      (expiresAt.getTime() - now.getTime()) / (1000 * 60 * 60 * 24),
    );

    expiryBadge.classList.remove("hidden");

    if (daysUntilExpiry <= 7) {
      expiryBadge.className =
        "px-3 py-1 text-sm rounded bg-yellow-100 text-yellow-800";
      expiryBadge.textContent = `Download access expires in ${daysUntilExpiry} day${daysUntilExpiry !== 1 ? "s" : ""}`;
    } else {
      expiryBadge.className =
        "px-3 py-1 text-sm rounded bg-primary-100 text-primary-700";
      expiryBadge.textContent = `Download access until ${expiresAt.toLocaleDateString()}`;
    }
  }
}

// Download all handler
downloadAllBtn.addEventListener("click", async () => {
  downloadBtnText.textContent = "Preparing...";
  downloadAllBtn.disabled = true;

  try {
    const response = await getAlbumZipUrl(albumId);

    // Create temporary link and trigger download
    const link = document.createElement("a");
    link.href = response.download_url;
    link.download = `${albumId}.zip`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);

    downloadBtnText.textContent = "Download All";
  } catch (error) {
    console.error("Download error:", error);
    downloadBtnText.textContent = "Download failed";
    setTimeout(() => {
      downloadBtnText.textContent = "Download All";
    }, 3000);
  } finally {
    downloadAllBtn.disabled = false;
  }
});
```

### Success Criteria:

#### Automated Verification:

- [ ] `npm run build` succeeds
- [ ] No TypeScript errors

#### Manual Verification:

- [ ] Dashboard shows expiration badges on album cards
- [ ] Badges show correct colors (green > 30 days, blue > 7 days, yellow <= 7 days)
- [ ] Album viewer shows "Download All" button
- [ ] Click "Download All" triggers ZIP download
- [ ] Expiry badge shows on album viewer page

---

## Phase 7: CLI Tools and Documentation

### Overview

Create helper scripts for admin workflow and document the full process.

### Changes Required:

#### 1. Create Album Upload Script

**File**: `scripts/upload-album.sh` (NEW FILE)

```bash
#!/bin/bash
# Upload photos to S3 for a client album
# Usage: ./scripts/upload-album.sh <album-id> <source-directory>

set -e

BUCKET="katelynns-photography-client-albums"

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <album-id> <source-directory>"
    echo "Example: $0 smith-wedding-2026 ~/Photos/Smith-Wedding/"
    exit 1
fi

ALBUM_ID="$1"
SOURCE_DIR="$2"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist"
    exit 1
fi

# Validate album ID format
if ! [[ "$ALBUM_ID" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
    echo "Error: album-id must be a URL-safe slug (lowercase letters, numbers, hyphens)"
    echo "Example: smith-wedding-2026"
    exit 1
fi

echo "Uploading photos to album: $ALBUM_ID"
echo "Source: $SOURCE_DIR"
echo "Destination: s3://$BUCKET/albums/$ALBUM_ID/photos/"
echo ""

# Sync photos to S3
aws s3 sync "$SOURCE_DIR" "s3://$BUCKET/albums/$ALBUM_ID/photos/" \
    --exclude ".*" \
    --exclude "*.DS_Store" \
    --exclude "Thumbs.db" \
    --include "*.jpg" \
    --include "*.jpeg" \
    --include "*.png" \
    --include "*.gif" \
    --include "*.JPG" \
    --include "*.JPEG" \
    --include "*.PNG"

# Count uploaded files
COUNT=$(aws s3 ls "s3://$BUCKET/albums/$ALBUM_ID/photos/" --recursive | wc -l)

echo ""
echo "Upload complete! $COUNT photos uploaded."
echo ""
echo "Next steps:"
echo "1. Register the album:"
echo "   curl -X POST https://api.katelynnsphotography.com/admin/albums \\"
echo "     -H 'Authorization: Bearer <token>' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"album_id\": \"$ALBUM_ID\", \"name\": \"Album Name\"}'"
echo ""
echo "2. Assign to user:"
echo "   curl -X POST https://api.katelynnsphotography.com/admin/albums/$ALBUM_ID/assign \\"
echo "     -H 'Authorization: Bearer <token>' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"email\": \"client@example.com\", \"first_name\": \"John\", \"last_name\": \"Doe\", \"expires_in_days\": 180, \"create_cognito_user\": true}'"
```

#### 2. Create Album Management Documentation

**File**: `docs/admin-album-workflow.md` (NEW FILE)

````markdown
# Client Album Management Workflow

## Overview

This document describes the workflow for uploading, registering, and assigning client albums.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Admin Cognito account with JWT token
- Photos exported and ready for upload

## Workflow Summary

1. Upload photos to S3 (CLI)
2. Optionally create metadata.json (for Lightroom workflow)
3. Register album in database (API)
4. Assign to client(s) (API)

## Step 1: Upload Photos to S3

```bash
./scripts/upload-album.sh <album-id> <source-directory>
```
````

Example:

```bash
./scripts/upload-album.sh smith-wedding-2026 ~/Photos/Smith-Wedding/
```

**Album ID Requirements:**

- Lowercase letters, numbers, and hyphens only
- Must start and end with letter or number
- Maximum 100 characters
- Examples: `smith-wedding-2026`, `jones-family-portraits`

## Step 2 (Optional): Create metadata.json

For Lightroom workflow or to pre-populate album info:

```bash
cat > /tmp/metadata.json << 'EOF'
{
  "name": "Smith Wedding 2026",
  "event_date": "2026-01-15",
  "shoot_type": "wedding",
  "location": "Denver, CO"
}
EOF

aws s3 cp /tmp/metadata.json s3://katelynns-photography-client-albums/albums/smith-wedding-2026/metadata.json
```

## Step 3: Register Album

```bash
curl -X POST https://api.katelynnsphotography.com/admin/albums \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "album_id": "smith-wedding-2026",
    "name": "Smith Wedding 2026",
    "event_date": "2026-01-15"
  }'
```

If metadata.json exists, name and event_date are optional (API reads from file).

## Step 4: Assign to User(s)

```bash
curl -X POST https://api.katelynnsphotography.com/admin/albums/smith-wedding-2026/assign \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "john@example.com",
    "first_name": "John",
    "last_name": "Smith",
    "phone": "303-555-1234",
    "expires_in_days": 180,
    "create_cognito_user": true
  }'
```

Options:

- `email`: User's email address (required)
- `first_name`, `last_name`, `phone`: Optional user info (stored in User table)
- `expires_in_days`: Days from now until expiration
- `expires_at`: Specific ISO date (alternative to expires_in_days)
- `create_cognito_user`: Create Cognito user if doesn't exist

## Managing Access

### List All Albums

```bash
curl https://api.katelynnsphotography.com/admin/albums \
  -H "Authorization: Bearer $TOKEN"
```

### List Album Users

```bash
curl https://api.katelynnsphotography.com/admin/albums/smith-wedding-2026/users \
  -H "Authorization: Bearer $TOKEN"
```

Returns user info (email, first_name, last_name, phone) along with assignment details.

### Revoke Access

```bash
curl -X DELETE https://api.katelynnsphotography.com/admin/albums/smith-wedding-2026/assign/john@example.com \
  -H "Authorization: Bearer $TOKEN"
```

Note: This removes the User_Album record but keeps the User record.

### Extend Expiration

Re-assign with new expiration:

```bash
curl -X POST https://api.katelynnsphotography.com/admin/albums/smith-wedding-2026/assign \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email": "john@example.com", "expires_in_days": 365}'
```

## ZIP Downloads

- Generated on first client download request
- Cached for 30 days, then auto-deleted
- Original photos remain (archived to Glacier after 365 days)
- **Limitation**: Albums >500 photos may timeout during ZIP generation

## Troubleshooting

### User Can't See Album

1. Verify assignment: `GET /admin/albums/{id}/users`
2. Check email matches exactly (case-insensitive)
3. Check expiration hasn't passed
4. Verify Cognito user exists and is active

### ZIP Download Fails

1. Check album size (<500 photos recommended)
2. Client can download individual photos as fallback
3. For large albums, consider splitting into multiple albums

```

### Success Criteria:

#### Automated Verification:

- [ ] Upload script is executable: `chmod +x scripts/upload-album.sh`
- [ ] Script syntax is valid: `bash -n scripts/upload-album.sh`

#### Manual Verification:

- [ ] Full workflow tested: upload → register → assign → client login → download

---

## Testing Strategy

### Integration Tests

1. Upload test photos to S3
2. Register album via API
3. Assign to test client
4. Login as client
5. Verify album appears in list
6. Verify photos load with presigned URLs
7. Verify ZIP download works
8. Set short expiry, verify 403 after expiration
9. Assign same album to second client, verify both can access

### Manual Testing Checklist

- [ ] Admin: Upload photos via CLI
- [ ] Admin: Register album (with and without metadata.json)
- [ ] Admin: Assign to multiple clients
- [ ] Client: Login and see assigned albums
- [ ] Client: View album photos
- [ ] Client: Download individual photo
- [ ] Client: Download all as ZIP
- [ ] Client: See expiration warning when < 7 days
- [ ] Client: Cannot access after expiration

---

## Cost Impact

### Monthly Estimates (Expected Usage)

| Component | Cost | Notes |
|-----------|------|-------|
| DynamoDB | ~$0-2 | On-demand, <1000 requests/month |
| S3 (photos) | ~$3-12 | 100-500GB @ $0.023/GB |
| S3 (ZIPs) | ~$0.50 | 30-day retention |
| S3 Data Transfer | ~$1-10 | Depends on downloads |
| Lambda | ~$0 | Free tier |
| **Total** | **~$5-25/month** | Scales with storage |

---

## References

- Master plan: `thoughts/shared/plans/2026-01-17-s3-media-management-master-plan.md`
- Portfolio media plan: `thoughts/shared/plans/2026-01-17-portfolio-s3-media-library.md`
- Client portal plan: `thoughts/shared/plans/2026-01-09-integrate-client-portal-into-astro.md`
- DynamoDB best practices: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html
- S3 presigned URLs: https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html
```
