#!/usr/bin/env bash
# Passe le vehicule en conduite autonome, une fois qu'un but a ete defini
# (dans RViz avec "2D Goal Pose", ou par l'API).
#
# Equivaut au bouton AUTO du panneau AutowareStatePanel, mais avec l'attente
# necessaire : engager avant que la planification ne soit prete declenche une
# manoeuvre de securite qui immobilise durablement le vehicule (voir README).
source "$(dirname "$0")/_common.sh"

title "Passage en mode autonome"
info "Attente que la planification publie une trajectoire stable, puis engagement."

cd "$PROJECT_DIR/docker"
HOST_UID=$(id -u) HOST_GID=$(id -g) AUTOWARE_IMAGE="$AUTOWARE_IMAGE" \
docker compose run --rm -T shell bash -c '
source /opt/autoware/setup.bash

for i in $(seq 1 40); do
  if timeout 10 ros2 topic echo --once /api/operation_mode/state 2>/dev/null \
     | grep -q "is_autonomous_mode_available: true"; then
    echo "Mode autonome disponible."; break
  fi
  echo "En attente de la planification..."
  sleep 3
done

for i in $(seq 1 12); do
  OUT=$(ros2 service call /api/operation_mode/change_to_autonomous \
        autoware_adapi_v1_msgs/srv/ChangeOperationMode "{}" 2>&1 | tail -2)
  if echo "$OUT" | grep -q "success=True"; then
    echo "ENGAGE : le vehicule part vers son but."
    exit 0
  fi
  echo "Refuse, nouvelle tentative dans 5 s..."
  sleep 5
done

echo "ECHEC : le mode autonome reste indisponible."
echo "Verifiez : ros2 topic echo --once /planning/scenario_planning/max_velocity"
echo "Si max_velocity vaut 0.0, relancez Autoware (voir README, section Depannage)."
exit 1
'
