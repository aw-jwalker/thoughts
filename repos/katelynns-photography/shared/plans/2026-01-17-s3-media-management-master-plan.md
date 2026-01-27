# S3 Media Management Master Plan

## Overview

This master plan covers two related but distinct features for managing media assets via S3:

1. **Portfolio Images** - Public gallery images for the website, managed by admins via CMS
2. **Client Albums** - Private photo albums shared with specific clients, with expiring access

Both features will use S3 as the consistent storage backend, moving away from git-based media storage for the portfolio.

## Current State

### What Exists Today

| Component       | Status       | Notes                                                                                              |
| --------------- | ------------ | -------------------------------------------------------------------------------------------------- |
| S3 Buckets      | Exists       | `katelynns-photography-portfolio-assets` (public), `katelynns-photography-client-albums` (private) |
| DecapCMS        | Working      | Currently stores images in git (`frontend/public/images`)                                          |
| Client Portal   | Working      | Authentication via Cognito, dashboard at `/client/dashboard`                                       |
| Presigned URLs  | Working      | Lambda generates time-limited download URLs                                                        |
| Album Structure | Needs Change | Currently `albums/{user_email}/album_name/` - doesn't support multi-client assignment              |

### Key Gaps

1. **No S3 integration with DecapCMS** - Portfolio images go to git, not S3
2. **No admin UI for album uploads** - Albums must be uploaded via AWS Console/CLI
3. **Single-client album design** - Current structure embeds user email in S3 path
4. **No access expiration** - Clients can access albums indefinitely
5. **No Lightroom integration** - Manual upload process only

## Desired End State

### Portfolio Images (Public)

- Admin uses DecapCMS to manage galleries
- Images are stored in S3, served via CloudFront/Amplify
- Each gallery can have 10-50+ images
- Images are optimized for web display
- CMS shows image picker/uploader that works with S3

### Client Albums (Private)

- Admin uploads albums via:
  - **Primary:** Adobe Lightroom Publish Service (if no additional cost)
  - **Backup:** CLI (`aws s3 sync`) for testing/quick uploads
  - **Future:** Web-based admin UI (drag-and-drop)
- Albums are stored independently of client assignments
- Multiple clients can be assigned to the same album
- Download access expires X days/months after event date
- Clients can download individual photos or entire albums (ZIP)

## Architecture Changes Required

### 1. Portfolio Images - S3 Integration with DecapCMS

**Current Flow:**

```
Admin uploads image in DecapCMS
  → Image committed to git (frontend/public/images/)
  → Git push triggers Amplify rebuild
  → Image served from Amplify static hosting
```

**New Flow:**

```
Admin uploads image in DecapCMS
  → Image uploaded directly to S3 (portfolio-assets bucket, public read)
  → CMS stores S3 URL in content JSON
  → Git push triggers Amplify rebuild (content only, not images)
  → Images served directly from S3 (public bucket)
```

**Note:** We moved from CloudFront to Amplify hosting (see `2026-01-16-switch-to-amplify-hosting.md`). The portfolio-assets S3 bucket is configured for public read access, so images are served directly from S3 without a CDN. This is fine for low-to-moderate traffic.

**Key Decision:** DecapCMS supports custom media libraries. We need to implement an S3 media handler.

### 2. Client Albums - Multi-Client Assignment

**Current S3 Structure (Single Client):**

```
s3://katelynns-photography-client-albums/
  albums/
    john.doe@example.com/
      smith-wedding-2026/
        IMG_001.jpg
        IMG_002.jpg
```

**New S3 Structure (Multi-Client):**

```
s3://katelynns-photography-client-albums/
  albums/
    {album-id}/                    # UUID or slug
      metadata.json                # Album metadata (name, event date, expiry)
      photos/
        IMG_001.jpg
        IMG_002.jpg
        ...
```

**DynamoDB Tables (Three-Table Design):**

Table naming convention: Singular (Album, User, User_Album)

