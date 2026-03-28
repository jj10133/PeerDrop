#!/bin/bash
set -e

echo "🔧 PeerDrop setup..."

# ── 1. Fix BareKit symlinks ───────────────────────────────────────────────────
FRAMEWORK="app/frameworks/BareKit.xcframework/macos-arm64_x86_64/BareKit.framework"

if [ -d "$FRAMEWORK" ]; then
  echo "🔗 Fixing BareKit symlinks..."

  cd "$FRAMEWORK"

  if [ -d "Versions/Current" ] && [ ! -L "Versions/Current" ]; then
    rm -rf Versions/Current
    ln -sf A Versions/Current
    echo "   ✓ Versions/Current"
  fi

  if [ -f "BareKit" ] && [ ! -L "BareKit" ]; then
    rm BareKit
    ln -sf Versions/Current/BareKit BareKit
    echo "   ✓ BareKit"
  fi

  if [ -d "Headers" ] && [ ! -L "Headers" ]; then
    rm -rf Headers
    ln -sf Versions/Current/Headers Headers
    echo "   ✓ Headers"
  fi

  if [ -d "Resources" ] && [ ! -L "Resources" ]; then
    rm -rf Resources
    ln -sf Versions/Current/Resources Resources
    echo "   ✓ Resources"
  fi

  if [ -d "Modules" ] && [ ! -L "Modules" ]; then
    rm -rf Modules
    ln -sf Versions/Current/Modules Modules
    echo "   ✓ Modules"
  fi

  cd - >/dev/null
  echo "   ✅ BareKit symlinks fixed"

  # ── 2. Sign the framework ──────────────────────────────────────────────────
  echo "✍️  Signing BareKit framework..."

  # Try Developer ID Application first (distribution)
  CERT=$(security find-identity -v -p codesigning 2>/dev/null |
    grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"')

  # Fall back to Apple Development (local builds)
  if [ -z "$CERT" ]; then
    CERT=$(security find-identity -v -p codesigning 2>/dev/null |
      grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"')
  fi

  if [ -z "$CERT" ]; then
    echo "   ⚠️  No Apple certificate found, signing locally"
    codesign --force --deep --sign - "$FRAMEWORK"
  else
    echo "   Using: $CERT"
    codesign --force --deep --sign "$CERT" \
      --options runtime \
      --timestamp \
      "$FRAMEWORK"
  fi

  echo "   ✅ BareKit signed"

else
  echo "   ⚠️  BareKit.xcframework not found — run:"
  echo "      gh release download --repo holepunchto/bare-kit <version>"
  echo "      unzip prebuilds.zip && mv macos/BareKit.xcframework app/frameworks/"
  exit 1
fi

# ── 3. Install node dependencies ──────────────────────────────────────────────
echo "📦 Installing node dependencies..."
npm install --silent
echo "   ✅ node_modules ready"

# ── 4. Generate Xcode project ─────────────────────────────────────────────────
echo "⚙️  Generating Xcode project..."
xcodegen generate
echo "   ✅ App.xcodeproj generated"

# ── 5. Clean DerivedData ──────────────────────────────────────────────────────
echo "🧹 Cleaning DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/App-*
echo "   ✅ DerivedData cleared"

echo ""
echo "✅ All done — open App.xcodeproj and hit ⌘R"
