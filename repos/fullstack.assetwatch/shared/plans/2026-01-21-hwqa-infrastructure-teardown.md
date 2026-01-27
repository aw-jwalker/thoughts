# HWQA Legacy Infrastructure Teardown Plan

## Overview

This plan details the systematic and safe teardown of the old fullstack.hwqa infrastructure following the successful migration to the integrated HWQA module in fullstack.assetwatch. The teardown will proceed environment-by-environment (dev → qa → prod).

> **Note**: With only ~5 active users, direct communication will be used to notify users of the new URLs instead of setting up DNS redirects.

## Current State Analysis

### Old fullstack.hwqa Resources (Per Environment)

| Resource Type | Naming Pattern | Count per Env |
|---------------|----------------|---------------|
| Lambda Function | `hwqa_backend_lambda_{env}_{branch}` | 1+ |
| Lambda Layer | `hwqa_backend_311` | 1 |
| API Gateway REST API | `hwqa_backend_{env}_{branch}` | 1+ |
| API Gateway Custom Domain | `api-hwqa-{branch}.{env}.assetwatch.com` | 1+ |
| API Gateway Authorizer | `hwqa_cognito_authorizer_{env}_{branch}` | 1+ |
| S3 Bucket (Frontend) | `hwqa-frontend-{env}` or `hwqa-frontend-{env}-{branch}` | 1+ |
| CloudFront Distribution | Per-branch | 1+ |
| CloudFront Security Headers Policy | `hwqa-security-headers-{env}-{branch}` | 1 |
| CloudFront OAI | Per-branch | 1+ |
| Route53 A Records | `hwqa-{branch}.{env}.assetwatch.com` | 1+ |
| Route53 A Records (API) | `api-hwqa-{branch}.{env}.assetwatch.com` | 1+ |
| ACM Certificate (Frontend) | `hwqa-{branch}.{env}.assetwatch.com` | 1+ |
| ACM Certificate (API) | `api-hwqa-{branch}.{env}.assetwatch.com` | 1+ |
| IAM Role | `hwqa_backend_lambda_role_{env}_{branch}` | 1+ |
| IAM Policy | `hwqa_backend_ssm_policy_{env}_{branch}` | 1+ |
| CloudWatch Log Group | `/aws/lambda/hwqa_backend_lambda_{env}_{branch}` | 1+ |
| CloudWatch Log Group (Frontend) | `/aws/cloudfront/hwqa-frontend-{env}-{branch}` | 1+ |

### Terraform State Configuration
- **State Buckets**: `assetwatch-terraform-state-{env}` (shared with fullstack.assetwatch)
- **State Key**: `hwqa/terraform.tfstate`
- **Workspace Key Prefix**: `hwqa_environments`
- **Lock Table**: `remote-state-lock` (shared DynamoDB table)

### Environments to Tear Down
1. **dev** - Workspaces: `dev`, `db-*` branches
2. **qa** - Workspaces: `qa`
3. **prod** - Workspaces: `master`

---

## ✅ Validated Resource Inventory (January 2025)

> **Note**: This inventory was validated using AWS CLI and Terraform state on 2025-01-21. Production validation was limited due to reduced permissions.

### DEV Environment (Account: 396913697939)

**Terraform Workspaces** (11 total):
```
default, db-iwa-12335, dev, iwa-11793-chris, iwa-11793-rollback, iwa-12321,
iwa-1234-testingbadcomp, iwa-13362, iwa-13820, iwa-14003, iwa-14034
```

**Lambda Functions** (5 - only branches with `create_aws_resources=true`):
| Function Name | Branch | Has Backend |
|---------------|--------|-------------|
| `hwqa_backend_lambda_dev_dev` | dev | ✅ |
| `hwqa_backend_lambda_dev_db-iwa-12335` | db-iwa-12335 | ✅ |
| `hwqa_backend_lambda_dev_iwa-11793-chris` | iwa-11793-chris | ✅ |
| `hwqa_backend_lambda_dev_iwa-11793-rollback` | iwa-11793-rollback | ✅ |
| `hwqa_backend_lambda_dev_iwa-12321` | iwa-12321 | ✅ |

**API Gateways** (5):
| API Name | API ID |
|----------|--------|
| `hwqa_backend_dev_dev` | `e44yqrybo1` |
| `hwqa_backend_dev_db-iwa-12335` | `np3sq4ymlj` |
| `hwqa_backend_dev_iwa-11793-chris` | `m0ng7yvkla` |
| `hwqa_backend_dev_iwa-11793-rollback` | `0h9pz52m2b` |
| `hwqa_backend_dev_iwa-12321` | `70x6pydmck` |

**S3 Buckets** (9 - all branches have frontend buckets):
```
hwqa-frontend-dev
hwqa-frontend-dev-db-iwa-12335
hwqa-frontend-dev-iwa-11793-chris
hwqa-frontend-dev-iwa-11793-rollback
hwqa-frontend-dev-iwa-12321
hwqa-frontend-dev-iwa-1234-testingbadcomp
hwqa-frontend-dev-iwa-13362
hwqa-frontend-dev-iwa-13820
hwqa-frontend-dev-iwa-14034
```

