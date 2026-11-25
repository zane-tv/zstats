#!/bin/bash
# Builds ZStats for Intel and Apple silicon and assembles a launchable .app bundle.
#
# SwiftPM cannot produce an app bundle, and a menu bar app needs one: LSUIElement,
# a bundle identifier for UserDefaults and notifications, and a code signature so
# macOS will grant it a status item. So we build both architectures and wrap them here.
#
#   Scripts/build.sh            → debug universal build
#   Scripts/build.sh release    → optimised universal build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="${1:-debug}"
if [ "$#" -gt 0 ]; then shift; fi

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  arm64) OTHER_ARCH="x86_64" ;;
  x86_64) OTHER_ARCH="arm64" ;;
  *)
    echo "error: unsupported build host architecture '$HOST_ARCH'" >&2
    exit 1
    ;;
esac

# The regular .build directory keeps the native build products where the README and
# contributor instructions expect them. The other slice gets its own SwiftPM scratch
# directory so the two architectures never overwrite each other's modules.
swift build -c "$CONFIG" "$@"
HOST_BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path "$@")"

OTHER_SCRATCH="$ROOT/.build-$OTHER_ARCH"
OTHER_TRIPLE="$OTHER_ARCH-apple-macosx14.0"
swift build -c "$CONFIG" --scratch-path "$OTHER_SCRATCH" --triple "$OTHER_TRIPLE" "$@"
OTHER_BIN_DIR="$(swift build -c "$CONFIG" --scratch-path "$OTHER_SCRATCH" \
  --triple "$OTHER_TRIPLE" --show-bin-path "$@")"

HOST_BINARY="$HOST_BIN_DIR/ZStats"
OTHER_BINARY="$OTHER_BIN_DIR/ZStats"
for required in "$HOST_BINARY" "$OTHER_BINARY"; do
  if [ ! -e "$required" ]; then
    echo "error: expected build product is missing: $required" >&2
    exit 1
  fi
done

MERGE_TMP="$(mktemp -d "$ROOT/.build-universal-merge.XXXXXX")"
trap 'rm -rf "$MERGE_TMP"' EXIT

# SwiftPM's swiftbuild backend can write the deployment target into the SDK-version
# slot as well. AppKit uses the latter to select the system appearance, so restore it
# in each thin executable before combining the two architectures.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
prepare_executable() {
  local source="$1"
  local destination="$2"
  local minimum

  minimum="$(vtool -show-build "$source" | awk '/minos/ { print $2; exit }')"
  if [ -z "$minimum" ]; then
    echo "error: could not read the minimum macOS version from $source" >&2
    return 1
  fi
  vtool -set-build-version macos "$minimum" "$SDK_VERSION" -replace \
    -output "$destination" "$source"
}

prepare_executable "$HOST_BINARY" "$MERGE_TMP/ZStats-$HOST_ARCH"
prepare_executable "$OTHER_BINARY" "$MERGE_TMP/ZStats-$OTHER_ARCH"
lipo -create "$MERGE_TMP/ZStats-$HOST_ARCH" "$MERGE_TMP/ZStats-$OTHER_ARCH" \
  -output "$MERGE_TMP/ZStats"
chmod +x "$MERGE_TMP/ZStats"

BIN_DIR="$HOST_BIN_DIR"
APP="$BIN_DIR/ZStats.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$MERGE_TMP/ZStats" "$APP/Contents/MacOS/ZStats"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# SwiftPM emits the UI target's resources as a bundle beside the binary. A signed app
# may hold resources only under Contents/Resources: putting this beside Contents leaves
# an unsealed object at the bundle root. Logo resolves this packaged location before it
# falls back to SwiftPM's development accessor.
#
# Named exactly rather than globbed: a tree built under an earlier package name leaves
# that name's bundle in the bin directory forever, and a glob ships both.
BUNDLE="$HOST_BIN_DIR/ZStats_ZStatUI.bundle"
if [ -d "$BUNDLE" ]; then
  cp -R "$BUNDLE" "$APP/Contents/Resources/"
else
  echo "error: $BUNDLE is missing; the app would launch with no logo" >&2
  exit 1
fi

# Ad-hoc signature. Without any signature macOS refuses some window-server
# privileges a status item needs.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
  echo "warning: codesign failed; the app may still run" >&2
}

echo "$APP"
