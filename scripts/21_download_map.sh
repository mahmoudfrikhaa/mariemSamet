#!/usr/bin/env bash
# Telecharge la carte Nishi-Shinjuku utilisee par Autoware
# (nuage de points .pcd + carte vectorielle Lanelet2 .osm).
source "$(dirname "$0")/_common.sh"

URL="https://github.com/autowarefoundation/AWSIM/releases/download/${AWSIM_MAP_VERSION}/Shinjuku-Map.zip"
CACHE="$HOME/Downloads/awsim"
mkdir -p "$CACHE" "$AW_DATA_DIR/maps"

title "Carte Shinjuku ${AWSIM_MAP_VERSION}"

if [ -f "$MAP_DIR/map/lanelet2_map.osm" ] && [ "${FORCE:-0}" != "1" ]; then
  ok "Deja installee : $MAP_DIR/map"
  exit 0
fi

wget -c -O "$CACHE/Shinjuku-Map.zip" "$URL"
TMP=$(mktemp -d)
unzip -q -o "$CACHE/Shinjuku-Map.zip" -d "$TMP"

# L'archive peut contenir un niveau de dossier supplementaire : on localise le
# repertoire qui contient reellement lanelet2_map.osm.
SRC=$(dirname "$(find "$TMP" -name 'lanelet2_map.osm' | head -1)")
[ -n "$SRC" ] && [ -d "$SRC" ] || die "lanelet2_map.osm introuvable dans l'archive."

rm -rf "$MAP_DIR"
mkdir -p "$MAP_DIR"
cp -r "$SRC" "$MAP_DIR/map"
rm -rf "$TMP"

title "Contenu installe"
ls -la "$MAP_DIR/map" | sed 's/^/       /'
[ -f "$MAP_DIR/map/pointcloud_map.pcd" ] || warn "pointcloud_map.pcd absent : verifiez le nom des fichiers (arg pointcloud_map_file)."
ok "Carte prete : $MAP_DIR/map"
