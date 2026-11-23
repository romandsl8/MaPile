"""Envoie un build TestFlight aux testeurs externes (groupes non internes) de MaPile.

- ajoute le build à chaque groupe externe ;
- renseigne « Quoi de neuf » (obligatoire pour les testeurs externes) ;
- le soumet à la vérification bêta d'Apple si besoin.

Le dépôt est public : le journal n'affiche que des nombres, jamais de noms ni d'e-mails.
Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUILD_NUMBER, WHATS_NEW.
"""
import json
import os
import time
import urllib.error
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.romandsl8.mapile"


def token():
    with open(os.environ["ASC_KEY_PATH"], "r") as f:
        key = f.read()
    now = int(time.time())
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


TOKEN = token()


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as err:
        raw = err.read()
        try:
            details = [e.get("detail") or e.get("title") for e in json.loads(raw).get("errors", [])]
        except Exception:
            details = [raw[:300]]
        return err.code, {"errors": details}


def main():
    number = os.environ["BUILD_NUMBER"]
    whats_new = os.environ.get("WHATS_NEW", "").strip()

    _, apps = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")
    app_id = apps["data"][0]["id"]

    _, builds = call("GET", f"/builds?filter[app]={app_id}&filter[version]={number}&include=buildBetaDetail")
    if not builds.get("data"):
        raise SystemExit(f"Build {number} introuvable.")
    build = builds["data"][0]
    build_id = build["id"]
    attrs = build["attributes"]
    print(f"Build {number} : traitement={attrs.get('processingState')} expiré={attrs.get('expired')}")
    if attrs.get("processingState") != "VALID":
        raise SystemExit("Le build n'est pas encore prêt chez Apple. Réessayez dans quelques minutes.")

    # « Quoi de neuf » en français (obligatoire pour les testeurs externes).
    if whats_new:
        _, locs = call("GET", f"/builds/{build_id}/betaBuildLocalizations")
        existing = [l for l in locs.get("data", []) if l["attributes"].get("locale", "").startswith("fr")]
        if existing:
            status, res = call("PATCH", f"/betaBuildLocalizations/{existing[0]['id']}",
                               {"data": {"type": "betaBuildLocalizations", "id": existing[0]["id"],
                                         "attributes": {"whatsNew": whats_new}}})
        else:
            status, res = call("POST", "/betaBuildLocalizations",
                               {"data": {"type": "betaBuildLocalizations",
                                         "attributes": {"locale": "fr-FR", "whatsNew": whats_new},
                                         "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
        print(f"Quoi de neuf : {status} {res.get('errors', '') if res else ''}")

    # Groupes de testeurs.
    _, groups = call("GET", f"/apps/{app_id}/betaGroups?limit=50")
    external = []
    for g in groups.get("data", []):
        internal = g["attributes"].get("isInternalGroup")
        _, testers = call("GET", f"/betaGroups/{g['id']}/betaTesters?limit=200&fields[betaTesters]=state")
        count = len(testers.get("data", []))
        print(f"Groupe {'interne' if internal else 'externe'} : {count} testeur(s)")
        if not internal:
            external.append(g["id"])

    if not external:
        print("Aucun groupe externe : les testeurs internes reçoivent les builds automatiquement.")
        return

    for gid in external:
        status, res = call("POST", f"/betaGroups/{gid}/relationships/builds",
                           {"data": [{"type": "builds", "id": build_id}]})
        print(f"Ajout au groupe externe : {status} {res.get('errors', '') if res else ''}")

    # Vérification bêta d'Apple (nécessaire pour les testeurs externes).
    status, sub = call("GET", f"/builds/{build_id}/betaAppReviewSubmission")
    if status == 200 and sub and sub.get("data"):
        print(f"Vérification bêta déjà demandée : {sub['data']['attributes'].get('betaReviewState')}")
    else:
        status, res = call("POST", "/betaAppReviewSubmissions",
                           {"data": {"type": "betaAppReviewSubmissions",
                                     "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
        state = res["data"]["attributes"].get("betaReviewState") if status in (200, 201) else res.get("errors")
        print(f"Demande de vérification bêta : {status} {state}")

    _, detail = call("GET", f"/builds/{build_id}/buildBetaDetail")
    if detail and detail.get("data"):
        print(f"État pour les testeurs externes : {detail['data']['attributes'].get('externalBuildState')}")


if __name__ == "__main__":
    main()
