#!/bin/bash
# common.sh - Shared functions for thoughts CLI
#
# This file provides configuration management functions used by all thoughts commands.

# Configuration file location
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/thoughts"
CONFIG_FILE="$CONFIG_DIR/config.json"

# Default values
DEFAULT_THOUGHTS_REPO="$HOME/repos/thoughts"
DEFAULT_REPOS_DIR="repos"
DEFAULT_GLOBAL_DIR="global"
DEFAULT_USER="${USER:-$(whoami)}"

# Ensure jq is available (required for JSON config)
check_jq() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required but not installed."
        echo "Install with: sudo apt install jq  (or brew install jq on macOS)"
        exit 1
    fi
}

# Initialize config file if it doesn't exist
init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        mkdir -p "$CONFIG_DIR"
        cat > "$CONFIG_FILE" << EOF
{
    "thoughtsRepo": "$DEFAULT_THOUGHTS_REPO",
    "reposDir": "$DEFAULT_REPOS_DIR",
    "globalDir": "$DEFAULT_GLOBAL_DIR",
    "user": "$DEFAULT_USER",
    "repoMappings": {}
}
EOF
    fi
}

# Get config value
get_config() {
    local key="$1"
    check_jq
    init_config
    jq -r ".$key // empty" "$CONFIG_FILE"
}

# Set config value
set_config() {
    local key="$1"
    local value="$2"
    check_jq
    init_config
    local tmp=$(mktemp)
    jq ".$key = \"$value\"" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

# Get repo mapping for a path
get_repo_mapping() {
    local repo_path="$1"
    check_jq
    init_config
    jq -r ".repoMappings[\"$repo_path\"] // empty" "$CONFIG_FILE"
}

# Set repo mapping
set_repo_mapping() {
    local repo_path="$1"
    local mapped_name="$2"
    check_jq
    init_config
    local tmp=$(mktemp)
    jq ".repoMappings[\"$repo_path\"] = \"$mapped_name\"" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

# Remove repo mapping
remove_repo_mapping() {
    local repo_path="$1"
    check_jq
    init_config
    local tmp=$(mktemp)
    jq "del(.repoMappings[\"$repo_path\"])" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

# Get all mapped repos
get_all_mappings() {
    check_jq
    init_config
    jq -r '.repoMappings | to_entries[] | "\(.key) → \(.value)"' "$CONFIG_FILE"
}

# Get current repo path (canonicalized)
get_current_repo() {
    local dir="$(pwd)"
    # Try to get git root, fall back to current directory
    local git_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$git_root" ]; then
        echo "$git_root"
    else
        echo "$dir"
    fi
}

# Sanitize directory name (allow alphanumeric, dots, dashes, underscores)
sanitize_name() {
    echo "$1" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

# Get thoughts repo path (expanded)
get_thoughts_repo() {
    local repo=$(get_config "thoughtsRepo")
    echo "${repo/#\~/$HOME}"
}

# Get repos directory name
get_repos_dir() {
    get_config "reposDir"
}

# Get global directory name
get_global_dir() {
    get_config "globalDir"
}

# Get user name
get_user() {
    get_config "user"
}
