#!/bin/bash
# thoughts config - View or edit thoughts configuration
#
# Usage:
#   thoughts config           Show current configuration
#   thoughts config --edit    Edit configuration in $EDITOR
#   thoughts config --json    Output configuration as JSON

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Parse options
EDIT=false
JSON=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --edit|-e)
            EDIT=true
            shift
            ;;
        --json|-j)
            JSON=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

main() {
    # Ensure config exists
    init_config

    # Handle edit mode
    if [ "$EDIT" = "true" ]; then
        local editor="${EDITOR:-vi}"
        exec "$editor" "$CONFIG_FILE"
    fi

    # Handle JSON output
    if [ "$JSON" = "true" ]; then
        cat "$CONFIG_FILE"
        exit 0
    fi

    # Display configuration
    local thoughts_repo=$(get_config "thoughtsRepo")
    local repos_dir=$(get_config "reposDir")
    local global_dir=$(get_config "globalDir")
    local user=$(get_config "user")

    echo "Thoughts Configuration"
    echo "=================================================="
    echo ""
    echo "Settings:"
    echo "  Config file:        $CONFIG_FILE"
    echo "  Thoughts repository: $thoughts_repo"
    echo "  Repos directory:     $repos_dir"
    echo "  Global directory:    $global_dir"
    echo "  User:               $user"
    echo ""

    echo "Repository Mappings:"
    local mappings=$(get_all_mappings)
    if [ -z "$mappings" ]; then
        echo "  (no repositories mapped yet)"
    else
        echo "$mappings" | while read -r mapping; do
            echo "  $mapping"
        done
    fi
    echo ""

    # Show current repo status
    local current_repo=$(get_current_repo)
    local current_mapping=$(get_repo_mapping "$current_repo")

    echo "Current Repository:"
    echo "  Path: $current_repo"
    if [ -n "$current_mapping" ]; then
        echo "  Mapped to: $repos_dir/$current_mapping"
        if [ -d "$current_repo/thoughts" ]; then
            echo "  Status: Initialized"
        else
            echo "  Status: Not initialized (run 'thoughts init')"
        fi
    else
        echo "  Status: Not mapped"
    fi
    echo ""

    echo "To edit configuration, run: thoughts config --edit"
}

main
