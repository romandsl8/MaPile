# MaPile – Fiche App Store (à copier-coller dans App Store Connect)

App Store Connect → Apps → MaPile → onglet **Distribution** → **1.0 Préparation pour la soumission**.

## Informations de l'app (menu « Informations sur l'app »)

| Champ | À saisir |
|---|---|
| Nom (30 car. max) | `MaPile` (ou `MaPile – Lectures` si déjà pris) |
| Sous-titre (30 car. max) | `Livres lus, PAL et stats` |
| Catégorie principale | **Livres** |
| Catégorie secondaire | **Productivité** |
| Droits sur le contenu | « Non, l'app ne contient pas, n'affiche pas et n'accède pas à du contenu de tiers » est **faux** : répondre **Oui**, l'app affiche des couvertures et résumés de tiers, et cocher que vous avez les droits nécessaires (données fournies par les API publiques de Google Books et Open Library). |
| Classification par âge | Répondre **Aucun / Non** à toutes les questions → **4+** |

## Version 1.0

**Texte promotionnel** (170 car. max, modifiable sans nouvelle version)
```
Scannez le code-barres d'un livre et retrouvez couverture, résumé et note des lecteurs. Suivez votre pile à lire et vos objectifs de lecture.
```

**Description**
```
MaPile est l'app simple et élégante pour suivre vos lectures.

📚 VOTRE PILE À LIRE ET VOS LIVRES LUS
Retrouvez tous vos livres dans une belle galerie de couvertures, comme sur une étagère. Passez un livre de votre PAL à vos lectures terminées en un geste.

🔎 AJOUT INSTANTANÉ
Cherchez par titre, auteur ou ISBN, ou scannez simplement le code-barres au dos du livre. MaPile récupère automatiquement la couverture, le résumé, l'auteur, le nombre de pages et la note moyenne des lecteurs, en privilégiant l'édition française.

⭐ VOS NOTES ET VOS AVIS
Notez chaque livre de 1 à 5 étoiles, écrivez votre avis et gardez la date de fin de lecture.

📊 VOS STATISTIQUES
Fixez-vous un objectif annuel et suivez votre progression : livres et pages lus par mois et par année, auteurs les plus lus, genres préférés, répartition de vos notes.

📱 PENSÉE POUR iOS 26
Interface Liquid Glass, mode sombre, et affichage adapté aux grands écrans et à l'iPhone pliable.

🔒 RESPECT DE VOTRE VIE PRIVÉE
Aucun compte, aucune publicité, aucun suivi. Votre bibliothèque reste sur votre iPhone.

Informations sur les livres fournies par Google Books et Open Library.
```

**Mots-clés** (100 car. max, séparés par des virgules, sans espaces)
```
lecture,livres,pal,pile à lire,bibliothèque,roman,isbn,scan,avis,notes,objectif,suivi,lecteur
```

**URL d'assistance** : `https://mapile.pages.dev/`
**URL de la politique de confidentialité** : `https://mapile.pages.dev/confidentialite`
**Copyright** : `2026 <votre prénom et nom>`

**Captures d'écran** : section « iPhone 6,9 pouces » (fournies par Claude, 1320 × 2868).

**Build** : cliquer sur « + » et choisir le dernier build Codemagic.

## Informations pour la vérification (App Review)

- Connexion requise : **non** (décocher)
- Coordonnées : vos prénom, nom, téléphone, e-mail (non publiés)
- Remarques :
```
MaPile n'a pas de compte utilisateur : toutes les données restent sur l'appareil.
Pour tester : onglet « Ajouter » (loupe), rechercher par exemple « Le Petit Prince », ouvrir un résultat puis « Ajouter à ma PAL ». Le bouton « Scanner » lit le code-barres ISBN d'un livre. Sur une fiche, « J'ai fini ! » déplace le livre dans « Lus ». L'onglet Statistiques se remplit avec les livres lus.
Les informations sur les livres proviennent des API publiques Google Books et Open Library.
```

## Confidentialité de l'app (menu « Confidentialité de l'app »)

- URL de la politique : `https://mapile.pages.dev/confidentialite`
- « Collectez-vous des données à partir de cette app ? » → **Non, nous ne collectons pas de données à partir de cette app**
- Résultat affiché : **Données non collectées**

## Tarifs et disponibilité

- Prix : **Gratuit (0 €)**
- Disponibilité : tous les pays (ou seulement les pays francophones si vous préférez)

## Conformité UE (Digital Services Act)

- Statut de commerçant : **« Je ne suis pas un commerçant »** (app gratuite, sans publicité ni achat intégré, activité non professionnelle).
- ⚠️ Si vous ajoutez des publicités plus tard, il faudra probablement passer en **commerçant** : votre nom, adresse, téléphone et e-mail seront alors affichés publiquement en Europe.

## Chiffrement (export)

Déjà réglé dans l'app (`ITSAppUsesNonExemptEncryption = NO`) : aucune question à remplir.
