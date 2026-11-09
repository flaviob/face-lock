#!/bin/zsh
# Builds FaceLock.app and installs it to ~/Applications
set -e
cd "$(dirname "$0")"
APP=build/FaceLock.app
rm -rf build && mkdir -p $APP/Contents/MacOS
swiftc -O Sources/main.swift -o $APP/Contents/MacOS/FaceLock
cat > $APP/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>FaceLock</string>
  <key>CFBundleIdentifier</key><string>com.flavio.facelock</string>
  <key>CFBundleExecutable</key><string>FaceLock</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSCameraUsageDescription</key><string>FaceLock checks whether you are in front of the screen. Frames never leave the Mac.</string>
</dict></plist>
EOF
codesign --force --sign - $APP
mkdir -p ~/Applications
rm -rf ~/Applications/FaceLock.app && cp -R $APP ~/Applications/
echo "Installed ~/Applications/FaceLock.app"
