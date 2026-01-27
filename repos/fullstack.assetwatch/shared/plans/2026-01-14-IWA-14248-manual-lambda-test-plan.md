---
date: 2026-01-14T09:45:00-05:00
author: Claude Code
branch: IWA-14248
repository: assetwatch-jobs
topic: "IWA-14248 Manual Lambda Test Plan - UniqueSensorCountLast7d Bug Fix"
tags: [test-plan, lambda, manual-deployment, jobs-insights]
status: ready
---

# IWA-14248 Manual Lambda Test Plan

## Overview

This plan outlines how to manually test the `UniqueSensorCountLast7d` bug fix in the dev environment before merging via PR.

**Why manual deployment?** Only branches prefixed with `db/`, or named `dev`, `qa`, or `master` get full backend infrastructure deployed via CI/CD. For quick testing of this fix, we'll manually update the Lambda.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Access to the `assetwatch-jobs` repository
- The fix has been committed to branch `IWA-14248`

## Verified Configuration

| Setting | Value | Source |
|---------|-------|--------|
| AWS Region | `us-east-2` | `terraform/main.tf:29` |
| Lambda Function Name | `jobs-insights-dev-dev` | `terraform/jobs/jobs_insights/lambda.tf:29` |
| Method Name | `loadTxRxMetrics` | `main.py:99` |
| Source Directory | `terraform/jobs/jobs_insights/jobs-insights/` | `lambda.tf:3` |

## Test Steps

### Step 1: Deploy the Fix

Ensure you're on the `IWA-14248` branch with the fix, then zip and deploy:

```bash
cd ~/repos/assetwatch-jobs
git checkout IWA-14248

cd terraform/jobs/jobs_insights/jobs-insights
zip -r /tmp/jobs-insights.zip .

aws lambda update-function-code \
  --function-name jobs-insights-dev-dev \
  --zip-file fileb:///tmp/jobs-insights.zip \
  --region us-east-2
```

### Step 2: Run the Job to Fix Data

Invoke the Lambda to recalculate all `TransponderMetric` values with the corrected column order:

```bash
aws lambda invoke \
  --function-name jobs-insights-dev-dev \
  --cli-binary-format raw-in-base64-out \
  --payload '{"meth": "loadTxRxMetrics"}' \
  --region us-east-2 \
  /tmp/lambda-response.json

cat /tmp/lambda-response.json
```

Expected: `"status": "success"` in the response.

### Step 3: Verify the Fix

1. Navigate to https://dev.dev.assetwatch.com
2. Go to CustomerDetail > Hubs page
3. Check that "Unique Sensors Last 7d" values are now **less than** "Readings Last 7d"
   - Before fix: Unique Sensors was ~3x Readings (impossible)
   - After fix: Unique Sensors should be ~10-50% of Readings (realistic)

### Step 4: Revert the Lambda Code

Switch back to the `dev` branch version of the file, re-zip, and redeploy:

```bash
cd ~/repos/assetwatch-jobs
git checkout dev -- terraform/jobs/jobs_insights/jobs-insights/tx_rx_metrics.py

cd terraform/jobs/jobs_insights/jobs-insights
zip -r /tmp/jobs-insights.zip .

aws lambda update-function-code \
  --function-name jobs-insights-dev-dev \
  --zip-file fileb:///tmp/jobs-insights.zip \
  --region us-east-2
```

### Step 5: Restore Original (Buggy) Data

Re-run the job to restore the swapped values so the dev environment matches expectations:

```bash
aws lambda invoke \
  --function-name jobs-insights-dev-dev \
  --cli-binary-format raw-in-base64-out \
  --payload '{"meth": "loadTxRxMetrics"}' \
  --region us-east-2 \
  /tmp/lambda-response.json

cat /tmp/lambda-response.json
```

### Step 6: Verify Revert

Refresh the CustomerDetail > Hubs page and confirm "Unique Sensors Last 7d" is back to the incorrect (high) values.

## Post-Test: Create Pull Request

After successful testing, create a PR from `IWA-14248` to `dev` in the `assetwatch-jobs` repository.

## The Bug Fix (Reference)

**File**: `terraform/jobs/jobs_insights/jobs-insights/tx_rx_metrics.py:73`

**Before** (columns swapped):
```sql
SELECT metrics7d.hub, metrics7d.readings_last_7d, metrics7d.unique_sensors_last_7d, metrics21d.readings_last_21d FROM
```

**After** (correct order matching Python parsing):
```sql
SELECT metrics7d.hub, metrics7d.readings_last_7d, metrics21d.readings_last_21d, metrics7d.unique_sensors_last_7d FROM
```

## Rollback Plan

If something goes wrong during testing, the revert steps (4-5) restore the original state. The next scheduled run of `jobs_insights` (every 3 hours at :35) will also restore data if the Lambda code is reverted.
