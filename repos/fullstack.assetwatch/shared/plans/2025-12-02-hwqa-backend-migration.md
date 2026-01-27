# HWQA Backend Migration to AssetWatch Repository

## Overview

Migrate the HWQA FastAPI backend from its standalone repository into the fullstack.assetwatch repository. The FastAPI application structure and business logic will remain largely unchanged - only the infrastructure integration (database access, authentication, API Gateway) will be adapted to use AssetWatch patterns.

## Current State Analysis

### HWQA Backend (Standalone)
- **Framework**: FastAPI with Mangum adapter for Lambda
- **Authentication**: JWT validation in middleware + Cognito group checks
- **Database**: Custom `DatabaseConnection` class with SSM parameter loading
- **API Gateway**: Own REST API with Cognito User Pool authorizer
- **Terraform**: Separate terraform configuration

### AssetWatch Backend Pattern
- **Framework**: Raw Lambda handlers with `db_resources` layer
- **Authentication**: AWS SigV4 at API Gateway + user extraction from request context
- **Database**: Shared `db_resources` layer with IAM auth to RDS Proxy
- **API Gateway**: OpenAPI specs with SigV4 security, base path mapping
- **Terraform**: Centralized in `terraform/` directory

## Desired End State

After migration:
1. HWQA backend exists at `lambdas/lf-vero-prod-hwqa/`
2. FastAPI app is preserved with minimal code changes
3. Uses `db_resources` layer for database connections (same as other lambdas)
4. Uses SigV4 authentication via API Gateway (same as other lambdas)
5. Accessible at `https://api.{branch}.{env}.assetwatch.com/hwqa/*`
6. Deployed via assetwatch terraform

### Verification:
- [ ] Lambda deploys successfully via terraform
- [ ] API Gateway routes to `/hwqa/*` work
- [ ] Frontend can call hwqa endpoints with existing auth
- [ ] Database queries return correct data

## What We're NOT Doing

- NOT converting FastAPI to raw Lambda handlers (keep FastAPI + Mangum)
- NOT changing route paths or API contracts
- NOT modifying business logic in services
- NOT changing database queries or stored procedures
- NOT rewriting frontend API calls (just need to work with assetwatch auth)

## Implementation Approach

The key insight is that FastAPI + Mangum can work with AssetWatch's auth pattern. We need to:
1. Remove HWQA's custom auth middleware (JWT decoding)
2. Adapt to extract user context from the Lambda event (like assetwatch)
3. Replace `DatabaseConnection` class with `db_resources` layer usage
4. Add terraform configuration for Lambda + API Gateway

---

## Phase 1: Copy Backend Code and Create Directory Structure

### Overview
Copy the HWQA backend code to assetwatch and set up the Lambda directory structure.

### Changes Required:

#### 1. Create Lambda Directory
**Directory**: `lambdas/lf-vero-prod-hwqa/`

```bash
# From fullstack.assetwatch root
mkdir -p lambdas/lf-vero-prod-hwqa

# Copy the hwqa backend app directory
cp -r ~/repos/hwqa/backend/app lambdas/lf-vero-prod-hwqa/
```

#### 2. Create requirements.txt
**File**: `lambdas/lf-vero-prod-hwqa/requirements.txt`

```txt
# FastAPI and ASGI
fastapi>=0.104.0
mangum>=0.17.0
pydantic>=2.0.0

# Note: mysql-connector-python, boto3, sentry-sdk come from Lambda layers
```

The HWQA backend uses these dependencies that will come from layers:
- `mysql-connector-python` → We'll switch to `pymysql` via layer
- `boto3` → Available in Lambda runtime
- `sentry-sdk` → Via sentry layer

### Success Criteria:

#### Automated Verification:
- [ ] Directory exists: `ls lambdas/lf-vero-prod-hwqa/app/`
- [ ] Main.py exists: `ls lambdas/lf-vero-prod-hwqa/app/main.py`
- [ ] Routes exist: `ls lambdas/lf-vero-prod-hwqa/app/routes/`

---

## Phase 2: Adapt Database Layer to Use db_resources

