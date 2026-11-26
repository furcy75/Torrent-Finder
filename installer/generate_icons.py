"""Generate high-visibility native icons for Android (including Adaptive Icons),
Windows (multi-size squircle .ico + title patch), and Linux (multi-size PNGs + GTK icon/title patch)
from assets/icon/app_icon.png.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC_ICON = ROOT / "assets" / "icon" / "app_icon.png"


def _zoom_shield(img: Image.Image, crop_fraction: float = 0.12) -> Image.Image:
    """Trim dark outer margin so the bright shield emblem fills the icon prominently."""
    w, h = img.size
    dx = int(w * crop_fraction)
    dy = int(h * crop_fraction)
    return img.crop((dx, dy, w - dx, h - dy))


def _make_squircle_icon(img: Image.Image, px: int) -> Image.Image:
    """Create a crisp rounded-square icon with a subtle luminous border that pops
    on both dark and light taskbars/desktops."""
    zoomed = _zoom_shield(img, crop_fraction=0.13).resize((px, px), Image.Resampling.LANCZOS)
    mask = Image.new("L", (px, px), 0)
    draw = ImageDraw.Draw(mask)
    radius = max(2, int(px * 0.22))
    draw.rounded_rectangle((0, 0, px - 1, px - 1), radius=radius, fill=255)

    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    out.paste(zoomed, (0, 0), mask)

    if px >= 32:
        border_layer = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        bdraw = ImageDraw.Draw(border_layer)
        bw = max(1, px // 48)
        bdraw.rounded_rectangle(
            (bw, bw, px - 1 - bw, px - 1 - bw),
            radius=max(2, radius - bw),
            outline=(56, 189, 248, 175),
            width=bw,
        )
        out = Image.alpha_composite(out, border_layer)
    return out


def _make_round_icon(img: Image.Image, px: int) -> Image.Image:
    zoomed = _zoom_shield(img, crop_fraction=0.13).resize((px, px), Image.Resampling.LANCZOS)
    mask = Image.new("L", (px, px), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, px - 1, px - 1), fill=255)
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    out.paste(zoomed, (0, 0), mask)
    return out


def _make_adaptive_foreground(img: Image.Image, px: int) -> Image.Image:
    """Android adaptive icon foreground (108dp canvas, safe zone inner 66dp).
    Uses a slightly padded zoomed shield on transparent canvas over the solid navy background."""
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    inner_px = int(px * 0.72)
    shield = _zoom_shield(img, crop_fraction=0.14).resize(
        (inner_px, inner_px), Image.Resampling.LANCZOS
    )
    # Soft circular mask inside adaptive foreground so background blends seamlessly
    mask = Image.new("L", (inner_px, inner_px), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, inner_px - 1, inner_px - 1), fill=255)
    offset = (px - inner_px) // 2
    canvas.paste(shield, (offset, offset), mask)
    return canvas


def generate_android() -> None:
    legacy_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    fg_sizes = {
        "drawable-mdpi": 108,
        "drawable-hdpi": 162,
        "drawable-xhdpi": 216,
        "drawable-xxhdpi": 324,
        "drawable-xxxhdpi": 432,
    }
    res_dir = ROOT / "android" / "app" / "src" / "main" / "res"
    with Image.open(SRC_ICON).convert("RGBA") as img:
        for folder, px in legacy_sizes.items():
            out_dir = res_dir / folder
            out_dir.mkdir(parents=True, exist_ok=True)
            _make_squircle_icon(img, px).save(out_dir / "ic_launcher.png", format="PNG")
            _make_round_icon(img, px).save(out_dir / "ic_launcher_round.png", format="PNG")

        for folder, px in fg_sizes.items():
            out_dir = res_dir / folder
            out_dir.mkdir(parents=True, exist_ok=True)
            _make_adaptive_foreground(img, px).save(
                out_dir / "ic_launcher_foreground.png", format="PNG"
            )

    # Adaptive icon background color & XML descriptors (Android 8+)
    values_dir = res_dir / "values"
    values_dir.mkdir(parents=True, exist_ok=True)
    (values_dir / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="ic_launcher_background">#0B1730</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )

    anydpi_dir = res_dir / "mipmap-anydpi-v26"
    anydpi_dir.mkdir(parents=True, exist_ok=True)
    adaptive_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n"
    )
    (anydpi_dir / "ic_launcher.xml").write_text(adaptive_xml, encoding="utf-8")
    (anydpi_dir / "ic_launcher_round.xml").write_text(adaptive_xml, encoding="utf-8")

    # Patch AndroidManifest to set label + roundIcon
    manifest = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if manifest.exists():
        text = manifest.read_text(encoding="utf-8")
        if "android.permission.INTERNET" not in text:
            text = text.replace(
                "<application",
                '    <uses-permission android:name="android.permission.INTERNET" />\n    <application',
                1,
            )
        text = text.replace('android:label="safetorrent"', 'android:label="Torrent Seeder"')
        if "android:roundIcon" not in text:
            text = text.replace(
                'android:icon="@mipmap/ic_launcher"',
                'android:icon="@mipmap/ic_launcher"\n        android:roundIcon="@mipmap/ic_launcher_round"',
                1,
            )
        manifest.write_text(text, encoding="utf-8")

    print("Generated high-visibility Android adaptive & legacy launcher icons.")


def generate_windows() -> None:
    ico_sizes = [256, 128, 64, 48, 32, 24, 16]
    targets = [
        ROOT / "windows" / "runner" / "resources" / "app_icon.ico",
        ROOT / "installer" / "app_icon.ico",
    ]
    with Image.open(SRC_ICON).convert("RGBA") as img:
        base_256 = _make_squircle_icon(img, 256)
        extras = [_make_squircle_icon(img, s) for s in ico_sizes[1:]]
        for target in targets:
            target.parent.mkdir(parents=True, exist_ok=True)
            base_256.save(
                target,
                format="ICO",
                append_images=extras,
                sizes=[(s, s) for s in ico_sizes],
            )

    # Patch Windows window title from "safetorrent" to "Torrent Seeder"
    main_cpp = ROOT / "windows" / "runner" / "main.cpp"
    if main_cpp.exists():
        txt = main_cpp.read_text(encoding="utf-8")
        txt = txt.replace('L"safetorrent"', 'L"Torrent Seeder"')
        main_cpp.write_text(txt, encoding="utf-8")

    print("Generated high-visibility Windows app & setup .ico icons.")


def generate_linux() -> None:
    linux_sizes = [48, 128, 256, 512]
    out_root = ROOT / "build" / "linux_icons"
    out_root.mkdir(parents=True, exist_ok=True)
    with Image.open(SRC_ICON).convert("RGBA") as img:
        for px in linux_sizes:
            _make_squircle_icon(img, px).save(out_root / f"icon_{px}.png", format="PNG")
        _make_squircle_icon(img, 256).save(ROOT / "build" / "deb_icon_256.png", format="PNG")

    # Patch Linux GTK window title & default window icon
    my_app_cc = ROOT / "linux" / "my_application.cc"
    if my_app_cc.exists():
        txt = my_app_cc.read_text(encoding="utf-8")
        txt = txt.replace('"safetorrent"', '"Torrent Seeder"')
        if "gtk_window_set_default_icon_name" not in txt:
            txt = txt.replace(
                "gtk_window_set_title(window, \"Torrent Seeder\");",
                'gtk_window_set_title(window, "Torrent Seeder");\n'
                '  gtk_window_set_default_icon_name("torrent-seeder");',
                1,
            )
        my_app_cc.write_text(txt, encoding="utf-8")

    print("Generated high-visibility Linux PNG icons (48..512px) and patched GTK metadata.")


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
