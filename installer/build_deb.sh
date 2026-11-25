#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-2.0.0}"
BUNDLE_DIR="build/linux/x64/release/bundle"
PKG_DIR="build/deb/torrent-seeder_${VERSION}_amd64"

rm -rf "$PKG_DIR"
mkdir -p \
  "$PKG_DIR/DEBIAN" \
  "$PKG_DIR/opt/torrent-seeder" \
  "$PKG_DIR/usr/bin" \
  "$PKG_DIR/usr/share/applications" \
  "$PKG_DIR/usr/share/icons/hicolor/256x256/apps"

cp -r "$BUNDLE_DIR"/* "$PKG_DIR/opt/torrent-seeder/"
chmod +x "$PKG_DIR/opt/torrent-seeder/safetorrent"

ln -s /opt/torrent-seeder/safetorrent "$PKG_DIR/usr/bin/torrent-seeder"

if [ -f "build/deb_icon_256.png" ]; then
  cp "build/deb_icon_256.png" "$PKG_DIR/usr/share/icons/hicolor/256x256/apps/torrent-seeder.png"
fi

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: torrent-seeder
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libblkid1, liblzma5
Maintainer: Torrent Seeder Contributors <noreply@github.com>
Description: Recherche de fichiers .torrent autonome avec bac a sable anti-virus et Seedr
 Torrent Seeder permet de rechercher des films et series TV (AlloCine, TVMaze,
 Wikidata), de suivre les dates de sortie des prochaines saisons, d'inspecter
 les fichiers .torrent dans un bac a sable et d'envoyer vers Seedr.
EOF

cat > "$PKG_DIR/usr/share/applications/torrent-seeder.desktop" <<EOF
[Desktop Entry]
Name=Torrent Seeder
Comment=Recherche de fichiers .torrent Films & Series avec bac a sable anti-virus et Seedr
Exec=/usr/bin/torrent-seeder
Icon=torrent-seeder
Terminal=false
Type=Application
Categories=Network;Utility;AudioVideo;
EOF

dpkg-deb --build --root-owner-group "$PKG_DIR" "TorrentSeeder-Linux-amd64.deb"
echo "Created TorrentSeeder-Linux-amd64.deb"
