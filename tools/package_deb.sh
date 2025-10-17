#!/usr/bin/env bash
set -euo pipefail

# Simple Debian package builder for the Clash Flutter Linux desktop build
# Usage: ./tools/package_deb.sh [version]

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
OUT_DIR="$ROOT_DIR/build/deb"

PKG_NAME=clash
ARCH=amd64
VERSION="$1"

if [ -z "$VERSION" ]; then
  # Try git describe, fall back to date-based nightly
  if command -v git >/dev/null 2>&1 && [ -d "$ROOT_DIR/.git" ]; then
    VERSION=$(git describe --tags --always --dirty 2>/dev/null || true)
  fi
  if [ -z "$VERSION" ]; then
    VERSION="nightly-$(date -u +%Y%m%d%H%M)"
  fi
fi

echo "Packaging $PKG_NAME version $VERSION ($ARCH)..."

if [ ! -d "$BUILD_DIR" ]; then
  echo "Linux build not found at $BUILD_DIR. Building..."
  (cd "$ROOT_DIR" && flutter build linux --release)
fi

PACKAGE_DIR="$OUT_DIR/${PKG_NAME}_${VERSION}_${ARCH}"
DEBIAN_DIR="$PACKAGE_DIR/DEBIAN"
OPT_DIR="$PACKAGE_DIR/opt/$PKG_NAME"
USR_BIN_DIR="$PACKAGE_DIR/usr/bin"
DESKTOP_DIR="$PACKAGE_DIR/usr/share/applications"
ICON_DIR="$PACKAGE_DIR/usr/share/icons/hicolor/512x512/apps"

rm -rf "$PACKAGE_DIR"
mkdir -p "$DEBIAN_DIR" "$OPT_DIR" "$USR_BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"

# Copy bundle contents into /opt/<pkg>
cp -r "$BUILD_DIR/"* "$OPT_DIR/"

# Make a small wrapper in /usr/bin
EXEC_NAME="$PKG_NAME"
if [ -f "$OPT_DIR/$PKG_NAME" ]; then
  EXEC_NAME="$PKG_NAME"
else
  # detect first executable file
  exec_file=$(find "$OPT_DIR" -maxdepth 1 -type f -perm /111 | head -n1 || true)
  if [ -n "$exec_file" ]; then
    EXEC_NAME=$(basename "$exec_file")
  fi
fi

cat > "$USR_BIN_DIR/$PKG_NAME" <<EOF
#!/usr/bin/env bash
exec "/opt/$PKG_NAME/$EXEC_NAME" "\$@"
EOF
chmod 0755 "$USR_BIN_DIR/$PKG_NAME"

# Desktop entry
cat > "$DESKTOP_DIR/$PKG_NAME.desktop" <<EOF
[Desktop Entry]
Name=Clash
Exec=/usr/bin/$PKG_NAME %u
Icon=$PKG_NAME
Type=Application
Categories=Network;Utility;
Terminal=false
EOF

# Icon (optional) - try to find a png in repository
ICON_SRC=""
for candidate in "$ROOT_DIR/icon.png" "$ROOT_DIR/assets/icon.png" "$ROOT_DIR/web/icon.png"; do
  if [ -f "$candidate" ]; then
    ICON_SRC="$candidate"
    break
  fi
done
if [ -n "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$ICON_DIR/$PKG_NAME.png"
fi

# Control file
DEPS="libc6 (>= 2.29), libstdc++6, libgtk-3-0, libasound2"
cat > "$DEBIAN_DIR/control" <<EOF
Package: $PKG_NAME
Version: $VERSION
Section: net
Priority: optional
Architecture: $ARCH
Depends: $DEPS
Maintainer: Clash Packager <noreply@example.com>
Description: Clash - local proxy and GUI frontend
 A desktop proxy client built with Flutter. Provides SOCKS5 and HTTP proxying and UI controls.
EOF

# Basic postinst to set permissions (optional)
cat > "$DEBIAN_DIR/postinst" <<'EOF'
#!/bin/sh
set -e
chmod 755 /usr/bin/clash
EOF
chmod 0755 "$DEBIAN_DIR/postinst"

# Set correct permissions for DEBIAN directory and files
chmod 0755 "$DEBIAN_DIR"
chmod 0644 "$DEBIAN_DIR/control"

mkdir -p "$OUT_DIR"
DEB_OUTPUT="$OUT_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb --build "$PACKAGE_DIR" "$DEB_OUTPUT"

echo "Created $DEB_OUTPUT"