**CloudFront Distributions** (10):
| Distribution ID | Comment |
|-----------------|---------|
| `E1EO6UF5621QS8` | HWQA Frontend Distribution - dev-dev |
| `E12UX3246CH0O3` | HWQA Frontend Distribution - dev-db-iwa-12335 |
| `E3U5FNIIBB46GU` | HWQA Frontend Distribution - dev-iwa-11793-chris |
| `E3KCGVB6NRZ20M` | HWQA Frontend Distribution - dev-iwa-11793-rollback |
| `EEZTEXO08U6XC` | HWQA Frontend Distribution - dev-iwa-12321 |
| `E2I3J7XVVKVQG6` | HWQA Frontend Distribution - dev-iwa-1234-testingbadcomp |
| `E2R3OYBSVDGMCK` | HWQA Frontend Distribution - dev-iwa-13362 |
| `E3IUHJUQPL2RF3` | HWQA Frontend Distribution - dev-iwa-13820 |
| `E9WJZEOCBINCD` | HWQA Frontend Distribution - dev-iwa-14003 |
| `E39M330NPEFS5G` | HWQA Frontend Distribution - dev-iwa-14034 |

**IAM Resources** (5 each):
- Roles: `hwqa_backend_lambda_role_dev_dev`, `hwqa_backend_lambda_role_dev_db-iwa-12335`, etc.
- Policies: `hwqa_backend_ssm_policy_dev_dev`, `hwqa_backend_ssm_policy_dev_db-iwa-12335`, etc.

**ACM Certificates**:
- Frontend (us-east-1): 10 certificates (`hwqa-*.dev.assetwatch.com`)
- API (us-east-2): 4 certificates (`api-hwqa-*.dev.assetwatch.com`)

**Route53 Records** (Zone: `Z09098873QPT4OZPJW9B`):
- A Records: `hwqa-dev.dev.assetwatch.com`, `api-hwqa-dev.dev.assetwatch.com`, etc.
- CNAME Records: ACM validation records

**Lambda Layer**: `hwqa_backend_311`

**Cognito User Pool**: `us-east-2_x7NmjJEZB` (Name: "AssetWatch Internal DEV")
- ⚠️ **No HWQA callback URLs found** in the "AssetWatch Internal DEV" app client - may already be cleaned up or using different auth

---

### QA Environment (Account: 221463224365)

**Terraform Workspaces** (2):
```
default, qa
```

**Lambda Function**: `hwqa_backend_lambda_qa_qa`

**API Gateway**: `hwqa_backend_qa_qa` (ID: `m6lf5ayv32`)

**S3 Bucket**: `hwqa-frontend-qa`

**CloudFront Distribution**: `E124MI9RMFIGUE` (HWQA Frontend Distribution - qa-qa)

**IAM Resources**:
- Role: `hwqa_backend_lambda_role_qa_qa`
- Policy: `hwqa_backend_ssm_policy_qa_qa`

**ACM Certificate** (us-east-1): `hwqa-qa.qa.assetwatch.com`

**Route53 Records** (Zone: `Z0432373NVSJPN9YHAV6`):
- `hwqa-qa.qa.assetwatch.com` (A)
- `api-hwqa-qa.qa.assetwatch.com` (A)
- `hwqa.qa.assetwatch.com` (A) - *Additional alias*

**Lambda Layer**: `hwqa_backend_311`

**Cognito User Pool**: `us-east-2_tGB8JmQO3` (Name: "Nikola Internal QA")

---

### PROD Environment (Account: 975740733715)

> ⚠️ **Note**: Limited permissions in prod - some resources could not be validated via AWS CLI. Terraform state was used for full inventory.

**Terraform Workspaces** (3):
```
default, dev (ORPHANED - 0 resources), master
```

**Lambda Function**: `hwqa_backend_lambda_prod_master`

**S3 Bucket**: `hwqa-frontend-prod-master`

**IAM Role**: `hwqa_backend_lambda_role_prod_master`

**Lambda Layer**: `hwqa_backend_311` (Version ARN: `arn:aws:lambda:us-east-2:975740733715:layer:hwqa_backend_311:10`)

**From Terraform State (master workspace)**:
- API Gateway REST API: `aws_api_gateway_rest_api.hwqa_backend[0]`
- CloudFront Distribution: `aws_cloudfront_distribution.frontend`
- Route53 Records:
  - `aws_route53_record.hwqa_prod_alias[0]` (likely `hwqa.assetwatch.com`)
  - `aws_route53_record.hwqa_cloudfront_record` (`hwqa-master.prod.assetwatch.com`)
  - `aws_route53_record.hwqa_api_domain[0]` (`api-hwqa-master.prod.assetwatch.com`)
- ACM Certificates covering: `hwqa.assetwatch.com`, `hwqa-master.prod.assetwatch.com`, `hwqa-main.prod.assetwatch.com`

**Cognito User Pool**: `us-east-2_MqZrrppS1` (could not verify name due to permissions)

**Route53 Hosted Zone**: `Z0078789R6E35PXK7VLM` (could not verify due to permissions)

---

### Key Discovery: Resource Creation Pattern

The old fullstack.hwqa uses conditional resource creation (`local.create_aws_resources`):
- **db-* branches** and **main branches** (dev, qa, master): Create full stack (Lambda, API Gateway, IAM)
- **Other feature branches**: Create only frontend resources (S3, CloudFront, ACM, Route53)

This explains why there are more S3 buckets/CloudFront distributions than Lambda functions in dev.

## Desired End State

After this plan is complete:
1. All AWS resources created by fullstack.hwqa are destroyed
2. Terraform state files and workspaces for hwqa are cleaned up
3. GitHub repository AssetWatch1/fullstack.hwqa is archived
4. All users access HWQA through the new fullstack.assetwatch URLs (communicated directly)

