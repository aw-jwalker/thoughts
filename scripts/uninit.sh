#!/bin/bash
# thoughts uninit - Remove thoughts setup from a project
#
# Usage: thoughts uninit [--force]
#
# This removes:
# - thoughts/ directory (symlinks only, not actual content)
# - Repository mapping from config
#
# Your actual thoughts content remains safe in the thoughts repository.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Parse options
FORCE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

main() {
    local current_repo=$(get_current_repo)
    local thoughts_dir="$current_repo/thoughts"
    local thoughts_repo=$(get_thoughts_repo)
    local repos_dir=$(get_repos_dir)

    # Check if thoughts directory exists
    if [ ! -e "$thoughts_dir" ] && [ ! -L "$thoughts_dir" ]; then
        echo "Error: Thoughts not initialized for this repository."
        exit 1
    fi

    # Get mapping
    local mapped_name=$(get_repo_mapping "$current_repo")

    if [ -z "$mapped_name" ] && [ "$FORCE" != "true" ]; then
        echo "Error: This repository is not in the thoughts configuration."
        echo "Use --force to remove the thoughts directory anyway."
        exit 1
    fi

    echo "Removing thoughts setup from current repository..."

    # Handle searchable directory if it exists (might have restricted permissions)
    if [ -d "$thoughts_dir/searchable" ]; then
        echo "Removing searchable directory..."
        chmod -R 755 "$thoughts_dir/searchable" 2>/dev/null || true
    fi

    # Remove the thoughts directory
    echo "Removing thoughts directory (symlinks only)..."
    rm -rf "$thoughts_dir"

    # Remove from config if mapped
    if [ -n "$mapped_name" ]; then
        echo "Removing repository from thoughts configuration..."
        remove_repo_mapping "$current_repo"
    fi

    echo ""
    echo "Thoughts removed from repository"

    # Show where content remains
    if [ -n "$mapped_name" ]; then
        echo ""
        echo "Note: Your thoughts content remains safe in:"
        echo "  $thoughts_repo/$repos_dir/$mapped_name"
        echo ""
        echo "Only the local symlinks and configuration were removed."
        echo "To re-initialize, run: thoughts init"
    fi
}

main
