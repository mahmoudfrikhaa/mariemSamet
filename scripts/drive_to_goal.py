"""Envoie un but a Autoware, passe en mode autonome et mesure le trajet.

Execute DANS le conteneur Autoware (voir scripts/60_drive_awsim.sh).
Arguments : GOAL_X GOAL_Y GOAL_QZ GOAL_QW [WATCH_SECONDS]
"""
import math
import sys
import time

import rclpy
from autoware_adapi_v1_msgs.msg import OperationModeState, RouteState
from autoware_adapi_v1_msgs.srv import ChangeOperationMode, SetRoutePoints
from nav_msgs.msg import Odometry
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy

gx, gy, qz, qw = map(float, sys.argv[1:5])
watch = float(sys.argv[5]) if len(sys.argv) > 5 else 180.0

rclpy.init()
n = Node('drive_to_goal')
st = {'op': None, 'route': None, 'pose': None, 'vmax': 0.0, 'start': None}
tl = QoSProfile(depth=1, durability=DurabilityPolicy.TRANSIENT_LOCAL,
                reliability=ReliabilityPolicy.RELIABLE)


def on_odom(m):
    p = m.pose.pose.position
    st['pose'] = (p.x, p.y)
    st['start'] = st['start'] or (p.x, p.y)
    st['vmax'] = max(st['vmax'], abs(m.twist.twist.linear.x))


n.create_subscription(Odometry, '/localization/kinematic_state', on_odom, 10)
n.create_subscription(OperationModeState, '/api/operation_mode/state',
                      lambda m: st.__setitem__('op', m), tl)
n.create_subscription(RouteState, '/api/routing/state',
                      lambda m: st.__setitem__('route', m.state), tl)


def spin(seconds):
    t = time.time()
    while time.time() - t < seconds:
        rclpy.spin_once(n, timeout_sec=0.1)


def call(srv_type, name, req, timeout=60.0):
    cli = n.create_client(srv_type, name)
    if not cli.wait_for_service(timeout_sec=timeout):
        return None
    fut = cli.call_async(req)
    rclpy.spin_until_future_complete(n, fut, timeout_sec=timeout)
    return fut.result()


spin(3)
print(f"Position de depart : {st['pose']}", flush=True)

print('--- 1. Itineraire ---', flush=True)
req = SetRoutePoints.Request()
req.header.frame_id = 'map'
req.goal.position.x, req.goal.position.y = gx, gy
req.goal.orientation.z, req.goal.orientation.w = qz, qw
for attempt in range(10):
    res = call(SetRoutePoints, '/api/routing/set_route_points', req)
    # Une reponse perdue (machine chargee) peut avoir quand meme pose la route.
    if res and (res.status.success or 'already set' in res.status.message):
        print('itineraire accepte', flush=True)
        break
    print(f"refuse ({res.status.message if res else 'service absent'}), nouvel essai...", flush=True)
    spin(5)
else:
    sys.exit('ECHEC : itineraire refuse')

print('--- 2. Attente du mode autonome ---', flush=True)
t = time.time()
while time.time() - t < 180:
    spin(1)
    if st['op'] and st['op'].is_autonomous_mode_available:
        print('mode autonome disponible', flush=True)
        break
else:
    print('mode autonome toujours indisponible, tentative quand meme', flush=True)

print('--- 3. Engagement ---', flush=True)
for attempt in range(12):
    res = call(ChangeOperationMode, '/api/operation_mode/change_to_autonomous',
               ChangeOperationMode.Request())
    if res and res.status.success:
        print('PASSAGE EN AUTONOME ACCEPTE', flush=True)
        break
    print(f"refuse ({res.status.message if res else 'service absent'}), nouvel essai dans 5 s", flush=True)
    spin(5)
else:
    sys.exit('ECHEC : passage en autonome refuse')

print(f'--- 4. Observation ({watch:.0f} s max) ---', flush=True)
st['start'] = st['pose']
t, last = time.time(), 0
while time.time() - t < watch:
    spin(1)
    if time.time() - last >= 10 and st['pose']:
        last = time.time()
        d = math.dist(st['start'], st['pose'])
        togo = math.dist(st['pose'], (gx, gy))
        print(f"  parcouru {d:6.1f} m | reste {togo:6.1f} m | vmax {st['vmax'] * 3.6:4.1f} km/h", flush=True)
    if st['route'] == RouteState.ARRIVED:
        break

d = math.dist(st['start'], st['pose'])
print(f"distance parcourue : {d:.1f} m, vitesse max {st['vmax'] * 3.6:.1f} km/h", flush=True)
print('RESULTAT : ' + ('ARRIVE AU BUT' if st['route'] == RouteState.ARRIVED
                        else 'le vehicule roule' if d > 1 else 'le vehicule ne bouge pas'), flush=True)