### New HWQA URLs
- **Frontend (prod)**: `https://hwqa.prod.assetwatch.com` (via fullstack.assetwatch)
- **API (prod)**: `https://api.prod.assetwatch.com/hwqa` (via fullstack.assetwatch)

## What We're NOT Doing

- NOT deleting the shared Terraform state buckets (used by fullstack.assetwatch)
- NOT deleting the shared DynamoDB lock table
- NOT deleting the Cognito User Pools (shared with fullstack.assetwatch)
- NOT deleting Route53 hosted zones (only individual records)
- NOT modifying VPCs or security groups created by fullstack.assetwatch
- NOT deleting Lambda layers that may be shared (`fastapi`, `boto3_311`, `mysql_connector_python_311`)

## Manual Console Steps Required

### Cognito Callback URL Cleanup

> ⚠️ **Update (January 2025)**: Initial validation found **NO HWQA callback URLs** in the dev Cognito User Pool's "AssetWatch Internal DEV" app client. This may indicate:
> 1. HWQA callback URLs have already been cleaned up
> 2. HWQA uses a different authentication flow
> 3. HWQA shares URLs with the main AssetWatch app
>
> **Action**: Before each environment teardown, manually verify if any HWQA callback URLs exist that need removal.

The old fullstack.hwqa may have added callback URLs to the shared Cognito User Pool App Clients that are **not managed by Terraform**. If present, these must be manually removed from the AWS Console after teardown.

**Potential URLs to Remove** (per environment - verify existence first):
- **Dev**: `https://hwqa-dev.dev.assetwatch.com`, `https://hwqa-{branch}.dev.assetwatch.com`
- **QA**: `https://hwqa-qa.qa.assetwatch.com`, `https://hwqa.qa.assetwatch.com`
- **Prod**: `https://hwqa.assetwatch.com`, `https://hwqa-master.prod.assetwatch.com`

**Cognito User Pool IDs** (verified):
- **Dev**: `us-east-2_x7NmjJEZB` (Name: "AssetWatch Internal DEV")
- **QA**: `us-east-2_tGB8JmQO3` (Name: "Nikola Internal QA")
- **Prod**: `us-east-2_MqZrrppS1`

**Steps**:
1. Navigate to AWS Console → Cognito → User Pools → Select environment pool
2. Go to "App integration" → "App client list"
3. Check each app client for HWQA callback URLs
4. If found, edit "Allowed callback URLs" and remove old HWQA URLs
5. Edit "Allowed sign-out URLs" and remove old HWQA URLs
6. Save changes

**Note**: Only remove URLs after the corresponding environment teardown is complete and verified.

## Implementation Approach

The teardown follows a phased approach:
1. **Environment Teardown**: Destroy resources environment-by-environment (dev → qa → prod) using GitHub Actions workflow
2. **State Cleanup**: Remove Terraform workspaces and state files
3. **Repository Archive**: Archive the GitHub repository
4. **User Communication**: Notify the ~5 active users of the new URLs directly

---

## Recommended: GitHub Actions Pipeline for Teardown

### Why Use a Pipeline?

| Benefit | Description |
|---------|-------------|
| **Audit Trail** | Every action logged with timestamps, actor, and full output |
| **Approval Gates** | GitHub Environments require designated reviewers before proceeding |
| **Team Visibility** | Everyone can watch progress in real-time via GitHub UI |
| **Controlled Execution** | Manual triggers only - no accidental runs |
| **Rollback Documentation** | Workflow file documents exact process for potential rollback |
| **Artifact Storage** | Terraform plan outputs saved for review before apply |

### Proposed Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    workflow_dispatch (manual)                    │
│                         ↓                                        │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  PLAN PHASE (no approval needed)                        │    │
│  │  • terraform plan -destroy for selected environment     │    │
│  │  • Upload plan as artifact                              │    │
│  │  • Post summary to workflow                             │    │
│  └─────────────────────────────────────────────────────────┘    │
│                         ↓                                        │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  REVIEW GATE (manual approval required)                 │    │
│  │  • GitHub Environment: "hwqa-teardown-{env}"            │    │
│  │  • Required reviewers: DevOps team members              │    │
│  │  • Review plan artifact before approving                │    │
│  └─────────────────────────────────────────────────────────┘    │
│                         ↓                                        │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  DESTROY PHASE (after approval)                         │    │
│  │  • For each workspace: plan → destroy → delete workspace│    │
│  │  • Detailed logging at each step                        │    │
│  │  • Fail-fast on any error                               │    │
│  └─────────────────────────────────────────────────────────┘    │
│                         ↓                                        │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  VERIFICATION PHASE                                     │    │
│  │  • Run AWS CLI checks to verify resources deleted       │    │
│  │  • Generate summary report                              │    │
│  │  • Post results to workflow summary                     │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### GitHub Environment Setup Required

Before running the pipeline, create these GitHub Environments with protection rules:

| Environment | Required Reviewers | Wait Timer | Branch Restriction |
|-------------|-------------------|------------|-------------------|
| `hwqa-teardown-dev` | 1 team member | None | None |
| `hwqa-teardown-qa` | 1 team member | None | None |
| `hwqa-teardown-prod` | 1 team member | None | `main` only |

> **Note**: You will reach out to the appropriate person on your team for each environment approval.

### Sample Workflow File

Create `.github/workflows/hwqa-teardown.yml` in the **fullstack.hwqa** repository.

