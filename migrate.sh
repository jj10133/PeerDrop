#!/bin/bash
set -e

echo "🚚 Migrating PeerDrop to new folder structure..."

# ── Create new directories ────────────────────────────────────────────────────
mkdir -p platforms/macos
mkdir -p platforms/ios
mkdir -p shared/swift/IPC
mkdir -p shared/swift/Models
mkdir -p shared/swift/Components
mkdir -p shared/js
mkdir -p frameworks
mkdir -p addons

echo "   ✓ Directories created"

# ── macOS platform UI ─────────────────────────────────────────────────────────
mv app/App.swift platforms/macos/App.swift
mv app/Core/Root/ContentView.swift platforms/macos/ContentView.swift
mv app/Core/Settings/SettingsView.swift platforms/macos/SettingsView.swift
mv app/Core/Settings/QRCodeView.swift platforms/macos/QRCodeView.swift
mv app/Core/Settings/DevicePanelView.swift platforms/macos/DevicePanelView.swift
mv app/Core/Settings/DevicePanelController.swift platforms/macos/DevicePanelController.swift
mv app/Assets.xcassets platforms/macos/Assets.xcassets
mv app/Info.plist platforms/macos/Info.plist
mv app/App.entitlements platforms/macos/App.entitlements

# Move icon file if present
[ -f app/PeerDrop.icon ] && mv app/PeerDrop.icon platforms/macos/PeerDrop.icon

echo "   ✓ macOS platform files moved"

# ── Shared Swift — IPC ────────────────────────────────────────────────────────
mv app/Core/IPC/IPCBridge.swift shared/swift/IPC/IPCBridge.swift
mv app/Core/IPC/Worker.swift shared/swift/IPC/Worker.swift
mv app/Core/IPC/Worker+Events.swift shared/swift/IPC/Worker+Events.swift
mv app/Core/IPC/Commands.swift shared/swift/IPC/Commands.swift

echo "   ✓ Shared IPC files moved"

# ── Shared Swift — Models ─────────────────────────────────────────────────────
mv app/Core/Models/PeerDevice.swift shared/swift/Models/PeerDevice.swift
mv app/Core/Models/FileTransfer.swift shared/swift/Models/FileTransfer.swift

echo "   ✓ Shared model files moved"

# ── Shared Swift — Components ─────────────────────────────────────────────────
mv app/Core/Components/TransferRow.swift shared/swift/Components/TransferRow.swift
mv app/Core/Components/DeviceRow.swift shared/swift/Components/DeviceRow.swift
mv app/Core/Components/PanelTransferRow.swift shared/swift/Components/PanelTransferRow.swift
mv app/Core/Components/SectionHeader.swift shared/swift/Components/SectionHeader.swift
mv app/Core/Components/ActionLink.swift shared/swift/Components/ActionLink.swift

echo "   ✓ Shared component files moved"

# ── Shared JS ─────────────────────────────────────────────────────────────────
mv app/js/app.js shared/js/app.js
mv app/js/transfers.js shared/js/transfers.js
mv app/js/store.js shared/js/store.js
mv app/js/commands.js shared/js/commands.js

echo "   ✓ Shared JS files moved"

# ── Frameworks & addons ───────────────────────────────────────────────────────
mv app/frameworks/BareKit.xcframework frameworks/BareKit.xcframework
mv app/addons/addons.yml addons/addons.yml

echo "   ✓ Frameworks and addons moved"

# ── Clean up empty app/ directories ──────────────────────────────────────────
rm -rf app/Core
rm -rf app/js
rm -rf app/frameworks
rm -rf app/addons

# Remove app/ if now empty
rmdir app 2>/dev/null && echo "   ✓ app/ removed (was empty)" || echo "   ℹ️  app/ kept (has other files)"

echo ""
echo "✅ Migration complete — folder structure:"
echo ""
find platforms shared frameworks addons -not -path "*/.*" | sort | sed 's/[^/]*\//  /g'

echo ""
echo "Next steps:"
echo "  1. Copy the new project.yml into your project root"
echo "  2. Run: ./setup.sh"
echo "  3. Run: xcodegen generate"
