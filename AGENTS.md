# Project workflow

Use the github-workflow skill for Git changes. Branches use type/kebab-case names and commits use Conventional Commits. Preserve the user's Git identity. Never merge PRs or enable automatic merging; humans merge.

Scope: macOS first, Windows later. Preserve permissions, first-run wizard, microphone driver and button mapping. No statistics collection, transcript history, audio archives, remote telemetry, upstream private extensions or upstream branding.

Use GPL-3.0-only and preserve third-party copyright and license notices. Public binaries require their matching complete source, including bundled driver sources. Do not copy proprietary logos, photos, signing keys or service credentials.

Use swift build --disable-keychain and swift test --disable-keychain. Test meaningful behavior changes. Build success is not hardware acceptance. Public release needs separate authorization, signing and notarization. Use public integration APIs and user-visible accessibility interfaces; do not access another app's private data.
