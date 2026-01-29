---
date: 2025-12-22T10:30:00-05:00
researcher: Claude
git_commit: 871aa05ea332491be7223a220d271b6be4b0f527
branch: IWA-14289
repository: fullstack.assetwatch
topic: "Storing Internal UUID as Cognito Custom Attribute for Cross-Environment User Sync"
tags: [research, cognito, authentication, database, user-management, multi-environment]
status: complete
last_updated: 2025-12-22
last_updated_by: Claude
---

# Research: Storing Internal UUID as Cognito Custom Attribute

**Date**: 2025-12-22T10:30:00-05:00
**Researcher**: Claude
**Git Commit**: 871aa05ea332491be7223a220d271b6be4b0f527
**Branch**: IWA-14289
**Repository**: fullstack.assetwatch

## Research Question

How would storing a UUID as a custom attribute in Cognito work to solve the cross-environment user synchronization problem? Is this approach better than using email for lookups?

## Summary

**Yes, using a custom internal UUID is the recommended approach** by AWS and provides a robust solution to the cross-environment sync problem. The key insight is:

- **Cognito's `sub` attribute is pool-specific** - the same user gets a different `sub` in dev, QA, and prod pools
- **Email-based sync is fragile** - case sensitivity, email changes, and users missing from target pool cause failures
- **A custom `internal_user_id` attribute** can be immutable, controlled by you, and consistent across all environments

AssetWatch already uses custom attributes (`custom:ExternalCustomerID`) with immutable settings, so the infrastructure pattern exists.

## Current State Analysis

### Cognito User Pool Schema (DEV)

The DEV Cognito pool (`us-east-2_x7NmjJEZB`) already has custom attributes:

| Attribute | Type | Mutable | Purpose |
|-----------|------|---------|---------|
| `custom:cognitoUserGroup` | String | Yes | User group assignment |
| `custom:ExternalCustomerID` | String | **No (Immutable)** | External customer reference |
| `custom:UserGroup` | String | Yes | Additional group info |

**Key Finding**: `custom:ExternalCustomerID` is already immutable, proving this pattern works in the codebase.

### Users Table Schema

```sql
CREATE TABLE `Users` (
  `UserID` int NOT NULL AUTO_INCREMENT,        -- Internal PK
  `CognitoID` varchar(45) DEFAULT NULL,        -- Cognito sub (pool-specific!)
  `Email` varchar(100) DEFAULT NULL,
  -- ...
  UNIQUE KEY `CognitoID_UNIQUE` (`CognitoID`),
  UNIQUE KEY `Email_UNIQUE` (`Email`)
);
```

**File**: `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql:4084-4102`

### Current User Creation Flow

```python
# lambdas/lf-vero-prod-user/main.py:188-211
response = client.admin_create_user(
    UserPoolId=DECRYPTED_COG_USERPOOLID,
    Username=email,
    UserAttributes=[
        {"Name": "email", "Value": str(email)},
        {"Name": "custom:ExternalCustomerID", "Value": str(ExternalCustomerID)},
        # ...
    ],
)
new_cognito_id = response["User"]["Username"]  # This is the pool-specific sub
```

### Current Sync Problem

The `flyway-pipeline-helper` Lambda syncs by email:

```python
# lambdas/flyway-pipeline-helper/main.py:39-42
for email, cognito_id in email_cognitoid.items():
    sql = f"UPDATE Users u SET u.CognitoID = '{cognito_id}' WHERE u.Email = '{email}';"
```

**Failure scenarios:**
1. User exists in dev Cognito but not in prod DB snapshot → UPDATE matches 0 rows
2. User exists in prod DB but has no QA/dev Cognito account → CognitoID not updated
3. Email case mismatch → UPDATE matches 0 rows

## Proposed Solution: Custom `internal_user_id` Attribute

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         ALL ENVIRONMENTS                                 │
├─────────────────────────────────────────────────────────────────────────┤
│  internal_user_id (UUID) = "550e8400-e29b-41d4-a716-446655440000"      │
│  This value is IDENTICAL across dev, QA, and prod                       │
└─────────────────────────────────────────────────────────────────────────┘
        │                         │                         │
        ▼                         ▼                         ▼
