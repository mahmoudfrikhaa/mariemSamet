# Simulation Autoware + AWSIM

Faire rouler une voiture autonome en simulation : **AWSIM** (simulateur Unity — une
Lexus RX450h dans le quartier de Nishi-Shinjuku à Tokyo, avec LiDAR, caméra, GNSS et IMU)
piloté par **Autoware** (pile de conduite autonome ROS 2, exécutée dans Docker).

```
┌──────────────────────── Ubuntu (natif ou WSL2) ────────────────────────┐
│                                                                         │
│   AWSIM-Demo.x86_64  ──────► capteurs simulés (LiDAR, caméra, GNSS…)    │
│   (Unity, Vulkan)     ◄────── commandes véhicule                        │
│          ▲                                                              │
│          │  ROS 2 / FastDDS (loopback + mémoire partagée)               │
│          ▼                                                              │
│   Conteneur Docker : Autoware (ROS 2 Humble) + RViz                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

Toutes les commandes passent par le `Makefile`. `make` sans argument affiche la liste.

---

## Prérequis

| | Recommandé |
|---|---|
| Système | **Ubuntu installé nativement** (22.04 ou plus récent) — WSL2 possible mais limité, voir plus bas |
| GPU | NVIDIA avec pilote **570 ou plus récent** (testé sur GTX 1650 4 Go) |
| RAM | 16 Go minimum, 32 Go conseillés |
| Disque | ~40 Go libres (simulateur, carte, modèles, image Docker) |
| Réseau | connexion rapide pour le premier téléchargement (~35 Go) |

Pilote NVIDIA sur Ubuntu natif, si ce n'est pas déjà fait :

```bash
sudo ubuntu-drivers autoinstall
sudo apt install libvulkan1
sudo reboot
```

---

## Lancer le projet — Ubuntu natif

```bash
git clone https://github.com/mahmoudfrikhaa/mariemSamet.git
cd mariemSamet

make native-setup   # 1. paquets, Docker, NVIDIA Container Toolkit, réglages réseau DDS (sudo)
                    #    → fermez puis rouvrez la session (ajout au groupe docker)
make download       # 2. simulateur AWSIM, carte, modèles, image Docker Autoware (~35 Go, une fois)
make check          # 3. diagnostic : tout doit être vert
```

Puis, dans **trois terminaux**, dans cet ordre :

```bash
make awsim      # terminal 1 — le simulateur (TOUJOURS en premier)
make autoware   # terminal 2 — Autoware + RViz
make drive      # terminal 3 — conduite autonome automatique (but calculé à ~200 m)
```

⏳ **Premier lancement d'Autoware : 10 à 30 minutes.** Autoware compile les moteurs
TensorRT des modèles de perception pour votre GPU. C'est fait une seule fois ; ensuite le
démarrage prend moins d'une minute.

### Conduire à la main depuis RViz (au lieu de `make drive`)

1. Attendre que le nuage de points LiDAR se **superpose** à la carte (localisation NDT
   convergée). Sinon, outil **`2D Pose Estimate`** pour replacer approximativement la voiture.
2. Outil **`2D Goal Pose`** : cliquer-glisser sur une route, dans le sens de circulation.
   Une trajectoire verte apparaît.
3. `make engage` (ou bouton **AUTO** du panneau *AutowareStatePanel*).

> ⚠️ Attendre que la trajectoire soit affichée **avant** de passer en AUTO. Sinon une
> manœuvre de sécurité (MRM) fige la limite de vitesse à 0 et la voiture ne repart plus :
> il faut alors relancer `make autoware`.

### Options utiles

```bash
DISTANCE=400 make drive                  # but plus lointain
GOAL="x y qz qw" make drive              # but imposé (repère map)
WIDTH=640 HEIGHT=480 make awsim          # fenêtre plus petite = plus fluide
./scripts/30_run_awsim.sh --igpu         # PC hybride : rendu Unity sur le GPU Intel
./scripts/30_run_awsim.sh --nvidia       # PC hybride : rendu sur le GPU NVIDIA
AW_LAUNCH_ARGS="perception:=false" make autoware   # mode dégradé (moins de VRAM)
```

Sur un **PC portable hybride Intel + NVIDIA avec moins de 8 Go de VRAM**, `make awsim`
fait automatiquement le rendu Unity sur le GPU Intel pour laisser le GPU NVIDIA au LiDAR
(OptiX) et à la perception. Mesuré sur GTX 1650 4 Go : rendu NVIDIA = 3,7 Go de VRAM et
LiDAR en *out of memory* ; rendu Intel = 0,5 Go et LiDAR fonctionnel.

Réglages de la simulation (trafic, position de départ, vitesse du temps simulé) :
`config/awsim-config.json`.

---

## Lancer le projet — WSL2 (Windows)

```bash
make setup          # 1. paquets + réglages réseau (sudo)
make docker-native  # 2. moteur Docker natif dans la distro — obligatoire, voir ci-dessous
                    #    → fermez et rouvrez le terminal
make download       # 3. ~35 Go
make check          # 4. diagnostic

