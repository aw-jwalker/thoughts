# Worktree Management for RPI Plugin - Implementation Plan

## Overview

Add git worktree management capabilities to the RPI plugin and thoughts CLI. This enables isolated implementation sessions that don't interfere with the main repository state, with proper cleanup when done.

## Current State Analysis

- `shared/commands/create_worktree.md` exists but requires `hack/create_worktree.sh` in each project (fragile)
- No worktree cleanup functionality exists
- The thoughts CLI (`~/dotfiles/thoughts/`) has a modular script structure ready for extension
- Worktrees are currently placed at `~/wt/{project}/{ticket}` per existing convention

### Key Discoveries:
- Thoughts CLI structure at `~/dotfiles/thoughts/`: main script + modular scripts (init.sh, sync.sh, etc.) - `thoughts:33-46`
- Existing create_worktree.md references non-existent scripts - `shared/commands/create_worktree.md:6`
- implement_plan.md is the primary implementation command - `rpi/commands/implement_plan.md`

## Desired End State

1. `thoughts worktree add <branch>` - Creates worktree at `~/wt/{project}/{branch}/`
2. `thoughts worktree remove <branch>` - Safely removes worktree and optionally the branch
3. `thoughts worktree list` - Lists worktrees for current project
4. `/implement_plan_wt [branch] <plan-path>` - Creates worktree and launches implementation
5. `/clean_worktree [branch]` - Removes worktree with safety checks
6. `shared/commands/create_worktree.md` - Removed (superseded)

### Verification:
- `thoughts worktree add test-branch` creates `~/wt/{project}/test-branch/`
- `thoughts worktree list` shows the worktree
- `thoughts worktree remove test-branch` cleans it up
- `/implement_plan_wt` extracts branch from plan filename and creates worktree

## What We're NOT Doing

- Not changing the worktree location convention (`~/wt/`)
- Not adding worktree functionality to projects that don't use the thoughts CLI
- Not integrating with the `commit-commands:clean_gone` skill (separate concerns)
- Not handling merge conflicts in worktrees (user responsibility)

## Implementation Approach

Add worktree management scripts to the thoughts CLI first (reusable foundation), then create RPI commands that leverage those scripts.

---

## Phase 1: Add Worktree Scripts to Thoughts CLI

### Overview
Add worktree management as a new subcommand to the thoughts CLI.

### Changes Required:

#### 1. Create worktree.sh script
**File**: `~/dotfiles/thoughts/worktree.sh`

