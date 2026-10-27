#!/usr/bin/env python3
"""Uçtan uca deneme: PC programına iPhone gibi bağlanır, paketleri doğrular.
   Linux'ta: (cd pc && cargo run) & python3 araclar/sahte_telefon.py"""
import json, socket, struct, sys, time

H = "127.0.0.1"; P = 47800
t = socket.create_connection((H, P)); f = t.makefile("rw")
def yolla(m): f.write(json.dumps(m) + "\n"); f.flush()
def oku():
    return json.loads(f.readline())
yolla({"t": "hello", "v": 1, "id": "deneme-telefon", "name": "Deneme iPhone"})
m = oku()
if m["t"] == "wait": print("onay bekleniyor (Linux: otomatik kabul)"); m = oku()
assert m["t"] == "welcome", m; oturum = m["session"]; print("welcome:", m)
u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.settimeout(0.5)
def punch():
    u.sendto(b"S" + bytes([4]) + struct.pack("<HIIIHBBI", 0, oturum, 0, 0, 0, 1, 1, 0), (H, P))
punch()
sayilar = {1: 0, 2: 0}; siralar = []; yedekli = 0; bas = time.time(); son_punch = bas
while time.time() - bas < 4.5:
    if time.time() - son_punch > 1: punch(); son_punch = time.time()
    try: v, _ = u.recvfrom(4096)
    except socket.timeout: continue
    tur = v[1]; bayrak, ot, sira, konum, kare, kanal, bicim, hiz = struct.unpack("<HIIIHBBI", v[2:24])
    assert ot == oturum
    sayilar[tur] = sayilar.get(tur, 0) + 1
    if tur == 1:
        assert (kare, kanal, bicim, hiz) == (160, 2, 1, 48000)
        assert len(v) == 24 + 640 * (2 if bayrak & 1 else 1)
        yedekli += bool(bayrak & 1); siralar.append(sira)
yolla({"t": "ping", "ts": 123}); yolla({"t": "focus", "phone": True}); yolla({"t": "focus", "phone": False})
yolla({"t": "mic", "on": True})
for i in range(50):
    u.sendto(b"S" + bytes([3]) + struct.pack("<HIIIHBBI", 0, oturum, i, i * 160, 160, 1, 1, 24000) + b"\x10\x00" * 160, (H, P))
mesajlar = []
t.settimeout(1.0)
try:
    while True: mesajlar.append(oku())
except Exception: pass
yolla({"t": "bye"})
print("ses paketi:", sayilar.get(1), "sessizlik paketi:", sayilar.get(2), "yedekli:", yedekli)
eksik = sum(b - a - 1 for a, b in zip(siralar, siralar[1:]))
print("sıra atlaması:", eksik, "  kayıp:", eksik)
print("mesajlar:", [m["t"] + ("" if m["t"] != "micstate" else ":" + m["state"]) for m in mesajlar])
saniye = 4.5
assert sayilar[1] > 0.6 * 300 * saniye * (2/3), "beklenenden az ses paketi"
assert sayilar.get(2, 0) >= 3, "sessiz saniyede sessizlik paketi gelmeli"
assert any(m["t"] == "pong" and m["ts"] == 123 for m in mesajlar)
print("✓ uçtan uca deneme geçti")
