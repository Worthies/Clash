#!/usr/bin/env bash
set -exuo pipefail

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
echo "Using build dir: $BUILD_DIR"
if [ -d "$BUILD_DIR" ]; then
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$BUILD_DIR/" "$OPT_DIR/"
  else
    cp -r "$BUILD_DIR/"* "$OPT_DIR/"
  fi
else
  echo "WARNING: build dir $BUILD_DIR not found; package may be incomplete"
fi

# Embed version/commit information into the packaged files so installed .deb can be verified
GIT_COMMIT=""
if command -v git >/dev/null 2>&1 && [ -d "$ROOT_DIR/.git" ]; then
  GIT_COMMIT=$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || true)
fi
echo "Package version: $VERSION commit: $GIT_COMMIT"
mkdir -p "$OPT_DIR"
echo "VERSION=$VERSION" > "$OPT_DIR/VERSION"
if [ -n "$GIT_COMMIT" ]; then
  echo "GIT_COMMIT=$GIT_COMMIT" >> "$OPT_DIR/VERSION"
fi
echo "Packaged files snapshot:" > "$OPT_DIR/PKG_FILES"
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$OPT_DIR" && find . -type f -print0 | xargs -0 sha256sum) >> "$OPT_DIR/PKG_FILES" || true
else
  (cd "$OPT_DIR" && find . -type f -print) >> "$OPT_DIR/PKG_FILES" || true
fi

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

cat > "$USR_BIN_DIR/$PKG_NAME" <<'WRAPPER_EOF'
#!/usr/bin/env bash
# If running in KDE/Plasma, some appindicator implementations behave better
# when XDG_CURRENT_DESKTOP is set to 'Unity' or 'GNOME'. Coerce that here
# so the tray indicator registration uses the AppIndicator path that Plasma
# will display.
case "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}" in
  *KDE*|*Plasma*|plasma)
    export XDG_CURRENT_DESKTOP=Unity
    ;;
esac
exec "/opt/clash/clash" "$@"
WRAPPER_EOF
chmod 0755 "$USR_BIN_DIR/$PKG_NAME"

# Desktop entry
cat > "$DESKTOP_DIR/$PKG_NAME.desktop" <<EOF
[Desktop Entry]
Name=Clash
Exec=/usr/bin/$PKG_NAME %u
Icon=/usr/share/pixmaps/$PKG_NAME.png
Type=Application
Categories=Network;Utility;
Terminal=false
StartupWMClass=Clash
EOF

# Icon (optional) - try to find a png in repository and install several sizes
ICON_SRC=""
for candidate in "$ROOT_DIR/icon.png" "$ROOT_DIR/assets/icon.png" "$ROOT_DIR/web/icon.png"; do
  if [ -f "$candidate" ]; then
    ICON_SRC="$candidate"
    break
  fi
done
if [ -n "$ICON_SRC" ]; then
  echo "Installing icon from $ICON_SRC"
  # target sizes (hicolor)
  SIZES=(512 256 128 64 48 32 24)
  for s in "${SIZES[@]}"; do
    dir="$PACKAGE_DIR/usr/share/icons/hicolor/${s}x${s}/apps"
    mkdir -p "$dir"
    if command -v convert >/dev/null 2>&1; then
      # use ImageMagick to scale
      convert "$ICON_SRC" -resize ${s}x${s} "$dir/$PKG_NAME.png" || cp "$ICON_SRC" "$dir/$PKG_NAME.png"
    else
      # fallback: copy source (desktop environments will scale)
      cp "$ICON_SRC" "$dir/$PKG_NAME.png"
    fi
  done
  # Also install a fallback in /usr/share/pixmaps which some DEs prefer
  PIXMAP_DIR="$PACKAGE_DIR/usr/share/pixmaps"
  mkdir -p "$PIXMAP_DIR"
  cp "$ICON_SRC" "$PIXMAP_DIR/$PKG_NAME.png"
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
# Update desktop database and icon cache so the installed package's icon shows up
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  # Force update of hicolor theme cache
  gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
# KDE sometimes needs kbuildsycoca5 to refresh the system config cache
if command -v kbuildsycoca5 >/dev/null 2>&1; then
  kbuildsycoca5 >/dev/null 2>&1 || true
fi
# Ensure the app's asset path points to the installed pixmap so tray plugins that
# use the asset path see the same image as the system icon theme.
if [ -f /usr/share/pixmaps/$PKG_NAME.png ]; then
  mkdir -p /opt/$PKG_NAME/data/flutter_assets || true
  ln -sf /usr/share/pixmaps/$PKG_NAME.png /opt/$PKG_NAME/data/flutter_assets/icon.png || true
fi
exit 0
EOF
chmod 0755 "$DEBIAN_DIR/postinst"

# Set correct permissions for DEBIAN directory and files
chmod 0755 "$DEBIAN_DIR"
chmod 0644 "$DEBIAN_DIR/control"

mkdir -p "$OUT_DIR"
DEB_OUTPUT="$OUT_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb --build "$PACKAGE_DIR" "$DEB_OUTPUT"

echo "Created $DEB_OUTPUT"