### Overview
Replace HWQA's custom `DatabaseConnection` class with calls to the shared `db_resources` layer.

### Key Changes Required:

#### 1. Create Compatibility Module
**File**: `lambdas/lf-vero-prod-hwqa/app/database/db_compat.py`

This module provides a compatibility layer that makes `db_resources` work like HWQA expects:

```python
"""
Database compatibility layer for HWQA.
Wraps the assetwatch db_resources layer to provide the interface HWQA services expect.
"""
import db_resources as db
import logging

logger = logging.getLogger(__name__)


class DatabaseConnection:
    """
    Compatibility wrapper around db_resources layer.
    Provides the same interface that HWQA services expect.
    """

    def __init__(self, role: str = "reader"):
        """
        Initialize database connection wrapper.

        Args:
            role: "reader" for read operations, "writer" for write operations
        """
        self.role = role
        self.connection = None
        self._cursor = None

    def connect(self, credentials=None) -> bool:
        """
        Establish database connection using db_resources layer.

        Note: credentials parameter is ignored - we use SSM parameters via db_resources.
        """
        try:
            db_option = db.RDS_READ_REPLICA_DB if self.role == "reader" else db.RDS_MAIN_DB
            self.connection = db.get_connection(db_option)
            return True
        except Exception as e:
            logger.error(f"Database connection failed: {e}")
            return False

    def cursor(self, dictionary=True):
        """Get a cursor from the connection."""
        import pymysql
        if self.connection:
            return self.connection.cursor(pymysql.cursors.DictCursor if dictionary else None)
        return None

    def execute_query(self, sql: str, params: tuple = None):
        """Execute a query and return results."""
        if not self.connection:
            raise Exception("Not connected to database")

        cursor = self.connection.cursor(pymysql.cursors.DictCursor)
        try:
            if params:
                cursor.execute(sql, params)
            else:
                cursor.execute(sql)
            results = cursor.fetchall()
            return results
        finally:
            cursor.close()

    def execute_procedure(self, procedure_name: str, params: tuple = ()):
        """Execute a stored procedure and return results."""
        if not self.connection:
            raise Exception("Not connected to database")

        cursor = self.connection.cursor(pymysql.cursors.DictCursor)
        try:
            cursor.callproc(procedure_name, params)
            results = []
            for result in cursor.stored_results():
                results.extend(result.fetchall())
            return results
        finally:
            cursor.close()

    def commit(self):
        """Commit the current transaction."""
        if self.connection:
            self.connection.commit()

    def close(self):
        """Close the database connection."""
        if self.connection:
            self.connection.close()
            self.connection = None


def get_connection(role: str = "reader"):
    """
    Get a database connection.
    Convenience function for simple use cases.
    """
    conn = DatabaseConnection(role=role)
    if conn.connect():
        return conn
    return None
```

#### 2. Update Import in connection.py
**File**: `lambdas/lf-vero-prod-hwqa/app/database/connection.py`

Replace the entire file to import from the compatibility layer:

```python
"""
Database connection module.
Re-exports from db_compat for backwards compatibility with HWQA services.
"""
from app.database.db_compat import DatabaseConnection, get_connection

__all__ = ['DatabaseConnection', 'get_connection']
```

#### 3. Remove env_settings.py SSM Logic
**File**: `lambdas/lf-vero-prod-hwqa/app/config/env_settings.py`

The SSM parameter loading is now handled by db_resources. Simplify to:

```python
"""
Environment settings for HWQA.
Database credentials are now handled by the db_resources layer.
"""
import os
import logging

logger = logging.getLogger(__name__)


class Settings:
    """Application settings loaded from environment variables."""

    def __init__(self):
        self.environment = os.environ.get('ENVIRONMENT', 'dev')
        self.branch = os.environ.get('BRANCH', 'dev')
        self.timezone = os.environ.get('TIMEZONE', 'America/New_York')

        # These are no longer needed - db_resources handles database config
        # Keeping as None for backwards compatibility if any code references them
        self.mysql_host = None
        self.mysql_ro_host = None
        self.mysql_user = None
        self.mysql_password = None
        self.mysql_database = None

        logger.info(f"Settings initialized: environment={self.environment}, branch={self.branch}")


settings = Settings()
```

