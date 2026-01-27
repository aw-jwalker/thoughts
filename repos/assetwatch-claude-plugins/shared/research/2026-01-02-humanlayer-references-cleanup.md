---
date: 2026-01-02T11:03:09-05:00
researcher: Claude
git_commit: b3a534a955ba1835e43f85944657699768caed60
branch: main
repository: assetwatch-claude-plugins
topic: "HumanLayer References Cleanup"
tags: [research, codebase, refactoring, humanlayer, migration]
status: complete
last_updated: 2026-01-02
last_updated_by: Claude
---

# Research: HumanLayer References Cleanup

**Date**: 2026-01-02T11:03:09-05:00
**Researcher**: Claude
**Git Commit**: b3a534a955ba1835e43f85944657699768caed60
**Branch**: main
**Repository**: assetwatch-claude-plugins

## Research Question

Identify all references to "humanlayer" in this repository that need to be updated since this code was copied from the HumanLayer repository and is being adapted for the AssetWatch system.

## Summary

Found **47 total references** to "humanlayer" across **11 files**. These references fall into 7 categories that should be addressed in separate implementation phases to maintain clean commits and easy rollback if needed.

## Detailed Findings

### Category 1: `humanlayer thoughts sync` Command (8 occurrences)

CLI commands to sync a thoughts directory. These should be **removed entirely** as AssetWatch doesn't use this CLI tool.