> **Design Decision**: This workflow follows the patterns established in other AssetWatch repositories (see `external.api`, `internal.api`, `fullstack.assetwatch`) with enhancements learned from `fullstack.assetwatch/devops/tf/delete-tf-workspaces.sh` for state lock handling.

```yaml
name: HWQA Infrastructure Teardown

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to tear down'
        required: true
        type: choice
        options:
          - dev
          - qa
          - prod
      workspace:
        description: 'Specific workspace to destroy (leave empty to destroy ALL workspaces)'
        required: false
        type: string
      confirm_destroy:
        description: 'Type "DESTROY" to confirm infrastructure destruction'
        required: true
        type: string
        default: ''

env:
  TF_VAR_env: ${{ inputs.environment }}
  AWS_REGION: us-east-2

permissions:
  contents: read
  id-token: write

jobs:
  teardown:
    name: "Teardown HWQA - ${{ inputs.environment }}"
    runs-on: ubuntu-latest
    environment: hwqa-teardown-${{ inputs.environment }}
    defaults:
      run:
        shell: bash
        working-directory: ./terraform

    steps:
      - name: Verify Destruction Confirmation
        run: |
          if [[ "${{ inputs.confirm_destroy }}" != "DESTROY" ]]; then
            echo "❌ DESTRUCTION NOT CONFIRMED!"
            echo "You must type 'DESTROY' in the confirm_destroy field to proceed."
            exit 1
          fi
          echo "✅ Destruction confirmed"

      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.ROLE_TO_ASSUME }}
          aws-region: ${{ env.AWS_REGION }}
          role-duration-seconds: 7200

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.8.5

      - name: Terraform Init
        run: |
          terraform init \
            -backend-config="bucket=assetwatch-terraform-state-${{ inputs.environment }}" \
            -backend-config="key=hwqa/terraform.tfstate" \
            -backend-config="workspace_key_prefix=hwqa_environments"

      - name: List Workspaces
        id: list-workspaces
        run: |
          echo "### Available Workspaces" >> $GITHUB_STEP_SUMMARY
          terraform workspace list >> $GITHUB_STEP_SUMMARY

          if [[ -n "${{ inputs.workspace }}" ]]; then
            echo "WORKSPACES=${{ inputs.workspace }}" >> $GITHUB_ENV
            echo "Targeting specific workspace: ${{ inputs.workspace }}"
          else
            # Get all non-default workspaces
            WORKSPACES=$(terraform workspace list | grep -v "default" | tr -d '* ' | tr '\n' ' ')
            echo "WORKSPACES=$WORKSPACES" >> $GITHUB_ENV
            echo "Targeting all workspaces: $WORKSPACES"
          fi

      - name: Destroy Workspaces
        run: |
          echo "### Destruction Log" >> $GITHUB_STEP_SUMMARY

          for workspace in $WORKSPACES; do
            if [[ -z "$workspace" ]]; then
              continue
            fi

            echo "=== Processing workspace: $workspace ===" | tee -a $GITHUB_STEP_SUMMARY

            # Select workspace
            terraform workspace select $workspace || {
              echo "❌ Failed to select workspace $workspace" >> $GITHUB_STEP_SUMMARY
              continue
            }

            export TF_VAR_branch=$workspace

            # Attempt terraform destroy with state lock handling
            echo "Running terraform destroy for $workspace..."
            set +e
            output=$(terraform destroy -input=false -auto-approve 2>&1)
            status=$?
            set -e

            # Handle state lock errors (pattern from delete-tf-workspaces.sh)
            if [[ $output =~ "Error acquiring the state lock" ]]; then
              lock_id=$(echo "$output" | grep -oP 'ID:\s+\K.*')
              echo "⚠️ State lock detected. Force unlocking: $lock_id" >> $GITHUB_STEP_SUMMARY
              terraform force-unlock -force "$lock_id"

              # Retry destroy
              set +e
              output=$(terraform destroy -input=false -auto-approve 2>&1)
              status=$?
              set -e
            fi

            if [[ $status -ne 0 ]]; then
              echo "❌ Destroy failed for $workspace" >> $GITHUB_STEP_SUMMARY
              echo "$output" | tail -20 >> $GITHUB_STEP_SUMMARY
              exit 1
            fi

            echo "✅ Destroyed resources in $workspace" >> $GITHUB_STEP_SUMMARY

            # Delete the workspace
            terraform workspace select default

            # Handle workspace-not-empty errors with retry (pattern from delete-tf-workspaces.sh)
            set +e
            delete_output=$(terraform workspace delete $workspace 2>&1)
            delete_status=$?
            set -e

            if [[ $delete_output == *"Workspace is not empty"* ]]; then
              echo "⚠️ Workspace not empty, retrying destroy..." >> $GITHUB_STEP_SUMMARY
              terraform workspace select $workspace
              terraform destroy -input=false -auto-approve
              terraform workspace select default
              terraform workspace delete $workspace
            elif [[ $delete_status -ne 0 ]]; then
              echo "⚠️ Failed to delete workspace $workspace: $delete_output" >> $GITHUB_STEP_SUMMARY
            else
              echo "✅ Deleted workspace $workspace" >> $GITHUB_STEP_SUMMARY
            fi
          done

          echo "🎉 Teardown complete!" >> $GITHUB_STEP_SUMMARY

      - name: Verify Resources Deleted
        run: |
          cd ..  # Exit terraform directory for AWS CLI commands
          echo "### Verification Results" >> $GITHUB_STEP_SUMMARY

          # Check Lambda
          LAMBDAS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, 'hwqa_backend_lambda_${{ inputs.environment }}')].[FunctionName]" --output text)
          if [ -z "$LAMBDAS" ]; then
            echo "✅ No HWQA Lambda functions found" >> $GITHUB_STEP_SUMMARY
          else
            echo "⚠️ Remaining Lambda functions: $LAMBDAS" >> $GITHUB_STEP_SUMMARY
          fi

          # Check S3
          S3_BUCKETS=$(aws s3 ls 2>/dev/null | grep "hwqa-frontend-${{ inputs.environment }}" || true)
          if [ -z "$S3_BUCKETS" ]; then
            echo "✅ No HWQA S3 buckets found" >> $GITHUB_STEP_SUMMARY
          else
            echo "⚠️ Remaining S3 buckets: $S3_BUCKETS" >> $GITHUB_STEP_SUMMARY
          fi

          # Check API Gateway
          APIS=$(aws apigateway get-rest-apis --query "items[?contains(name, 'hwqa_backend_${{ inputs.environment }}')].[name]" --output text)
          if [ -z "$APIS" ]; then
            echo "✅ No HWQA API Gateways found" >> $GITHUB_STEP_SUMMARY
          else
            echo "⚠️ Remaining API Gateways: $APIS" >> $GITHUB_STEP_SUMMARY
          fi

      - name: Final Workspace List
        run: |
          echo "### Remaining Workspaces" >> $GITHUB_STEP_SUMMARY
          terraform workspace list >> $GITHUB_STEP_SUMMARY
```

