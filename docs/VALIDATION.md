# Validation status — 17 November 2026

This is prepared source for the initial iPhone port, not a verified installable build yet.

Passed locally:

- Frame conversion and audio-buffer regression executable, with AddressSanitizer and UndefinedBehaviorSanitizer. LeakSanitizer is unavailable under this workspace's process tracing, so its check was disabled.
- Python build-script syntax checks.
- YAML parsing for the XcodeGen specification and GitHub Actions workflow.
- Privacy manifest plist parsing and git whitespace checks.

Blocked:

- Publishing to GitHub: the connected GitHub integration returned HTTP 403 `Resource not accessible by integration` for repository writes. Command-line GitHub authentication is not configured either. The remote main branch still contains only the original README.
- Xcode compilation, Swift model regression tests, iOS core compilation and full bundle/signature checks must run on the prepared GitHub Mac workflow after upload. The current workspace is Linux and has no Xcode or Swift compiler.
- Physical iPhone gameplay and save/restore testing must follow installation. No claim is made that the app or each emulator core has passed that testing.

Do not treat the unsigned source or a frontend-only compile as a ready TestFlight build. The complete bundle job must pass with all five native core frameworks, and the signing job must succeed.
