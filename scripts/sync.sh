#!/bin/bash
# thoughts sync - Sync thoughts repo with remote
#
# Usage: thoughts sync [commit message]
#   If message not provided, uses timestamp
#
# This also creates/updates the searchable directory with hard links
# so AI tools can search without following symlinks.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Create searchable directory with hard links
create_searchable_directory() {
    local thoughts_dir="$1"
    local search_dir="$thoughts_dir/searchable"

    # Remove existing searchable directory
    if [ -d "$search_dir" ]; then
        chmod -R 755 "$search_dir" 2>/dev/null || true
        rm -rf "$search_dir"
    fi

    # Create new searchable directory
    mkdir -p "$search_dir"

    local linked_count=0

    # Function to process a directory and create hard links
    process_directory() {
        local dir="$1"
        local rel_prefix="$2"  # Relative path prefix for target

        # Resolve the real path (follow symlinks)
        local real_dir=$(readlink -f "$dir" 2>/dev/null || echo "$dir")

        # Find all files (not directories, not hidden, not CLAUDE.md)
        while IFS= read -r -d '' file; do
            local basename=$(basename "$file")

            # Skip hidden files and CLAUDE.md
            [[ "$basename" == .* ]] && continue
            [[ "$basename" == "CLAUDE.md" ]] && continue

            # Get relative path from the source dir
            local rel_path="${file#$real_dir/}"

            # Target path in searchable directory
            local target_path="$search_dir/$rel_prefix/$rel_path"
            local target_dir=$(dirname "$target_path")

            # Create target directory structure
            mkdir -p "$target_dir"

            # Create hard link
            if ln "$file" "$target_path" 2>/dev/null; then
                linked_count=$((linked_count + 1))
            fi
        done < <(find "$real_dir" -type f -print0 2>/dev/null)
    }

    # Process each symlink directory in thoughts/
    for item in "$thoughts_dir"/*; do
        [ -e "$item" ] || continue

        local name=$(basename "$item")

        # Skip searchable directory itself and CLAUDE.md
        [[ "$name" == "searchable" ]] && continue
        [[ "$name" == "CLAUDE.md" ]] && continue

        if [ -L "$item" ] || [ -d "$item" ]; then
            process_directory "$item" "$name"
        fi
    done

    echo "Created $linked_count hard links in searchable directory"
}

# Main sync logic
main() {
    local message="$*"

    local thoughts_repo=$(get_thoughts_repo)
    local current_repo=$(get_current_repo)
    local thoughts_dir="$current_repo/thoughts"

    # Check if thoughts are initialized for current repo
    if [ -d "$thoughts_dir" ]; then
        echo "Creating searchable index..."
        create_searchable_directory "$thoughts_dir"
    fi

    # Default commit message
    if [ -z "$message" ]; then
        message="Sync: $(date '+%Y-%m-%d %H:%M:%S')"
    fi

    cd "$thoughts_repo"

    # Check for changes
    if [ -z "$(git status --porcelain)" ]; then
        echo "No changes to sync"

        # Still pull in case there are remote changes
        if git remote get-url origin &>/dev/null; then
            echo "Pulling from remote..."
            git pull --rebase 2>/dev/null || echo "Warning: Could not pull"
        fi
        return 0
    fi

    # Show what's changed
    echo "Changes to sync:"
    git status --short
    echo ""

    # Stage all changes
    git add -A

    # Commit
    echo "Committing: $message"
    git commit -m "$message"

    # Push if remote exists
    if git remote get-url origin &>/dev/null; then
        echo "Pushing to remote..."
        git pull --rebase 2>/dev/null || {
            echo "Warning: Merge conflict during rebase. Please resolve manually in:"
            echo "  $thoughts_repo"
            exit 1
        }
        git push
        echo "Synced to remote!"
    else
        echo "No remote configured, changes committed locally only"
    fi
}

main "$@"
