"""Soumet une version App Store de MaPile à la vérification d'Apple.

À lancer uniquement après accord explicite. Le journal n'affiche ni nom, ni e-mail, ni téléphone.
Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, APP_VERSION.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from prepare_version import BUNDLE_ID, call  # noqa: E402


def main():
    version_string = os.environ["APP_VERSION"]
    _, apps = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")
    app_id = apps["data"][0]["id"]

    _, versions = call("GET", f"/apps/{app_id}/appStoreVersions?filter[versionString]={version_string}"
                              f"&filter[platform]=IOS&include=build")
    if not versions.get("data"):
        raise SystemExit(f"Version {version_string} introuvable.")
    version = versions["data"][0]
    state = version["attributes"].get("appStoreState")
    print(f"Version {version_string} : état {state}")
    if state not in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
        raise SystemExit("Cette version n'est pas dans un état qui permet de la soumettre.")
    build = (version.get("relationships", {}).get("build", {}) or {}).get("data")
    if not build:
        raise SystemExit("Aucun build rattaché à la version.")
    for inc in versions.get("included", []):
        if inc["id"] == build["id"]:
            print(f"Build rattaché : {inc['attributes'].get('version')}")

    # Réutilise une soumission en préparation s'il y en a une, sinon en crée une.
    _, subs = call("GET", f"/reviewSubmissions?filter[app]={app_id}&filter[platform]=IOS"
                          f"&filter[state]=READY_FOR_REVIEW")
    if subs.get("data"):
        sub_id = subs["data"][0]["id"]
        print("Soumission en préparation réutilisée")
    else:
        status, res = call("POST", "/reviewSubmissions",
                           {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        print(f"Création de la soumission : {status} {res.get('errors', '') if res else ''}")
        if status >= 300:
            raise SystemExit(1)
        sub_id = res["data"]["id"]

    status, res = call("POST", "/reviewSubmissionItems",
                       {"data": {"type": "reviewSubmissionItems",
                                 "relationships": {
                                     "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                                     "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})
    print(f"Ajout de la version : {status} {res.get('errors', '') if res else ''}")
    if status >= 300 and status != 409:
        raise SystemExit(1)

    status, res = call("PATCH", f"/reviewSubmissions/{sub_id}",
                       {"data": {"type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}})
    print(f"Envoi à Apple : {status} {res.get('errors', '') if res else ''}")
    if status >= 300:
        raise SystemExit(1)

    _, after = call("GET", f"/appStoreVersions/{version['id']}")
    print(f"Nouvel état de la version : {after['data']['attributes'].get('appStoreState')}")


if __name__ == "__main__":
    main()
