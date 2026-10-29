"""Package a verified app with an Applications shortcut, without automating Finder."""

import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

import dmgbuild


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    app = Path(sys.argv[1]).resolve()
    destination = Path(sys.argv[2]).resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if app.name != "Paper Library.app" or info.get("CFBundleIdentifier") != "com.hoonably.PaperLibrary":
        raise SystemExit("A packaged Paper Library.app is required.")
    version = info["CFBundleShortVersionString"]
    if not all(part.isdigit() for part in version.split(".")):
        raise SystemExit("The app version must contain numeric components.")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    architectures = subprocess.check_output(
        ["lipo", "-archs", str(app / "Contents/MacOS/PaperLibrary")], text=True
    ).split()
    architecture = "universal" if set(architectures) == {"arm64", "x86_64"} else "-".join(architectures)
    if architecture not in {"arm64", "x86_64", "universal"}:
        raise SystemExit("Unsupported app architecture.")
    destination.mkdir(parents=True, exist_ok=True)
    output = destination / f"Paper-Library-v{version}-macos-{architecture}.dmg"
    with tempfile.TemporaryDirectory(prefix=".paper-library-dmg-", dir=destination) as staging:
        temporary = Path(staging)
        background = temporary / "background.tiff"
        subprocess.run(["xcrun", "swift", str(root / "scripts/build-dmg-background.swift"), str(background)], check=True)
        image = temporary / output.name
        dmgbuild.build_dmg(str(image), "Paper Library", settings={
            "format": "UDZO",
            "filesystem": "HFS+",
            "files": [str(app)],
            "symlinks": {"Applications": "/Applications"},
            "icon": str(app / "Contents/Resources/AppIcon.icns"),
            "background": str(background),
            "window_rect": ((240, 200), (640, 420)),
            "default_view": "icon-view",
            "include_icon_view_settings": True,
            "include_list_view_settings": False,
            "icon_locations": {"Paper Library.app": (180, 218), "Applications": (460, 218)},
            "icon_size": 112,
            "text_size": 14,
            "grid_spacing": 90,
            "show_icon_preview": True,
        }, lookForHiDPI=False)
        subprocess.run(["hdiutil", "verify", str(image)], check=True)
        mount = temporary / "mounted"
        mount.mkdir()
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                        "-mountpoint", str(mount), str(image)], check=True, stdout=subprocess.DEVNULL)
        try:
            shortcut = mount / "Applications"
            if not shortcut.is_symlink() or os.readlink(shortcut) != "/Applications":
                raise RuntimeError("The Applications shortcut is invalid.")
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(mount / app.name)], check=True)
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
        os.replace(image, output)
    print(f"Created and verified installer {output}")


if __name__ == "__main__":
    main()