### Success Criteria:

#### Automated Verification:
- [ ] File exists: `lambdas/lf-vero-prod-hwqa/app/database/db_compat.py`
- [ ] Python syntax valid: `python -m py_compile lambdas/lf-vero-prod-hwqa/app/database/db_compat.py`

---

## Phase 3: Adapt Authentication Middleware

### Overview
Replace HWQA's JWT-based middleware with user context extraction from Lambda event (AssetWatch pattern).

### Key Changes:

#### 1. Rewrite Middleware
**File**: `lambdas/lf-vero-prod-hwqa/app/middleware.py`

Replace the JWT decoding with Lambda event context extraction:

```python
"""
Middleware for HWQA FastAPI application.
Extracts user context from Lambda/API Gateway event (AssetWatch pattern).
"""
from fastapi import Request
from fastapi.responses import JSONResponse
from app.database.db_compat import DatabaseConnection
import logging
import os

logger = logging.getLogger(__name__)

# Cognito groups allowed to access HWQA
ALLOWED_COGNITO_GROUPS = ["NikolaTeam", "ContractManufacturer", "HardwareQualityAssurance"]


def extract_cognito_id_from_event(event: dict) -> str | None:
    """
    Extract Cognito ID from Lambda event context.
    This mirrors the pattern used in db_resources.get_user_details().

    Format: "cognito-idp.region.amazonaws.com/poolId,cognito-idp.region.amazonaws.com/poolId:CognitoSignIn:{user-uuid}"
    """
    try:
        cognito_auth_provider = (
            event.get("requestContext", {})
            .get("identity", {})
            .get("cognitoAuthenticationProvider")
        )

        if cognito_auth_provider and ":CognitoSignIn:" in cognito_auth_provider:
            return cognito_auth_provider.split(":CognitoSignIn:")[1]

        return None
    except (KeyError, IndexError, AttributeError) as e:
        logger.warning(f"Failed to extract Cognito ID from event: {e}")
        return None


def extract_user_group_from_event(event: dict) -> str | None:
    """
    Extract user group from Lambda event IAM role.
    Format: "arn:aws:sts::account:assumed-role/rbac_role-{group}/{session}"
    """
    try:
        user_arn = (
            event.get("requestContext", {})
            .get("identity", {})
            .get("userArn", "")
        )

        if "rbac_role-" in user_arn:
            # Extract group from role name
            role_part = user_arn.split("/")[1] if "/" in user_arn else ""
            return role_part.replace("rbac_role-", "")

        return None
    except (KeyError, IndexError, AttributeError) as e:
        logger.warning(f"Failed to extract user group from event: {e}")
        return None


def get_user_context_from_db(cognito_id: str) -> dict:
    """
    Look up user details from database using Cognito ID.
    """
    if not cognito_id:
        return {
            "cognito_id": None,
            "user_id": None,
            "firstName": None,
            "lastName": None,
            "roles": [],
            "error": "No Cognito ID provided"
        }

    db = DatabaseConnection(role="reader")
    if not db.connect():
        return {
            "cognito_id": cognito_id,
            "user_id": None,
            "firstName": None,
            "lastName": None,
            "roles": [],
            "error": "Database connection failed"
        }

    try:
        cursor = db.connection.cursor(pymysql.cursors.DictCursor)

        # Query user by Cognito ID with roles
        query = """
            SELECT
                u.UserID,
                u.FirstName,
                u.LastName,
                u.Email,
                (
                    SELECT JSON_ARRAYAGG(r.RoleName)
                    FROM Users_Roles ur
                    JOIN Roles r ON ur.RoleID = r.RoleID
                    WHERE ur.UserID = u.UserID
                ) as roles
            FROM Users u
            WHERE u.CognitoID = %s
        """
        cursor.execute(query, (cognito_id,))
        result = cursor.fetchone()
        cursor.close()

        if result:
            roles = []
            if result.get('roles'):
                import json
                try:
                    roles_json = result['roles']
                    if isinstance(roles_json, str):
                        roles = json.loads(roles_json)
                    else:
                        roles = roles_json or []
                    roles = [r for r in roles if r]
                except (json.JSONDecodeError, TypeError):
                    roles = []

            return {
                "cognito_id": cognito_id,
                "user_id": result.get('UserID'),
                "firstName": result.get('FirstName'),
                "lastName": result.get('LastName'),
                "email": result.get('Email'),
                "roles": roles,
                "error": None
            }
        else:
            return {
                "cognito_id": cognito_id,
                "user_id": None,
                "firstName": None,
                "lastName": None,
                "roles": [],
                "error": f"User not found for Cognito ID: {cognito_id}"
            }
    except Exception as e:
        logger.error(f"Error looking up user: {e}")
        return {
            "cognito_id": cognito_id,
            "user_id": None,
            "firstName": None,
            "lastName": None,
            "roles": [],
            "error": str(e)
        }
    finally:
        db.close()


async def user_context_middleware(request: Request, call_next):
    """
    Middleware to extract user context from Lambda event and inject into request state.

    Uses AssetWatch pattern: extracts Cognito ID from API Gateway request context
    (populated by SigV4 auth), then looks up user details from database.
    """
    # Skip auth for health check endpoints
    path = request.url.path
    if path in ["/health", "/connection-info", "/public"]:
        return await call_next(request)

    cognito_id = None
    user_group = None

    # Check if this is a Lambda request with AWS event context
    if hasattr(request.scope, 'get') and request.scope.get('aws.event'):
        event = request.scope['aws.event']
        cognito_id = extract_cognito_id_from_event(event)
        user_group = extract_user_group_from_event(event)

        if cognito_id:
            logger.debug(f"Extracted Cognito ID from event: {cognito_id}, group: {user_group}")

    # For local development, use environment variable
    if not cognito_id and os.environ.get("LOCAL_COGNITO_ID"):
        cognito_id = os.environ.get("LOCAL_COGNITO_ID")
        logger.debug(f"Using LOCAL_COGNITO_ID: {cognito_id}")

    # Look up user context from database
    if cognito_id:
        user_context = get_user_context_from_db(cognito_id)
        user_context["user_group"] = user_group
    else:
        # No authentication - set default context
        user_context = {
            "cognito_id": None,
            "user_id": None,
            "firstName": "Anonymous",
            "lastName": "User",
            "roles": [],
            "user_group": None,
            "error": "No authentication context available"
        }
        logger.warning("No Cognito ID available - request may be unauthenticated")

    request.state.user_context = user_context
    return await call_next(request)


async def error_handler(request: Request, call_next):
    """Global error handler middleware."""
    try:
        return await call_next(request)
    except Exception as e:
        logger.error(f"Unhandled error: {e}")
        return JSONResponse(
            status_code=500,
            content={"detail": str(e)}
        )


# Need to import pymysql for cursor usage
import pymysql.cursors
```

