---
date: 2026-01-02T16:00:08-05:00
researcher: Claude
git_commit: 7d814be13828d78dec2e77ed91ebfb43e538b73c
branch: main
repository: assetwatch-claude-plugins
topic: "AssetWatch Thoughts CLI Planning"
tags: [implementation, strategy, cli, thoughts, humanlayer-migration]
status: in_progress
last_updated: 2026-01-02
last_updated_by: Claude
type: implementation_strategy
---

# Handoff: AssetWatch Thoughts CLI Planning

## Task(s)

| Task                                                        | Status          |
| ----------------------------------------------------------- | --------------- |
| Research HumanLayer references in assetwatch-claude-plugins | **Completed**   |
| Deep-dive into HumanLayer thoughts CLI implementation       | **Completed**   |
| Design AssetWatch thoughts CLI strategy                     | **In Progress** |
| Create implementation plan                                  | **Planned**     |

**Context**: The assetwatch-claude-plugins repo was copied from HumanLayer and contains 47 references to "humanlayer" across 11 files. Rather than just removing these references, the user wants to **replicate the HumanLayer thoughts system** for AssetWatch team use.

**Key Decision Pending**: Whether to:

1. Build a new `assetwatch` CLI (replicating `humanlayer` CLI)
2. Use the existing `humanlayer` CLI directly in AssetWatch repos (if possible)

## Critical References

1. **Research document**: `thoughts/shared/research/2026-01-02-humanlayer-references-cleanup.md` - Contains all 47 humanlayer references categorized
2. **HumanLayer thoughts implementation**: `/home/aw-jwalker/repos/humanlayer/hlyr/src/commands/thoughts/` - The gold standard to follow

## Recent Changes

- `thoughts/shared/research/2026-01-02-humanlayer-references-cleanup.md` - Created comprehensive research document with GitHub permalinks

## Learnings

### HumanLayer Thoughts System Architecture

The system consists of three main components:

#### 1. Central Thoughts Repository (Separate Git Repo)

- Default location: `~/thoughts/`
- Structure:
  ```
  ~/thoughts/
  ├── repos/           # Per-repository thoughts
  │   ├── repo-name/
  │   │   ├── USERNAME/   # Personal notes
  │   │   └── shared/     # Team-shared notes
  │   └── ...
  ├── global/          # Cross-repository thoughts
  │   ├── USERNAME/
  │   └── shared/
  └── .git/
  ```

#### 2. CLI Commands (`humanlayer thoughts <command>`)

- **`init`** (`hlyr/src/commands/thoughts/init.ts`):
  - Creates `thoughts/` directory in code repo with symlinks to central thoughts repo
  - Sets up git hooks (pre-commit prevents committing thoughts/, post-commit auto-syncs)
  - Creates searchable/ directory with hard links
  - Generates CLAUDE.md documentation

- **`sync`** (`hlyr/src/commands/thoughts/sync.ts`):
  - `git add -A` all changes in thoughts repo
  - `git commit` with message
  - `git pull --rebase`
  - `git push`
  - Recreates searchable/ hard links

- **`status`** (`hlyr/src/commands/thoughts/status.ts`):
  - Shows thoughts repo git status
  - Shows uncommitted changes
  - Shows remote sync status

#### 3. Configuration (`~/.config/humanlayer/humanlayer.json`)

```json
{
  "thoughts": {
    "thoughtsRepo": "~/thoughts",
    "reposDir": "repos",
    "globalDir": "global",
    "user": "USERNAME",
    "repoMappings": {
      "/path/to/repo": "repo-name"
    },
    "profiles": { ... }  // For multiple thoughts repos
  }
}
```

### Key Implementation Files in HumanLayer

