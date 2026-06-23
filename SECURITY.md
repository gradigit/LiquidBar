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

## Permission Model

LiquidBar asks for powerful macOS permissions only for features that need them:

- Accessibility: focusing, hiding, minimizing, closing, and resizing windows.
- Screen Recording: capturing static window thumbnails for previews and the
  keyboard switcher.
- Input Monitoring: intercepting Cmd-Tab style shortcuts before macOS handles
  them.
- Automation: optional provider or media-control actions that need to control
  another app.

Update checks are network calls to the canonical GitHub release namespace.
Launch at Login and Dock auto-hide are user-visible system settings, not TCC
privacy permissions.

The code is open source so users can audit the permission-sensitive paths,
build the app themselves, and disable features they do not want in
`config.json`. Do not add opaque network services or background capture loops
without documenting the data flow and adding tests.

## Release Trust Model

Official update metadata must come from the project-owned
`gradigit/LiquidBar` GitHub repository. The app should only present or open
release URLs under `https://github.com/gradigit/LiquidBar/releases/tag/...`.

Release builds should be signed and notarized before distribution. GitHub
Actions used for CI or release automation should be pinned to reviewed commit
SHAs, and any workflow that publishes artifacts should document who can approve
or trigger that release path.

Do not publish `LiquidBar Test.app` or any bundle using the
`com.liquidbar.test` identifier as an official artifact.
