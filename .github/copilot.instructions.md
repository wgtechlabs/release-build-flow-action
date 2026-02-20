---
applyTo: "**"
---

# Release Build Flow Action — Copilot Instructions

A GitHub Action (composite, Bash-only) that automates release creation and changelog maintenance using **Clean Commit** convention and **Keep a Changelog** format.

For full agent instructions, coding guidelines, and project structure, see [AGENTS.md](../AGENTS.md).
For contributor guidelines (including development workflow and testing), see [CONTRIBUTING.md](../CONTRIBUTING.md).

## Clean Commit Convention

This repository follows the **Clean Commit** workflow for all commit messages.

Reference: https://github.com/wgtechlabs/clean-commit

### Format

```text
<emoji> <type>: <description>
<emoji> <type> (<scope>): <description>
```

### The 9 Types

| Emoji | Type       | What it covers                                    |
|:-----:|------------|---------------------------------------------------|
| 📦    | `new`      | Adding new features, files, or capabilities       |
| 🔧    | `update`   | Changing existing code, refactoring, improvements |
| 🗑️    | `remove`   | Removing code, files, features, or dependencies   |
| 🔒    | `security` | Security fixes, patches, vulnerability resolutions|
| ⚙️    | `setup`    | Project configs, CI/CD, tooling, build systems    |
| ☕    | `chore`    | Maintenance tasks, dependency updates, housekeeping|
| 🧪    | `test`     | Adding, updating, or fixing tests                 |
| 📖    | `docs`     | Documentation changes and updates                 |
| 🚀    | `release`  | Version releases and release preparation          |

### Rules

- Use lowercase for type
- Use present tense ("add" not "added")
- No period at the end
- Keep description under 72 characters

### Examples

- `📦 new: user authentication system`
- `🔧 update (api): improve error handling`
- `🗑️ remove (deps): unused lodash dependency`
- `🔒 security: patch XSS vulnerability`
- `⚙️ setup: add eslint configuration`
- `☕ chore: update npm dependencies`
- `🧪 test: add unit tests for auth service`
- `📖 docs: update installation instructions`
- `🚀 release: version 1.0.0`

## Key Coding Rules

- Bash scripts: start with `set -euo pipefail`, use `log_info`/`log_success`/`log_warning`/`log_debug` helpers, quote all variables, prefer `[[ ]]`
- Tests: standalone Bash scripts in `tests/`, run via `bash tests/test_*.sh`
- New inputs: update `action.yml`, the consuming script, and the README inputs table
- New outputs: update `scripts/generate-outputs.sh`, `action.yml` outputs, and the README outputs table
- PR titles: Clean Commit format without the emoji prefix