### Patterns Learned from Other Repositories

The workflow above incorporates patterns from existing destroy/delete workflows in your GitHub organization:

| Repository | File | Key Pattern Applied |
|------------|------|---------------------|
| `fullstack.assetwatch` | `wflow-manual-env-delete.yml` | Single-job structure with environment protection |
| `fullstack.assetwatch` | `devops/tf/delete-tf-workspaces.sh` | State lock handling with `force-unlock`, workspace-not-empty retry logic |
| `assetwatch-mobile-backend` | `terraform-manual-destroy.yml` | `confirm_destroy` input for explicit confirmation |
| `external.api` / `internal.api` | `terraform-manual-workspace-delete.yml` | Branch name normalization, simple sequential destroy |

**Key improvements over the original plan:**
1. **Single job instead of multi-job matrix** - Simpler, easier to debug, follows team patterns
2. **State lock handling** - Auto-recovers from locks left by failed runs
3. **Workspace-not-empty retry** - Handles edge case where resources weren't fully destroyed
4. **Dual confirmation** - Both text input ("DESTROY") AND GitHub Environment approval required
5. **Extended role duration** - 7200 seconds to handle long-running destroy operations

### Monitoring Progress

1. **Real-time**: Watch the GitHub Actions tab for live logs
2. **Summary**: The workflow posts detailed results to the GitHub Step Summary for easy review
3. **Verification**: The final step lists any remaining resources that need manual cleanup

### Rollback During Pipeline

If something goes wrong mid-execution:

1. **Cancel the workflow** immediately via GitHub UI
2. **Review which workspaces completed** in the workflow logs (check the Step Summary)
3. **For partially destroyed workspaces**:
   ```bash
   cd /home/aw-jwalker/repos/hwqa/terraform
   terraform workspace select <workspace-name>
   terraform apply  # Recreates from state
   ```

### Running the Workflow

1. Navigate to **Actions** tab in the `fullstack.hwqa` repository
2. Select **HWQA Infrastructure Teardown** workflow
3. Click **Run workflow**
4. Fill in:
   - **Environment**: Select `dev`, `qa`, or `prod`
   - **Workspace**: Leave empty to destroy ALL workspaces, or enter a specific workspace name
   - **Confirm**: Type `DESTROY` (case-sensitive)
5. Click **Run workflow**
6. Wait for the GitHub Environment approval request (your designated reviewer will be notified)
7. Once approved, the teardown proceeds automatically

---

## Phase 1: Dev Environment Teardown

### Overview
Destroy all dev environment resources from the old fullstack.hwqa repository using the GitHub Actions workflow.

### Pre-requisites:
- No active development branches in fullstack.hwqa that users depend on
- GitHub Environment `hwqa-teardown-dev` is created with 1 required reviewer
- AWS OIDC role configured for the workflow

### Steps:

#### 1.1 Run the Teardown Workflow for Dev

1. Navigate to **Actions** tab in the `fullstack.hwqa` repository
2. Select **HWQA Infrastructure Teardown** workflow
3. Click **Run workflow**
4. Select **Environment**: `dev`
5. Leave **Workspace** empty (to destroy all dev workspaces)
6. Type `DESTROY` in the confirmation field
7. Wait for reviewer approval
8. Monitor the workflow run

#### 1.2 Alternative: Manual CLI Execution (Reference Only)

If the workflow fails or you need to run manually, use these commands:

##### List All Dev Terraform Workspaces
```bash
cd /home/aw-jwalker/repos/hwqa/terraform

# Configure AWS credentials for dev
export AWS_PROFILE=dev  # or use aws-vault

# Initialize Terraform with dev backend
export TF_CLI_ARGS_init="-backend-config bucket=assetwatch-terraform-state-dev -backend-config key=hwqa/terraform.tfstate -backend-config workspace_key_prefix=hwqa_environments"
terraform init

# List all workspaces
terraform workspace list
```

