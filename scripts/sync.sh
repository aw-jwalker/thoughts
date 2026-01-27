#!/bin/bash
# thoughts sync - Sync thoughts repo with remote
#
# Usage: thoughts sync [commit message]
#   If message not provided, uses timestamp

set -e

THOUGHTS_REPO="$HOME/repos/thoughts"

cd "$THOUGHTS_REPO"

# Default commit message
if [ -n "$1" ]; then
    MESSAGE="$*"
else
    MESSAGE="Sync: $(date '+%Y-%m-%d %H:%M:%S')"
fi

# Check for changes
if [ -z "$(git status --porcelain)" ]; then
    echo "No changes to sync"

    # Still pull in case there are remote changes
    if git remote get-url origin &>/dev/null; then
        echo "Pulling from remote..."
        git pull --rebase
    fi
    exit 0
fi

# Show what's changed
echo "Changes to sync:"
git status --short
echo ""

# Stage all changes
git add -A

# Commit
echo "Committing: $MESSAGE"
git commit -m "$MESSAGE"

# Push if remote exists
if git remote get-url origin &>/dev/null; then
    echo "Pushing to remote..."
    git pull --rebase
    git push
    echo "Synced to remote!"
else
    echo "No remote configured, changes committed locally only"
fi