### Success Criteria:

#### Automated Verification:
- [ ] Python syntax valid: `python -m py_compile lambdas/lf-vero-prod-hwqa/app/middleware.py`

---

## Phase 4: Update main.py for AssetWatch Integration

### Overview
Update the FastAPI app entry point to work with the new middleware and remove unnecessary CORS configuration (API Gateway handles CORS).

### Changes Required:

#### 1. Simplify main.py
**File**: `lambdas/lf-vero-prod-hwqa/app/main.py`

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os
import warnings

# Suppress Pydantic serialization warnings
warnings.filterwarnings("ignore", category=UserWarning, module="pydantic")

from app.routes import (
    auth_routes,
    sensor_shipment_routes,
    sensor_test_routes,
    glossary_routes,
)
from app.routes.sensor_dashboard_routes import router as sensor_dashboard_routes
from app.routes.sensor_conversion_routes import router as sensor_conversion_routes
from app.routes.hub_test_routes import router as hub_test_routes
from app.routes.hub_shipment_routes import router as hub_shipment_routes
from app.routes.hub_dashboard_routes import router as hub_dashboard_routes
from app.routes.bulk_test_routes import router as bulk_test_routes
from app.middleware import error_handler, user_context_middleware
from mangum import Mangum
import logging

# Initialize Sentry (using assetwatch's sentry layer)
try:
    from sentry_utils import initialize_sentry
    initialize_sentry()
