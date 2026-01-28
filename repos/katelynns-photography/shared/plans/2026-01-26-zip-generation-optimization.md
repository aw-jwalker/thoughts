# ZIP Generation & Storage Optimization Implementation Plan

## Overview

Implement event-driven ZIP pre-generation and storage cost optimization for client albums. This replaces the current synchronous, on-demand ZIP generation with an asynchronous system that pre-generates ZIPs when albums are created or modified, improving client UX and supporting larger albums (up to 1,000 photos).

This plan also serves as a learning opportunity for AWS services: SQS, EventBridge, S3 Event Notifications, and S3 Intelligent-Tiering.

## Current State Analysis

### What Exists Today

| Component      | Status                                           | Location                                           |
| -------------- | ------------------------------------------------ | -------------------------------------------------- |
| ZIP Generation | Synchronous, in-memory                           | `backend/client_portal/app/services/s3.py:152-219` |
| Lambda Config  | 30s timeout, 256MB memory                        | `terraform/lambda.tf:151-152`                      |
| ZIP Caching    | 30-day auto-delete                               | `terraform/s3.tf:141-149`                          |
| ZIP Download   | 6-hour presigned URLs                            | `terraform/lambda.tf:165`                          |
| Photo Storage  | Standard → STANDARD_IA (90d) → GLACIER_IR (365d) | `terraform/s3.tf:117-136`                          |

### Current Limitations

1. **500-photo limit**: Albums with >500 photos timeout during ZIP generation
2. **Synchronous generation**: Client waits 10-30 seconds for ZIP to generate
3. **No invalidation**: ZIP becomes stale if photos added/removed after generation
4. **Memory-bound**: Entire ZIP buffer held in Lambda memory (256MB limit)

### Key Discoveries

- ZIP generation loads all photos into memory: `s3.py:173-203`
- No tracking of photo changes for ZIP invalidation
- `zip_generated_at` exists in DynamoDB but `photo_count` isn't compared
- Current lifecycle rules already handle photo archival well

## Desired End State

After implementation:

1. **Asynchronous ZIP generation**: ZIPs pre-generated when albums created/modified
2. **Client experience**: "Download All" shows immediately or "Preparing..." status
3. **Larger album support**: Up to 1,000 photos per album
4. **Smart invalidation**: ZIP regenerated when photo count changes
5. **Cost optimization**: S3 Intelligent-Tiering for automatic tiering

### Architecture (MVP)

The MVP focuses on registration-triggered ZIP generation. S3 event notifications for photo additions are deferred to a later phase.

```
┌─────────────────────────────────────────────────────────────────┐
│                     Admin Workflow (MVP)                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Admin uploads        2. Admin registers       3. ZIP queued  │
│     photos to S3    ──►     album via API    ──►    via SQS     │
│     (aws s3 sync)           POST /admin/albums                   │
│                                                                  │
│                                                    ▼             │
│                                             ZIP Generator Lambda │
│                                             (5-min, 1024MB)      │
│                                                    │             │
│                                                    ▼             │
│                                             zips/{album_id}.zip  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     Client Download Flow                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  GET /albums/{id}/download                                       │
│       │                                                          │
│       ├─► ZIP ready? ──► Return presigned URL (6hr)             │
│       │                                                          │
│       └─► ZIP pending/generating? ──► Return status + poll      │
│       │                                                          │
│       └─► ZIP not started? ──► Queue generation + return status │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     Deferred: Photo Addition Flow                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [FUTURE] S3 Event      ──►  SQS Queue  ──►  ZIP Regeneration   │
│           (PutObject)        (deduped)                           │
│                                                                  │
│  Use case: Admin adds photos to an already-shared album          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Phase Summary

| Phase | Name | Priority | Description |
|-------|------|----------|-------------|
| **0** | Test Environment Setup | 🔴 First | Create test album, verify current state |
| **1** | SQS Queue Infrastructure | 🔴 Core | Queue for ZIP generation jobs |
| **2** | ZIP Generator Lambda | 🔴 Core | Dedicated Lambda with higher limits |
| **3** | Client API Updates | 🔴 Core | Async status + queue on download |
| **4** | Admin API Updates | 🔴 Core | Queue ZIP on album registration |
| **5** | Frontend Polling | 🔴 Core | UI shows generation status |
| **6** | S3 Event Notifications | 🟡 Deferred | Auto-regenerate when photos added |
| **7** | S3 Intelligent-Tiering | 🟢 Optional | Storage cost optimization |
| **8** | EventBridge Maintenance | 🟢 Optional | Daily stale ZIP cleanup |

### Verification Checklist

**MVP (Phases 0-5):**
- [ ] Test album created in S3 with sample photos
- [ ] ZIP Generator Lambda can be manually invoked successfully
- [ ] Admin registers album → ZIP auto-generated within 5 minutes
- [ ] Client download shows "ready" status immediately for pre-generated ZIPs
- [ ] Client download shows "preparing" status for pending ZIPs
- [ ] Albums up to 1,000 photos generate successfully
- [ ] Multiple download clicks don't create duplicate ZIPs (race condition protected)

**Deferred (Phases 6-8):**
- [ ] Adding photos to existing album triggers ZIP regeneration (Phase 6)
- [ ] S3 Intelligent-Tiering applied to photos bucket (Phase 7)
- [ ] Daily EventBridge job runs successfully (Phase 8)

### Race Condition Protections

This plan includes two levels of protection against duplicate ZIP generation:

1. **API Level (Phase 3)**: The `_queue_zip_generation()` function uses a DynamoDB conditional write to atomically set `zip_status = "pending"`. Only the first request succeeds; subsequent concurrent requests see the condition fail and return the existing status instead of queuing duplicates.

2. **Lambda Level (Phase 2)**: The ZIP Generator Lambda uses a conditional write to set `zip_status = "generating"` before starting work. If another Lambda is already processing the same album, the condition fails and the Lambda skips the work.

This two-layer approach handles:
- User clicking "Download All" multiple times quickly
- Multiple users requesting the same album simultaneously
- S3 event floods from batch photo uploads (hundreds of events → one ZIP generation)

## What We're NOT Doing

- ❌ Step Functions for unlimited album sizes (would require Option C)
- ❌ Streaming ZIP generation (too complex for current needs)
- ❌ Real-time WebSocket updates for ZIP status (polling is sufficient)
- ❌ Multi-part ZIP downloads for very large albums
- ❌ Client-side ZIP assembly in browser

## Known Limitations

| Limitation                   | Impact                                  | Future Solution                          |
| ---------------------------- | --------------------------------------- | ---------------------------------------- |
| 1,000 photo max (soft limit) | Very large weddings may need splitting  | Step Functions distributed processing    |
| 5-minute Lambda timeout      | Large albums with big files may timeout | Increase to 15 min or use Step Functions |
| Single ZIP file              | Can't resume partial downloads          | Chunked downloads or torrent-style       |

## Future Migration Path: Option B → Option C (Step Functions)

This plan implements **Option B** (SQS + dedicated Lambda). If album sizes regularly exceed 1,000 photos in the future, we can migrate to **Option C** (Step Functions) with minimal disruption.

### Why Migration is Low-Risk

| Component | Reusable? | Notes |
|-----------|-----------|-------|
| SQS queue | ✅ Yes | Can remain as the entry point |
| DynamoDB status tracking | ✅ Yes | Same `zip_status` field works |
| S3 structure (`zips/{album_id}.zip`) | ✅ Yes | Output location unchanged |
| API contract (status: ready/generating/pending) | ✅ Yes | Frontend doesn't need changes |
| Frontend polling logic | ✅ Yes | Already handles async |

### What Would Change

```
Option B:  SQS → ZIP Lambda → S3

