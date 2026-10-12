#!/bin/bash
# Shared by Installer and the standalone uninstaller. Only fixed product paths.
buddy_check_bundle() {
    local path="$1" expected="$2"
    [[ -e "$path" || -L "$path" ]] || return 0
    [[ -d "$path" && ! -L "$path" ]] || { echo "Refusing unexpected bundle: $path" >&2; return 1; }
    local actual
    actual="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$path/Contents/Info.plist" 2>/dev/null)" || return 1
    [[ "$actual" == "$expected" ]] || { echo "Refusing unrelated bundle: $path" >&2; return 1; }
}
buddy_remove_bundle() {
    buddy_check_bundle "$1" "$2" || return 1
    [[ -e "$1" ]] || return 0
    /bin/rm -rf -- "$1"
}
buddy_cleanup_user_data() {
    local user_home="$1"
    for path in \
        "$user_home/Library/Preferences/com.zfdang.voice-input-buddy.plist" \
        "$user_home/Library/Application Support/VoiceInputBuddy" \
        "$user_home/Library/Logs/VoiceInputBuddy" \
        "$user_home/Library/Caches/com.zfdang.voice-input-buddy" \
        "$user_home/Library/Saved Application State/com.zfdang.voice-input-buddy.savedState"; do
        /bin/rm -rf -- "$path"
    done
}