```
Album Table (PK: album_id)
─────────────────────────────────────────────────────────────────
album_id        | name            | event_date | photo_count | ...
smith-wed-2026  | Smith Wedding   | 2026-01-15 | 247         |

User Table (PK: email)
─────────────────────────────────────────────────────────────────
email                | first_name | last_name | phone        | created_at
john@example.com     | John       | Smith     | 303-555-1234 | 2026-01-17T...

User_Album Table (PK: album_id, SK: email, GSI: email)
─────────────────────────────────────────────────────────────────
album_id        | email                | expires_at           | assigned_at
smith-wed-2026  | john@example.com     | 2026-07-15T00:00:00Z | 2026-01-17T...
smith-wed-2026  | jane@example.com     | 2026-07-15T00:00:00Z | 2026-01-17T...
```

**Key Decisions Made:**

- Three-table normalized design (Album, User, User_Album)
- User table supplements Cognito (stores business data like phone)
- GSI on User_Album.email for efficient "list user's albums" query
- Scan operations acceptable at expected scale (<500 albums)

### 3. Access Expiration

**Implementation Options:**

| Option                                           | Pros                     | Cons                                       |
| ------------------------------------------------ | ------------------------ | ------------------------------------------ |
| **A) Check expiry at API level**                 | Simple, immediate effect | Requires API call for every access         |
| **B) Revoke Cognito access**                     | Leverages existing auth  | Complex to manage per-album                |
| **C) Short-lived presigned URLs + expiry check** | Secure, standard pattern | Need to check expiry before generating URL |

**Recommended:** Option C - Check expiry date before generating presigned URLs. If expired, return 403.

### 4. Lightroom Publish Service

**Research Needed:**

- Does Adobe Lightroom Classic support custom S3 publish services?
- Is there an existing plugin, or do we need to build one?
- Cost: Must be free (included in Creative Cloud subscription)

**Fallback:** If Lightroom integration is complex, prioritize CLI workflow first.

## Implementation Phases

This work is split into implementation plans, with some features deferred to follow-up plans.

### Plan A: Portfolio Images (S3 + DecapCMS)

**Status:** ✅ COMPLETED - See `2026-01-17-portfolio-s3-media-library.md`

**Scope:**

- Configure S3 bucket for public portfolio images
- Implement DecapCMS S3 media library integration
- Migrate existing images from git to S3
- Update Astro pages to reference S3 URLs

**Complexity:** Medium
**Dependencies:** None (can be done independently)

### Plan B: Client Albums (Multi-Client + Expiration)

**Status:** ✅ COMPLETED - See `2026-01-24-client-albums-multi-client.md`

**Scope:**

- Redesign S3 structure for multi-client albums
- Create DynamoDB tables (Album, User, User_Album)
- Update Lambda APIs for new structure
- Add expiration checking logic
- Update client portal UI for new album structure
- Basic on-demand ZIP download (with 500-photo limit)
- CLI workflow for album uploads

**Complexity:** High
**Dependencies:**

- Requires DynamoDB (new infrastructure)
- Terraform updates for tables and IAM

**Deferred to follow-up plans:**

- Lightroom integration (see Plan C below)
- Advanced ZIP handling with cost optimization (see Plan D below)

---

## Follow-Up Plans (To Be Created)

### Plan C: Lightroom Integration

**Status:** 📝 NOT STARTED - Plan needs to be created

**Why separate:** Lightroom integration is a nice-to-have that shouldn't block core album functionality. It requires research into plugin options and may have complexities around authentication and publish service implementation.

**Scope (tentative):**

- Research Adobe Lightroom Classic S3 publish service options
- Evaluate existing plugins vs. custom Lua plugin
- Implement publish service that uploads to `albums/{album-id}/photos/`
- Optionally generate `metadata.json` from Lightroom metadata
- Handle incremental sync (add/remove photos)

**Research questions:**

