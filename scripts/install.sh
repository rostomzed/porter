#!/bin/zsh
# Builds (if needed) and installs Porter into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Porter"
APP_DIR="build/$APP_NAME.app"

if [[ ! -d "$APP_DIR" ]]; then
    ./scripts/build.sh
fi

echo "==> Installing to /Applications"
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_DIR" "/Applications/$APP_NAME.app"

echo "==> Installing command-line tool (porter)"
BIN_LINK="/usr/local/bin/porter"
APP_BIN="/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME"
if mkdir -p /usr/local/bin 2>/dev/null && ln -sf "$APP_BIN" "$BIN_LINK" 2>/dev/null; then
    echo "    Installed: porter (try: porter --help)"
else
    echo "    Needs admin rights — run:  sudo ln -sf \"$APP_BIN\" $BIN_LINK"
fi

echo "==> Launching"
open "/Applications/$APP_NAME.app"

echo ""
echo "Installed. On first use:"
echo "  • macOS will ask permission for Porter to control Word/Excel/etc. — click OK."
echo "  • Right-click any file in Finder → Quick Actions → Convert to PDF."
echo "  • Drop files into ~/Desktop/PDF Drop for automatic conversion."
