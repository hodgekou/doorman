#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
plist=dist/Doorman.app/Contents/Info.plist
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[0-9]+$ ]]
tool=.build/artifacts/sparkle/Sparkle/bin/sign_update
image=dist/Doorman.dmg
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  signature=$(printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$tool" --ed-key-file - -p "$image")
else
  signature=$("$tool" --account dev.doorman.Doorman -p "$image")
fi
public_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")
swift scripts/verify-update.swift "$image" "$public_key" "$signature"
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Doorman</title>
    <item>
      <title>Doorman $version</title>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/hodgekou/doorman/releases/download/v$version/Doorman.dmg" length="$(stat -f %z "$image")" sparkle:edSignature="$signature" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