**Validated workspaces (as of 2025-01-21)**:
```
* default
  db-iwa-12335        # Has backend resources
  dev                 # Has backend resources
  iwa-11793-chris     # Has backend resources
  iwa-11793-rollback  # Has backend resources
  iwa-12321           # Has backend resources
  iwa-1234-testingbadcomp  # Frontend only
  iwa-13362           # Frontend only
  iwa-13820           # Frontend only
  iwa-14003           # Frontend only (S3 bucket not found - may be stale)
  iwa-14034           # Frontend only
```

##### Destroy Each Workspace (Feature Branches First)

**Order**: Start with frontend-only branches, then branches with backend resources, then main `dev` workspace.

```bash
# Frontend-only branches first (less risk)
for branch in iwa-1234-testingbadcomp iwa-13362 iwa-13820 iwa-14003 iwa-14034; do
  echo "Destroying workspace: $branch"
  terraform workspace select $branch
  export TF_VAR_env=dev
  export TF_VAR_branch=$branch
  terraform destroy -auto-approve
  terraform workspace select default
  terraform workspace delete $branch
done

# Then branches with backend resources
for branch in iwa-11793-chris iwa-11793-rollback iwa-12321 db-iwa-12335; do
  echo "Destroying workspace: $branch"
  terraform workspace select $branch
  export TF_VAR_env=dev
  export TF_VAR_branch=$branch
  terraform destroy -auto-approve
  terraform workspace select default
  terraform workspace delete $branch
done
```

##### Destroy Main Dev Workspace
```bash
terraform workspace select dev
export TF_VAR_env=dev
export TF_VAR_branch=dev
terraform destroy -auto-approve
terraform workspace select default
terraform workspace delete dev
```

### Success Criteria:

#### Automated Verification:
- [ ] `terraform workspace list` shows only `default` workspace for dev
- [ ] AWS CLI: `aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'hwqa_backend_lambda_dev')]"` returns empty
- [ ] AWS CLI: `aws apigateway get-rest-apis --query "items[?starts_with(name, 'hwqa_backend_dev')]"` returns empty
- [ ] AWS CLI: `aws s3 ls | grep hwqa-frontend-dev` returns nothing (or error)
- [ ] AWS CLI: `aws cloudfront list-distributions --query "DistributionList.Items[?Comment && contains(Comment, 'hwqa-dev')]"` returns empty

#### Manual Verification:
- [ ] Old dev HWQA URLs no longer serve the old app (return 404 or DNS error)
- [ ] New integrated HWQA dev environment still works
- [ ] No orphaned resources visible in AWS Console

**Implementation Note**: After completing this phase, pause for 24-48 hours to monitor for any issues before proceeding to QA.

### 1.3 Clean Up Dev Cognito Callback URLs (Console)
1. Navigate to AWS Console → Cognito → User Pools → `us-east-2_x7NmjJEZB` (dev)
2. Go to "App integration" → "App client list"
3. Edit the app client and remove these callback URLs:
   - `https://hwqa-dev.dev.assetwatch.com`
   - `https://hwqa-dev.dev.assetwatch.com/`
   - Any `https://hwqa-db-*.dev.assetwatch.com` URLs
4. Remove corresponding sign-out URLs
5. Save changes

---

## Phase 2: QA Environment Teardown

### Overview
Destroy all QA environment resources from the old fullstack.hwqa repository.

### Steps:

#### 2.1 Run the Teardown Workflow for QA

1. Navigate to **Actions** tab in the `fullstack.hwqa` repository
2. Select **HWQA Infrastructure Teardown** workflow
3. Click **Run workflow**
4. Select **Environment**: `qa`
5. Leave **Workspace** empty
6. Type `DESTROY` in the confirmation field
7. Wait for reviewer approval
8. Monitor the workflow run

#### 2.2 Alternative: Manual CLI Execution (Reference Only)
```bash
cd /home/aw-jwalker/repos/hwqa/terraform

# Configure AWS credentials for QA
export AWS_PROFILE=qa  # or use aws-vault

# Initialize Terraform with QA backend
export TF_CLI_ARGS_init="-backend-config bucket=assetwatch-terraform-state-qa -backend-config key=hwqa/terraform.tfstate -backend-config workspace_key_prefix=hwqa_environments"
terraform init

# List workspaces
terraform workspace list
```

**Validated workspaces (as of 2025-01-21)**:
```
* default
  qa      # Main QA workspace - has all resources
```

**Validated QA Resources**:
- Lambda: `hwqa_backend_lambda_qa_qa`
- API Gateway: `hwqa_backend_qa_qa` (ID: `m6lf5ayv32`)
- S3 Bucket: `hwqa-frontend-qa`
- CloudFront: `E124MI9RMFIGUE`
- Route53 Zone: `Z0432373NVSJPN9YHAV6`
- Route53 Records: `hwqa-qa.qa.assetwatch.com`, `api-hwqa-qa.qa.assetwatch.com`, `hwqa.qa.assetwatch.com` (alias)

##### Destroy QA Workspace (Manual)
```bash
terraform workspace select qa
export TF_VAR_env=qa
export TF_VAR_branch=qa
terraform destroy -auto-approve
terraform workspace select default
terraform workspace delete qa
```

### Success Criteria:

#### Automated Verification:
- [ ] `terraform workspace list` shows only `default` workspace for qa
- [ ] AWS CLI: `aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'hwqa_backend_lambda_qa')]"` returns empty
- [ ] AWS CLI: `aws s3 ls | grep hwqa-frontend-qa` returns nothing
- [ ] AWS CLI: `aws cloudfront list-distributions --query "DistributionList.Items[?Comment && contains(Comment, 'hwqa-qa')]"` returns empty

