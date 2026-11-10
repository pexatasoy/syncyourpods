#!/bin/bash
# Kaynağı toparlayıp derleme hattının çekeceği zip'i yayınlar (Medowl düzeninin aynısı).
#   ./yayinla-ios.sh  →  pexatasoy/syncyourpods (private, derleme dalı)
# Sonra: ci/kos.sh tetikle && ci/kos.sh bekle && ci/kos.sh indir
# ⚠️ Kaynak GitHub deposunda DEĞİL burada; depoda yalnız iş akışı tarifi var.
set -e
KOK="$(cd "$(dirname "$0")" && pwd)"
cd "$KOK"
export PATH=/opt/swift/usr/bin:$PATH

echo "→ çekirdek testleri"
(cd Cekirdek && swift test >/dev/null 2>&1) || { echo "❌ çekirdek testleri geçmedi"; (cd Cekirdek && swift test 2>&1 | grep -E "error" | head); exit 1; }
echo "   ✓ geçti"

echo "→ söz dizimi denetimi"
HATA=0
while IFS= read -r f; do
  swiftc -parse "$f" >/dev/null 2>/tmp/syp-parse.err || { echo "söz dizimi hatası: $f"; sed -n 1,6p /tmp/syp-parse.err; HATA=1; }
done < <(find SyncYourPods -name "*.swift")
[ "$HATA" = 1 ] && exit 1
echo "   ✓ $(find SyncYourPods -name '*.swift' | wc -l) dosya temiz"

date -u '+%Y-%m-%d %H:%M UTC' > DAMGA.txt
git -C "$KOK" rev-parse --short HEAD 2>/dev/null >> DAMGA.txt || true


# Aynı paket private repoya da gider (pexatasoy/syncyourpods, `derleme` dalı); hatlar oradan çeker.
/root/github-profil/duzen/derleme-yukle.sh syncyourpods "$PWD" SyncYourPods Destek Cekirdek project.yml DAMGA.txt
echo "✅ hazır (paket: github.com/pexatasoy/syncyourpods, private)"
