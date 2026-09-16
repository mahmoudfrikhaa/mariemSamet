#!/usr/bin/env bash
# Test automatise de conduite autonome (sans clic dans RViz).
#
# Autoware doit deja tourner (make psim, ou make autoware avec AWSIM).
# Le script utilise l'AD API d'Autoware pour :
#   1. initialiser la localisation a un point de la carte Shinjuku,
#   2. definir un itineraire vers un but situe ~300 m plus loin,
#   3. passer en mode autonome,
#   4. mesurer la distance reellement parcourue.
#
# Les coordonnees par defaut sont le debut et la fin du plus long troncon
# routier de la carte Nishi-Shinjuku (repere "map", projection MGRS 54SUE).
source "$(dirname "$0")/_common.sh"

# Points calcules sur la ligne centrale du plus long troncon routier de la carte
# (repere "map", projection MGRS 54SUE) : 15 m apres son debut et 15 m avant sa
# fin, avec l'orientation tangente a la voie. Le planificateur refuse un but qui
# ne tombe pas sur une voie, orientation comprise.
START_X="${START_X:-82202.464}"; START_Y="${START_Y:-50472.469}"
START_QZ="${START_QZ:-0.987690}"; START_QW="${START_QW:-0.156425}"
GOAL_X="${GOAL_X:-81901.366}";   GOAL_Y="${GOAL_Y:-50447.257}"
GOAL_QZ="${GOAL_QZ:--0.996818}"; GOAL_QW="${GOAL_QW:-0.079716}"
WATCH_SECONDS="${WATCH_SECONDS:-60}"

title "Test de conduite autonome"
info "Depart  : ($START_X, $START_Y)  distance ~300 m"
info "But     : ($GOAL_X, $GOAL_Y)"
info "Duree d'observation : ${WATCH_SECONDS} s"

cd "$PROJECT_DIR/docker"
HOST_UID=$(id -u) HOST_GID=$(id -g) AUTOWARE_IMAGE="$AUTOWARE_IMAGE" \
docker compose -f "$PROJECT_DIR/docker/awsim.compose.yaml" run --rm -T shell bash -c "
set -e
source /opt/autoware/setup.bash

echo '--- 1. Initialisation de la localisation ---'
ros2 service call /api/localization/initialize \
  autoware_adapi_v1_msgs/srv/InitializeLocalization \
  '{pose: [{header: {frame_id: map}, pose: {pose: {position: {x: $START_X, y: $START_Y, z: 0.0}, orientation: {x: 0.0, y: 0.0, z: $START_QZ, w: $START_QW}}, covariance: [0.25,0,0,0,0,0, 0,0.25,0,0,0,0, 0,0,0.25,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0.07]}}]}' \
  | tail -3

sleep 5
echo '--- 2. Definition de l itineraire ---'
ros2 service call /api/routing/set_route_points \
  autoware_adapi_v1_msgs/srv/SetRoutePoints \
  '{header: {frame_id: map}, goal: {position: {x: $GOAL_X, y: $GOAL_Y, z: 0.0}, orientation: {x: 0.0, y: 0.0, z: $GOAL_QZ, w: $GOAL_QW}}, waypoints: []}' \
  | tail -3

echo '--- 3. Attente que la planification produise une trajectoire ---'
# Le mode autonome n'est propose qu'une fois la trajectoire publiee de facon
# stable ; sur une machine chargee cela demande une trentaine de secondes.
for i in \$(seq 1 40); do
  if timeout 10 ros2 topic echo --once /api/operation_mode/state 2>/dev/null \
     | grep -q 'is_autonomous_mode_available: true'; then
    echo 'mode autonome disponible'; break
  fi
  sleep 3
done

echo '--- 4. Passage en mode autonome ---'
# La disponibilite du mode peut osciller pendant que la pile se stabilise :
# on reessaie plutot que d'abandonner au premier refus.
for i in \$(seq 1 12); do
  OUT=\$(ros2 service call /api/operation_mode/change_to_autonomous \
         autoware_adapi_v1_msgs/srv/ChangeOperationMode '{}' 2>&1 | tail -2)
  echo \$OUT | grep -q 'success=True' && { echo 'PASSAGE EN AUTONOME ACCEPTE'; break; }
  echo 'refuse, nouvelle tentative dans 5 s...'
  sleep 5
done

echo '--- 5. Observation du deplacement ---'
python3 - <<'PYEOF'
import rclpy, math, time
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from nav_msgs.msg import Odometry

rclpy.init()
n = Node('drive_watch')
n.set_parameters([rclpy.parameter.Parameter('use_sim_time', value=False)])
state = {'first': None, 'last': None, 'vmax': 0.0, 'n': 0}

def cb(msg):
    p = msg.pose.pose.position
    v = msg.twist.twist.linear.x
    if state['first'] is None:
        state['first'] = (p.x, p.y)
    state['last'] = (p.x, p.y)
    state['vmax'] = max(state['vmax'], abs(v))
    state['n'] += 1

qos = QoSProfile(depth=10, reliability=ReliabilityPolicy.RELIABLE, history=HistoryPolicy.KEEP_LAST)
n.create_subscription(Odometry, '/localization/kinematic_state', cb, qos)

t0 = time.time()
while time.time() - t0 < $WATCH_SECONDS:
    rclpy.spin_once(n, timeout_sec=0.5)

if state['n'] == 0:
    print('AUCUNE donnee de position recue')
else:
    d = math.dist(state['first'], state['last'])
    print(f\"messages recus : {state['n']}\")
    print(f\"distance parcourue : {d:.2f} m\")
    print(f\"vitesse max : {state['vmax']:.2f} m/s ({state['vmax']*3.6:.1f} km/h)\")
    print('RESULTAT : ' + ('le vehicule roule' if d > 1.0 else 'le vehicule ne bouge pas'))
PYEOF
"
