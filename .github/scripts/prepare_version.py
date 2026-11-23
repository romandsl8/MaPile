"""Prépare une version App Store de MaPile sans la soumettre.

- rattache le build choisi à la version (attend qu'Apple ait fini de le traiter) ;
- déclare le contenu publié par les utilisateurs (« Les avis MaPile ») dans la classification par âge ;
- renseigne les notes pour l'équipe de vérification d'Apple (où signaler / masquer un avis).

Le dépôt est public : le journal n'affiche ni nom, ni e-mail, ni téléphone.
Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, APP_VERSION, BUILD_NUMBER.
"""
import json
import os
import time
import urllib.error
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.romandsl8.mapile"

REVIEW_NOTES = """Bonjour,

Cette version active « Les avis MaPile » : des notes et commentaires anonymes que les lecteurs choisissent de partager (désactivé par défaut, règles à accepter avant de publier).

Modération :
- Ouvrir la fiche d'un livre (onglet PAL ou Lus), carte « Les avis MaPile ».
- Sur un avis d'un autre lecteur, bouton « … » puis « Signaler ou masquer » : choix d'un motif de signalement, ou « Masquer tous les avis de cet utilisateur » (blocage immédiat sur l'appareil).
- Les signalements sont examinés par l'éditeur sous 24 h ; les mots interdits sont filtrés avant publication.
- Règles de la communauté : https://mapile.pages.dev/regles

Aucun compte n'est nécessaire : l'app utilise uniquement iCloud (base publique CloudKit) de façon anonyme.

Merci !"""


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
    version_string = os.environ["APP_VERSION"]
    number = os.environ.get("BUILD_NUMBER", "").strip()

    _, apps = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")
    app_id = apps["data"][0]["id"]

    _, versions = call("GET", f"/apps/{app_id}/appStoreVersions?filter[versionString]={version_string}&filter[platform]=IOS")
    if not versions.get("data"):
        raise SystemExit(f"Version {version_string} introuvable : lancez d'abord l'envoi de la fiche.")
    version = versions["data"][0]
    version_id = version["id"]
    print(f"Version {version_string} : état {version['attributes'].get('appStoreState')}")

    # 1. Build
    if number:
        for attempt in range(40):
            _, builds = call("GET", f"/builds?filter[app]={app_id}&filter[version]={number}"
                                    f"&filter[preReleaseVersion.version]={version_string}")
            data = builds.get("data") or []
            state = data[0]["attributes"].get("processingState") if data else "absent"
            if state == "VALID":
                break
            print(f"Build {number} : {state}, nouvel essai dans 30 s")
            time.sleep(30)
        else:
            raise SystemExit("Le build n'est toujours pas prêt chez Apple.")
        build_id = data[0]["id"]
        # Chiffrement : l'app n'utilise que le chiffrement standard d'iOS (exemptée).
        if data[0]["attributes"].get("usesNonExemptEncryption") is None:
            status, res = call("PATCH", f"/builds/{build_id}",
                               {"data": {"type": "builds", "id": build_id,
                                         "attributes": {"usesNonExemptEncryption": False}}})
            print(f"Chiffrement déclaré : {status} {res.get('errors', '') if res else ''}")
        status, res = call("PATCH", f"/appStoreVersions/{version_id}/relationships/build",
                           {"data": {"type": "builds", "id": build_id}})
        print(f"Build {number} rattaché : {status} {res.get('errors', '') if res else ''}")

    # 2. Classification par âge : contenu publié par les utilisateurs
    _, infos = call("GET", f"/apps/{app_id}/appInfos")
    editable = [i for i in infos.get("data", [])
                if i["attributes"].get("appStoreState") not in ("READY_FOR_SALE", "REPLACED_WITH_NEW_INFO")
                and i["attributes"].get("state") not in ("READY_FOR_DISTRIBUTION",)]
    info = (editable or infos.get("data", []))[-1]
    status, decl = call("GET", f"/appInfos/{info['id']}/ageRatingDeclaration")
    if status == 200 and decl and decl.get("data"):
        decl_id = decl["data"]["id"]
        before = decl["data"]["attributes"].get("userGeneratedContent")
        status, res = call("PATCH", f"/ageRatingDeclarations/{decl_id}",
                           {"data": {"type": "ageRatingDeclarations", "id": decl_id,
                                     "attributes": {"userGeneratedContent": True}}})
        print(f"Classification par âge (contenu des utilisateurs, avant : {before}) : {status} "
              f"{res.get('errors', '') if res else ''}")
    else:
        print(f"Classification par âge introuvable : {status} {decl.get('errors', '') if decl else ''}")

    # 3. Notes pour la vérification d'Apple (les coordonnées existantes ne sont ni lues ni affichées)
    status, detail = call("GET", f"/appStoreVersions/{version_id}/appStoreReviewDetail")
    if status == 200 and detail and detail.get("data"):
        detail_id = detail["data"]["id"]
        status, res = call("PATCH", f"/appStoreReviewDetails/{detail_id}",
                           {"data": {"type": "appStoreReviewDetails", "id": detail_id,
                                     "attributes": {"notes": REVIEW_NOTES}}})
        print(f"Notes pour Apple : {status} {res.get('errors', '') if res else ''}")
    else:
        status, res = call("POST", "/appStoreReviewDetails",
                           {"data": {"type": "appStoreReviewDetails",
                                     "attributes": {"notes": REVIEW_NOTES},
                                     "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions",
                                                                                    "id": version_id}}}}})
        print(f"Notes pour Apple (création) : {status} {res.get('errors', '') if res else ''}")

    print("Rien n'a été soumis à Apple.")


if __name__ == "__main__":
    main()
