#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-2.1.1}"
BUNDLE_DIR="build/linux/x64/release/bundle"
PKG_DIR="build/deb/torrent-seeder_${VERSION}_amd64"

rm -rf "$PKG_DIR"
mkdir -p \
  "$PKG_DIR/DEBIAN" \
  "$PKG_DIR/opt/torrent-seeder" \
  "$PKG_DIR/usr/bin" \
  "$PKG_DIR/usr/share/applications" \
  "$PKG_DIR/usr/share/pixmaps" \
  "$PKG_DIR/usr/share/icons/hicolor/48x48/apps" \
  "$PKG_DIR/usr/share/icons/hicolor/128x128/apps" \
  "$PKG_DIR/usr/share/icons/hicolor/256x256/apps" \
  "$PKG_DIR/usr/share/icons/hicolor/512x512/apps"

cp -r "$BUNDLE_DIR"/* "$PKG_DIR/opt/torrent-seeder/"
chmod +x "$PKG_DIR/opt/torrent-seeder/safetorrent"

ln -s /opt/torrent-seeder/safetorrent "$PKG_DIR/usr/bin/torrent-seeder"

for sz in 48 128 256 512; do
  if [ -f "build/linux_icons/icon_${sz}.png" ]; then
    cp "build/linux_icons/icon_${sz}.png" "$PKG_DIR/usr/share/icons/hicolor/${sz}x${sz}/apps/torrent-seeder.png"
  fi
done
if [ -f "build/deb_icon_256.png" ]; then
  cp "build/deb_icon_256.png" "$PKG_DIR/usr/share/pixmaps/torrent-seeder.png"
fi

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: torrent-seeder
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libblkid1, liblzma5
Maintainer: Torrent Seeder Contributors <noreply@github.com>
Description: Standalone Movie & TV Series torrent search engine with anti-malware sandbox & Seedr
 Torrent Seeder searches Movies and TV Series (AlloCine, TVMaze, Wikidata),
 inspects and sanitizes .torrent files in an isolated sandbox, and integrates
 with one or more Seedr.cc accounts.
EOF

cat > "$PKG_DIR/usr/share/applications/torrent-seeder.desktop" <<EOF
[Desktop Entry]
Name=Torrent Seeder
Comment=Standalone Movie & TV Series Torrent Search with Anti-Malware Sandbox & Seedr
Exec=/usr/bin/torrent-seeder
Icon=torrent-seeder
StartupWMClass=safetorrent
Terminal=false
Type=Application
Categories=Network;Utility;AudioVideo;
EOF

dpkg-deb --build --root-owner-group "$PKG_DIR" "TorrentSeeder-Linux-amd64.deb"
echo "Created TorrentSeeder-Linux-amd64.deb"
