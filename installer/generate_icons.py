"""Generate platform-native icons (Android mipmaps, Windows .ico, Linux PNG) from assets/icon/app_icon.png."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC_ICON = ROOT / "assets" / "icon" / "app_icon.png"


def generate_android() -> None:
    sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    res_dir = ROOT / "android" / "app" / "src" / "main" / "res"
    with Image.open(SRC_ICON).convert("RGBA") as img:
        for folder, px in sizes.items():
            out_dir = res_dir / folder
            out_dir.mkdir(parents=True, exist_ok=True)
            resized = img.resize((px, px), Image.Resampling.LANCZOS)
            resized.save(out_dir / "ic_launcher.png", format="PNG")
    print("Generated Android launcher icons.")


def generate_windows() -> None:
    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    targets = [
        ROOT / "windows" / "runner" / "resources" / "app_icon.ico",
        ROOT / "installer" / "app_icon.ico",
    ]
    with Image.open(SRC_ICON).convert("RGBA") as img:
        for target in targets:
            target.parent.mkdir(parents=True, exist_ok=True)
            img.save(target, format="ICO", sizes=ico_sizes)
    print("Generated Windows app & setup .ico icons.")


def generate_linux() -> None:
    target = ROOT / "build" / "deb_icon_256.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(SRC_ICON).convert("RGBA") as img:
        img.resize((256, 256), Image.Resampling.LANCZOS).save(target, format="PNG")
    print("Generated Linux 256x256 icon.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=["android", "windows", "linux"], required=True)
    args = parser.parse_args()

    if args.platform == "android":
        generate_android()
    elif args.platform == "windows":
        generate_windows()
    elif args.platform == "linux":
        generate_linux()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