except ImportError:
    pass  # Sentry not available locally

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s:%(name)s:%(message)s'
)

logger = logging.getLogger(__name__)

app = FastAPI(
    title="Hardware Quality Assurance API",
    description="API for hardware testing and quality assurance",
    version="0.1.0",
)

# CORS middleware - API Gateway also handles CORS, but this is needed for local dev
# In Lambda, the CORS headers from API Gateway take precedence
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # API Gateway OpenAPI spec controls actual CORS in Lambda
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add middleware - user_context must run before error_handler
app.middleware("http")(user_context_middleware)
app.middleware("http")(error_handler)

# Mount the routers
app.include_router(auth_routes)
app.include_router(sensor_dashboard_routes, prefix="/sensor/dashboard", tags=["Sensor Dashboard"])
app.include_router(sensor_test_routes, prefix="/sensor/tests", tags=["Sensor Tests"])
app.include_router(sensor_shipment_routes, prefix="/sensor/shipments", tags=["Sensor Shipments"])
app.include_router(glossary_routes, prefix="/glossary", tags=["Glossary"])
app.include_router(sensor_conversion_routes, prefix="/sensor/conversion", tags=["Sensor Conversion"])
app.include_router(hub_test_routes, prefix="/hub/tests", tags=["Hub Tests"])
app.include_router(hub_shipment_routes, prefix="/hub/shipments", tags=["Hub Shipments"])
app.include_router(hub_dashboard_routes, prefix="/hub/dashboard", tags=["Hub Dashboard"])
app.include_router(bulk_test_routes, prefix="/bulk", tags=["Bulk Testing"])


