#!/bin/bash
# thoughts init - Initialize thoughts symlinks for a project
#
# Usage: thoughts init [project-name]
#   If project-name is not provided, uses the current directory name

set -e

THOUGHTS_REPO="$HOME/repos/thoughts"
REPOS_DIR="$THOUGHTS_REPO/repos"

# Get project name
if [ -n "$1" ]; then
    PROJECT_NAME="$1"
else
    PROJECT_NAME=$(basename "$(pwd)")
fi

PROJECT_THOUGHTS="$REPOS_DIR/$PROJECT_NAME"

echo "Initializing thoughts for: $PROJECT_NAME"

# Check if we're in a git repo
if [ ! -d ".git" ] && [ ! -f ".git" ]; then
    echo "Warning: Not in a git repository root"
fi

# Create project directory in thoughts repo if it doesn't exist
if [ ! -d "$PROJECT_THOUGHTS" ]; then
    echo "Creating thoughts directory: $PROJECT_THOUGHTS"
    mkdir -p "$PROJECT_THOUGHTS/shared"
fi

# Handle existing thoughts directory
if [ -d "thoughts" ] && [ ! -L "thoughts" ]; then
    echo "Error: thoughts/ directory exists and is not a symlink"
    echo "If you want to migrate existing thoughts, run:"
    echo "  mv thoughts/* $PROJECT_THOUGHTS/"
    echo "  rm -rf thoughts"
    echo "Then run this script again."
    exit 1
fi

# Remove existing symlink if present
if [ -L "thoughts" ]; then
    echo "Removing existing symlink"
    rm thoughts
fi

# Create the symlink
echo "Creating symlink: thoughts -> $PROJECT_THOUGHTS"
ln -s "$PROJECT_THOUGHTS" thoughts

# Add to .gitignore if not already present
if [ -f ".gitignore" ]; then
    if ! grep -q "^thoughts/$" .gitignore 2>/dev/null; then
        echo "Adding thoughts/ to .gitignore"
        echo "thoughts/" >> .gitignore
    fi
else
    echo "Creating .gitignore with thoughts/"
    echo "thoughts/" > .gitignore
fi

echo ""
echo "Done! Your thoughts directory is now linked to:"
echo "  $PROJECT_THOUGHTS"
echo ""
echo "To sync thoughts: thoughts sync"