```bash
#!/bin/bash
# worktree.sh - Git worktree management for thoughts-enabled projects
#
# Usage:
#   worktree.sh add <branch> [--base <base-branch>]  - Create worktree
#   worktree.sh remove <branch> [--delete-branch]    - Remove worktree
#   worktree.sh list                                  - List worktrees
#   worktree.sh path <branch>                         - Print worktree path

set -e

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/common.sh" 2>/dev/null || true

# Worktree root directory
WT_ROOT="${THOUGHTS_WT_ROOT:-$HOME/wt}"

# Get project name from git repo
get_project_name() {
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "Error: Not in a git repository" >&2
        exit 1
    }
    basename "$repo_root"
}

# Get worktree path for a branch
get_worktree_path() {
    local branch="$1"
    local project
    project=$(get_project_name)
    echo "$WT_ROOT/$project/$branch"
}

# Check if worktree exists
worktree_exists() {
    local branch="$1"
    local wt_path
    wt_path=$(get_worktree_path "$branch")
    [ -d "$wt_path" ]
}

# Add a new worktree
cmd_add() {
    local branch=""
    local base_branch="main"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --base)
                base_branch="$2"
                shift 2
                ;;
            -*)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
            *)
                branch="$1"
                shift
                ;;
        esac
    done

    if [ -z "$branch" ]; then
        echo "Usage: thoughts worktree add <branch> [--base <base-branch>]" >&2
        exit 1
    fi

    local project
    project=$(get_project_name)
    local wt_path
    wt_path=$(get_worktree_path "$branch")

    if worktree_exists "$branch"; then
        echo "Worktree already exists: $wt_path"
        echo "$wt_path"
        exit 0
    fi

    # Create worktree directory parent
    mkdir -p "$WT_ROOT/$project"

    # Check if branch exists
    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
        echo "Using existing branch: $branch"
        git worktree add "$wt_path" "$branch"
    elif git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
        echo "Checking out remote branch: $branch"
        git worktree add "$wt_path" "$branch"
    else
        echo "Creating new branch: $branch (from $base_branch)"
        # Ensure we have latest base branch
        git fetch origin "$base_branch" 2>/dev/null || true
        git worktree add -b "$branch" "$wt_path" "origin/$base_branch" 2>/dev/null || \
            git worktree add -b "$branch" "$wt_path" "$base_branch"
    fi

    echo ""
    echo "Worktree created: $wt_path"
    echo "$wt_path"
}

# Remove a worktree
cmd_remove() {
    local branch=""
    local delete_branch=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --delete-branch)
                delete_branch=true
                shift
                ;;
            -*)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
            *)
                branch="$1"
                shift
                ;;
        esac
    done

    if [ -z "$branch" ]; then
        echo "Usage: thoughts worktree remove <branch> [--delete-branch]" >&2
        exit 1
    fi

    local wt_path
    wt_path=$(get_worktree_path "$branch")

    # Check if we're currently in the worktree
    local current_dir
    current_dir=$(pwd)
    if [[ "$current_dir" == "$wt_path"* ]]; then
        echo "WARNING: You are currently in this worktree!" >&2
        echo "Please cd to a different directory before removing." >&2
        echo ""
        echo "Suggested: cd $(git rev-parse --show-toplevel 2>/dev/null || echo ~)" >&2
        exit 1
    fi

    if ! worktree_exists "$branch"; then
        echo "Worktree does not exist: $wt_path" >&2
        # Still try to prune in case of stale entries
        git worktree prune 2>/dev/null || true
        exit 0
    fi

    echo "Removing worktree: $wt_path"
    git worktree remove "$wt_path" --force 2>/dev/null || {
        echo "Forcing removal..."
        rm -rf "$wt_path"
        git worktree prune
    }

    if [ "$delete_branch" = true ]; then
        echo "Deleting branch: $branch"
        git branch -D "$branch" 2>/dev/null || echo "Branch not found or already deleted"
    fi

    echo "Done."
}

# List worktrees for current project
cmd_list() {
    local project
    project=$(get_project_name)
    local project_wt_dir="$WT_ROOT/$project"

    echo "Worktrees for $project:"
    echo "Location: $project_wt_dir"
    echo ""

    if [ -d "$project_wt_dir" ]; then
        git worktree list | grep "$project_wt_dir" || echo "(none)"
    else
        echo "(none)"
    fi

    echo ""
    echo "All worktrees:"
    git worktree list
}

# Print worktree path
cmd_path() {
    local branch="$1"
    if [ -z "$branch" ]; then
        echo "Usage: thoughts worktree path <branch>" >&2
        exit 1
    fi
    get_worktree_path "$branch"
}

# Main dispatch
case "${1:-help}" in
    add)
        shift
        cmd_add "$@"
        ;;
    remove|rm)
        shift
        cmd_remove "$@"
        ;;
    list|ls)
        shift
        cmd_list "$@"
        ;;
    path)
        shift
        cmd_path "$@"
        ;;
    help|--help|-h)
        echo "thoughts worktree - Git worktree management"
        echo ""
        echo "Usage:"
        echo "  thoughts worktree add <branch> [--base <base>]  Create worktree at ~/wt/{project}/{branch}"
        echo "  thoughts worktree remove <branch> [--delete-branch]  Remove worktree"
        echo "  thoughts worktree list                          List worktrees"
        echo "  thoughts worktree path <branch>                 Print worktree path"
        echo ""
        echo "Environment:"
        echo "  THOUGHTS_WT_ROOT  Override worktree root (default: ~/wt)"
        ;;
    *)
        echo "Unknown subcommand: $1" >&2
        echo "Run 'thoughts worktree help' for usage" >&2
        exit 1
        ;;
esac
```

#### 2. Update thoughts main script
**File**: `~/dotfiles/thoughts/thoughts`
**Changes**: Add worktree case to the main dispatch

Add this case before the `help` case (around line 176):