# Mangum handler for AWS Lambda
handler = Mangum(app)
```

### Success Criteria:

#### Automated Verification:
- [ ] Python syntax valid: `python -m py_compile lambdas/lf-vero-prod-hwqa/app/main.py`

---

## Phase 5: Remove Unnecessary Files

### Overview
Remove files that are now redundant because their functionality is provided by assetwatch layers.

### Files to Delete:
```
lambdas/lf-vero-prod-hwqa/app/config/env_settings.py  # Keep but simplified (Phase 2)
lambdas/lf-vero-prod-hwqa/app/services/user_service.py  # User lookup moved to middleware
lambdas/lf-vero-prod-hwqa/app/utils/auth.py  # If exists, JWT utils no longer needed
```

### Files to Keep (business logic):
```
lambdas/lf-vero-prod-hwqa/app/routes/*  # All route handlers
lambdas/lf-vero-prod-hwqa/app/services/*  # Keep all except user_service.py
lambdas/lf-vero-prod-hwqa/app/schemas/*  # All Pydantic models
lambdas/lf-vero-prod-hwqa/app/auth.py  # Role decorators still used
lambdas/lf-vero-prod-hwqa/app/errors.py  # Custom exceptions
```

### Success Criteria:

#### Automated Verification:
- [ ] No import errors when loading main.py

---

## Phase 6: Create OpenAPI Specification

### Overview
Create an OpenAPI spec file for the HWQA API Gateway, following AssetWatch patterns.

### Changes Required:

#### 1. Create OpenAPI Spec
**File**: `api/api-vero-hwqa.yaml`

```yaml
openapi: "3.0.1"
info:
  title: "hwqa-${branch}-${env}"
  version: "0.1.0"
servers:
- url: "https://api.${branch}.${env}.assetwatch.com/hwqa"
paths:
  /{proxy+}:
    x-amazon-apigateway-any-method:
      parameters:
      - name: proxy
        in: path
        required: true
        schema:
          type: string
      responses:
        "200":
          description: "200 response"
          headers:
            Access-Control-Allow-Origin:
              schema:
                type: "string"
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Empty"
      security:
      - sigv4: []
      x-amazon-apigateway-integration:
        uri: "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${lambda_arn}/invocations"
        httpMethod: "POST"
        responses:
          default:
            statusCode: "200"
            responseParameters:
              method.response.header.Access-Control-Allow-Origin: "'*'"
        passthroughBehavior: "when_no_match"
        contentHandling: "CONVERT_TO_TEXT"
        type: "aws_proxy"
    options:
      parameters:
      - name: proxy
        in: path
        required: true
        schema:
          type: string
      responses:
        "200":
          description: "200 response"
          headers:
            Access-Control-Allow-Origin:
              schema:
                type: "string"
            Access-Control-Allow-Methods:
              schema:
                type: "string"
            Access-Control-Allow-Headers:
              schema:
                type: "string"
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Empty"
      x-amazon-apigateway-integration:
        responses:
          default:
            statusCode: "200"
            responseParameters:
              method.response.header.Access-Control-Allow-Methods: "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
              method.response.header.Access-Control-Allow-Headers: "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,Sentry-Trace,Baggage'"
              method.response.header.Access-Control-Allow-Origin: "'*'"
        requestTemplates:
          application/json: "{\"statusCode\": 200}"
        passthroughBehavior: "when_no_match"
        type: "mock"
components:
  schemas:
    Empty:
      title: "Empty Schema"
      type: "object"
  securitySchemes:
    sigv4:
      type: "apiKey"
      name: "Authorization"
      in: "header"
      x-amazon-apigateway-authtype: "awsSigv4"
x-amazon-apigateway-gateway-responses:
  DEFAULT_4XX:
    responseParameters:
      gatewayresponse.header.Access-Control-Allow-Methods: "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
      gatewayresponse.header.Access-Control-Allow-Origin: "'*'"
      gatewayresponse.header.Access-Control-Allow-Headers: "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,Sentry-Trace,Baggage'"
  DEFAULT_5XX:
    responseParameters:
      gatewayresponse.header.Access-Control-Allow-Methods: "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
      gatewayresponse.header.Access-Control-Allow-Origin: "'*'"
      gatewayresponse.header.Access-Control-Allow-Headers: "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,Sentry-Trace,Baggage'"
```

### Success Criteria:

#### Automated Verification:
- [ ] File exists: `api/api-vero-hwqa.yaml`
- [ ] YAML is valid syntax

---

## Phase 7: Add Terraform Configuration

### Overview
Add terraform configuration for the HWQA Lambda and API Gateway.

### Changes Required:

#### 1. Add Lambda Definition
**File**: `terraform/lambdas.tf` (append to end of file)

```hcl
#######################
# HWQA Lambda
#######################

data "archive_file" "lf_vero_hwqa" {
  count       = local.create_db ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/lf-vero-prod-hwqa"
  output_path = "${path.module}/${local.lambda_archive_path}/lf-vero-prod-hwqa.zip"
}

resource "aws_lambda_function" "lf_vero_hwqa" {
  count       = local.create_db ? 1 : 0
  description = "Hardware Quality Assurance API - FastAPI with Mangum"

  environment {
    variables = {
      RDS_PARAMETERS = (var.env == "prod" && var.branch == "master") ? "/nikola/prod/rds/rds-parameters" : local.db_ssm_params
      SENTRY_DSN     = local.sentry_api_dsn
      ENV_VAR        = var.env
      ENVIRONMENT    = var.env
      BRANCH         = var.branch
    }
  }

  function_name    = "hwqa-${var.env}-${var.branch}"
  handler          = "app.main.handler"
  filename         = data.archive_file.lf_vero_hwqa[count.index].output_path
  source_code_hash = data.archive_file.lf_vero_hwqa[count.index].output_base64sha256

  layers = [
    aws_lambda_layer_version.pymysql_311.arn,
    aws_lambda_layer_version.db_resources_311.arn,
    local.lambda_layer_sentry
  ]

  memory_size                    = 256
  package_type                   = "Zip"
  reserved_concurrent_executions = -1
  role                           = aws_iam_role.hwqa_role[count.index].arn
  runtime                        = "python3.11"
  timeout                        = 30

  vpc_config {
    security_group_ids = (var.env == "prod" && var.branch == "master") ? ["sg-0e142012aac50584e", "sg-92a76ff3"] : [aws_security_group.lambda_access_control.id]
    subnet_ids         = (var.env == "prod" && var.branch == "master") ? ["subnet-03683540a0347f3b4", "subnet-0c3291d2109263317", "subnet-0884d85106e7a12e5"] : module.nikola_vpc.private_subnets
  }

  tags = {
    Application = "AssetWatch"
    Component   = "HWQA"
    Environment = var.env
  }
}
```

#### 2. Add IAM Role
**File**: `terraform/lambda-iam-roles.tf` (append to end of file)

```hcl
#######################
# HWQA Lambda IAM Role
#######################

resource "aws_iam_role" "hwqa_role" {
  count                = local.create_db ? 1 : 0
  description          = "Allows HWQA Lambda functions to call AWS services"
  name                 = "hwqa-${var.env}-${var.branch}-role"
  path                 = "/"
  max_session_duration = 3600

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
    Application = "AssetWatch"
    Component   = "HWQA"
    Environment = var.env
  }
}

resource "aws_iam_policy" "hwqa_policy" {
  count       = local.create_db ? 1 : 0
  name        = "hwqa-${var.env}-${var.branch}-policy"
  path        = "/"
  description = "Standard policies for HWQA lambda function"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Action" : [
          "ssm:GetParameter"
        ],
        "Effect" : "Allow",
        "Resource" : [
          "${local.lambda_policy_arn}"
        ]
      }
    ]
  })

  tags = {
    Application = "AssetWatch"
    Component   = "HWQA"
    Environment = var.env
  }
}

resource "aws_iam_role_policy_attachment" "hwqa_policy_attachment" {
  count      = local.create_db ? 1 : 0
  role       = aws_iam_role.hwqa_role[count.index].name
  policy_arn = aws_iam_policy.hwqa_policy[count.index].arn
}

resource "aws_iam_role_policy_attachment" "hwqa_managed_policy_attachment" {
  count      = local.create_db ? 1 : 0
  role       = aws_iam_role.hwqa_role[count.index].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
```

#### 3. Add API Gateway Configuration
**File**: `terraform/api-gateway.tf` (append to end of file)

```hcl
#######################
# HWQA API Gateway
#######################

resource "aws_api_gateway_rest_api" "hwqa" {
  count          = local.create_db ? 1 : 0
  name           = "hwqa-${var.env}-${var.branch}"
  description    = "Hardware Quality Assurance API"
  api_key_source = "HEADER"

  body = templatefile("../api/api-vero-hwqa.yaml",
    {
      lambda_arn = aws_lambda_function.lf_vero_hwqa[count.index].arn
      aws_region = data.aws_region.current.name
      branch     = var.branch
      env        = var.env
  })

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Application = "AssetWatch"
    Component   = "HWQA"
    Environment = var.env
  }
}

resource "aws_api_gateway_deployment" "hwqa" {
  count       = local.create_db ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.hwqa[count.index].id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.hwqa[count.index].body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "hwqa" {
  count         = local.create_db ? 1 : 0
  deployment_id = aws_api_gateway_deployment.hwqa[count.index].id
  rest_api_id   = aws_api_gateway_rest_api.hwqa[count.index].id
  stage_name    = var.env

  access_log_settings {
    destination_arn = "arn:aws:logs:us-east-2:${data.aws_caller_identity.current.account_id}:log-group:/aws/apigateway/accesslogs"
    format = jsonencode({
      requestId                     = "$context.requestId"
      ip                           = "$context.identity.sourceIp"
      requestTime                  = "$context.requestTime"
      httpMethod                   = "$context.httpMethod"
      routeKey                     = "$context.routeKey"
      status                       = "$context.status"
      protocol                     = "$context.protocol"
      responseLength               = "$context.responseLength"
      cognitoAuthenticationProvider = "$context.identity.cognitoAuthenticationProvider"
    })
  }

  tags = {
    Application = "AssetWatch"
    Component   = "HWQA"
    Environment = var.env
  }
}

resource "aws_api_gateway_method_settings" "hwqa" {
  count       = local.create_db ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.hwqa[count.index].id
  stage_name  = aws_api_gateway_stage.hwqa[count.index].stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "INFO"
    data_trace_enabled = var.env == "prod" ? var.enable_data_trace_in_prod : true
  }
}

resource "aws_api_gateway_base_path_mapping" "hwqa" {
  count       = local.create_db ? 1 : 0
  api_id      = aws_api_gateway_rest_api.hwqa[count.index].id
  stage_name  = aws_api_gateway_stage.hwqa[count.index].stage_name
  domain_name = aws_api_gateway_domain_name.aw_api.domain_name
  base_path   = "hwqa"
}

resource "aws_lambda_permission" "hwqa_api_gateway" {
  count         = local.create_db ? 1 : 0
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lf_vero_hwqa[count.index].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.hwqa[count.index].execution_arn}/*/*"
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Terraform validates: `cd terraform && terraform validate`