1. Does Lightroom Classic support custom S3 publish services natively?
2. Are there existing free plugins? (e.g., Jeffrey Friedl's plugins)
3. If custom plugin needed, what's the Lua SDK complexity?
4. How to handle album ID generation from Lightroom?

**AWS services to learn:** None new (uses existing S3)

**Dependencies:** Plan B must be complete (S3 structure finalized)

### Plan D: ZIP Generation & Storage Optimization

**Status:** 📝 NOT STARTED - Plan needs to be created

**Why separate:** The MVP uses simple on-demand ZIP generation with a 30-day cache. This follow-up plan will implement cost-optimized ZIP handling using additional AWS services, which is a great learning opportunity.

**Scope (tentative):**

- Event-driven ZIP generation (S3 Events → SQS → Lambda)
- Or scheduled batch generation (EventBridge → Lambda)
- S3 storage class transitions for cost optimization:
  - ZIP files: Standard → delete after 30 days, OR
  - ZIP files: Standard (30 days) → Glacier (long-term archive)
- Album archival workflow (move old albums to Glacier)
- Handle large albums (>500 photos) with Step Functions
- Cost monitoring with AWS Cost Explorer

**AWS services to learn:**

| Service                    | Purpose                                |
| -------------------------- | -------------------------------------- |
| **S3 Event Notifications** | Trigger on photo upload                |
| **SQS**                    | Queue ZIP generation jobs              |
| **EventBridge**            | Scheduled cleanup/archival jobs        |
| **S3 Intelligent-Tiering** | Automatic cost optimization            |
| **S3 Glacier**             | Long-term archive storage (~$0.004/GB) |
| **Step Functions**         | Orchestrate large album ZIP generation |
| **Cost Explorer**          | Monitor and optimize costs             |

**Cost optimization strategies:**

| Strategy                  | Monthly Cost (150GB ZIPs) | Complexity            |
| ------------------------- | ------------------------- | --------------------- |
| Store forever (Standard)  | $3.45                     | Low                   |
| 30-day cache, then delete | ~$1-2                     | Low                   |
| 30-day Standard → Glacier | ~$0.80                    | Medium                |
| On-demand only, no cache  | $0                        | Medium (timeout risk) |

**Dependencies:** Plan B must be complete

## Technical Decisions

### For Portfolio Images: 📋 PLANNED

See `2026-01-17-portfolio-s3-media-library.md` for details.

1. **Image Optimization:** Preserve originals, lazy loading for web display
2. **DecapCMS Media Library:** Custom S3 integration (not yet implemented)

### For Client Albums: ✅ DECIDED

See `2026-01-24-client-albums-multi-client.md` for details.

1. **Database Choice:** ✅ DynamoDB with three tables (Album, User, User_Album)

2. **Album Metadata Storage:** ✅ Hybrid approach
   - DynamoDB is authoritative for runtime queries
   - `metadata.json` in S3 is optional input (for Lightroom workflow handoff)
   - Album fields: name, event_date, photo_count, shoot_type, location, notes

3. **ZIP Download Implementation:** ✅ On-demand with caching (MVP)
   - Generate on first request, cache in S3 for 30 days
   - 500 photo soft limit (Lambda timeout constraint)
   - 6-hour presigned URLs for ZIP downloads (vs 1-hour for photos)
   - Advanced optimization deferred to Plan D

4. **Lightroom Integration:** ⏳ DEFERRED to Plan C
   - Not blocking core album functionality
   - S3 structure designed to support it (metadata.json handoff)

5. **Admin Assignment UI:** ✅ CLI + API for MVP
   - `aws s3 sync` for uploads
   - REST API for registration and assignment
   - Web UI deferred to future

## Cost Considerations

### Portfolio Images (Estimated Monthly)

| Component   | Cost            | Notes                                  |
| ----------- | --------------- | -------------------------------------- |
| S3 Storage  | ~$0.50          | ~20GB portfolio images                 |
| S3 Requests | ~$0.05          | PUT/GET requests (direct S3 access)    |
| S3 Transfer | ~$0-2           | Data transfer out (depends on traffic) |
| **Total**   | **~$0.50-2.50** | Low traffic = low cost                 |

**Note:** No CloudFront CDN - images served directly from S3. For high traffic, consider adding CloudFront later.

### Client Albums (Estimated Monthly)

| Component   | Cost       | Notes                               |
| ----------- | ---------- | ----------------------------------- |
| S3 Storage  | ~$3-10     | 100-500GB, lifecycle rules help     |
| S3 Requests | ~$0.10     | Presigned URL generation, downloads |
| DynamoDB    | ~$0-1      | On-demand, minimal reads/writes     |
| Lambda      | ~$0        | Free tier covers expected usage     |
| **Total**   | **~$3-11** | Depends on album size/count         |

## Risk Assessment

| Risk                                   | Impact | Mitigation                                            |
| -------------------------------------- | ------ | ----------------------------------------------------- |
| DecapCMS S3 integration doesn't exist  | High   | Research first; may need custom solution              |
| Lightroom plugin unavailable/paid      | Medium | CLI workflow as primary; web UI as future             |
| Large album ZIP generation times out   | Medium | Use streaming/chunked downloads, or pre-generate      |
| Client doesn't understand expiration   | Low    | Clear messaging in portal, email notifications        |
| S3 direct access slow for high traffic | Low    | Add CloudFront CDN later if needed                    |
| Original image quality degraded        | High   | Always preserve originals; only resize copies for web |

## Success Metrics

### Portfolio Images

- [ ] Admin can upload images via DecapCMS without git bloat
- [ ] Images load quickly on portfolio pages (< 2s)
- [ ] Gallery pages support 10-50 images per gallery
- [ ] No manual S3/CLI work required for portfolio updates

### Client Albums

- [ ] Admin can upload album via CLI in < 5 minutes
- [ ] Admin can assign album to multiple clients
- [ ] Client sees their albums in portal
- [ ] Client can download individual photos
- [ ] Client can download full album as ZIP
- [ ] Access correctly expires after configured date
- [ ] Lightroom publish service works (stretch goal)

## Next Steps

1. ~~**Review this master plan**~~ ✅ Done
2. ~~**Create Plan A**~~ ✅ Done - `2026-01-17-portfolio-s3-media-library.md`
3. ~~**Implement Plan A**~~ ✅ Done (2026-01-25)
4. ~~**Create Plan B**~~ ✅ Done - `2026-01-24-client-albums-multi-client.md`
5. ~~**Implement Plan B**~~ ✅ Done (2026-01-25)
6. **Create Plan C** - Lightroom Integration (optional future enhancement)
7. **Create Plan D** - ZIP & Storage Optimization (optional future enhancement)

## References

### Internal Plans

- Original master plan: `thoughts/shared/plans/2026-01-08-build-website-master-plan.md`
- Amplify hosting plan: `thoughts/shared/plans/2026-01-16-switch-to-amplify-hosting.md`
- DecapCMS plan: `thoughts/shared/plans/2026-01-16-admin-cms-decap.md`
- Client portal plan: `thoughts/shared/plans/2026-01-09-integrate-client-portal-into-astro.md`
- **Portfolio S3 plan: `thoughts/shared/plans/2026-01-17-portfolio-s3-media-library.md`**
- **Client albums plan: `thoughts/shared/plans/2026-01-24-client-albums-multi-client.md`**

### External Documentation

- DecapCMS custom media: https://decapcms.org/docs/custom-widgets/
- S3 presigned URLs: https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html
- S3 Storage Classes: https://aws.amazon.com/s3/storage-classes/
- S3 Lifecycle Rules: https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html
- EventBridge Scheduler: https://docs.aws.amazon.com/eventbridge/latest/userguide/scheduler.html
- Step Functions: https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html
- Lightroom SDK: https://www.adobe.io/apis/creativecloud/lightroomclassic.html
- DynamoDB best practices: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html