```bash
    worktree|wt)
        shift
        "$SCRIPTS_DIR/worktree.sh" "$@"
        ;;
```

### Success Criteria:

#### Automated Verification:
- [ ] `thoughts worktree help` shows usage
- [ ] Script is executable: `chmod +x ~/dotfiles/thoughts/worktree.sh`

#### Manual Verification:
- [ ] `thoughts worktree add test-branch` creates `~/wt/{project}/test-branch/`
- [ ] `thoughts worktree list` shows the new worktree
- [ ] `thoughts worktree path test-branch` prints the correct path
- [ ] `thoughts worktree remove test-branch` removes it cleanly

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 2.

---

## Phase 2: Create /implement_plan_wt Command

### Overview
Create an RPI command that creates a worktree and launches plan implementation in one step.

### Changes Required:

#### 1. Create implement_plan_wt.md
**File**: `rpi/commands/implement_plan_wt.md`

```markdown
---
description: Create worktree and implement plan in isolated environment
argument-hint: <[branch] thoughts/shared/plans/2025-01-01-IWA-1234-feature.md>
---

# Implement Plan in Worktree

Creates a git worktree for isolated implementation, then launches a Claude session to implement the plan.

## Argument Parsing

Arguments: `[branch] <plan-path>`

- If TWO arguments: first is branch name, second is plan path
- If ONE argument: it's the plan path, extract branch from filename

## Branch Name Extraction

When branch is not provided, extract from plan filename:

1. Plan filename format: `YYYY-MM-DD-{identifier}-description.md`
2. Extract the identifier portion (usually ticket number)
3. Examples:
   - `2025-01-29-IWA-1234-add-feature.md` → branch: `IWA-1234`
   - `2025-01-29-gh-9-fix-zips.md` → branch: `gh-9-fix-zips`
   - `2025-01-29-MOBILE-567-update-api.md` → branch: `MOBILE-567`

Pattern: After the date prefix, take everything up to but not including the last hyphenated segment if it looks like a description (lowercase words), OR take everything after the date if it's all identifier-like.

If extraction fails or is ambiguous, ask the user for the branch name.

## Workflow

1. **Parse arguments** to get branch name and plan path

2. **Validate plan exists**:
   ```bash
   # Check plan file exists
   test -f "$PLAN_PATH"
   ```

3. **Check current branch**:
   ```bash
   git branch --show-current
   ```
   - If already on a feature branch (not main/master/dev), warn user and ask if they want to continue

4. **Create worktree** using thoughts CLI:
   ```bash
   thoughts worktree add "$BRANCH_NAME"
   ```
   - Capture the worktree path from output (last line)

5. **Confirm with user**:
   ```
   Ready to launch implementation session:

   Worktree: ~/wt/{project}/{branch}
   Branch: {branch}
   Plan: {plan-path}

   Command:
       claude -w ~/wt/{project}/{branch} "/implement_plan {plan-path}"

   Proceed? (The session will implement the plan, run tests, commit, and create a PR)
   ```

6. **Launch Claude session**:
   ```bash
   claude -w "$WORKTREE_PATH" "/implement_plan $PLAN_PATH and when you are done implementing and all tests pass, /commit then /describe_pr then add a comment to the ticket with the PR link"
   ```

## Error Handling

- If `thoughts worktree` command not found: Show installation instructions
- If worktree creation fails: Show error and suggest manual steps
- If plan file not found: List available plans in `thoughts/shared/plans/`

## Example Usage

```
/implement_plan_wt thoughts/shared/plans/2025-01-29-IWA-1234-feature.md
# → Creates branch IWA-1234, worktree at ~/wt/project/IWA-1234, launches implementation

/implement_plan_wt my-custom-branch thoughts/shared/plans/2025-01-29-feature.md
# → Uses explicit branch name "my-custom-branch"
```
```

### Success Criteria:

#### Automated Verification:
- [ ] File exists: `rpi/commands/implement_plan_wt.md`
- [ ] YAML frontmatter is valid

#### Manual Verification:
- [ ] `/implement_plan_wt` with no args shows usage
- [ ] `/implement_plan_wt thoughts/shared/plans/test-plan.md` extracts branch correctly
- [ ] Worktree is created at expected location
- [ ] Claude session launches with correct working directory

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 3.

