#!/usr/bin/env python3
"""Calcule un but valide pour Autoware, a une distance donnee le long des voies.

Part de la voie (lanelet) qui contient la position de depart, suit ses
successeurs sur la carte Lanelet2 et renvoie un point de la ligne centrale
avec l'orientation de la voie (le planificateur refuse un but hors voie ou
a contresens).

Usage : lanelet_goal.py MAP.osm X Y YAW_RAD [DISTANCE_M]
Sortie : "x y qz qw" sur une ligne.
"""
import math
import sys
import xml.etree.ElementTree as ET

osm, x0, y0, yaw0 = sys.argv[1], *map(float, sys.argv[2:5])
target = float(sys.argv[5]) if len(sys.argv) > 5 else 200.0

root = ET.parse(osm).getroot()
nodes = {}
for n in root.iter('node'):
    tags = {t.get('k'): t.get('v') for t in n.iter('tag')}
    if 'local_x' in tags:
        nodes[n.get('id')] = (float(tags['local_x']), float(tags['local_y']))
ways = {w.get('id'): [nodes[nd.get('ref')] for nd in w.iter('nd') if nd.get('ref') in nodes]
        for w in root.iter('way')}

lanelets = {}
for r in root.iter('relation'):
    tags = {t.get('k'): t.get('v') for t in r.iter('tag')}
    if tags.get('type') != 'lanelet' or tags.get('subtype', 'road') != 'road':
        continue
    m = {mb.get('role'): mb.get('ref') for mb in r.iter('member')}
    left, right = ways.get(m.get('left')), ways.get(m.get('right'))
    if not left or not right:
        continue
    k = max(len(left), len(right))
    def at(line, i):
        t = i / (k - 1) * (len(line) - 1)
        j = min(int(t), len(line) - 2)
        f = t - j
        return (line[j][0] + f * (line[j + 1][0] - line[j][0]), line[j][1] + f * (line[j + 1][1] - line[j][1]))
    center = [((a[0] + b[0]) / 2, (a[1] + b[1]) / 2) for a, b in (
        (at(left, i), at(right, i)) for i in range(k))]
    lanelets[r.get('id')] = {'left': m['left'], 'right': m['right'], 'lp': left, 'rp': right, 'c': center}

def contains(ll, x, y):
    poly = ll['lp'] + ll['rp'][::-1]
    inside = False
    for (xa, ya), (xb, yb) in zip(poly, poly[1:] + poly[:1]):
        if (ya > y) != (yb > y) and x < xa + (y - ya) * (xb - xa) / (yb - ya):
            inside = not inside
    return inside

def heading(c):
    return math.atan2(c[-1][1] - c[0][1], c[-1][0] - c[0][0])

def yaw_gap(i):
    return abs(math.remainder(heading(lanelets[i]['c']) - yaw0, 2 * math.pi))


cands = [i for i, ll in lanelets.items() if contains(ll, x0, y0)]
cands.sort(key=yaw_gap)
if not cands or yaw_gap(cands[0]) > math.pi / 2:
    # Localisation un peu decalee (bord de voie) : voie la plus proche dans le bon sens.
    near = [i for i in lanelets if yaw_gap(i) < math.pi / 2]
    cands = sorted(near, key=lambda i: min(math.dist(p, (x0, y0)) for p in lanelets[i]['c']))[:1]
if not cands:
    sys.exit('aucune voie trouvee pres du point de depart')

# Successeur : voie dont le debut des bordures coincide avec la fin des notres.
start_index = {}
for i, ll in lanelets.items():
    start_index.setdefault((round(ll['lp'][0][0], 2), round(ll['lp'][0][1], 2),
                            round(ll['rp'][0][0], 2), round(ll['rp'][0][1], 2)), []).append(i)

def successors(i):
    ll = lanelets[i]
    key = (round(ll['lp'][-1][0], 2), round(ll['lp'][-1][1], 2),
           round(ll['rp'][-1][0], 2), round(ll['rp'][-1][1], 2))
    return start_index.get(key, [])

cur, travelled, seen = cands[0], 0.0, set()
pts = lanelets[cur]['c']
# on ne compte que la partie de la premiere voie situee devant le vehicule
j0 = min(range(len(pts)), key=lambda j: math.dist(pts[j], (x0, y0)))
path = pts[j0:]
while True:
    seen.add(cur)
    length = sum(math.dist(a, b) for a, b in zip(path, path[1:]))
    if travelled + length >= target or not successors(cur):
        break
    travelled += length
    nxt = [s for s in successors(cur) if s not in seen]
    if not nxt:
        break
    # prefere la continuation la plus droite
    h = heading(lanelets[cur]['c'])
    cur = min(nxt, key=lambda s: abs(math.remainder(heading(lanelets[s]['c']) - h, 2 * math.pi)))
    path = lanelets[cur]['c']

# point final : au milieu de la derniere voie pour eviter les bords
c = lanelets[cur]['c']
mid = len(c) // 2
gx, gy = c[mid]
a, b = c[max(mid - 1, 0)], c[min(mid + 1, len(c) - 1)]
yaw = math.atan2(b[1] - a[1], b[0] - a[0])
print(f"{gx:.3f} {gy:.3f} {math.sin(yaw / 2):.6f} {math.cos(yaw / 2):.6f}")
print(f"# voie {cur}, ~{travelled + (len(c) and 0):.0f} m de voies suivies", file=sys.stderr)
