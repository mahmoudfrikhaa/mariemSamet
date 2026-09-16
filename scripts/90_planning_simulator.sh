#!/usr/bin/env bash
# PLAN B : conduite autonome sans AWSIM ni Unity.
# Autoware simule lui-meme le vehicule (planning_simulator) et tout se passe
# dans RViz : meme carte, meme pile de planification et de controle.
# Utile si le rendu Unity ne fonctionne pas sous WSL, ou pour travailler
# sans solliciter le GPU.
source "$(dirname "$0")/_common.sh"

[ -f "$MAP_DIR/map/lanelet2_map.osm" ] || die "Carte absente. Lancez : make map"
command -v xhost >/dev/null 2>&1 && xhost +local:docker >/dev/null 2>&1 || true

title "Planning simulator (sans AWSIM)"
info "Dans RViz : '2D Pose Estimate' pour poser la voiture, puis '2D Goal Pose'"
info "pour le but, et enfin le bouton AUTO du panneau AutowareStatePanel."

cd "$PROJECT_DIR/docker"
HOST_UID=$(id -u) HOST_GID=$(id -g) \
AUTOWARE_IMAGE="$AUTOWARE_IMAGE" \
AW_LAUNCH_ARGS="${AW_LAUNCH_ARGS:-}" \
  exec docker compose -f "$PROJECT_DIR/docker/awsim.compose.yaml" run --rm psim