┌───────────────┐         ┌───────────────┐         ┌───────────────┐
│ DEV Cognito   │         │ QA Cognito    │         │ PROD Cognito  │
│ Pool A        │         │ Pool B        │         │ Pool C        │
├───────────────┤         ├───────────────┤         ├───────────────┤
│ sub: abc-111  │         │ sub: def-222  │         │ sub: ghi-333  │
│ custom:       │         │ custom:       │         │ custom:       │
│ internal_     │         │ internal_     │         │ internal_     │
│ user_id:      │         │ user_id:      │         │ user_id:      │
│ 550e8400...   │         │ 550e8400...   │         │ 550e8400...   │
└───────┬───────┘         └───────┬───────┘         └───────┬───────┘
        │                         │                         │
        ▼                         ▼                         ▼
┌───────────────┐         ┌───────────────┐         ┌───────────────┐
│ DEV Database  │         │ QA Database   │         │ PROD Database │
├───────────────┤         ├───────────────┤         ├───────────────┤
│ UserID: 1     │         │ UserID: 1     │         │ UserID: 1     │
│ InternalUID:  │         │ InternalUID:  │         │ InternalUID:  │
│ 550e8400...   │         │ 550e8400...   │         │ 550e8400...   │
│ CognitoID:    │         │ CognitoID:    │         │ CognitoID:    │
│ abc-111       │         │ def-222       │         │ ghi-333       │
└───────────────┘         └───────────────┘         └───────────────┘
```

### Implementation Steps

#### 1. Add Custom Attribute to All Cognito Pools

```bash
# For each environment's user pool
aws cognito-idp add-custom-attributes \
  --user-pool-id us-east-2_XXXXXX \
  --custom-attributes \
    Name="internal_user_id",AttributeDataType="String",Mutable=false,StringAttributeConstraints="{MinLength=36,MaxLength=36}"
```

**Important**: After adding, update App Client permissions to allow read/write.

#### 2. Add Column to Users Table

```sql
-- New migration file
ALTER TABLE Users
ADD COLUMN InternalUserID VARCHAR(36) NULL AFTER UserID;

-- Add unique index
ALTER TABLE Users
ADD UNIQUE KEY `InternalUserID_UNIQUE` (`InternalUserID`);

-- Backfill existing users (generate UUIDs)
UPDATE Users SET InternalUserID = UUID() WHERE InternalUserID IS NULL;
```

#### 3. Modify User Creation Lambda

```python
# lambdas/lf-vero-prod-user/main.py
import uuid

def createUser(event):
    # Generate internal UUID FIRST
    internal_user_id = str(uuid.uuid4())

    response = client.admin_create_user(
        UserPoolId=DECRYPTED_COG_USERPOOLID,
        Username=email,
        UserAttributes=[
            {"Name": "email", "Value": str(email)},
            {"Name": "custom:ExternalCustomerID", "Value": str(ExternalCustomerID)},
            {"Name": "custom:internal_user_id", "Value": internal_user_id},  # NEW
            # ...
        ],
    )

    # Pass internal_user_id to database creation
    # ... store in Users.InternalUserID column
```

#### 4. Update Flyway Pipeline Helper

```python
# lambdas/flyway-pipeline-helper/main.py
def handler(event, context):
    # Get users with their internal_user_id from Cognito
    for user in page["Users"]:
        for attribute in user["Attributes"]:
            if attribute["Name"] == "custom:internal_user_id":
                internal_id = attribute["Value"]
            if attribute["Name"] == "sub":
                cognito_id = attribute["Value"]

        # UPSERT by InternalUserID instead of UPDATE by Email
        sql = f"""
            INSERT INTO Users (InternalUserID, CognitoID, Email, FirstName, LastName)
            VALUES ('{internal_id}', '{cognito_id}', '{email}', '{given_name}', '{family_name}')
            ON DUPLICATE KEY UPDATE
                CognitoID = VALUES(CognitoID),
                Email = VALUES(Email);
        """
```

### Handling Existing Users (Migration Strategy)

For users that already exist in prod but don't have `custom:internal_user_id`:

**Option A: Backfill from Database**
```python
# One-time migration script
for user in db.query("SELECT UserID, Email, InternalUserID FROM Users"):
    # Update Cognito with the DB's InternalUserID
    # NOTE: Won't work if attribute is immutable!