| File                                   | Purpose                                               |
| -------------------------------------- | ----------------------------------------------------- |
| `hlyr/src/commands/thoughts/init.ts`   | Main init logic (729 lines)                           |
| `hlyr/src/commands/thoughts/sync.ts`   | Sync logic with searchable index creation (243 lines) |
| `hlyr/src/commands/thoughts/status.ts` | Status display (207 lines)                            |
| `hlyr/src/thoughtsConfig.ts`           | Config loading/saving, path helpers (422 lines)       |
| `hlyr/src/config.ts`                   | General config resolver (265 lines)                   |
| `hack/spec_metadata.sh`                | Metadata script for plans/research (36 lines)         |

### AssetWatch Repos That Would Use This System

From `~/repos/` directory:

- assetwatch-claude-plugins
- assetwatch-jobs
- assetwatch-mobile-backend
- assetwatch.mobile
- fullstack.assetwatch
- fullstack.jobs
- external.api
- internal.api
- cloud-support-utils
- vero-utilities
- hwqa
- aws-projects

## Artifacts

1. `thoughts/shared/research/2026-01-02-humanlayer-references-cleanup.md` - Complete research with all 47 references categorized and GitHub permalinks

## Action Items & Next Steps

### Immediate Decision Needed

**Can we use the existing `humanlayer` CLI for AssetWatch repos?**

The `humanlayer` CLI is in `/home/aw-jwalker/repos/humanlayer/hlyr/`. To use it:

1. Install it globally: `cd /home/aw-jwalker/repos/humanlayer && npm install -g ./hlyr`
2. Configure thoughts for AssetWatch repos
3. The CLI doesn't care what repo you're in - it just manages thoughts

**Pros of using existing humanlayer CLI:**

- No new code to write
- Already tested and working
- Updates from HumanLayer automatically available

**Cons:**

- Confusing naming (using "humanlayer" tool for AssetWatch)
- Dependency on external repo
- May diverge from AssetWatch needs over time

**Alternative: Build `assetwatch` CLI**

- Fork/adapt the thoughts commands from humanlayer
- Create new package with AssetWatch branding
- Full control over implementation

### If Building New CLI

1. **Decide on architecture**:
   - Where should CLI code live? (`assetwatch-claude-plugins/cli/` or new repo)
   - What should it be called? (`assetwatch`, `aw`, etc.)

2. **Create thoughts repo**:
   - Create `AssetWatch1/assetwatch-thoughts` on GitHub
   - Set up structure: `repos/`, `global/`

3. **Implement CLI**:
   - Port `init.ts`, `sync.ts`, `status.ts` from humanlayer
   - Update config paths to `~/.config/assetwatch/`
   - Update branding/messages

4. **Update plugin commands**:
   - Replace `humanlayer thoughts sync` with `assetwatch thoughts sync`
   - Replace all other humanlayer references

### If Using Existing humanlayer CLI

1. **Set up thoughts repo**:
   - Can use same `~/thoughts/` or create AssetWatch-specific one
   - Configure profiles in humanlayer config for AssetWatch repos

2. **Update plugin commands**:
   - Keep `humanlayer thoughts sync` as-is (it works!)
   - Remove/update other humanlayer-specific references (wui paths, debug paths, etc.)

## Other Notes

### Files with HumanLayer References (Summary)

| Category                             | Count | Action Needed                   |
| ------------------------------------ | ----- | ------------------------------- |
| `humanlayer thoughts sync` commands  | 8     | Keep or replace with assetwatch |
| `humanlayer thoughts` setup messages | 3     | Keep or replace                 |
| `humanlayer-wui/` directory refs     | 8     | Remove (HumanLayer-specific)    |
| `~/wt/humanlayer/` worktree paths    | 5     | Remove (HumanLayer-specific)    |
| `humanlayer launch` commands         | 2     | Remove (HumanLayer-specific)    |
| `~/.humanlayer/` config paths        | 17    | Remove (HumanLayer-specific)    |
| GitHub remote refs                   | 1     | Update to AssetWatch            |

### Questions for Next Session

1. Should we use the existing `humanlayer` CLI or build a new `assetwatch` CLI?
2. If new CLI: Where should the code live?
3. Should the thoughts repo be hosted on GitHub for team collaboration?
4. What should the configuration path be? (`~/.config/assetwatch/`)
