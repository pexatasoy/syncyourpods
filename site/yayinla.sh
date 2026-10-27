#!/bin/bash
# İndirme sayfasını yayınlar: https://chainmedia.co/fotoyol/<.site-dizini>/
#   ./yayinla.sh   → sayfa + Windows programı + (varsa) iPhone .ipa ve kurulum bildirimi
# iPhone: önce ios/ci/kos.sh indir (ipa ios/cikti altına gelir).
# Windows: pc/ içinde `cargo build --release --target x86_64-pc-windows-gnu`.
set -e
KOK="$(cd "$(dirname "$0")" && pwd)"
DIZIN=$(cat "$KOK/.site-dizini")
HEDEF=/var/www/fotoyol/$DIZIN
ADRES="https://chainmedia.co/fotoyol/$DIZIN"
mkdir -p "$HEDEF"
cp "$KOK/index.html" "$KOK/simge.png" "$KOK/simge-57.png" "$HEDEF/"

EXE=/root/syncyourpods/pc/msvc/SyncYourPods.exe  # GitHub Windows koşucusunda MSVC ile derlenir (pc/ci-windows.yml)
[ -f "$EXE" ] && cp "$EXE" "$HEDEF/SyncYourPods.exe" && echo "Windows: $(du -h "$HEDEF/SyncYourPods.exe" | cut -f1)"

IPA=$(ls /root/syncyourpods/ios/cikti/*.ipa 2>/dev/null | head -1)
if [ -n "$IPA" ]; then
  cp "$IPA" "$HEDEF/SyncYourPods.ipa"
  DERLEME=$(cat /root/syncyourpods/ios/cikti/derleme.txt 2>/dev/null | tr -d '[:space:]')
  SURUM="1.0.0"
  cat > "$HEDEF/manifest.xml" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict><key>kind</key><string>software-package</string><key>url</key><string>$ADRES/SyncYourPods.ipa</string></dict>
        <dict><key>kind</key><string>display-image</string><key>url</key><string>$ADRES/simge-57.png</string></dict>
        <dict><key>kind</key><string>full-size-image</string><key>url</key><string>$ADRES/simge.png</string></dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>com.atasoy.syncyourpods</string>
        <key>bundle-version</key><string>$SURUM</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>SyncYourPods</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST
  echo "$SURUM (${DERLEME:-?})" > "$HEDEF/surum.txt"
  echo "iPhone: $(du -h "$HEDEF/SyncYourPods.ipa" | cut -f1), sürüm $SURUM (${DERLEME:-?})"
fi
echo "✅ $ADRES/"