Option C:  SQS → Step Functions → [Worker Lambdas in parallel] → Combine Lambda → S3
```

The ZIP Generator Lambda code can be adapted as a "worker" that processes a batch of photos (e.g., 100 at a time) instead of the whole album.

### Cost Difference

Option C adds ~$0.002 (0.2¢) per album in Step Functions state transitions - negligible.

### Migration Trigger

Consider migrating when:
- Albums regularly exceed 500-700 photos
- Lambda timeouts appear in CloudWatch for ZIP generation
- Clients report failed ZIP downloads for large albums

---

## Phase 0: Test Environment Setup

### Overview

Before building anything, set up a test environment to validate the current system and provide test data for development. This follows test-driven development principles.

### Goals

1. Create a test album with sample photos in S3
2. Verify the existing synchronous ZIP generation works (baseline)
3. Document current performance characteristics
4. Have test data ready for all subsequent phases

### Steps

#### 1. Create Test Album in S3

```bash
# Create a test album with 20-50 sample photos
# Use actual photos or generate test images

# Option A: Copy existing photos
aws s3 sync ~/test-photos/ s3://katelynns-photography-client-albums/albums/test-zip-optimization/photos/ \
    --exclude ".*"

# Option B: Generate test images (if no photos available)
mkdir -p /tmp/test-photos
for i in {1..25}; do
    convert -size 1920x1080 xc:gray +noise Random /tmp/test-photos/test-photo-$i.jpg 2>/dev/null || \
    dd if=/dev/urandom bs=1024 count=500 2>/dev/null | base64 > /tmp/test-photos/test-photo-$i.jpg
done
aws s3 sync /tmp/test-photos/ s3://katelynns-photography-client-albums/albums/test-zip-optimization/photos/
```

#### 2. Register Test Album in DynamoDB

```bash
# Using AWS CLI
aws dynamodb put-item \
    --table-name katelynns-photography-album \
    --item '{
        "album_id": {"S": "test-zip-optimization"},
        "name": {"S": "ZIP Optimization Test Album"},
        "photo_count": {"N": "25"},
        "created_at": {"S": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"},
        "created_by": {"S": "test@example.com"}
    }'
```

Or use the existing admin API if available:
```bash
curl -X POST https://api.katelynnsphotography.com/admin/albums \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"album_id": "test-zip-optimization", "name": "ZIP Optimization Test Album"}'
```

#### 3. Test Current ZIP Generation (Baseline)

```bash
# Test the current synchronous ZIP generation
# This establishes baseline performance

# If client portal is running locally:
curl -X GET "http://localhost:8000/albums/test-zip-optimization/download" \
    -H "Authorization: Bearer $CLIENT_TOKEN"

# Or test via the deployed API (as a test client user)
# Time how long it takes - this is the baseline to beat
```

#### 4. Document Baseline Metrics

Record in this section after testing:

| Metric | Value | Notes |
|--------|-------|-------|
| Test album photo count | ___ | |
| Total album size (MB) | ___ | |
| Current ZIP generation time | ___ seconds | |
| Lambda memory used | ___ MB | Check CloudWatch |
| Lambda timeout? | Yes/No | |

### Success Criteria

- [ ] Test album exists at `s3://katelynns-photography-client-albums/albums/test-zip-optimization/photos/`
- [ ] Album registered in DynamoDB
- [ ] Baseline ZIP generation tested and timed
- [ ] Metrics documented above

### Test Data for Later Phases

This test album will be used to:
- **Phase 2**: Test ZIP Generator Lambda with manual invocation
- **Phase 3**: Test API status responses
- **Phase 4**: Test admin registration flow
- **Phase 5**: Test frontend polling UI

---

## Phase 1: SQS Queue Infrastructure

### Overview

Create the SQS queue for ZIP generation jobs. S3 event notifications are deferred to Phase 6.

### AWS Services to Learn

| Service | Purpose | Documentation |
|---------|---------|---------------|
| **SQS** | Queue ZIP generation jobs for async processing | [SQS Developer Guide](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/welcome.html) |

### Changes Required:

#### 1. Create SQS Queue

**File**: `terraform/sqs.tf` (NEW FILE)

```hcl
# ============================================================
# SQS Queue for ZIP Generation
# ============================================================
# Queue receives messages when:
# 1. Album is registered via API (Phase 4)
# 2. Client requests download and ZIP doesn't exist (Phase 3)
# 3. Photos are uploaded to an album (Phase 6 - deferred)

resource "aws_sqs_queue" "zip_generation" {
  name                       = "${var.project_name}-zip-generation"
  visibility_timeout_seconds = 360  # 6 minutes (Lambda timeout + buffer)
  message_retention_seconds  = 86400  # 1 day
  receive_wait_time_seconds  = 20  # Long polling

  # Dead letter queue for failed messages
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.zip_generation_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "${var.project_name}-zip-generation"
    Environment = var.environment
  }
}

# Dead Letter Queue for failed ZIP generation jobs
resource "aws_sqs_queue" "zip_generation_dlq" {
  name                      = "${var.project_name}-zip-generation-dlq"
  message_retention_seconds = 1209600  # 14 days

  tags = {
    Name        = "${var.project_name}-zip-generation-dlq"
    Environment = var.environment
  }
}

# ============================================================
# Outputs
# ============================================================
output "zip_generation_queue_url" {
  value = aws_sqs_queue.zip_generation.url
}

output "zip_generation_queue_arn" {
  value = aws_sqs_queue.zip_generation.arn
}

output "zip_generation_dlq_url" {
  value = aws_sqs_queue.zip_generation_dlq.url
}
```

### Success Criteria:

#### Automated Verification:

- [ ] `terraform plan` shows SQS queue creation
- [ ] `terraform apply` completes successfully

#### Manual Verification:

- [ ] SQS queue visible in AWS Console
- [ ] Dead letter queue visible
- [ ] Manually send test message to queue via AWS Console
- [ ] Verify message appears (Console → Poll for messages)

**Test Command**:
```bash
# Send a test message manually
aws sqs send-message \
    --queue-url $(terraform output -raw zip_generation_queue_url) \
    --message-body '{"album_id": "test-zip-optimization", "source": "manual-test"}'

# Poll for the message
aws sqs receive-message \
    --queue-url $(terraform output -raw zip_generation_queue_url) \
    --max-number-of-messages 1
```

---

## Phase 2: ZIP Generator Lambda

### Overview

Create a dedicated Lambda function for ZIP generation that processes messages from the SQS queue. This Lambda has higher memory (1024MB) and longer timeout (5 minutes) than the main API Lambda.

### Changes Required:

#### 1. Create ZIP Generator Lambda Code

**File**: `backend/zip_generator/handler.py` (NEW FILE)

```python
"""
ZIP Generator Lambda

Processes SQS messages to generate ZIP files for client albums.
Triggered by:
1. S3 event notifications (photo uploads)
2. Admin API (album registration)

Message format:
{
    "album_id": "smith-wedding-2026",
    "source": "s3_event" | "api" | "manual",
    "force": false  # Optional: regenerate even if exists
}
"""
import os
import io
import json
import zipfile
import hashlib
from datetime import datetime, timezone
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError


# Environment variables
CLIENT_ALBUMS_BUCKET = os.environ.get(
    "CLIENT_ALBUMS_BUCKET", "katelynns-photography-client-albums"
)
ALBUM_TABLE_NAME = os.environ.get("ALBUM_TABLE_NAME", "katelynns-photography-album")
REGION = os.environ.get("AWS_REGION_NAME", "us-east-2")

# Clients
s3_client = boto3.client(
    "s3",
    region_name=REGION,
    config=Config(s3={"addressing_style": "virtual"})
)
dynamodb = boto3.resource("dynamodb", region_name=REGION)
album_table = dynamodb.Table(ALBUM_TABLE_NAME)


def lambda_handler(event, context):
    """
    Process SQS messages for ZIP generation.

    Handles both:
    - S3 event notifications (batch of object creates)
    - Direct API messages (single album_id)
    """
    print(f"Received event with {len(event.get('Records', []))} records")

    # Collect unique album IDs to process
    albums_to_process = set()

    for record in event.get("Records", []):
        body = json.loads(record.get("body", "{}"))

        # Check if this is an S3 event notification
        if "Records" in body:
            # S3 event format: {"Records": [{"s3": {"object": {"key": "..."}}}]}
            for s3_record in body.get("Records", []):
                key = s3_record.get("s3", {}).get("object", {}).get("key", "")
                album_id = extract_album_id_from_key(key)
                if album_id:
                    albums_to_process.add(album_id)
        elif "album_id" in body:
            # Direct API message format
            albums_to_process.add(body["album_id"])

    print(f"Albums to process: {albums_to_process}")

    # Process each album
    results = []
    for album_id in albums_to_process:
        try:
            result = process_album(album_id)
            results.append({"album_id": album_id, **result})
        except Exception as e:
            print(f"Error processing album {album_id}: {e}")
            results.append({
                "album_id": album_id,
                "status": "error",
                "error": str(e)
            })

    return {
        "statusCode": 200,
        "body": json.dumps({"processed": results})
    }


def extract_album_id_from_key(key: str) -> str | None:
    """
    Extract album_id from S3 key.

    Key format: albums/{album_id}/photos/{filename}
    Returns: album_id or None if not a photo key
    """
    if not key.startswith("albums/"):
        return None

    parts = key.split("/")
    if len(parts) < 4 or parts[2] != "photos":
        return None

    return parts[1]


def process_album(album_id: str) -> dict:
    """
    Generate ZIP for an album if needed.

    Returns:
        dict with status and details
    """
    print(f"Processing album: {album_id}")

    # Get album metadata from DynamoDB
    album = album_table.get_item(Key={"album_id": album_id}).get("Item")

    if not album:
        return {"status": "skipped", "reason": "Album not registered in DynamoDB"}

    # Count current photos in S3
    prefix = f"albums/{album_id}/photos/"
    current_photo_count = count_photos(prefix)

    if current_photo_count == 0:
        return {"status": "skipped", "reason": "No photos in album"}

    # Check if ZIP needs regeneration
    stored_photo_count = album.get("photo_count", 0)
    zip_generated_at = album.get("zip_generated_at")

    needs_regeneration = (
        not zip_exists(album_id) or  # ZIP doesn't exist
        current_photo_count != stored_photo_count or  # Photo count changed
        not zip_generated_at  # Never generated
    )

    if not needs_regeneration:
        print(f"Album {album_id}: ZIP is current, skipping")
        return {"status": "skipped", "reason": "ZIP already current"}

    # RACE CONDITION FIX: Use conditional write to "claim" the generation
    # Only one Lambda can successfully set status to "generating"
    # This prevents duplicate ZIP generation from concurrent requests
    try:
        album_table.update_item(
            Key={"album_id": album_id},
            UpdateExpression="SET zip_status = :generating, zip_generation_started_at = :now, photo_count = :count",
            ConditionExpression="attribute_not_exists(zip_status) OR zip_status <> :generating",
            ExpressionAttributeValues={
                ":generating": "generating",
                ":now": datetime.now(timezone.utc).isoformat(),
                ":count": current_photo_count
            }
        )
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            # Another Lambda is already generating this ZIP - skip
            print(f"Album {album_id}: Generation already in progress, skipping")
            return {"status": "skipped", "reason": "Generation already in progress"}
        raise

    try:
        # Generate the ZIP
        zip_key = generate_zip(album_id, prefix)

        # Get ZIP size
        zip_size = get_object_size(zip_key)

        # Update DynamoDB with completion
        update_zip_status(
            album_id,
            "ready",
            current_photo_count,
            zip_size=zip_size
        )

        print(f"Album {album_id}: ZIP generated successfully ({current_photo_count} photos, {zip_size} bytes)")
        return {
            "status": "generated",
            "photo_count": current_photo_count,
            "zip_size": zip_size
        }

    except Exception as e:
        # Update DynamoDB with error
        update_zip_status(album_id, "error", current_photo_count, error=str(e))
        raise


def count_photos(prefix: str) -> int:
    """Count photos in S3 prefix."""
    count = 0
    paginator = s3_client.get_paginator("list_objects_v2")

    for page in paginator.paginate(Bucket=CLIENT_ALBUMS_BUCKET, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not key.endswith("/") and not key.endswith(".keep"):
                count += 1

    return count


def zip_exists(album_id: str) -> bool:
    """Check if ZIP file exists in S3."""
    zip_key = f"zips/{album_id}.zip"
    try:
        s3_client.head_object(Bucket=CLIENT_ALBUMS_BUCKET, Key=zip_key)
        return True
    except ClientError:
        return False


def get_object_size(key: str) -> int:
    """Get size of S3 object in bytes."""
    try:
        response = s3_client.head_object(Bucket=CLIENT_ALBUMS_BUCKET, Key=key)
        return response.get("ContentLength", 0)
    except ClientError:
        return 0


def generate_zip(album_id: str, prefix: str) -> str:
    """
    Generate ZIP file for album and upload to S3.

    Uses streaming approach to handle larger albums.
    Returns the S3 key of the generated ZIP.
    """
    zip_key = f"zips/{album_id}.zip"

    # Create ZIP in memory
    # Note: For very large albums (>1000 photos), consider streaming to disk
    zip_buffer = io.BytesIO()

    with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
        paginator = s3_client.get_paginator("list_objects_v2")
        photo_count = 0

        for page in paginator.paginate(Bucket=CLIENT_ALBUMS_BUCKET, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                if key.endswith("/") or key.endswith(".keep"):
                    continue

                file_name = key.split("/")[-1]

                # Download file content
                response = s3_client.get_object(
                    Bucket=CLIENT_ALBUMS_BUCKET,
                    Key=key
                )
                file_content = response["Body"].read()

                # Add to ZIP with just filename (no path)
                zf.writestr(file_name, file_content)
                photo_count += 1

                # Log progress every 100 photos
                if photo_count % 100 == 0:
                    print(f"Processed {photo_count} photos...")

    print(f"ZIP created with {photo_count} photos, uploading to S3...")

    # Upload ZIP to S3
    zip_buffer.seek(0)
    s3_client.put_object(
        Bucket=CLIENT_ALBUMS_BUCKET,
        Key=zip_key,
        Body=zip_buffer.getvalue(),
        ContentType="application/zip",
        Metadata={
            "photo_count": str(photo_count),
            "generated_at": datetime.now(timezone.utc).isoformat()
        }
    )

    return zip_key


def update_zip_status(
    album_id: str,
    status: str,
    photo_count: int,
    zip_size: int = None,
    error: str = None
):
    """
    Update album record with ZIP generation status.

    status: "generating" | "ready" | "error"
    """
    now = datetime.now(timezone.utc).isoformat()

    update_expr = "SET zip_status = :status, photo_count = :count"
    expr_values = {
        ":status": status,
        ":count": photo_count
    }

    if status == "ready":
        update_expr += ", zip_generated_at = :generated"
        expr_values[":generated"] = now

        if zip_size:
            update_expr += ", zip_size = :size"
            expr_values[":size"] = zip_size

    if status == "generating":
        update_expr += ", zip_generation_started_at = :started"
        expr_values[":started"] = now

    if error:
        update_expr += ", zip_error = :error"
        expr_values[":error"] = error

    album_table.update_item(
        Key={"album_id": album_id},
        UpdateExpression=update_expr,
        ExpressionAttributeValues=expr_values
    )
```

