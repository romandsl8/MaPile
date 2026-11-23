#!/bin/bash
# Habille les captures pour l'App Store : fond dégradé MaPile, accroche en haut, capture arrondie.
# Usage : frame_screenshots.sh <dossier des captures> <dossier de sortie>
set -euo pipefail
IN=$1
OUT=$2
mkdir -p "$OUT"

FONT="${FONT:-/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf}"
[ -f "$FONT" ] || FONT="DejaVu-Sans-Bold"
IM=$(command -v magick || command -v convert)
IDENT() { if command -v magick >/dev/null; then magick identify "$@"; else identify "$@"; fi; }

W=1320; H=2868
SHOT_W=1080
TOP=600

frame() { # nom-capture accroche
  local NAME=$1 TEXT=$2
  local SRC="$IN/$NAME.png"
  [ -f "$SRC" ] || { echo "manque $SRC"; return; }
  local TMP; TMP=$(mktemp -d)
  $IM "$SRC" -resize ${SHOT_W}x "$TMP/shot.png"
  local SW SH; SW=$(IDENT -format %w "$TMP/shot.png"); SH=$(IDENT -format %h "$TMP/shot.png")
  # Coins arrondis
  $IM -size ${SW}x${SH} xc:none -fill white -draw "roundrectangle 0,0 $((SW-1)),$((SH-1)) 64,64" "$TMP/mask.png"
  $IM "$TMP/shot.png" "$TMP/mask.png" -alpha off -compose CopyOpacity -composite "$TMP/rounded.png"
  # Ombre douce
  $IM "$TMP/rounded.png" \( +clone -background black -shadow 45x28+0+18 \) +swap -background none -layers merge +repage "$TMP/shadowed.png"
  # Fond + accroche + capture
  $IM -size ${W}x${H} gradient:'#F28C57'-'#7A2E55' \
    \( -size 1160x$((TOP-110)) -background none -fill white -font "$FONT" -pointsize 92 -gravity center caption:"$TEXT" \) \
    -gravity north -geometry +0+70 -composite \
    "$TMP/shadowed.png" -gravity north -geometry +0+$((TOP-20)) -composite \
    -alpha off "$OUT/$NAME.png"
  rm -rf "$TMP"
  echo "ok $NAME"
}

frame appstore-1-pal "Votre pile à lire, enfin belle"
frame appstore-2-encours "Chaque page et chaque minute comptent"
frame appstore-3-idees "Fini le « je lis quoi maintenant ? »"
frame appstore-4-saga "Chaque saga, dans le bon ordre"
frame appstore-5-stats "Vos stats de lecteur, mois après mois"
frame appstore-6-lus "Tous vos livres lus, notés et commentés"
frame appstore-7-sombre "Superbe, de jour comme de nuit"
