# Project workflow

Use the github-workflow skill for Git changes. Branches use type/kebab-case names and commits use Conventional Commits. Preserve the user's Git identity. Never merge PRs or enable automatic merging; humans merge.

Development stage: assume no legacy users or data. Remove obsolete logic instead of adding compatibility migrations or legacy cleanup flags.

This is a product assumption: do not retain retired API stubs just in case. Preserve active behavior such as audio routing, onboarding validation and completed-update detection.

Scope: macOS first, Windows later. Preserve permissions, first-run wizard, microphone driver and button mapping. No statistics collection, transcript history, audio archives, remote telemetry, upstream private extensions or upstream branding.

Use GPL-3.0-only and preserve third-party copyright and license notices. Public binaries require their matching complete source, including bundled driver sources. Do not copy proprietary logos, photos, signing keys or service credentials.

Use swift build --disable-keychain and swift test --disable-keychain. Test meaningful behavior changes. Build success is not hardware acceptance. Pushes to main are authorized to publish public Releases automatically through the release workflow. Keep this behavior. Updates require this project's Sparkle signature; production app and driver builds use the fixed self-signed release certificate from GitHub Secrets, while local/PR builds default to ad-hoc signing. Do not add certificate trust settings. The installer remains unsigned because no Apple Developer ID is available; document that releases are not notarized. Use public integration APIs and user-visible accessibility interfaces; do not access another app's private data.
