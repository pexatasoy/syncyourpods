#!/bin/bash
# SyncYourPods iOS derleme hattını sunucudan sürer (Medowl ci/kos.sh kopyası; aynı depo, aynı token).
#
#   ci/kos.sh gonder    → iş akışı dosyasını depoya yükler (DEĞİŞTİYSE ŞART, yoksa GitHub eskisini koşturur)
#   ci/kos.sh tetikle   → derlemeyi başlatır (ekran görüntüleri + Ad Hoc .ipa)
#   ci/kos.sh bekle     → son koşu bitene kadar bekler
#   ci/kos.sh hata      → son koşunun hata satırları
#   ci/kos.sh indir     → ipa + ekran görüntülerini ios/cikti altına koyar (herkese açık DEĞİL)
#   ci/kos.sh sir       → SYNC_PROFIL gizli değişkenini depoya yazar (profil yenilenince tekrar)
#
# ⚠️ Kaynak depoda DEĞİL: önce `./yayinla-ios.sh`, sonra tetikle.
# ⚠️ Token /root/.isik-gh-token: bu betik root ile çalışır. Depo public → macOS dakikaları ücretsiz.
set -e
T=$(cat /root/.isik-gh-token)
R=pexatasoy/fotoaktar-masaustu
A=(-s -H "Authorization: Bearer $T" -H "Accept: application/vnd.github+json")
AKIS="syncyourpods.yml"
AKIS_ADI="SyncYourPods iOS"
KOMUT="$1"
CI_KOK="$(cd "$(dirname "$0")" && pwd)"
HEDEF=/root/syncyourpods/ios/cikti

# ⚠️ Aynı depoda başka uygulamaların akışları da var: koşuları ADA göre süz.
sonKosu() {
  curl "${A[@]}" "https://api.github.com/repos/$R/actions/runs?per_page=30" \
    | AD="$AKIS_ADI" python3 -c "
import sys, json, os
ad = os.environ['AD']
for r in json.load(sys.stdin)['workflow_runs']:
    if r['name'] == ad: print(r['id']); break
else: sys.exit('koşu bulunamadı: ' + ad)"
}

case "$KOMUT" in
  gonder)
    Y=".github/workflows/$AKIS"
    SHA=$(curl "${A[@]}" "https://api.github.com/repos/$R/contents/$Y" \
      | python3 -c "import sys,json;print(json.load(sys.stdin).get('sha',''))")
    python3 - "$CI_KOK/$AKIS" "$SHA" <<'PY' > /tmp/syp_yml.json
import base64, json, sys
f, sha = sys.argv[1], sys.argv[2]
g = {"message": f.split("/")[-1] + " güncellendi",
     "content": base64.b64encode(open(f, "rb").read()).decode()}
if sha: g["sha"] = sha
json.dump(g, sys.stdout)
PY
    curl "${A[@]}" -X PUT "https://api.github.com/repos/$R/contents/$Y" \
      --data-binary @/tmp/syp_yml.json \
      | python3 -c "import sys,json;d=json.load(sys.stdin);print('gönderildi:', d.get('content',{}).get('path','HATA '+str(d.get('message'))))"
    rm -f /tmp/syp_yml.json
    ;;
  sir)
    # Sağlama profili gizli değişken olarak yazılır (depo public, dosyaya konamaz).
    python3 - "$T" "$R" <<'PY'
import base64, json, sys, urllib.request
from nacl import encoding, public
tok, repo = sys.argv[1], sys.argv[2]
def cagir(yol, govde=None):
    i = urllib.request.Request(f"https://api.github.com/repos/{repo}/{yol}",
        data=json.dumps(govde).encode() if govde else None,
        headers={"Authorization": f"Bearer {tok}", "Accept": "application/vnd.github+json"},
        method="PUT" if govde else "GET")
    with urllib.request.urlopen(i) as c:
        g = c.read(); return c.status, (json.loads(g) if g else {})
_, anahtar = cagir("actions/secrets/public-key")
kutu = public.SealedBox(public.PublicKey(anahtar["key"].encode(), encoding.Base64Encoder()))
ham = open("/root/.asc/syncyourpods-adhoc.mobileprovision", "rb").read()
deger = base64.b64encode(kutu.encrypt(base64.b64encode(ham))).decode()
k, _ = cagir("actions/secrets/SYNC_PROFIL", {"encrypted_value": deger, "key_id": anahtar["key_id"]})
print("SYNC_PROFIL yazıldı, HTTP", k)
PY
    ;;
  tetikle)
    curl "${A[@]}" -o /dev/null -w "tetiklendi (%{http_code}) — $AKIS\n" \
      -X POST "https://api.github.com/repos/$R/actions/workflows/$AKIS/dispatches" \
      -d '{"ref":"main"}'
    sleep 8
    echo "koşu: $(sonKosu)"
    ;;
  bekle)
    ID=${2:-$(sonKosu)}
    while :; do
      D=$(curl "${A[@]}" "https://api.github.com/repos/$R/actions/runs/$ID")
      S=$(echo "$D" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['status'],d['conclusion'])")
      [ "${S%% *}" = "completed" ] && { echo "$S (koşu $ID)"; break; }
      sleep 15
    done
    ;;
  hata)
    ID=${2:-$(sonKosu)}
    curl -sL -H "Authorization: Bearer $T" \
      "https://api.github.com/repos/$R/actions/runs/$ID/logs" -o /tmp/syp_kayit.zip
    rm -rf /tmp/syp_kayit && mkdir -p /tmp/syp_kayit && unzip -qo /tmp/syp_kayit.zip -d /tmp/syp_kayit
    # ⚠️ Yalnız error: satırları — xcodebuild binlerce satır basıyor.
    grep -rhE "error:|DERLEME HATALARI|ARŞİV HATALARI|✅|Kaynak indirilemedi" /tmp/syp_kayit \
      | sed 's/^[0-9T:.Z-]* //' | sort -u | head -60
    ;;
  indir)
    ID=${2:-$(sonKosu)}
    mkdir -p "$HEDEF"
    curl "${A[@]}" "https://api.github.com/repos/$R/actions/runs/$ID/artifacts" | python3 -c "
import sys, json
for a in json.load(sys.stdin)['artifacts']: print(a['name'], a['archive_download_url'])" \
    | while read -r AD URL; do
      case "$AD" in
        syncyourpods-ipa)
          rm -f "$HEDEF"/*.ipa
          curl -sL -H "Authorization: Bearer $T" "$URL" -o /tmp/syp_ipa.zip \
            && unzip -qo /tmp/syp_ipa.zip -d "$HEDEF" && ls -lh "$HEDEF"/*.ipa;;
        ekran-goruntuleri)
          rm -rf "$HEDEF/gorseller" && mkdir -p "$HEDEF/gorseller"
          curl -sL -H "Authorization: Bearer $T" "$URL" -o /tmp/syp_ss.zip \
            && unzip -qo /tmp/syp_ss.zip -d "$HEDEF/gorseller" && ls "$HEDEF/gorseller";;
      esac
    done
    ;;
  *) echo "kullanım: ci/kos.sh {gonder|tetikle|bekle|hata|indir|sir}"; exit 1;;
esac
