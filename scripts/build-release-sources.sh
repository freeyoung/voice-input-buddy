#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
: "${RELEASE_TAG:?Run release-metadata.sh first}"
work="$(mktemp -d "$root/.build/release-sources.XXXXXX")"
trap 'rm -rf "$work"' EXIT
source_root="$work/Voice_Input_Buddy_$RELEASE_TAG"
mkdir -p "$source_root/vendor" "$root/dist/release"
# Use exactly the release commit, not unrelated local files.
git archive HEAD | tar -x -C "$source_root"
for dependency in BlackHole Sparkle; do
    if [[ "$dependency" == BlackHole ]]; then
        dependency_path="$root/.build/buddy-driver/BlackHole"
    else
        dependency_path="$root/.build/app-x86_64/checkouts/Sparkle"
    fi
    test -d "$dependency_path/.git"
    git -C "$dependency_path" rev-parse HEAD > "$source_root/vendor/$dependency.revision"
    mkdir -p "$source_root/vendor/$dependency"
    # Include the actual patched driver source and full dependency license files.
    tar --exclude=.git -cf - -C "$dependency_path" . | tar -xf - -C "$source_root/vendor/$dependency"
done
tar -czf "$root/dist/release/Voice_Input_Buddy_${RELEASE_TAG}_sources.tar.gz" -C "$work" "Voice_Input_Buddy_$RELEASE_TAG"
