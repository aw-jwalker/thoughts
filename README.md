# Thoughts

Central repository for project thoughts, research notes, plans, and handoffs.

## Structure

```
thoughts/
├── repos/           # Per-project thoughts
│   ├── project-a/
│   │   └── shared/
│   └── project-b/
│       └── shared/
└── scripts/         # CLI tools
    ├── thoughts     # Main CLI
    ├── init.sh      # Initialize a project
    └── sync.sh      # Sync to remote
```

## Installation

Add the scripts directory to your PATH:

```bash
echo 'export PATH="$HOME/repos/thoughts/scripts:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Usage

### Initialize a new project

```bash
cd ~/repos/myproject
thoughts init
```

This creates a symlink from `myproject/thoughts/` to `~/repos/thoughts/repos/myproject/`.

### Sync thoughts to remote

```bash
thoughts sync "Added research notes"
```

### Check status

```bash
thoughts status
```

## Per-project structure

Each project typically has:

```
thoughts/
└── shared/
    ├── handoffs/    # Session handoff documents
    ├── plans/       # Implementation plans
    └── research/    # Research notes and findings
```
