# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]






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