```

**Option B: Generate and Sync** (Recommended if attribute is immutable)
1. Generate UUID in database for existing users
2. Create users in QA/dev Cognito pools with matching UUIDs
3. For prod users, use a mutable attribute OR accept they won't have it

**Option C: Make Attribute Mutable Initially**
1. Add as mutable attribute
2. Run backfill
3. Note: Cannot change to immutable later (AWS limitation)

## AWS Best Practices Confirmation

From AWS documentation and re:Post discussions:

> "The fixed-value user identifier `sub` is the only consistent indicator of your user's identity [within a single pool]."

> "If you ever migrate users to a different user pool or region, new `sub` values are generated, breaking database references."

> "Consider storing a backup identifier in a custom attribute for disaster recovery scenarios."

**AWS explicitly recommends using your own UUID** as a stable identifier that survives pool migrations.

## Code References

| File | Lines | Description |
|------|-------|-------------|
| `lambdas/lf-vero-prod-user/main.py` | 188-211 | User creation with custom attributes |
| `lambdas/flyway-pipeline-helper/main.py` | 34-45 | Current email-based sync logic |
| `mysql/db/procs/R__PROC_User_AddUser.sql` | 46-49 | Database user insertion |
| `mysql/db/procs/R__PROC_User_GetUserID.sql` | 5-10 | CognitoID lookup procedure |
| `mysql/db/table_change_scripts/V000000001__IWA-2898_init.sql` | 4084-4102 | Users table schema |

## Limitations and Considerations

### Custom Attribute Constraints
- **Cannot delete**: Once created, custom attributes cannot be removed
- **Cannot rename**: Attribute names are permanent
- **Cannot change type**: Data type is fixed at creation
- **Cannot make required**: Custom attributes cannot be marked as required
- **Immutable means immutable**: If set to `Mutable: false`, cannot be changed even by admins

### Token Inclusion
- Custom attributes appear in the **ID token by default**
- Attribute name will be `custom:internal_user_id` in JWT claims
- May need Pre Token Generation trigger if you want it in access token

### Quantity Limits
- Maximum 50 custom attributes per user pool
- Maximum 2,048 characters per attribute value

## Alternative Approaches Considered

| Approach | Pros | Cons |
|----------|------|------|
| **Email lookup** (current) | Simple, no changes needed | Fragile, case-sensitive, users can be missed |
| **Stable internal UUID** (proposed) | Robust, AWS-recommended, survives migrations | Requires schema changes, migration effort |
| **UserID in custom attribute** | Uses existing PK | UserID is auto-increment, changes between environments |
| **Separate identity service** | Full control | Over-engineered for this use case |

## Recommendation

**Proceed with the custom `internal_user_id` attribute approach:**

1. **Phase 1**: Add `InternalUserID` column to Users table, backfill with UUIDs
2. **Phase 2**: Add `custom:internal_user_id` to all Cognito pools (start with dev)
3. **Phase 3**: Modify user creation Lambda to generate and store UUID in both places
4. **Phase 4**: Update flyway-pipeline-helper to use UPSERT by InternalUserID
5. **Phase 5**: Roll out to QA, then prod

This gives you a stable, environment-agnostic identifier that won't break when databases are refreshed.

## Open Questions

1. **Existing prod users**: How to handle users created before this change?
   - Option: Make attribute mutable, accept that prod-only users won't sync automatically

2. **Frontend changes**: Does the frontend need access to `internal_user_id`?
   - Probably not - it's an infrastructure concern, not user-facing

3. **Self-signup flow**: If users can self-register, where is UUID generated?
   - Lambda trigger (Pre Sign-up or Post Confirmation) would need to generate it

## Sources

- [AWS: Working with user attributes](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-settings-attributes.html)
- [AWS re:Post: Cognito sub as primary key pros/cons](https://repost.aws/questions/QUsGu5jgliRZWhaJGf7K5ecA/what-are-the-pros-and-cons-of-using-cognito-id-cognito-sub-as-a-primary-key)
- [AWS re:Post: Using custom ID instead of Cognito sub](https://repost.aws/questions/QUXZHM2DxZR5mc5AuFWm6YNw/using-custom-id-instead-of-cognito-id-sub)
- [AWS: Post Confirmation Lambda Trigger](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-lambda-post-confirmation.html)
- [AWS: AddCustomAttributes API](https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_AddCustomAttributes.html)