#### Manual Verification:
- [ ] Old QA HWQA URLs no longer serve the old app
- [ ] New integrated HWQA QA environment works correctly
- [ ] QA team confirms no disruption to their testing workflows

**Implementation Note**: After completing this phase, pause for 24-48 hours to ensure stability before proceeding to production.

### 2.3 Clean Up QA Cognito Callback URLs (Console)
1. Navigate to AWS Console → Cognito → User Pools → `us-east-2_tGB8JmQO3` (qa)
2. Go to "App integration" → "App client list"
3. Edit the app client and remove these callback URLs:
   - `https://hwqa-qa.qa.assetwatch.com`
   - `https://hwqa-qa.qa.assetwatch.com/`
4. Remove corresponding sign-out URLs
5. Save changes

---

## Phase 3: Production Environment Teardown

### Overview
Destroy all production environment resources. This is the most critical phase requiring extra caution.

### Pre-requisites:
- Dev teardown completed and verified (Phase 1)
- QA teardown completed and verified (Phase 2)
- All ~5 users have been notified of the new URLs
- Redirect records verified working in production
- Stakeholder approval for production teardown
- Maintenance window scheduled (if required)

### Steps:

#### 3.1 Run the Teardown Workflow for Prod

1. Navigate to **Actions** tab in the `fullstack.hwqa` repository
2. Select **HWQA Infrastructure Teardown** workflow
3. Click **Run workflow**
4. Select **Environment**: `prod`
5. Leave **Workspace** empty (or enter `master` to target only the production workspace)
6. Type `DESTROY` in the confirmation field
7. Wait for reviewer approval
8. Monitor the workflow run

**IMPORTANT**: Ensure all ~5 users have been notified of the new URLs before running production teardown.

#### 3.2 Alternative: Manual CLI Execution (Reference Only)
```bash
cd /home/aw-jwalker/repos/hwqa/terraform

# Configure AWS credentials for Prod
export AWS_PROFILE=prod  # or use aws-vault

# Initialize Terraform with Prod backend
export TF_CLI_ARGS_init="-backend-config bucket=assetwatch-terraform-state-prod -backend-config key=hwqa/terraform.tfstate -backend-config workspace_key_prefix=hwqa_environments"
terraform init

# List workspaces
terraform workspace list
```

**Validated workspaces (as of 2025-01-21)**:
```
* default
  dev     # ORPHANED - 0 resources (delete this workspace)
  master  # Main prod workspace - has all resources
```

##### Clean Up Orphaned "dev" Workspace
```bash
# The "dev" workspace in prod state is orphaned with 0 resources - delete it
terraform workspace select dev
terraform state list  # Should be empty
terraform workspace select default
terraform workspace delete dev
```

##### Review Resources Before Destruction
```bash
terraform workspace select master
export TF_VAR_env=prod
export TF_VAR_branch=master

# Review what will be destroyed
terraform plan -destroy
```

**IMPORTANT**: Review the plan output carefully before proceeding.

##### Destroy Production Workspace (Manual)
```bash
# Only after careful review and stakeholder approval
terraform destroy -auto-approve
terraform workspace select default
terraform workspace delete master
```

### Success Criteria:

#### Automated Verification:
- [ ] `terraform workspace list` shows only `default` workspace for prod
- [ ] AWS CLI: `aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'hwqa_backend_lambda_prod')]"` returns empty
- [ ] AWS CLI: `aws s3 ls | grep hwqa-frontend-prod` returns nothing
- [ ] AWS CLI: `aws cloudfront list-distributions --query "DistributionList.Items[?Comment && contains(Comment, 'hwqa-prod')]"` returns empty

#### Manual Verification:
- [ ] Old `hwqa.assetwatch.com` no longer serves the old app (DNS error expected)
- [ ] Old `hwqa-master.prod.assetwatch.com` no longer serves the old app
- [ ] Production users can access HWQA without disruption
- [ ] No customer complaints or support tickets about HWQA access

**Implementation Note**: Monitor production closely for 1 week after this phase. Keep rollback capability by NOT archiving the repo until Phase 5.

### 3.3 Clean Up Prod Cognito Callback URLs (Console)
1. Navigate to AWS Console → Cognito → User Pools → `us-east-2_MqZrrppS1` (prod)
2. Go to "App integration" → "App client list"
3. Edit the app client and remove these callback URLs:
   - `https://hwqa.assetwatch.com`
   - `https://hwqa.assetwatch.com/`
   - `https://hwqa-master.prod.assetwatch.com`
   - `https://hwqa-master.prod.assetwatch.com/`
   - `https://hwqa-main.prod.assetwatch.com` (if exists)
4. Remove corresponding sign-out URLs
5. Save changes

**IMPORTANT**: Double-check that new HWQA callback URLs (from fullstack.assetwatch) are NOT removed. Only remove old URLs that match the patterns above.

---

## Phase 4: Terraform State Cleanup

### Overview
Clean up any remaining Terraform state files and verify no orphaned resources exist.

### Steps:

#### 4.1 Verify State Files in S3
```bash
# Check for any remaining hwqa state files
aws s3 ls s3://assetwatch-terraform-state-dev/hwqa/ --recursive
aws s3 ls s3://assetwatch-terraform-state-qa/hwqa/ --recursive
aws s3 ls s3://assetwatch-terraform-state-prod/hwqa/ --recursive
```