---

## Phase 3: Create /clean_worktree Command

### Overview
Create an RPI command to safely remove worktrees.

### Changes Required:

#### 1. Create clean_worktree.md
**File**: `rpi/commands/clean_worktree.md`

```markdown
---
description: Safely remove git worktrees
argument-hint: <[branch-name]>
---

# Clean Worktree

Safely removes git worktrees created by `/implement_plan_wt`.

## Safety Checks

**CRITICAL**: This command MUST check if the current Claude session is running inside the worktree being removed. If so, bash commands will fail after removal.

## Workflow

### If branch name provided:

1. **Check if we're in the target worktree**:
   ```bash
   pwd
   thoughts worktree path "$BRANCH_NAME"
   ```
   - If current directory is inside the worktree path, STOP and warn:
     ```
     ⚠️  Cannot remove worktree - you are currently inside it!

     Current directory: /home/user/wt/project/branch
     Worktree to remove: /home/user/wt/project/branch

     To clean this worktree:
     1. Open a new terminal
     2. cd to the main repository: cd ~/repos/project
     3. Run: thoughts worktree remove {branch} --delete-branch

     Or start a new Claude session in the main repo and run /clean_worktree {branch}
     ```

2. **Confirm removal**:
   ```
   Remove worktree for branch '{branch}'?

   Worktree path: ~/wt/{project}/{branch}

   Options:
   1. Remove worktree only (keep branch)
   2. Remove worktree AND delete branch
   3. Cancel
   ```

3. **Execute removal**:
   ```bash
   # Option 1:
   thoughts worktree remove "$BRANCH_NAME"

   # Option 2:
   thoughts worktree remove "$BRANCH_NAME" --delete-branch
   ```

### If no branch name provided:

1. **List available worktrees**:
   ```bash
   thoughts worktree list
   ```

2. **Ask user which to remove** (or allow "all merged" option)

## Example Usage

```
/clean_worktree IWA-1234
# → Removes worktree for IWA-1234 after confirmation

/clean_worktree
# → Lists worktrees and prompts for selection
```
```

### Success Criteria:

#### Automated Verification:
- [ ] File exists: `rpi/commands/clean_worktree.md`
- [ ] YAML frontmatter is valid

#### Manual Verification:
- [ ] `/clean_worktree` lists available worktrees
- [ ] `/clean_worktree branch-name` prompts for confirmation
- [ ] Safety check prevents removal when inside the worktree
- [ ] Worktree is actually removed after confirmation

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 4.

---

## Phase 4: Remove Old create_worktree.md

### Overview
Remove the deprecated command now that it's superseded.

### Changes Required:

#### 1. Delete create_worktree.md
**File**: `shared/commands/create_worktree.md`
**Action**: Delete this file

```bash
rm shared/commands/create_worktree.md
```

#### 2. Update any references
Check for references to `create_worktree` in other files and update them to reference `implement_plan_wt`.

### Success Criteria:

#### Automated Verification:
- [ ] `shared/commands/create_worktree.md` does not exist
- [ ] No broken references: `grep -r "create_worktree" rpi/ shared/` returns no results

#### Manual Verification:
- [ ] Plugin loads without errors

---

## Testing Strategy

### Unit Tests:
- Not applicable (bash scripts)

### Integration Tests:
- Create a test worktree with `thoughts worktree add test-branch`
- Verify it appears in `git worktree list`
- Remove it with `thoughts worktree remove test-branch`
- Verify cleanup

### Manual Testing Steps:
1. In a thoughts-enabled repo, run `thoughts worktree add test-wt`
2. Verify `~/wt/{project}/test-wt/` exists
3. Run `thoughts worktree list` - should show the worktree
4. Run `thoughts worktree remove test-wt` - should clean up
5. Test `/implement_plan_wt` with a real plan file
6. Test `/clean_worktree` from the main repo

## References

- Existing create_worktree.md: `shared/commands/create_worktree.md`
- Thoughts CLI: `~/dotfiles/thoughts/thoughts`
- implement_plan.md: `rpi/commands/implement_plan.md:1-89`
- Git worktree best practices: https://gist.github.com/induratized/49cdedace4a200fa8ae32db9ba3e9a44
