#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.0.0}"
BUNDLE_DIR="build/linux/x64/release/bundle"
PKG_DIR="build/deb/safetorrent_${VERSION}_amd64"

rm -rf "$PKG_DIR"
mkdir -p \
  "$PKG_DIR/DEBIAN" \
  "$PKG_DIR/opt/safetorrent" \
  "$PKG_DIR/usr/bin" \
  "$PKG_DIR/usr/share/applications"

cp -r "$BUNDLE_DIR"/* "$PKG_DIR/opt/safetorrent/"
chmod +x "$PKG_DIR/opt/safetorrent/safetorrent"

ln -s /opt/safetorrent/safetorrent "$PKG_DIR/usr/bin/safetorrent"

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: safetorrent
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libblkid1, liblzma5
Maintainer: SafeTorrent Contributors <noreply@github.com>
Description: Recherche de fichiers .torrent autonome avec bac a sable anti-virus
 SafeTorrent permet de rechercher des films (avec titre anglais via AlloCine,
 choix de la langue FR/EN/ES, qualite, taille, seeders/leechers) et d'inspecter
 puis assainir les fichiers .torrent dans un bac a sable avant telechargement.
EOF

cat > "$PKG_DIR/usr/share/applications/safetorrent.desktop" <<EOF
[Desktop Entry]
Name=SafeTorrent
Comment=Recherche de fichiers .torrent avec bac a sable anti-virus
Exec=/usr/bin/safetorrent
Terminal=false
Type=Application
Categories=Network;Utility;AudioVideo;
EOF

dpkg-deb --build --root-owner-group "$PKG_DIR" "SafeTorrent-Linux-amd64.deb"
echo "Created SafeTorrent-Linux-amd64.deb"
