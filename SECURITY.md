# Security Policy

## Supported Version

Security fixes target the current `main` branch.

## Reporting

If you find a vulnerability, use GitHub private vulnerability reporting when it
is enabled for the repository. If that is not available, open a minimal issue
that states there is a security concern without publishing exploit details.

## Project Boundaries

LiquidBar uses macOS Accessibility, Core Graphics, AppKit, and
ScreenCaptureKit capabilities. Changes that expand permissions, add new
interprocess communication, or capture additional window data should include
tests and documentation describing why the permission is needed.

## Release Trust Model

Official update metadata must come from the project-owned
`gradigit/LiquidBar` GitHub repository. The app should only present or open
release URLs under `https://github.com/gradigit/LiquidBar/releases/tag/...`.

Release builds should be signed and notarized before distribution. GitHub
Actions used for CI or release automation should be pinned to reviewed commit
SHAs, and any workflow that publishes artifacts should document who can approve
or trigger that release path.