**Implementation Note**: After completing this phase, run terraform plan to verify the changes before applying.

---

## Phase 8: Update Frontend Configuration

### Overview
Ensure the frontend config properly maps `apiVeroHwqa` to the new API Gateway endpoint.

### Changes Required:

#### 1. Verify config.ts Entry
**File**: `frontend/src/config.ts`

The entry should already exist (from the previous migration attempt). Verify it looks like:

```typescript
apiVeroHwqa: {
  legacy: `${BASE_URL}/hwqa`,
  terraform: `${BASE_URL}/hwqa`,
},
```

And in the `apiConfig` object:

```typescript
apiVeroHwqa: {
  name: "apiVeroHwqa",
  URL: apiGatewayMap.apiVeroHwqa[ENV_TYPE],
},
```

### Success Criteria:

#### Automated Verification:
- [ ] Config contains apiVeroHwqa: `grep -q "apiVeroHwqa" frontend/src/config.ts`

---

## Phase 9: Fix Frontend TypeScript Errors

### Overview
Fix the TypeScript errors in the hwqa frontend code that were identified earlier.

### Key Errors to Fix:

#### 1. DateRangeFilter - Date type mismatch
**File**: `frontend/src/hwqa/components/common/DateRangeFilter/DateRangeFilter.tsx:37`

