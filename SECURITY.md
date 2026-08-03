# Security Policy

## Supported Versions

Security fixes are applied to the latest stable release line.

## Reporting a Vulnerability

Please do not open public issues for security vulnerabilities.

Use one of the following:
- [GitHub private vulnerability reporting](https://github.com/jakhongir97/PlayerKit/security/advisories/new) (preferred)

Include:
- Affected version(s)
- Reproduction steps
- Impact assessment
- Suggested mitigation (if available)

Custom player backends must treat `PlayerKitError` associated strings as private
diagnostics and must not include credentials, signed URLs, or tokens. Host UI
should use `PlayerKitError.userFacingDescription`, which does not echo those
payloads.

If private vulnerability reporting is unavailable, open a public issue containing
only a request for a private contact channel—do not include exploit details.

We will acknowledge reports promptly and coordinate responsible disclosure before public release.