#### 4.2 Delete Remaining State Files (if empty/orphaned)
```bash
# Only if workspaces are properly deleted and state files are orphaned
# aws s3 rm s3://assetwatch-terraform-state-dev/hwqa/ --recursive
# aws s3 rm s3://assetwatch-terraform-state-qa/hwqa/ --recursive
# aws s3 rm s3://assetwatch-terraform-state-prod/hwqa/ --recursive
```

#### 4.3 Clean Up Any Orphaned AWS Resources
Run a sweep for any resources that might have been missed:

```bash
# Check for orphaned Lambda functions
aws lambda list-functions --query "Functions[?contains(FunctionName, 'hwqa_backend')].[FunctionName]" --output text

# Check for orphaned API Gateways
aws apigateway get-rest-apis --query "items[?contains(name, 'hwqa_backend')].[name,id]" --output text

# Check for orphaned S3 buckets
aws s3 ls | grep hwqa-frontend

# Check for orphaned CloudWatch log groups
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/hwqa_backend" --query "logGroups[].logGroupName" --output text
aws logs describe-log-groups --log-group-name-prefix "/aws/cloudfront/hwqa-frontend" --query "logGroups[].logGroupName" --output text

# Check for orphaned IAM roles
aws iam list-roles --query "Roles[?contains(RoleName, 'hwqa_backend')].[RoleName]" --output text

# Check for orphaned ACM certificates
aws acm list-certificates --query "CertificateSummaryList[?contains(DomainName, 'hwqa')].[DomainName,CertificateArn]" --output text
```

### Success Criteria:

#### Automated Verification:
- [ ] All S3 hwqa state prefixes are empty or deleted
- [ ] No orphaned Lambda functions found
- [ ] No orphaned API Gateways found
- [ ] No orphaned S3 buckets found
- [ ] No orphaned CloudWatch log groups found

#### Manual Verification:
- [ ] AWS Cost Explorer shows reduced costs from deleted resources
- [ ] No unexpected AWS bills related to hwqa resources

---

## Phase 5: Repository Archive

### Overview
Archive the fullstack.hwqa GitHub repository to prevent accidental deployments while preserving history.

### Steps:

#### 5.1 Disable GitHub Actions
1. Go to `https://github.com/AssetWatch1/fullstack.hwqa/settings/actions`
2. Select "Disable actions" to prevent any workflow runs

#### 5.2 Archive the Repository
1. Go to `https://github.com/AssetWatch1/fullstack.hwqa/settings`
2. Scroll to "Danger Zone"
3. Click "Archive this repository"
4. Confirm the archive action

#### 5.3 Update Documentation
Update any internal documentation that references the old repo to point to the new integrated HWQA in fullstack.assetwatch.

### Success Criteria:

#### Manual Verification:
- [ ] GitHub repo shows "Archived" badge
- [ ] Push attempts to the repo are rejected
- [ ] GitHub Actions are disabled
- [ ] Team members are notified of the archive
- [ ] Internal documentation updated

---

## Testing Strategy

### Pre-Teardown Tests
1. Verify new integrated HWQA is fully functional in all environments
2. Notify all ~5 users of the new HWQA URLs
3. Confirm users have updated their bookmarks/links

### Post-Teardown Tests
1. Verify old URLs return 404 or DNS errors (as expected)
2. Verify new integrated HWQA continues to function
3. Monitor for any 404 errors from old URL patterns
4. Check CloudWatch for any lambda invocation errors

### Rollback Strategy
If issues are discovered during teardown:
1. **Before workspace deletion**: Run `terraform apply` to recreate resources
2. **After workspace deletion**: Manually recreate workspace and run `terraform apply`
3. **After repo archive**: Unarchive repo and redeploy

---

## Timeline Estimate

| Phase | Duration | Cumulative |
|-------|----------|------------|
| User notification | 1 day | 1 day |
| Phase 1: Dev Teardown | 1-2 hours | 1-2 days |
| Validation period | 24-48 hours | 2-4 days |
| Phase 2: QA Teardown | 1 hour | 3-5 days |
| Validation period | 24-48 hours | 4-7 days |
| Phase 3: Prod Teardown | 1-2 hours | 5-8 days |
| Monitoring period | 1 week | 2 weeks |
| Phase 4: State Cleanup | 1 hour | 2 weeks |
| Phase 5: Repo Archive | 30 minutes | 2 weeks |

**Total estimated time**: ~2 weeks (including validation periods)

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Users on old URLs lose access | Low | Low | Direct notification to ~5 users before teardown |
| Terraform state corruption | Medium | Low | Backup state files before operations |
| Orphaned resources increase AWS costs | Low | Medium | Phase 4 sweep for orphans |
| Rollback needed after workspace deleted | High | Low | Keep repo unarchived until Phase 5 |
| Shared resources accidentally deleted | High | Low | Explicit "What We're NOT Doing" list |

---

## References

- Old repository: `AssetWatch1/fullstack.hwqa` (local: `/home/aw-jwalker/repos/hwqa`)
- New integrated HWQA: `fullstack.assetwatch/lambdas/lf-vero-prod-hwqa`
- Terraform state buckets: `assetwatch-terraform-state-{env}`
- Related Terraform files:
  - Old: `/home/aw-jwalker/repos/hwqa/terraform/*.tf`
  - New: `/home/aw-jwalker/repos/fullstack.assetwatch/terraform/lambdas.tf:1687-1745`