#### 2. Create ZIP Generator Lambda Terraform

**File**: `terraform/lambda.tf`
**Location**: Add after the admin_api Lambda (around line 200)

```hcl
# ============================================================
# ZIP Generator Lambda
# ============================================================
# Processes SQS messages to generate ZIP files asynchronously
# Higher memory and longer timeout than API lambdas

data "archive_file" "zip_generator" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/zip_generator"
  output_path = "${path.module}/../backend/zip_generator.zip"
}

resource "aws_lambda_function" "zip_generator" {
  function_name = "${var.project_name}-zip-generator"
  role          = aws_iam_role.lambda_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.zip_generator.output_path
  source_code_hash = data.archive_file.zip_generator.output_base64sha256

  timeout     = 300   # 5 minutes for large albums
  memory_size = 1024  # 1GB for ZIP buffer

  environment {
    variables = {
      CLIENT_ALBUMS_BUCKET = aws_s3_bucket.client_albums.id
      ALBUM_TABLE_NAME     = aws_dynamodb_table.album.name
      AWS_REGION_NAME      = "us-east-2"
    }
  }

  tags = {
    Name        = "${var.project_name}-zip-generator"
    Environment = var.environment
  }
}

# SQS trigger for ZIP Generator Lambda
resource "aws_lambda_event_source_mapping" "zip_generator_sqs" {
  event_source_arn = aws_sqs_queue.zip_generation.arn
  function_name    = aws_lambda_function.zip_generator.arn
  batch_size       = 10  # Process up to 10 albums per invocation

  # Wait up to 60 seconds to batch messages
  maximum_batching_window_in_seconds = 60
}

# Allow Lambda to read from SQS
resource "aws_iam_role_policy" "zip_generator_sqs" {
  name = "zip-generator-sqs-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.zip_generation.arn,
          aws_sqs_queue.zip_generation_dlq.arn
        ]
      }
    ]
  })
}

# CloudWatch Log Group for ZIP Generator
resource "aws_cloudwatch_log_group" "zip_generator" {
  name              = "/aws/lambda/${aws_lambda_function.zip_generator.function_name}"
  retention_in_days = 30
}
```

#### 3. Create Lambda Directory Structure

Create the directory and `__init__.py`:

```bash
mkdir -p backend/zip_generator
touch backend/zip_generator/__init__.py
```

### Success Criteria:

#### Automated Verification:

- [ ] `terraform plan` shows Lambda creation
- [ ] `terraform plan` shows SQS event source mapping
- [ ] `terraform apply` completes successfully
- [ ] Lambda deploys without errors

#### Manual Verification:

- [ ] Send test message to SQS queue manually
- [ ] Verify Lambda invoked (check CloudWatch logs)
- [ ] For registered album with photos, verify ZIP generated
- [ ] Verify DynamoDB record updated with `zip_status`

**Implementation Note**: Test with a small album first before proceeding.

---

## Phase 3: Update API for Async ZIP Status

### Overview

Modify the client portal API to check ZIP status from DynamoDB rather than generating on-demand. If ZIP is not ready, return a status response so the frontend can poll.

### Changes Required:

#### 1. Update Album Download Endpoint

**File**: `backend/client_portal/app/routes/albums.py`
**Changes**: Check `zip_status` instead of generating on-demand

Replace the `get_download_url` function:

```python
@router.get("/albums/{album_id}/download", response_model=DownloadResponse)
async def get_download_url(
    album_id: str = Path(..., description="Album identifier"),
    file_name: Optional[str] = Query(None, description="Specific file to download"),
    user: dict = Depends(get_current_user)
):
    """
    Get presigned URL for downloading.

    If file_name is provided: returns 1-hour URL for that specific file.
    Otherwise: returns status of ZIP download:
    - If ready: 6-hour URL for ZIP
    - If generating: status with ETA
    - If not started: queues generation and returns pending status
    """
    user_email = user.get("email")

    # Check access (raises if denied)
    _check_album_access(album_id, user_email)

    try:
        if file_name:
            # Single file download (1-hour URL)
            url, expires = s3_service.generate_presigned_url(album_id, file_name)
            return DownloadResponse(
                album_id=album_id,
                download_url=url,
                expires_in=expires,
                file_count=1,
                status="ready"
            )

        # ZIP download - check status from DynamoDB
        album_data = db_service.get_album(album_id)
        if not album_data:
            raise HTTPException(status_code=404, detail="Album not found")

        zip_status = album_data.get("zip_status", "not_started")
        photo_count = album_data.get("photo_count", 0)

        if zip_status == "ready" and s3_service.zip_exists(album_id):
            # ZIP is ready - return presigned URL
            url, expires = s3_service.get_zip_download_url(album_id)
            return DownloadResponse(
                album_id=album_id,
                download_url=url,
                expires_in=expires,
                file_count=photo_count,
                status="ready"
            )

        elif zip_status == "generating":
            # ZIP is being generated - return status
            started_at = album_data.get("zip_generation_started_at")
            return DownloadResponse(
                album_id=album_id,
                download_url=None,
                expires_in=0,
                file_count=photo_count,
                status="generating",
                message="Your download is being prepared. This may take a few minutes for large albums."
            )

        elif zip_status == "error":
            # Previous generation failed - queue retry (with race condition protection)
            _queue_zip_generation(album_id, source="api_retry")  # Will succeed since status is "error"
            return DownloadResponse(
                album_id=album_id,
                download_url=None,
                expires_in=0,
                file_count=photo_count,
                status="generating",
                message="Retrying download preparation. Please check back shortly."
            )

        else:
            # Not started - queue generation (with race condition protection)
            if _queue_zip_generation(album_id, source="api"):
                return DownloadResponse(
                    album_id=album_id,
                    download_url=None,
                    expires_in=0,
                    file_count=photo_count,
                    status="pending",
                    message="Preparing your download. This may take a few minutes."
                )
            else:
                # Another request already queued - return generating status
                return DownloadResponse(
                    album_id=album_id,
                    download_url=None,
                    expires_in=0,
                    file_count=photo_count,
                    status="generating",
                    message="Your download is being prepared."
                )

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        print(f"Error getting download URL for {album_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to get download status")


def _queue_zip_generation(album_id: str, source: str = "api") -> bool:
    """
    Send message to SQS queue for ZIP generation.

    Uses conditional write to prevent duplicate queuing from concurrent requests.
    Returns True if successfully queued, False if another request already queued.
    """
    import boto3
    import json
    import os
    from botocore.exceptions import ClientError

    # RACE CONDITION FIX: Atomically set status to "pending" only if not already pending/generating
    # This prevents multiple API requests from queuing duplicate messages
    try:
        db_service.album_table.update_item(
            Key={"album_id": album_id},
            UpdateExpression="SET zip_status = :pending",
            ConditionExpression="attribute_not_exists(zip_status) OR zip_status IN (:not_started, :error, :ready)",
            ExpressionAttributeValues={
                ":pending": "pending",
                ":not_started": "not_started",
                ":error": "error",
                ":ready": "ready"  # Allow re-queue if ready but stale
            }
        )
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            # Already pending or generating - don't queue again
            print(f"Album {album_id}: ZIP already queued/generating, skipping duplicate queue")
            return False
        raise

    # Only queue if we successfully updated the status
    sqs = boto3.client("sqs", region_name=os.environ.get("AWS_REGION_NAME", "us-east-2"))
    queue_url = os.environ.get("ZIP_GENERATION_QUEUE_URL")

    if not queue_url:
        print(f"Warning: ZIP_GENERATION_QUEUE_URL not set, cannot queue generation")
        return False

    sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps({
            "album_id": album_id,
            "source": source
        })
    )
    return True
```

#### 2. Update DownloadResponse Model

**File**: `backend/client_portal/app/models.py`
**Changes**: Add status and message fields

```python
class DownloadResponse(BaseModel):
    """Response for download URL endpoint."""
    album_id: str
    download_url: Optional[str] = None  # None if not ready
    expires_in: int
    file_count: int
    status: str = "ready"  # "ready" | "generating" | "pending" | "error"
    message: Optional[str] = None
```

#### 3. Add SQS Queue URL to Lambda Environment

**File**: `terraform/lambda.tf`
**Location**: Update client_portal Lambda environment variables

```hcl
environment {
  variables = {
    CLIENT_ALBUMS_BUCKET      = aws_s3_bucket.client_albums.id
    COGNITO_USER_POOL_ID      = aws_cognito_user_pool.clients.id
    COGNITO_CLIENT_ID         = aws_cognito_user_pool_client.web.id
    AWS_REGION_NAME           = "us-east-2"
    PRESIGNED_URL_EXPIRY      = "3600"
    ZIP_URL_EXPIRY            = "21600"
    ALBUM_TABLE_NAME          = aws_dynamodb_table.album.name
    USER_TABLE_NAME           = aws_dynamodb_table.user.name
    USER_ALBUM_TABLE_NAME     = aws_dynamodb_table.user_album.name
    ZIP_GENERATION_QUEUE_URL  = aws_sqs_queue.zip_generation.url  # NEW
  }
}
```

#### 4. Add SQS Send Permission to Lambda

**File**: `terraform/lambda.tf`
**Location**: Add to lambda_custom policy

```hcl
    # Add to aws_iam_role_policy.lambda_custom Statement array:
    {
      Sid    = "SQSSendMessage"
      Effect = "Allow"
      Action = [
        "sqs:SendMessage"
      ]
      Resource = [
        aws_sqs_queue.zip_generation.arn
      ]
    }
```

### Success Criteria:

#### Automated Verification:

- [ ] `terraform plan` shows environment variable addition
- [ ] `terraform apply` completes successfully
- [ ] Lambda deploys without errors

#### Manual Verification:

- [ ] Call download endpoint for album without ZIP → returns "pending" status
- [ ] Check SQS queue → message received
- [ ] After Lambda processes, call download endpoint → returns "ready" with URL
- [ ] Call download for album mid-generation → returns "generating" status

**Implementation Note**: The frontend will need updates to handle the new status responses.

---

## Phase 4: Admin API - Queue ZIP on Album Registration

### Overview

Update the admin API to queue ZIP generation when an album is registered, so ZIPs are pre-generated before clients access them.

### Changes Required:

#### 1. Update Admin API Register Album

**File**: `backend/admin_api/handler.py`
**Changes**: Queue ZIP generation after album registration

Add SQS client setup:

```python
# Add near other client setup
sqs_client = boto3.client("sqs", region_name="us-east-2")
ZIP_GENERATION_QUEUE_URL = os.environ.get("ZIP_GENERATION_QUEUE_URL", "")
```

Add to the `register_album` function (after the DynamoDB put):

```python
    album_table.put_item(Item=item)

    # Queue ZIP generation
    if ZIP_GENERATION_QUEUE_URL:
        try:
            sqs_client.send_message(
                QueueUrl=ZIP_GENERATION_QUEUE_URL,
                MessageBody=json.dumps({
                    "album_id": album_id,
                    "source": "registration"
                })
            )
            print(f"Queued ZIP generation for album {album_id}")
        except Exception as e:
            print(f"Warning: Failed to queue ZIP generation: {e}")
            # Don't fail registration if queue fails

    return {
        "statusCode": 201,
        # ... rest of response
```

#### 2. Add Queue URL to Admin Lambda

**File**: `terraform/lambda.tf`
**Location**: Update admin_api Lambda environment variables

```hcl
environment {
  variables = {
    CLIENT_ALBUMS_BUCKET      = aws_s3_bucket.client_albums.id
    COGNITO_USER_POOL_ID      = aws_cognito_user_pool.clients.id
    ADMIN_EMAIL               = var.admin_email
    ALBUM_TABLE_NAME          = aws_dynamodb_table.album.name
    USER_TABLE_NAME           = aws_dynamodb_table.user.name
    USER_ALBUM_TABLE_NAME     = aws_dynamodb_table.user_album.name
    ZIP_GENERATION_QUEUE_URL  = aws_sqs_queue.zip_generation.url  # NEW
  }
}
```

### Success Criteria:

#### Automated Verification:

- [ ] `terraform apply` completes successfully
- [ ] Lambda deploys without errors

#### Manual Verification:

- [ ] Register album via API → check SQS queue has message
- [ ] ZIP Generator Lambda processes message
- [ ] Album record has `zip_status: ready` after generation
- [ ] Client download returns ready status immediately