make psim           # conduite autonome dans RViz (fonctionne en temps réel sous WSL)
make test           # même chose, entièrement automatisée, avec mesure du trajet
```

Limites de WSL2, constatées et documentées dans [`docs/diagnostic-wsl.md`](docs/diagnostic-wsl.md) :

- **Rendu AWSIM logiciel** : le build n'accepte que Vulkan, et WSL n'expose aucun Vulkan
  matériel NVIDIA → quelques images par seconde.
- **LiDAR AWSIM impossible** : il repose sur NVIDIA OptiX, que WSL n'expose pas. Sans
  LiDAR, pas de localisation ni de perception → la démo AWSIM complète exige Ubuntu natif.
- **Docker Desktop inutilisable** : son réseau `--network host` est isolé de la distro, AWSIM
  et Autoware ne se verraient pas. `make docker-native` installe un moteur Docker dans la
  distro, sans toucher à Docker Desktop (`docker context use default` pour y revenir).

Conseillé : copier `config/wslconfig.sample` vers `C:\Users\<vous>\.wslconfig`, puis
`wsl --shutdown` dans PowerShell, pour donner plus de RAM à WSL.

---

## Plan B : `make psim` (sans AWSIM)

Lance le **planning simulator** d'Autoware : même carte, même localisation / planification /
contrôle, même RViz, mais le véhicule est simulé par Autoware lui-même (ni Unity, ni LiDAR).
Fonctionne partout, y compris sous WSL.

1. `make psim`, attendre que RViz affiche la carte (~1 min).
2. **`2D Pose Estimate`** pour poser la voiture, puis **`2D Goal Pose`** pour le but.
3. Bouton **AUTO** une fois la trajectoire affichée.

Version sans clic : `make test` — résultat obtenu : **302 m parcourus** en autonomie,
jusqu'à 15,5 km/h, arrêt au but à 2 cm près.

---

## Toutes les commandes

| Commande | Rôle |
|---|---|
| `make native-setup` | (Ubuntu natif) paquets, Docker, GPU, réseau DDS |
| `make setup` / `make docker-native` | (WSL) équivalent en deux étapes |
| `make download` | tout télécharger (= `awsim-dl` + `map` + `models` + `pull`) |
| `make models-all` | catalogue complet des modèles (très volumineux) |
| `make check` | diagnostic de la machine |
| `make awsim` | lance le simulateur |
| `make autoware` | lance Autoware + RViz |
| `make engage` | passe en mode autonome (but posé dans RViz) |
| `make drive` | but calculé automatiquement + conduite autonome |
| `make psim` / `make test` | plan B sans AWSIM |
| `make shell` | shell ROS 2 dans le conteneur |
| `make topics` / `make hz` | liste des topics / fréquence du LiDAR (~10 Hz attendu) |
| `make clean-cache` | supprime les archives téléchargées |

## Où est installé quoi

| Chemin | Contenu |
|---|---|
| `~/awsim/` | simulateur AWSIM v2.0.1 (variante *Lightweight*) |
| `~/autoware_data/maps/Shinjuku-Map/map/` | carte Shinjuku v2.0.0 (`pointcloud_map.pcd`, `lanelet2_map.osm`) |
| `~/autoware_data/ml_models/` | modèles de perception |
| `~/Downloads/awsim/` | archives (supprimables avec `make clean-cache`) |
| image `ghcr.io/autowarefoundation/autoware:universe-cuda-humble` | Autoware compilé (~20 Go) |

Versions et chemins sont définis dans `scripts/_common.sh`.

## Organisation du dépôt

```
Makefile              point d'entrée de toutes les commandes
scripts/              installation (1x), téléchargement (2x), lancement (3x-6x), plan B (9x)
config/               profils FastDDS, réglages AWSIM, exemple .wslconfig
docker/               Compose Autoware (+ complément WSL chargé automatiquement)
docs/                 diagnostic détaillé WSL
```

---

## Dépannage

| Symptôme | Cause et solution |
|---|---|
| `make topics` ne montre aucun topic AWSIM | AWSIM non lancé ; `ROS_LOCALHOST_ONLY` défini quelque part (à supprimer) ; sous WSL, contexte Docker `awsim-native` non sélectionné (`docker context ls`). |
| AWSIM se ferme aussitôt | Lire `/tmp/awsim.log`. Vérifier qu'un pilote Vulkan est présent : `ls /usr/share/vulkan/icd.d/`. |
| `shaders will not be available` | AWSIM lancé en OpenGL (`--gl`) : ce build est Vulkan uniquement, utiliser `make awsim`. |
| LiDAR absent / *out of memory* | VRAM insuffisante : `./scripts/30_run_awsim.sh --igpu`, fenêtre plus petite, ou `AW_LAUNCH_ARGS="perception:=false"`. |
| Localisation qui ne converge pas | `2D Pose Estimate` dans RViz pour replacer la voiture ; NDT affine ensuite. |
| La voiture ne démarre pas, `max_velocity: 0.0` | MRM déclenchée (AUTO trop tôt) : relancer Autoware et attendre la trajectoire. |
| La voiture ne démarre pas | Vérifier `ros2 topic echo --once /api/operation_mode/state` dans `make shell` (`is_autonomous_mode_available: true`). |
| Fenêtre RViz noire ou absente | `xhost +local:docker` et vérifier `echo $DISPLAY`. |
| Nuages de points hachés | Réglages DDS non appliqués : relancer le setup ; `sysctl net.core.rmem_max` doit valoir 2147483647. |
| Diagnostics Autoware « STALE » | Machine surchargée : fermer les autres applications, réduire la fenêtre AWSIM. |
| Échec au lancement d'Autoware lié à `centerpoint` | Mauvaise version des modèles : `make models` (v3.0 attendue par l'image Humble). |

## Références

- [Démo de démarrage AWSIM](https://autowarefoundation.github.io/AWSIM/GettingStarted/QuickStartDemo/)
- [Documentation Autoware](https://docs.autoware.org/)
- [Images Docker Autoware](https://github.com/autowarefoundation/autoware/tree/main/docker)
- [Réglages DDS pour ROS 2](https://autowarefoundation.github.io/autoware-documentation/main/installation/additional-settings-for-developers/network-configuration/dds-settings/)