The Mantine DateRangeInput expects `DatesRangeValue<string>` but hwqa passes `[Date | null, Date | null]`.

#### 2. Notifications - Type mismatch
**File**: `frontend/src/hwqa/components/common/Notifications/notifications.tsx:123`

Mantine 8 notification API changed.

#### 3. Unused variables
Multiple files have unused variable warnings - clean these up.

### Success Criteria:

#### Automated Verification:
- [ ] TypeScript compiles: `cd frontend && npx tsc --noEmit 2>&1 | grep -c "hwqa" < 5` (fewer than 5 hwqa-specific errors)

---

## Testing Strategy

### Unit Tests:
- Test `DatabaseConnection` compatibility wrapper with mocked db_resources
- Test middleware user context extraction with sample Lambda events

### Integration Tests:
1. Deploy to dev environment
2. Test API calls through frontend
3. Verify database queries return correct data

### Manual Testing Steps:
1. Navigate to HWQA section in AssetWatch frontend
2. Verify dashboard data loads
3. Test creating a new sensor test
4. Test shipment operations
5. Verify all tabs work (sensor tests, hub tests, shipments, glossary, conversion)

---

## Performance Considerations

- FastAPI adds some overhead compared to raw Lambda handlers, but this is acceptable for HWQA's use case
- Mangum is lightweight and well-optimized
- Database connection per request is fine (same as other assetwatch lambdas)

---

## Migration Notes

- No database schema changes required - HWQA tables already exist in assetwatch database
- No data migration required - same database
- Frontend code already exists on db/IWA-14069 branch - just needs TypeScript fixes

---

## References

- Original research: `thoughts/shared/research/2025-12-01-hwqa-native-integration-migration.md`
- Previous plan: `thoughts/shared/plans/2025-12-01-hwqa-minimal-migration.md`
- HWQA repo: `~/repos/hwqa`
- AssetWatch repo: `~/repos/fullstack.assetwatch`