---

## Phase 5: Frontend Polling for ZIP Status

### Overview

Update the frontend to poll the download endpoint when ZIP is not ready, showing appropriate loading states.

### Changes Required:

#### 1. Update API Types

**File**: `frontend/src/lib/api.ts`
**Changes**: Update DownloadResponse type

```typescript
export interface DownloadResponse {
  album_id: string;
  download_url: string | null;
  expires_in: number;
  file_count: number;
  status: "ready" | "generating" | "pending" | "error";
  message?: string;
}
```

#### 2. Update Album Viewer Download Handler

**File**: `frontend/src/pages/client/albums/[...id].astro`
**Changes**: Add polling logic for ZIP status

Replace the download handler in the script section:

```typescript
// Download all handler with polling
let pollInterval: number | null = null;

async function checkDownloadStatus(): Promise<DownloadResponse> {
  return apiRequest(`/albums/${albumId}/download`);
}

async function handleDownloadAll() {
  downloadBtnText.textContent = "Preparing...";
  downloadAllBtn.disabled = true;

  try {
    const response = await checkDownloadStatus();

    if (response.status === "ready" && response.download_url) {
      // ZIP ready - trigger download
      triggerDownload(response.download_url);
      downloadBtnText.textContent = "Download All";
      downloadAllBtn.disabled = false;
    } else if (
      response.status === "generating" ||
      response.status === "pending"
    ) {
      // Show progress and start polling
      downloadBtnText.textContent = "Preparing download...";
      showDownloadProgress(response.message || "Preparing your download...");
      startPolling();
    } else if (response.status === "error") {
      // Error - show message and allow retry
      downloadBtnText.textContent = "Retry Download";
      downloadAllBtn.disabled = false;
      showDownloadError(response.message || "Download failed. Click to retry.");
    }
  } catch (error) {
    console.error("Download error:", error);
    downloadBtnText.textContent = "Download failed";
    downloadAllBtn.disabled = false;
    setTimeout(() => {
      downloadBtnText.textContent = "Download All";
    }, 3000);
  }
}

function startPolling() {
  if (pollInterval) return; // Already polling

  pollInterval = window.setInterval(async () => {
    try {
      const response = await checkDownloadStatus();

      if (response.status === "ready" && response.download_url) {
        stopPolling();
        hideDownloadProgress();
        triggerDownload(response.download_url);
        downloadBtnText.textContent = "Download All";
        downloadAllBtn.disabled = false;
      } else if (response.status === "error") {
        stopPolling();
        hideDownloadProgress();
        downloadBtnText.textContent = "Retry Download";
        downloadAllBtn.disabled = false;
        showDownloadError(
          response.message || "Download preparation failed. Click to retry.",
        );
      }
      // Continue polling if still generating/pending
    } catch (error) {
      console.error("Polling error:", error);
      // Continue polling on transient errors
    }
  }, 5000); // Poll every 5 seconds
}

function stopPolling() {
  if (pollInterval) {
    clearInterval(pollInterval);
    pollInterval = null;
  }
}

function triggerDownload(url: string) {
  const link = document.createElement("a");
  link.href = url;
  link.download = `${albumId}.zip`;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}

function showDownloadProgress(message: string) {
  // Add a progress indicator element if it doesn't exist
  let progressEl = document.getElementById("download-progress");
  if (!progressEl) {
    progressEl = document.createElement("div");
    progressEl.id = "download-progress";
    progressEl.className =
      "fixed bottom-4 right-4 bg-primary-900 text-white px-4 py-3 rounded-lg shadow-lg flex items-center gap-3";
    document.body.appendChild(progressEl);
  }
  progressEl.innerHTML = `
    <svg class="animate-spin h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
    </svg>
    <span>${message}</span>
  `;
  progressEl.classList.remove("hidden");
}

function hideDownloadProgress() {
  const progressEl = document.getElementById("download-progress");
  if (progressEl) {
    progressEl.classList.add("hidden");
  }
}

function showDownloadError(message: string) {
  let errorEl = document.getElementById("download-error");
  if (!errorEl) {
    errorEl = document.createElement("div");
    errorEl.id = "download-error";
    errorEl.className =
      "fixed bottom-4 right-4 bg-red-600 text-white px-4 py-3 rounded-lg shadow-lg";
    document.body.appendChild(errorEl);
  }
  errorEl.textContent = message;
  errorEl.classList.remove("hidden");

  // Auto-hide after 5 seconds
  setTimeout(() => {
    errorEl?.classList.add("hidden");
  }, 5000);
}

// Clean up polling on page unload
window.addEventListener("beforeunload", stopPolling);

downloadAllBtn.addEventListener("click", handleDownloadAll);
```

### Success Criteria:

#### Automated Verification:

- [ ] `npm run build` succeeds
- [ ] No TypeScript errors

#### Manual Verification:

- [ ] Click "Download All" on album without ZIP → shows "Preparing download..."
- [ ] Progress indicator appears with spinner
- [ ] After ZIP generates (check CloudWatch), download auto-triggers
- [ ] Progress indicator disappears after download
- [ ] If error, shows retry button

**Implementation Note**: Consider adding estimated time based on photo count in future iteration.

---

## Phase 6: S3 Event Notifications (DEFERRED)

### Overview

**Status: Deferred** - Implement only if the use case arises (admin adds photos to an already-shared album).

Add S3 event notifications to automatically trigger ZIP regeneration when photos are added to an existing album. This is deferred because the primary workflow (upload → register → share) doesn't require it.

### Use Case

```
Admin workflow WITHOUT S3 events (MVP):
1. Upload all photos
2. Register album → ZIP generated
3. Share with client
4. Done

Admin workflow WITH S3 events (if needed later):
1. Upload photos, register, share
2. Later: "Oops, forgot these 5 photos"
3. Upload additional photos
4. S3 event triggers ZIP regeneration automatically
```

### Changes Required (When Implementing)

#### 1. Add S3 Event Notification

**File**: `terraform/s3.tf`

```hcl
# ============================================================
# S3 Event Notification for Photo Uploads
# ============================================================
# Triggers ZIP regeneration when photos are added to albums

resource "aws_s3_bucket_notification" "client_albums_notification" {
  bucket = aws_s3_bucket.client_albums.id

  queue {
    queue_arn     = aws_sqs_queue.zip_generation.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "albums/"
    filter_suffix = ""  # All files under albums/
  }

  # Avoid triggering on ZIP files (would cause loop)
  # The prefix filter ensures we only watch albums/, not zips/
}

# Allow S3 to send messages to SQS
resource "aws_sqs_queue_policy" "allow_s3_to_sqs" {
  queue_url = aws_sqs_queue.zip_generation.url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.zip_generation.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.client_albums.arn
          }
        }
      }
    ]
  })
}
```

### Success Criteria (When Implementing)

- [ ] `terraform apply` adds S3 event notification
- [ ] Upload photo to existing registered album
- [ ] SQS message received
- [ ] ZIP Generator processes and updates ZIP
- [ ] Client sees updated photo count

### Why Deferred

