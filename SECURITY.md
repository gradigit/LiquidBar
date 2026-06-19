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
