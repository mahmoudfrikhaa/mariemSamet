#!/usr/bin/env bash
# Conduite autonome dans AWSIM, sans aucun clic.
# AWSIM et Autoware doivent tourner (make awsim, puis make autoware).
#
# Le script lit la position actuelle du vehicule, calcule sur la carte
# Lanelet2 un but situe DISTANCE metres plus loin le long des voies, puis
# l'envoie a Autoware, passe en mode autonome et suit le trajet.
#
# Usage :
#   scripts/60_drive_awsim.sh               # but a ~200 m
#   DISTANCE=400 scripts/60_drive_awsim.sh
#   GOAL="x y qz qw" scripts/60_drive_awsim.sh   # but impose (repere map)
source "$(dirname "$0")/_common.sh"

CTR=autoware_awsim
DISTANCE="${DISTANCE:-200}"
WATCH_SECONDS="${WATCH_SECONDS:-240}"
docker inspect "$CTR" >/dev/null 2>&1 || die "Conteneur $CTR absent : lancez d'abord 'make autoware'."

# Meme utilisateur qu'Autoware dans le conteneur : avec le transport par
# memoire partagee, un processus root ne recevrait rien (droits sur /dev/shm).
EXEC=(docker exec -i -u "$(id -u):$(id -g)" -e HOME=/tmp "$CTR")
ros_py() { "${EXEC[@]}" bash -c "source /opt/autoware/setup.bash && python3 - $*" 2>&1 | grep --line-buffered -v '^\[WARN\]'; }

title "Position actuelle du vehicule"
POSE=$(ros_py <<'EOF'
import math, time, rclpy
from nav_msgs.msg import Odometry
rclpy.init(); n = rclpy.create_node('pose_probe'); out = {}
n.create_subscription(Odometry, '/localization/kinematic_state', lambda m: out.setdefault('p', m.pose.pose), 10)
t = time.time()
while 'p' not in out and time.time() - t < 20: rclpy.spin_once(n, timeout_sec=0.2)
p = out.get('p')
if p: print(f"{p.position.x} {p.position.y} {2 * math.atan2(p.orientation.z, p.orientation.w)}")
EOF
)
POSE=$(echo "$POSE" | tail -1)
[ -n "$POSE" ] && [ "$(echo "$POSE" | wc -w)" = 3 ] || die "Pas de position : la localisation n'a pas converge (voir RViz)."
info "x y cap : $POSE"

if [ -z "${GOAL:-}" ]; then
  title "Calcul du but (~${DISTANCE} m le long des voies)"
  GOAL=$(python3 "$PROJECT_DIR/scripts/lanelet_goal.py" "$MAP_DIR/map/lanelet2_map.osm" $POSE "$DISTANCE")
fi
info "But (x y qz qw) : $GOAL"

title "Conduite autonome"
"${EXEC[@]}" bash -c "source /opt/autoware/setup.bash && python3 - $GOAL $WATCH_SECONDS" \
  < "$PROJECT_DIR/scripts/drive_to_goal.py" 2>&1 | grep --line-buffered -v '^\[WARN\]'
