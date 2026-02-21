# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]















## [1.4.3] - 2026-02-21

### Changed

- use shared temp file for WORKSPACE_PACKAGES in monorepo mode (#24)

## [1.4.2] - 2026-02-20

### Changed

- fix monorepo mode crash with "Cannot index string with string path"
- optimize JSON handling for commit parsing and routing
- improve JSON handling in package information collection
- validate WORKSPACE_PACKAGES format in version detection script
- validate WORKSPACE_PACKAGES format in commit changelog script

## [1.4.1] - 2026-02-20

### Fixed

- fix monorepo mode crash with "Cannot index string with string path" in jq 1.6+ (#21)

## [1.4.0] - 2026-02-20

### Added

- add version detection from manifest files for version bumping

## [1.3.0] - 2026-02-20

### Added

- add script to run all tests with summary output

### Changed

- stage only modified per-package manifest files in monorepo mode
- optimize package data extraction in sync_monorepo_packages
- add monorepo support for version syncing in manifest files
- stage per-package manifest files in monorepo mode
- add support for monorepo and unified version inputs
- enable automatic version sync in manifest files

### Removed

- delete CLAUDE.md file

## [1.2.2] - 2026-02-20

### Changed

- fix local used outside function in detect-version-bump.sh line 410 (#19)
- add funding file
- add contributing file
- add clean commit convention in this project

## [1.2.1] - 2026-02-20

### Changed

- change default git user name and email for commits

## [1.2.0] - 2026-02-20

### Added

- auto-sync version to manifest files on release (#15)

## [1.1.4] - 2026-02-20

### Changed

- refine default release name template handling

## [1.1.3] - 2026-02-20

### Changed

- refine release name generation to avoid bash brace parsing issues

## [1.1.2] - 2026-02-20

### Changed

- replace sed with bash string replacement for release name generation

## [1.1.1] - 2026-02-20

### Changed

- refine exclude types based on commit convention
- refine version bump keywords for conventional commits
- enhance commit type mapping and exclusion configurations
- enhance release name generation for reliable placeholder replacement

## [1.1.0] - 2026-02-20

### Added

- add commit convention input for auto-generated commits

### Changed

- implement commit message formatting based on convention
- enhance tag message formatting based on commit convention
- update copyright holder name in LICENSE file
- modify release name template to support {tag} placeholder (#13)
- modify release name template to support {tag} placeholder (#12)
- optimize subject cleaning in commit parsing to handle emojis
- modify release name template to support {tag} placeholder
- modify release name template to support {tag} placeholder
- modify release name template to support {tag} placeholder

## [1.0.1] - 2026-02-19

### Removed

- delete CHANGELOG.md file

### Fixed

- compact `commits-json` output with `jq -c` in `parse-commits.sh` (#11)

