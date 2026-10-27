#!/usr/bin/env python3
"""SyncYourPods — Ad Hoc imza kurulumu (App Store / TestFlight YOK: doğrudan link ile kurulum).

    ci/adhoc_kur.py kur      → paket kimliğini kaydeder, Ad Hoc profilini (kayıtlı iPhone'larla) üretir
    ci/adhoc_kur.py yenile   → yeni cihaz eklendiyse profili yeniden üretir (sonra `ci/kos.sh sir` + yeniden derle)
    ci/adhoc_kur.py cihazlar → hesaptaki cihazlar

⚠️ Profil yalnız İÇİNDEKİ cihazlara kurulur. Yeni iPhone = Apple hesabına cihaz kaydı + `yenile`.
"""
import sys, os, json, base64
sys.path.insert(0, "/root/isik/ci")
import asc

BUNDLE = "com.atasoy.syncyourpods"
PROFIL_ADI = "SyncYourPods Ad Hoc"
ASC = "/root/.asc"
# Yalnız Efe'nin telefonu (Serkan'ınkini eklemek için listeye ad yaz + `yenile`).
CIHAZLAR = ["Efe’s iPhone 16"]


def bundle_id():
    k, d = asc.cagir("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}")
    for b in d.get("data", []):
        if b["attributes"]["identifier"] == BUNDLE:
            return b["id"]
    k, d = asc.cagir("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": BUNDLE, "name": "SyncYourPods", "platform": "IOS"}}})
    if k != 201:
        sys.exit(f"paket kimliği açılamadı: {k} {d}")
    print("paket kimliği kaydedildi:", BUNDLE)
    return d["data"]["id"]


def cihaz_idleri():
    k, d = asc.cagir("GET", "/v1/devices?limit=200")
    ids = [x["id"] for x in d["data"] if x["attributes"]["name"] in CIHAZLAR and x["attributes"]["status"] == "ENABLED"]
    if not ids:
        sys.exit("cihaz bulunamadı")
    return ids


def profil(yenile=False):
    bid = bundle_id()
    k, d = asc.cagir("GET", f"/v1/profiles?filter[name]={PROFIL_ADI.replace(' ', '%20')}")
    for p in d.get("data", []):
        if not yenile and p["attributes"]["profileState"] == "ACTIVE":
            kaydet(p)
            return
        asc.cagir("DELETE", f"/v1/profiles/{p['id']}")
    sertifika = open(os.path.join(ASC, "dagitim.id")).read().strip()
    k, d = asc.cagir("POST", "/v1/profiles", {"data": {"type": "profiles",
        "attributes": {"name": PROFIL_ADI, "profileType": "IOS_APP_ADHOC"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bid}},
            "certificates": {"data": [{"type": "certificates", "id": sertifika}]},
            "devices": {"data": [{"type": "devices", "id": i} for i in cihaz_idleri()]}}}})
    if k != 201:
        sys.exit(f"profil üretilemedi: {k} {json.dumps(d)[:600]}")
    kaydet(d["data"])


def kaydet(p):
    yol = os.path.join(ASC, "syncyourpods-adhoc.mobileprovision")
    open(yol, "wb").write(base64.b64decode(p["attributes"]["profileContent"]))
    os.chmod(yol, 0o600)
    print("profil:", p["attributes"]["name"], p["attributes"]["profileState"], "→", yol)


if __name__ == "__main__":
    k = sys.argv[1] if len(sys.argv) > 1 else ""
    if k == "kur": profil()
    elif k == "yenile": profil(yenile=True)
    elif k == "cihazlar":
        _, d = asc.cagir("GET", "/v1/devices?limit=200")
        for x in d["data"]: print(x["attributes"]["name"], x["attributes"]["status"])
    else: print(__doc__)
