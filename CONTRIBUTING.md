# Contributing to PlayerKit

Thank you for contributing.

## Ground Rules

- Keep changes scoped and focused.
- Preserve public API compatibility unless the change is intentionally breaking.
- Update documentation for behavior or API changes.
- Add or update tests where applicable.

## Local Validation

Run the same core checks used for release readiness:

```bash
swift package describe
./scripts/verify_binary_targets.sh
./scripts/verify_third_party_notices.sh
xcodebuild -scheme PlayerKit -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme PlayerKit -destination 'generic/platform=iOS' build
./scripts/run_unit_tests.sh
```

## Pull Requests

- Use clear titles and describe user-facing impact.
- Include notes for API changes, migration, and release impact.
- Ensure CI is green before merge.

## Versioning

This project follows Semantic Versioning:
- Major: breaking public API changes
- Minor: backward-compatible features
- Patch: backward-compatible fixes

## Licensing

By contributing, you agree that your contributions are licensed under the MIT License used by this repository.