1. **Rarely needed**: Admin typically uploads all photos before sharing
2. **Race condition complexity**: Batch uploads create event floods
3. **Simplifies MVP**: Fewer moving parts to test and debug
4. **Can add later**: No breaking changes required

---

## Phase 7: S3 Intelligent-Tiering (OPTIONAL)

### Overview

**Status: Optional** - Nice-to-have for cost optimization, not required for MVP.

Implement S3 Intelligent-Tiering for automatic cost optimization of photo storage.

### AWS Services to Learn

| Service                    | Purpose                             | Documentation                                                                                                     |
| -------------------------- | ----------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **S3 Intelligent-Tiering** | Automatic storage class transitions | [S3 Intelligent-Tiering](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering-overview.html) |

### Changes Required:

#### 1. Update S3 Bucket Configuration

**File**: `terraform/s3.tf`
**Changes**: Add Intelligent-Tiering configuration for photos

Add after the lifecycle configuration:

```hcl
# ============================================================
# S3 Intelligent-Tiering Configuration
# ============================================================
# Automatically moves objects between access tiers based on usage
# - Frequent Access: First 30 days (or when accessed)
# - Infrequent Access: After 30 days of no access
# - Archive Instant Access: After 90 days of no access
# Note: Objects < 128KB are always in Frequent Access tier

resource "aws_s3_bucket_intelligent_tiering_configuration" "client_albums_photos" {
  bucket = aws_s3_bucket.client_albums.id
  name   = "photos-tiering"

  # Only apply to photos, not ZIPs
  filter {
    prefix = "albums/"
  }

  # Automatic tier: Infrequent Access after 30 days
  tiering {
    access_tier = "ARCHIVE_INSTANT_ACCESS"
    days        = 90
  }
}
```

#### 2. Update Upload Script for Intelligent-Tiering

**File**: `scripts/upload-album.sh`
**Changes**: Add storage class flag

```bash
# Update the aws s3 sync command to use Intelligent-Tiering
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
    --include "*.PNG" \
    --storage-class INTELLIGENT_TIERING  # NEW
```

### Success Criteria:

#### Automated Verification:

- [ ] `terraform plan` shows Intelligent-Tiering configuration
- [ ] `terraform apply` completes successfully

#### Manual Verification:

- [ ] Upload new album with storage class flag
- [ ] Verify object storage class in S3 Console: INTELLIGENT_TIERING
- [ ] After 30+ days (or simulated), verify objects moved to Infrequent Access tier

---

## Phase 8: EventBridge Scheduled Maintenance (OPTIONAL)

### Overview

**Status: Optional** - Nice-to-have for maintenance automation, not required for MVP.

Create a scheduled EventBridge rule to run daily maintenance: check for stale ZIPs, update statuses, and handle stuck generation jobs.

### AWS Services to Learn