| File                                                                                                                                                                               | Line | Reference                  |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | -------------------------- |
| [shared/commands/describe_pr.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/describe_pr.md#L61)        | 61   | `humanlayer thoughts sync` |
| [shared/commands/ci_describe_pr.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/ci_describe_pr.md#L60)  | 60   | `humanlayer thoughts sync` |
| [rpi/commands/resume_handoff.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/resume_handoff.md#L22)        | 22   | `humanlayer thoughts sync` |
| [rpi/commands/iterate_plan.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/iterate_plan.md#L137)           | 137  | `humanlayer thoughts sync` |
| [rpi/commands/create_handoff.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/create_handoff.md#L69)        | 69   | `humanlayer thoughts sync` |
| [rpi/commands/research_codebase.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/research_codebase.md#L166) | 166  | `humanlayer thoughts sync` |
| [rpi/commands/create_plan.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/create_plan.md#L284)             | 284  | `humanlayer thoughts sync` |
| [rpi/commands/create_plan.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/create_plan.md#L304)             | 304  | `humanlayer thoughts sync` |

**Action**: Remove all `humanlayer thoughts sync` commands and related steps.

---

### Category 2: `humanlayer thoughts` Setup References (3 occurrences)

Error messages about "humanlayer thoughts setup" being incomplete. These should be **removed or updated** with AssetWatch-appropriate messaging.

| File                                                                                                                                                                              | Line | Reference                                         |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | ------------------------------------------------- |
| [shared/commands/describe_pr.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/describe_pr.md#L13)       | 13   | `humanlayer thoughts` setup incomplete            |
| [shared/commands/ci_describe_pr.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/ci_describe_pr.md#L13) | 13   | `humanlayer thoughts` setup incomplete            |
| [shared/commands/local_review.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/local_review.md#L31)     | 31   | `humanlayer thoughts init --directory humanlayer` |

**Action**: Remove error messages about humanlayer thoughts setup and the init command.

---

### Category 3: `humanlayer-wui/` Directory References (8 occurrences)

References to a "humanlayer-wui" directory (Web UI component). These are **HumanLayer-specific** and should be removed as AssetWatch has different project structure.

| File                                                                                                                                                                         | Line | Reference                      |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | ------------------------------ |
| [rpi/commands/iterate_plan.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/iterate_plan.md#L82)      | 82   | `humanlayer-wui/` directory    |
| [rpi/commands/iterate_plan.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/iterate_plan.md#L200)     | 200  | `make -C humanlayer-wui check` |
| [rpi/commands/create_plan.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/create_plan.md#L60)        | 60   | `humanlayer-wui/` directory    |
| [rpi/commands/create_plan.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/create_plan.md#L327)       | 327  | `make -C humanlayer-wui check` |
| [rpi/commands/create_plan.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/create_plan.md#L417)       | 417  | `humanlayer-wui/` directory    |
| [rpi/commands/create_plan_nt.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/create_plan_nt.md#L58)  | 58   | `humanlayer-wui/` directory    |
| [rpi/commands/create_plan_nt.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/create_plan_nt.md#L315) | 315  | `make -C humanlayer-wui check` |
| [rpi/commands/create_plan_nt.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/create_plan_nt.md#L402) | 402  | `humanlayer-wui/` directory    |

**Action**: Remove HumanLayer-specific directory references or generalize them.

---

### Category 4: `~/wt/humanlayer/` Worktree Paths (5 occurrences)

Worktree paths that reference humanlayer. These are **HumanLayer-specific development workflow** references.

| File                                                                                                                                                                                | Line | Reference                  |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | -------------------------- |
| [shared/commands/local_review.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/local_review.md#L26)       | 26   | `~/wt/humanlayer/`         |
| [shared/commands/local_review.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/local_review.md#L47)       | 47   | `~/wt/humanlayer/`         |
| [shared/commands/create_worktree.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/create_worktree.md#L27) | 27   | `~/wt/humanlayer/IWA-XXXX` |
| [shared/commands/create_worktree.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/create_worktree.md#L36) | 36   | `~/wt/humanlayer/IWA-XXXX` |
| [shared/commands/create_worktree.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/create_worktree.md#L41) | 41   | `~/wt/humanlayer/IWA-XXXX` |

**Action**: Remove these commands entirely as they're HumanLayer-specific workflow.

---

### Category 5: `humanlayer launch` Command (2 occurrences)

CLI commands to launch humanlayer sessions. These are **HumanLayer-specific**.

| File                                                                                                                                                                                | Line | Reference                        |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | -------------------------------- |
| [shared/commands/create_worktree.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/create_worktree.md#L36) | 36   | `humanlayer launch --model opus` |
| [shared/commands/create_worktree.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/create_worktree.md#L41) | 41   | `humanlayer launch --model opus` |

**Action**: Remove `humanlayer launch` commands entirely.

---

### Category 6: `~/.humanlayer/` Config/Log Paths (17 occurrences)

All in `rpi/commands/debug.md` - references to logs, database, and sockets. These are **HumanLayer-specific daemon infrastructure**.

| Line                                                                                                                                     | Reference                                             |
| ---------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| [41](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L41)   | `~/.humanlayer/logs/mcp-claude-approvals-*.log`       |
| [42](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L42)   | `~/.humanlayer/logs/wui-${BRANCH_NAME}/codelayer.log` |
| [46](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L46)   | `~/.humanlayer/daemon-{BRANCH_NAME}.db`               |
| [57](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L57)   | `~/.humanlayer/daemon.sock`                           |
| [82](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L82)   | `~/.humanlayer/logs/daemon-*.log`                     |
| [83](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L83)   | `~/.humanlayer/logs/wui-*.log`                        |
| [93](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L93)   | `~/.humanlayer/daemon.db`                             |
| [126](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L126) | `~/.humanlayer/logs/`                                 |
| [153](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L153) | `HUMANLAYER_DEBUG=true`                               |
| [177](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L177) | `~/.humanlayer/logs/daemon-*.log`                     |
| [178](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L178) | `~/.humanlayer/logs/wui-*.log`                        |
| [183](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L183) | `~/.humanlayer/daemon.db`                             |
| [184](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L184) | `~/.humanlayer/daemon.db`                             |
| [185](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/rpi/commands/debug.md#L185) | `~/.humanlayer/daemon.db`                             |

**Action**: The entire `debug.md` file is HumanLayer-specific and should likely be removed or completely rewritten for AssetWatch.

---

### Category 7: GitHub Remote Reference (1 occurrence)

| File                                                                                                                                                                          | Line | Reference                            |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | ------------------------------------ |
| [shared/commands/local_review.md](https://github.com/AssetWatch1/assetwatch-claude-plugins/blob/b3a534a955ba1835e43f85944657699768caed60/shared/commands/local_review.md#L24) | 24   | `git@github.com:USERNAME/humanlayer` |

**Action**: Update to AssetWatch repository reference.

---

## Files Requiring Changes

| File                                 | # of References | Categories              |
| ------------------------------------ | --------------- | ----------------------- |
| `rpi/commands/debug.md`              | **17**          | Config paths, env var   |
| `rpi/commands/create_plan.md`        | **5**           | thoughts sync, wui dir  |
| `rpi/commands/create_plan_nt.md`     | **3**           | wui dir                 |
| `rpi/commands/iterate_plan.md`       | **3**           | thoughts sync, wui dir  |
| `shared/commands/local_review.md`    | **5**           | paths, github, thoughts |
| `shared/commands/create_worktree.md` | **5**           | paths, launch cmd       |
| `shared/commands/describe_pr.md`     | **2**           | thoughts sync/setup     |
| `shared/commands/ci_describe_pr.md`  | **2**           | thoughts sync/setup     |
| `rpi/commands/research_codebase.md`  | **1**           | thoughts sync           |
| `rpi/commands/resume_handoff.md`     | **1**           | thoughts sync           |
| `rpi/commands/create_handoff.md`     | **1**           | thoughts sync           |

---

## Implementation Plan

The cleanup should be done in **4 phases** to maintain clean git history:

### Phase 1: Remove CLI Commands (Categories 1 & 2)

**Files affected**: 8 files

- Remove all `humanlayer thoughts sync` commands
- Remove `humanlayer thoughts` setup error messages
- Remove `humanlayer thoughts init` commands

### Phase 2: Remove Directory Structure References (Category 3)

**Files affected**: 3 files

- Remove/generalize `humanlayer-wui/` directory references
- Remove `make -C humanlayer-wui` commands

### Phase 3: Remove Launch/Testing References (Categories 4, 5 & 6)

**Files affected**: 3 files

- Remove `~/wt/humanlayer/` worktree paths
- Remove `humanlayer launch` commands
- Consider removing or rewriting `debug.md` entirely

### Phase 4: Update GitHub References (Category 7)

**Files affected**: 1 file

- Update GitHub remote reference to AssetWatch

---

## Open Questions

1. Should `debug.md` be removed entirely, or should it be rewritten for AssetWatch debugging needs?
2. Should `local_review.md` and `create_worktree.md` be removed, or adapted for AssetWatch workflow?
3. Are there AssetWatch-specific CLI tools that should replace the humanlayer commands?
