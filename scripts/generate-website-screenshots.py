#!/usr/bin/env python3
"""Generate optimized screenshots for the Voice Input Buddy website."""
import os
from pathlib import Path
import subprocess
import tempfile
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
APP_PATH = ROOT / "dist/Voice Input Buddy.app/Contents/MacOS/VoiceInputBuddy"
OUTPUT_DIR = ROOT / "pages/assets/screenshots"

SECTIONS = [
    ("mapping", "mapping-1020x772.png", "mapping"),
    ("connection", "connection-1020x772.png", "connection"),
    ("integration", "integration-1020x772.png", "integration"),
    ("commonPhrases", "commonPhrases-1020x772.png", "phrases"),
    ("permissions", "permissions-1020x772.png", "permissions"),
]

def ensure_binary() -> Path:
    if not APP_PATH.exists():
        print("Debug app bundle not found; building with CONFIGURATION=debug...")
        env = os.environ.copy()
        env["CONFIGURATION"] = "debug"
        subprocess.run(["scripts/build-app.sh"], cwd=ROOT, env=env, check=True)
    return APP_PATH

def render_screenshots(bin_path: Path, language: str, output_tmp: Path):
    env = os.environ.copy()
    env["VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_DIR"] = str(output_tmp)
    env["VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_REMOTE_CARDS"] = "1"
    env["VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_LANGUAGE"] = language
    env["VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_APPEARANCE"] = "light"
    subprocess.run([str(bin_path)], cwd=ROOT, env=env, check=True)

def optimize_png(src: Path, dst: Path):
    with Image.open(src) as img:
        img.save(dst, format="PNG", optimize=True)

def main():
    bin_path = ensure_binary()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    for lang_code, lang_suffix in [("zh-Hans", "zh"), ("en", "en")]:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            print(f"Rendering {lang_code} screenshots...")
            render_screenshots(bin_path, lang_code, tmp_path)

            for section_id, raw_filename, target_id in SECTIONS:
                source_file = tmp_path / raw_filename
                if not source_file.exists():
                    raise FileNotFoundError(f"Missing screenshot: {source_file}")
                target_file = OUTPUT_DIR / f"{target_id}-{lang_suffix}.png"
                print(f"Optimizing {target_file.name}...")
                optimize_png(source_file, target_file)

    print("Screenshots generation complete!")

if __name__ == "__main__":
    main()
