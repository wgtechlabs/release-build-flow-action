# Agent Instructions

This file provides instructions for AI coding agents working on the **Release Build Flow Action** repository.

## Project Overview

A GitHub Action that automates release creation and changelog maintenance using the **Clean Commit** convention and **Keep a Changelog** format. It is a composite action written entirely in Bash scripts—no Node.js runtime, no compiled binaries.

### Key Technologies

- **GitHub Actions** composite action (`action.yml`)
- **Bash** scripts (`scripts/`)
- **Shell-based tests** (`tests/`)

### Repository Structure

```text
action.yml              # Action definition (inputs, outputs, steps)
scripts/                # Core logic (Bash)
  commit-changelog.sh   # Commit and push changelog changes
  create-release.sh     # Create GitHub Release via API
  create-tag.sh         # Create and push git tags
  detect-version-bump.sh # Determine version bump type
  detect-workspace.sh   # Monorepo workspace detection
  generate-changelog.sh # Generate Keep a Changelog entries
  generate-outputs.sh   # Set GitHub Actions outputs
  parse-commits.sh      # Parse and categorize commits
  sync-version-files.sh # Update version in manifest files
  validate-inputs.sh    # Validate action inputs
tests/                  # Shell-based test scripts
  test_emoji_prefix.sh
  test_release_name.sh
  test_setup_type.sh
  test_sync_version_files.sh
```

## Clean Commit Convention

This repository follows the **Clean Commit** workflow for all commit messages.

Reference: <https://github.com/wgtechlabs/clean-commit>

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

## Coding Guidelines

### Bash Scripts

- Start every script with `set -euo pipefail`
- Include a header comment block describing the script's purpose, expected environment variables, and outputs
- Use logging helper functions (`log_info`, `log_success`, `log_warning`, `log_debug`) for user-facing output directed to `>&2`
- Use colored output via ANSI escape codes for readability
- Quote all variables: `"$VAR"` not `$VAR`
- Prefer `[[ ]]` over `[ ]` for conditionals

### Testing

- Tests live in `tests/` as standalone Bash scripts
- Tests are run via `bash tests/test_*.sh` (no test framework)
- Each test script sources or extracts functions from the corresponding script in `scripts/`
- Run all tests locally before committing: `for f in tests/test_*.sh; do bash "$f"; done`
- Tests are also executed in CI via `.github/workflows/test.yml` on push to `main` and on PRs

### Action Inputs & Outputs

- All inputs are defined in `action.yml` under `inputs:` with descriptions and defaults
- All outputs are defined under `outputs:` and set via `scripts/generate-outputs.sh`
- When adding a new input, also update the README inputs table and any relevant script that consumes it
- When adding a new output, update `scripts/generate-outputs.sh`, the `outputs:` section in `action.yml`, and the README outputs table

### Pull Requests

- Branch names should be descriptive (e.g., `feat/add-x`, `fix/correct-y`, `docs/update-z`)
- PR titles should follow Clean Commit format without the emoji prefix
- Keep PRs focused—one logical change per PR
