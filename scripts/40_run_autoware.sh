#!/usr/bin/env bash
# Lance Autoware (conteneur Docker) connecte a AWSIM.
# AWSIM doit deja tourner (scripts/30_run_awsim.sh).
#
# Usage :
#   scripts/40_run_autoware.sh
#   AW_LAUNCH_ARGS="perception:=false" scripts/40_run_autoware.sh   # mode degrade
source "$(dirname "$0")/_common.sh"

title "Verifications prealables"
[ -f "$MAP_DIR/map/lanelet2_map.osm" ] || die "Carte absente. Lancez : make map"
[ -d "$ML_MODELS_DIR" ] || die "Modeles absents. Lancez : make models"
docker image inspect "$AUTOWARE_IMAGE" >/dev/null 2>&1 || {
  warn "Image $AUTOWARE_IMAGE absente, telechargement (~20 Go)..."
  docker pull "$AUTOWARE_IMAGE"
}
if ! pgrep -f '\.x86_64' >/dev/null 2>&1; then
  warn "AWSIM ne semble pas demarre : Autoware attendra les capteurs indefiniment."
  info "Ouvrez un autre terminal et lancez 'make awsim' avant de continuer."
  read -r -p "Continuer quand meme ? [o/N] " a
  [[ "$a" =~ ^[oOyY]$ ]] || exit 1
fi
ok "Pret"

# Autorise les clients X11 du conteneur a s'afficher (RViz).
command -v xhost >/dev/null 2>&1 && xhost +local:docker >/dev/null 2>&1 || true

title "Demarrage d'Autoware"
info "Image : $AUTOWARE_IMAGE"
[ -n "${AW_LAUNCH_ARGS:-}" ] && info "Arguments additionnels : $AW_LAUNCH_ARGS"
info "Premier lancement : la construction des moteurs TensorRT peut prendre"
info "10 a 30 minutes. Ce n'est pas un blocage."

cd "$PROJECT_DIR/docker"
HOST_UID=$(id -u) HOST_GID=$(id -g) \
AUTOWARE_IMAGE="$AUTOWARE_IMAGE" \
AW_LAUNCH_ARGS="${AW_LAUNCH_ARGS:-}" \
  exec docker compose run --rm --name autoware_awsim autoware
