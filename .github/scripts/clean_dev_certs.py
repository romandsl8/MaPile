"""Supprime les certificats « Apple Development » créés automatiquement par l'API
App Store Connect (une machine GitHub vierge en crée un à chaque compilation, jusqu'à
atteindre la limite du compte). Les certificats de DISTRIBUTION ne sont jamais touchés.

Variables d'environnement : ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
"""
import json
import os
import time
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com/v1"
DEV_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}


def token():
    with open(os.environ["ASC_KEY_PATH"], "r") as f:
        key = f.read()
    now = int(time.time())
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, tok):
    req = urllib.request.Request(API + path, method=method, headers={"Authorization": f"Bearer {tok}"})
    with urllib.request.urlopen(req) as resp:
        body = resp.read()
        return json.loads(body) if body else None


def main():
    tok = token()
    data = call("GET", "/certificates?limit=200&fields[certificates]=name,displayName,certificateType", tok)
    removed = 0
    for cert in data.get("data", []):
        attrs = cert.get("attributes", {})
        kind = attrs.get("certificateType", "")
        label = f"{attrs.get('name', '')} {attrs.get('displayName', '')}"
        if kind in DEV_TYPES and "Created via API" in label:
            call("DELETE", f"/certificates/{cert['id']}", tok)
            removed += 1
    print(f"Certificats de développement créés par l'API supprimés : {removed}")


if __name__ == "__main__":
    main()
