# Résume un rapport de plantage Apple (.ips) : type d'erreur et premières fonctions du fil fautif.
import json, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
body = json.loads(text.split("\n", 1)[1])
print("exception:", body.get("exception"))
print("termination:", body.get("termination"))
info = body.get("asi") or {}
print("asi:", json.dumps(info)[:1500])
threads = body.get("threads", [])
images = body.get("usedImages", [])
for t in threads:
    if t.get("triggered"):
        for f in t.get("frames", [])[:25]:
            img = images[f.get("imageIndex", 0)].get("name", "?") if images else "?"
            print("  ", img, f.get("symbol", "?"))
