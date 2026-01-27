---
date: 2025-12-17T10:30:00-06:00
researcher: Claude
git_commit: 8b251ce90ffdfec9a182f5e595930d7e41b7466d
branch: dev
repository: fullstack.assetwatch
topic: "Asset Alerts / Maintenance Requests - Comment Conversation System"
tags: [research, codebase, asset-alerts, comments, conversation, customer-cme-communication]
status: complete
last_updated: 2025-12-17
last_updated_by: Claude
---

# Research: Asset Alerts / Maintenance Requests - Comment Conversation System

**Date**: 2025-12-17T10:30:00-06:00
**Researcher**: Claude
**Git Commit**: 8b251ce90ffdfec9a182f5e595930d7e41b7466d
**Branch**: dev
**Repository**: fullstack.assetwatch

## Research Question
Understand how "Maintenance Requests" (also called "Asset Alerts") work, specifically the conversation/commenting functionality between Customer users and CME users. Find the frontend code, lambda methods, database tables, and stored procedures.

## Summary

The Asset Alert commenting system enables two-way communication between **Customer users** and **CME (Condition Monitoring Engineers) users**. Comments are stored in the `AssetAlertComment` table with flags indicating:
- **Who created it**: `CreatedByCustomerFlag` (0 = CME, 1 = Customer)
- **Whether it's been read**: `ConfirmedFlag` (0 = unconfirmed/unread, 1 = confirmed/read)

When a CME views an alert conversation, unconfirmed customer comments are automatically marked as confirmed (and vice versa). This provides a "read receipt" mechanism for the conversation.

## Detailed Findings

### Database Schema

#### Primary Table: `AssetAlertComment`

| Column | Type | Purpose |
|--------|------|---------|
| `AssetAlertCommentID` | INT (PK) | Primary key |
| `AssetAlertID` | INT (FK) | Links to parent AssetAlert |
| `Comment` | VARCHAR(3000) | The comment text |
| `DateCreated` | DATETIME | When comment was created |
| `UserID` | INT (FK) | User who created comment |
| `ConfirmedFlag` | INT | 0 = unconfirmed, 1 = confirmed (read) |
| `CreatedByCustomerFlag` | INT | 0 = CME user, 1 = Customer user |
| `ExternalCommentID` | VARCHAR | UUID for external sync |

#### Supporting Tables
- `AssetAlert` - Main alert with status, observation, recommendation, resolution
- `AssetAlertNextStep` - Tracks maintenance next steps/work orders
- `Users` - User information linked via `UserID` and `CognitoID`

### Comment Creation Flow

```
┌─────────────────┐     ┌────────────────────────────┐     ┌─────────────────────────┐
│   ReplyBox.tsx  │────▶│  useAddAlertComment.ts     │────▶│ AssetAlertNextStepService│
│   (User types)  │     │  (TanStack Mutation)       │     │ addAlertComment()       │
└─────────────────┘     └────────────────────────────┘     └───────────┬─────────────┘
                                                                       │
                                                                       ▼
┌─────────────────┐     ┌────────────────────────────┐     ┌─────────────────────────┐
│AssetAlertComment│◀────│ AssetAlertComment_Update   │◀────│lf-vero-prod-assetalert- │
│   (DB Table)    │     │  (Stored Procedure)        │     │nextstep Lambda          │
└─────────────────┘     └────────────────────────────┘     └─────────────────────────┘
```

#### Key Code Locations

1. **Frontend Component**: `frontend/src/components/AlertConversation/ReplyBox.tsx`
2. **React Hook**: `frontend/src/components/AlertConversation/hooks/useAddAlertComment.ts`
3. **API Service**: `frontend/src/shared/api/AssetAlertNextStepService.ts:97-121`
4. **Lambda Handler**: `lambdas/lf-vero-prod-assetalertnextstep/main.py:383-405`
5. **Stored Procedure**: `mysql/db/procs/R__PROC_AssetAlertComment_Update.sql`

### Customer vs CME Flag Logic

The `ccflg` (CreatedByCustomerFlag) is determined in the frontend API service:

```typescript
// AssetAlertNextStepService.ts:113
ccflg: cognitoUserGroup[0] === "Customer" ? 1 : 0
```

- **ccflg = 1**: Comment created by a Customer user
- **ccflg = 0**: Comment created by a CME/internal user

### Comment Confirmation (Read Receipt) Logic

When comments are fetched via `useAlertConversation.ts`, unconfirmed comments from the "other" user type are automatically confirmed:

```typescript
// useAlertConversation.ts:136-148
useEffect(() => {
  if (isCustomer) return;  // Only CME auto-confirms
  if (!unconfirmedComments?.length) return;
  // ... auto-confirm logic
  handleUnconfirmedComments(commentsToConfirm);
}, [unconfirmedComments, isCustomer, handleUnconfirmedComments]);
```

The stored procedure `AssetAlertComment_UpdateStatus` ensures only opposite-party comments get confirmed:

```sql
-- R__PROC_AssetAlertComment_UpdateStatus.sql:17-21
UPDATE AssetAlertComment
SET ConfirmedFlag=1
WHERE AssetAlertCommentID=inAssetAlertCommentID
  AND CreatedByCustomerFlag <> localCustomerUser  -- Only confirm OTHER party's comments
  AND ConfirmedFlag=0;
```

### Fetching Conversation History

The conversation includes multiple activity types fetched in parallel:

```typescript
// AssetAlertNextStepService.ts:22-39
const activities = await Promise.all([
  fetchActivity("getCommentConversationActivity", aaid),
  fetchActivity("getObservationCreatedConversationActivity", aaid),
  fetchActivity("getObservationUpdatedConversationActivity", aaid),
  fetchActivity("getNextStepCreatedConversationActivity", aaid),
  fetchActivity("getNextStepCompletedConversationActivity", aaid),
  fetchActivity("getUploadFileConversationActivity", aaid),
  fetchActivity("getAssetAlertChartMetadataConversationActivity", aaid),
  fetchActivity("getAssetAlertLastComment", aaid),
  // ... precision recommendations
]);
```

### Email Notifications

When a customer adds a comment, the system can send email notifications via:
- Lambda method: `addNewAssetAlertCommentAndNotify` (main.py:425-451)
- Notification Lambda: `lf-vero-prod-notification` with `emailCommentUpdate` method

## Code References

### Frontend
- `frontend/src/components/AlertConversation/AlertConversation.tsx` - Main conversation component
- `frontend/src/components/AlertConversation/Message.tsx` - Individual message display
- `frontend/src/components/AlertConversation/ReplyBox.tsx` - Comment input
- `frontend/src/components/AlertConversation/hooks/useAddAlertComment.ts` - Add comment mutation
- `frontend/src/components/AlertConversation/hooks/useAlertConversation.ts` - Fetch & auto-confirm logic
- `frontend/src/shared/api/AssetAlertNextStepService.ts` - API service layer
- `frontend/src/shared/types/asset-alerts/AssetAlertComment.ts` - TypeScript type definition

### Backend (Lambda)
- `lambdas/lf-vero-prod-assetalertnextstep/main.py:383-480` - Comment CRUD operations
- `lambdas/lf-vero-prod-notification/lambda_function.py:649` - Email notifications

### Database
- `mysql/db/procs/R__PROC_AssetAlertComment_Update.sql` - Insert/update comments
- `mysql/db/procs/R__PROC_AssetAlertComment_UpdateStatus.sql` - Confirm comments (read receipts)
- `mysql/db/procs/R__PROC_AssetAlert_GetCommentConversationActivity.sql` - Fetch comment history
- `mysql/db/procs/R__PROC_AssetAlertComment_GetLastComment.sql` - Get most recent comment
- `mysql/db/triggers/R__TRIGGER_INSERT_AssetAlertCommentTrigger.sql` - Insert trigger
- `mysql/db/triggers/R__TRIGGER_UPDATE_AssetAlertCommentTrigger.sql` - Update trigger

## Architecture Insights

1. **Terminology**: The codebase uses "Asset Alerts" internally, not "Maintenance Requests" (though users may call them that)

2. **Conversation Types**: The "conversation" includes more than just comments:
   - Comments (user messages)
   - Observation created/updated
   - Next step created/completed
   - File uploads
   - Chart attachments
   - Precision recommendations

3. **Optimistic Updates**: The frontend uses TanStack Query's optimistic update pattern - comments appear immediately before server confirmation

4. **Polling**: Conversations auto-refresh every 10 seconds (`refetchInterval: 10000`)

5. **Read Receipts**: The `ConfirmedFlag` acts as a read receipt - when one party views comments from the other party, those comments are automatically marked as confirmed

## SQL Queries for Investigation

### View all comments for a specific alert
```sql
SELECT
  aac.AssetAlertCommentID,
  aac.AssetAlertID,
  aac.Comment,
  aac.DateCreated,
  aac.ConfirmedFlag,
  aac.CreatedByCustomerFlag,
  u.FirstName,
  u.LastName,
  u.CognitoID
FROM AssetAlertComment aac
JOIN Users u ON aac.UserID = u.UserID
WHERE aac.AssetAlertID = <ALERT_ID>
ORDER BY aac.DateCreated ASC;
```

### Find unconfirmed comments (not yet read by other party)
```sql
SELECT
  aac.*,
  u.FirstName,
  u.LastName
FROM AssetAlertComment aac
JOIN Users u ON aac.UserID = u.UserID
WHERE aac.ConfirmedFlag = 0
ORDER BY aac.DateCreated DESC
LIMIT 50;
```

### Count comments by user type
```sql
SELECT
  aac.AssetAlertID,
  SUM(CASE WHEN aac.CreatedByCustomerFlag = 1 THEN 1 ELSE 0 END) AS customer_comments,
  SUM(CASE WHEN aac.CreatedByCustomerFlag = 0 THEN 1 ELSE 0 END) AS cme_comments
FROM AssetAlertComment aac
GROUP BY aac.AssetAlertID
HAVING customer_comments > 0 AND cme_comments > 0;
```

### View recent comment activity with user details
```sql
SELECT
  aa.AssetAlertID,
  c.CustomerName,
  aac.Comment,
  aac.DateCreated,
  CASE WHEN aac.CreatedByCustomerFlag = 1 THEN 'Customer' ELSE 'CME' END AS CommentBy,
  CASE WHEN aac.ConfirmedFlag = 1 THEN 'Read' ELSE 'Unread' END AS Status,
  u.FirstName,
  u.LastName
FROM AssetAlertComment aac
JOIN AssetAlert aa ON aac.AssetAlertID = aa.AssetAlertID
JOIN Customer c ON aa.CustomerID = c.CustomerID
JOIN Users u ON aac.UserID = u.UserID
ORDER BY aac.DateCreated DESC
LIMIT 20;
```

## Open Questions
- Are there specific bugs related to comment confirmation not working properly?
- Is there a timing issue with the auto-confirmation useEffect?
- Are there edge cases where `CreatedByCustomerFlag` might be set incorrectly?