| Service         | Purpose                            | Documentation                                                                                    |
| --------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------ |
| **EventBridge** | Scheduled rules for periodic tasks | [EventBridge Scheduler](https://docs.aws.amazon.com/eventbridge/latest/userguide/scheduler.html) |

### Changes Required:

#### 1. Create Maintenance Lambda

**File**: `backend/maintenance/handler.py` (NEW FILE)

```python
"""
Maintenance Lambda

Runs daily via EventBridge to:
1. Check for stale ZIPs (photo count changed)
2. Reset stuck "generating" statuses
3. Clean up orphaned resources
"""
import os
import json
from datetime import datetime, timezone, timedelta
import boto3
from botocore.exceptions import ClientError


# Environment variables
CLIENT_ALBUMS_BUCKET = os.environ.get(
    "CLIENT_ALBUMS_BUCKET", "katelynns-photography-client-albums"
)
ALBUM_TABLE_NAME = os.environ.get("ALBUM_TABLE_NAME", "katelynns-photography-album")
ZIP_GENERATION_QUEUE_URL = os.environ.get("ZIP_GENERATION_QUEUE_URL", "")
REGION = os.environ.get("AWS_REGION_NAME", "us-east-2")

# Clients
s3_client = boto3.client("s3", region_name=REGION)
sqs_client = boto3.client("sqs", region_name=REGION)
dynamodb = boto3.resource("dynamodb", region_name=REGION)
album_table = dynamodb.Table(ALBUM_TABLE_NAME)


def lambda_handler(event, context):
    """
    Daily maintenance tasks.
    """
    print(f"Running maintenance at {datetime.now(timezone.utc).isoformat()}")

    results = {
        "stale_zips_queued": 0,
        "stuck_jobs_reset": 0,
        "errors": []
    }

    try:
        # Get all albums
        response = album_table.scan()
        albums = response.get("Items", [])

        # Handle pagination
        while "LastEvaluatedKey" in response:
            response = album_table.scan(
                ExclusiveStartKey=response["LastEvaluatedKey"]
            )
            albums.extend(response.get("Items", []))

        print(f"Checking {len(albums)} albums")

        for album in albums:
            album_id = album["album_id"]

            try:
                # Check for stale ZIPs
                if is_zip_stale(album):
                    queue_zip_regeneration(album_id, "maintenance_stale")
                    results["stale_zips_queued"] += 1

                # Check for stuck generation jobs
                if is_generation_stuck(album):
                    reset_stuck_generation(album_id)
                    results["stuck_jobs_reset"] += 1

            except Exception as e:
                results["errors"].append({
                    "album_id": album_id,
                    "error": str(e)
                })

    except Exception as e:
        results["errors"].append({"general": str(e)})

    print(f"Maintenance complete: {results}")
    return results


def is_zip_stale(album: dict) -> bool:
    """
    Check if album's ZIP needs regeneration.

    ZIP is stale if:
    - zip_status is "ready" but photo count doesn't match
    - ZIP file doesn't exist but status says ready
    """
    zip_status = album.get("zip_status")

    if zip_status != "ready":
        return False

    album_id = album["album_id"]
    stored_count = album.get("photo_count", 0)

    # Count current photos
    current_count = count_photos(album_id)

    if current_count != stored_count:
        print(f"Album {album_id}: photo count changed ({stored_count} → {current_count})")
        return True

    # Check if ZIP file exists
    if not zip_exists(album_id):
        print(f"Album {album_id}: ZIP file missing but status is ready")
        return True

    return False


def is_generation_stuck(album: dict) -> bool:
    """
    Check if ZIP generation has been stuck for too long.

    Generation is stuck if status is "generating" for > 30 minutes.
    """
    zip_status = album.get("zip_status")

    if zip_status != "generating":
        return False

    started_at = album.get("zip_generation_started_at")
    if not started_at:
        return True  # No start time but generating - stuck

    started_dt = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
    stuck_threshold = datetime.now(timezone.utc) - timedelta(minutes=30)

    return started_dt < stuck_threshold


def count_photos(album_id: str) -> int:
    """Count photos in S3."""
    prefix = f"albums/{album_id}/photos/"
    count = 0
    paginator = s3_client.get_paginator("list_objects_v2")

    for page in paginator.paginate(Bucket=CLIENT_ALBUMS_BUCKET, Prefix=prefix):
        for obj in page.get("Contents", []):
            if not obj["Key"].endswith("/") and not obj["Key"].endswith(".keep"):
                count += 1

    return count


def zip_exists(album_id: str) -> bool:
    """Check if ZIP exists in S3."""
    try:
        s3_client.head_object(
            Bucket=CLIENT_ALBUMS_BUCKET,
            Key=f"zips/{album_id}.zip"
        )
        return True
    except ClientError:
        return False


def queue_zip_regeneration(album_id: str, source: str):
    """Queue ZIP regeneration."""
    if not ZIP_GENERATION_QUEUE_URL:
        print(f"Warning: Cannot queue regeneration, no queue URL")
        return

    sqs_client.send_message(
        QueueUrl=ZIP_GENERATION_QUEUE_URL,
        MessageBody=json.dumps({
            "album_id": album_id,
            "source": source,
            "force": True
        })
    )

    # Update status
    album_table.update_item(
        Key={"album_id": album_id},
        UpdateExpression="SET zip_status = :status",
        ExpressionAttributeValues={":status": "pending"}
    )


def reset_stuck_generation(album_id: str):
    """Reset stuck generation job."""
    print(f"Album {album_id}: resetting stuck generation")

    album_table.update_item(
        Key={"album_id": album_id},
        UpdateExpression="SET zip_status = :status, zip_error = :error",
        ExpressionAttributeValues={
            ":status": "error",
            ":error": "Generation timed out, will retry"
        }
    )
```

#### 2. Create EventBridge Rule and Lambda Terraform

**File**: `terraform/eventbridge.tf` (NEW FILE)

```hcl
# ============================================================
# EventBridge Scheduled Rules
# ============================================================

# ------------------------------------------------------------
# Daily Maintenance Schedule
# ------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "daily_maintenance" {
  name                = "${var.project_name}-daily-maintenance"
  description         = "Run daily maintenance tasks"
  schedule_expression = "rate(1 day)"

  tags = {
    Name        = "${var.project_name}-daily-maintenance"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "maintenance_lambda" {
  rule      = aws_cloudwatch_event_rule.daily_maintenance.name
  target_id = "MaintenanceLambda"
  arn       = aws_lambda_function.maintenance.arn
}

resource "aws_lambda_permission" "eventbridge_maintenance" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.maintenance.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_maintenance.arn
}
```

#### 3. Create Maintenance Lambda Terraform

**File**: `terraform/lambda.tf`
**Location**: Add after zip_generator Lambda

```hcl
# ============================================================
# Maintenance Lambda
# ============================================================
# Runs daily via EventBridge for maintenance tasks

data "archive_file" "maintenance" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/maintenance"
  output_path = "${path.module}/../backend/maintenance.zip"
}

resource "aws_lambda_function" "maintenance" {
  function_name = "${var.project_name}-maintenance"
  role          = aws_iam_role.lambda_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.maintenance.output_path
  source_code_hash = data.archive_file.maintenance.output_base64sha256

  timeout     = 300  # 5 minutes
  memory_size = 256

  environment {
    variables = {
      CLIENT_ALBUMS_BUCKET     = aws_s3_bucket.client_albums.id
      ALBUM_TABLE_NAME         = aws_dynamodb_table.album.name
      ZIP_GENERATION_QUEUE_URL = aws_sqs_queue.zip_generation.url
      AWS_REGION_NAME          = "us-east-2"
    }
  }

  tags = {
    Name        = "${var.project_name}-maintenance"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "maintenance" {
  name              = "/aws/lambda/${aws_lambda_function.maintenance.function_name}"
  retention_in_days = 30
}
```

### Success Criteria:

#### Automated Verification:

- [ ] `terraform plan` shows EventBridge rule creation
- [ ] `terraform plan` shows maintenance Lambda creation
- [ ] `terraform apply` completes successfully

#### Manual Verification:

- [ ] EventBridge rule visible in AWS Console
- [ ] Manually invoke maintenance Lambda → check logs
- [ ] Modify album's photo_count in DynamoDB to mismatch
- [ ] Run maintenance → verify ZIP queued for regeneration
- [ ] Set zip_generation_started_at to old date, status=generating
- [ ] Run maintenance → verify status reset to error

---

## Testing Strategy

### Unit Tests

1. ZIP Generator Lambda
   - Extract album ID from various S3 key formats
   - Handle empty albums gracefully
   - Update DynamoDB correctly on success/failure

2. Download endpoint
   - Return correct status for each zip_status value
   - Queue message when status is not_started
   - Handle missing queue URL gracefully

### Integration Tests

1. **Full workflow test**:
   - Upload photos to S3 via CLI
   - Register album via API
   - Verify SQS message queued
   - Verify ZIP Generator Lambda runs
   - Verify ZIP file created in S3
   - Verify DynamoDB updated with status=ready
   - Call download endpoint → get presigned URL
   - Download ZIP and verify contents

2. **Photo change detection**:
   - Generate ZIP for album
   - Add new photo to album
   - Run maintenance Lambda
   - Verify ZIP queued for regeneration

### Manual Testing Checklist

- [ ] Admin: Upload 100-photo album → ZIP generated automatically
- [ ] Admin: Upload 500-photo album → ZIP generated within 5 minutes
- [ ] Admin: Upload 1000-photo album → ZIP generated successfully
- [ ] Client: Download small album → immediate download
- [ ] Client: Download large album mid-generation → shows "Preparing..."
- [ ] Client: Polling works and triggers download when ready
- [ ] Maintenance: Daily job runs and logs results
- [ ] Storage: New uploads use Intelligent-Tiering class

---

## Cost Impact

### Monthly Estimates

| Component            | Current    | After Implementation | Notes                            |
| -------------------- | ---------- | -------------------- | -------------------------------- |
| Lambda (API)         | ~$0        | ~$0                  | Free tier                        |
| Lambda (ZIP Gen)     | N/A        | ~$0.50               | 5-min executions                 |
| Lambda (Maintenance) | N/A        | ~$0                  | Daily 5-min                      |
| SQS                  | N/A        | ~$0.01               | Low volume                       |
| EventBridge          | N/A        | ~$0                  | Free tier                        |
| S3 (photos)          | ~$5-12     | ~$3-8                | Intelligent-Tiering saves 20-40% |
| S3 (ZIPs)            | ~$0.50     | ~$0.50               | Same 30-day retention            |
| **Total**            | **~$5-13** | **~$4-9**            | Slight reduction from tiering    |

### AWS Service Learning Value

This plan introduces you to:

- **SQS**: Message queuing for async processing
- **EventBridge**: Scheduled tasks and event routing
- **S3 Event Notifications**: Event-driven architecture
- **S3 Intelligent-Tiering**: Automatic cost optimization
- **Lambda event sources**: Different trigger types (API Gateway, SQS, EventBridge)

---

## References

- Master plan: `thoughts/shared/plans/2026-01-17-s3-media-management-master-plan.md`
- Client albums plan: `thoughts/shared/plans/2026-01-24-client-albums-multi-client.md`
- [SQS Developer Guide](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/welcome.html)
- [S3 Event Notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html)
- [EventBridge Scheduler](https://docs.aws.amazon.com/eventbridge/latest/userguide/scheduler.html)
- [S3 Intelligent-Tiering](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering-overview.html)
- [Lambda with SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
