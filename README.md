# Simulation Autoware + AWSIM

Faire rouler une voiture autonome en simulation : **AWSIM** (le simulateur Unity — une
Lexus RX450h dans le quartier de Nishi-Shinjuku à Tokyo, avec LiDAR, caméra, GNSS et IMU)
piloté par **Autoware** (la pile logicielle de conduite autonome, en ROS 2).

On pose un but dans RViz, et la voiture y va toute seule : elle se localise, détecte les
obstacles, planifie sa trajectoire et s'arrête aux feux.

```
┌─────────────────── WSL2 / Ubuntu ────────────────────┐
│                                                       │
│   AWSIM-Demo.x86_64  ──────► capteurs simulés         │
│   (Unity, Vulkan)     ◄────── commandes véhicule      │
│          ▲                                            │
│          │  ROS 2 / FastDDS (loopback)                │
│          ▼                                            │
│   Conteneur Docker : Autoware                         │
│     ros2 launch autoware_launch e2e_simulator...      │
│     + RViz (affiché via WSLg)                         │
│                                                       │
└───────────────────────────────────────────────────────┘
```

> ## ⚠️ État sur cette machine (WSL2)
>
> Trois points ont été vérifiés en conditions réelles, pas supposés :
>
> | | |
> |---|---|
> | **Autoware** | ✅ **validé sur cette machine.** 102 nœuds, 557 topics, RViz en OpenGL matériel. Test automatisé (`make test`) : la voiture a parcouru **302 m en autonomie** jusqu'à 15,5 km/h et s'est arrêtée au but à 2 cm près. |
> | **AWSIM — rendu** | ⚠️ logiciel uniquement. Le build n'accepte que Vulkan, et WSL n'expose aucun Vulkan matériel NVIDIA → quelques images par seconde. |
> | **AWSIM — LiDAR** | ❌ **impossible sous WSL**. Le LiDAR d'AWSIM repose sur NVIDIA OptiX ; sous WSL, `libnvoptix.so.1` n'est qu'un chargeur qui n'expose pas l'API OptiX (`optixQueryFunctionTable` absent). Sans LiDAR, pas de localisation NDT ni de perception. |
>
> **Conclusion** : la démo AWSIM + Autoware complète demande un **Ubuntu installé nativement**
> avec un GPU NVIDIA. Tout est prêt et scripté ici pour ce jour-là — voir *Passer sur Ubuntu natif*.
> En attendant, `make psim` fournit sur cette machine une démonstration de conduite autonome
> Autoware complète et fluide.
>
> Les commandes et les sorties qui établissent ces constats sont réunies dans
> [`docs/diagnostic-wsl.md`](docs/diagnostic-wsl.md).

Autoware tourne dans **Docker** : cette machine est sous Ubuntu 26.04, or Autoware exige
ROS 2 Humble (Ubuntu 22.04). L'image officielle pré-compilée évite à la fois le problème de
version et plusieurs heures de compilation.

---

## Démarrage rapide

```bash
cd ~/projects/mariem_project

make setup          # 1. paquets + réglages réseau (demande le mot de passe sudo)
make docker-native  # 2. moteur Docker natif — obligatoire, voir plus bas
make download       # 3. simulateur, carte, modèles, image Docker (~35 Go, une fois)
make check          # 4. diagnostic : tout doit être vert

# Conduite autonome sur cette machine (fonctionne en temps réel) :
make psim

# Démo complète avec AWSIM (nécessite un Ubuntu natif + GPU NVIDIA, voir encadré) :
make awsim      # terminal 1 — le simulateur (à lancer EN PREMIER)
make autoware   # terminal 2 — Autoware + RViz
make engage     # terminal 3 — une fois le but défini dans RViz
```

`make` sans argument affiche la liste des commandes.

---

## Où est installé quoi

| Chemin | Contenu |
|---|---|
| `~/projects/mariem_project` | ce projet (scripts, configuration, doc) |
| contexte Docker `awsim-native` | moteur Docker natif de cette distribution WSL |
| `~/awsim/` | le simulateur AWSIM (binaire Unity) |
| `~/autoware_data/maps/Shinjuku-Map/map/` | carte : `pointcloud_map.pcd` + `lanelet2_map.osm` |
| `~/autoware_data/ml_models/` | modèles de perception (TensorRT/ONNX) |
| `~/Downloads/awsim/` | archives téléchargées (supprimables : `make clean-cache`) |
| image Docker `…/autoware:universe-cuda-humble` | Autoware compilé, ~20 Go |

Versions utilisées : **AWSIM v2.0.1** (variante *Lightweight*, rendu URP) et la carte
**Shinjuku v2.0.0**. Elles sont figées dans `scripts/_common.sh`.

---

## Les étapes en détail

### 1. `make setup`

Installe `mesa-utils`, `vulkan-tools`, `libvulkan1`, `python3-venv`… puis applique les
réglages réseau exigés par le transport DDS :

- `net.core.rmem_max = 2 Go` — sans cela les nuages de points LiDAR arrivent tronqués
  (la valeur par défaut d'Ubuntu, 208 Kio, est très insuffisante) ;
- `ipfrag_time` / `ipfrag_high_thresh` — réassemblage des gros datagrammes fragmentés ;
- multicast activé sur `lo` — c'est par la loopback que se font les échanges.

**Quelle implémentation DDS ?** AWSIM v2.0.1 embarque `ros2-for-unity` compilé avec
**FastDDS** (son journal affiche `RMW: rmw_fastrtps_cpp`). L'image Autoware, elle, est
réglée sur CycloneDDS par défaut : le projet la **bascule sur FastDDS**, sans quoi les deux
moitiés de la simulation ne se verraient pas. Le profil commun `config/fastdds.xml`
désactive la mémoire partagée et agrandit les tampons pour les nuages de points.

⚠️ Ne définissez **jamais** `ROS_LOCALHOST_ONLY=1` : cela casse la liaison avec AWSIM.

**Recommandé** : donner plus de mémoire à WSL. Copiez `config/wslconfig.sample` vers
`C:\Users\<vous>\.wslconfig`, puis dans PowerShell `wsl --shutdown`, et rouvrez le terminal.
Par défaut WSL ne reçoit que la moitié de la RAM de la machine.

### 2. `make docker-native` — indispensable

**Docker Desktop ne peut pas convenir ici.** Son moteur tourne dans une autre distribution
WSL : un conteneur lancé avec `--network host` se retrouve sur un réseau isolé
(`192.168.65.x`) qui ne peut même pas joindre cette distribution Ubuntu (`172.18.x.x`).
Or AWSIM publie ses capteurs en ROS 2 depuis cette distribution : sans pile réseau
commune, Autoware ne verrait jamais un seul topic. C'est vérifié, pas théorique.

Le script installe donc un **moteur Docker natif dans cette distribution**, où
`--network host` signifie vraiment « le réseau d'Ubuntu », loopback comprise.

C'est **non destructif** : Docker Desktop continue de fonctionner comme avant. Le moteur
natif écoute sur sa propre socket (`/run/docker-native.sock`) et s'utilise via un
contexte Docker dédié, que les scripts du projet sélectionnent automatiquement.

```bash
docker context use awsim-native   # moteur natif (ce projet)
docker context use default        # Docker Desktop (vos autres projets)
docker context ls                 # voir lequel est actif
```

Le script installe aussi le **NVIDIA Container Toolkit**, qui donne au moteur natif l'accès
au GPU. Après son exécution, **fermez et rouvrez le terminal** (ajout au groupe `docker`).

### 3. `make download`

Quatre téléchargements indépendants et reprenables (`make awsim-dl`, `map`, `models`, `pull`).
Les modèles de perception ne sont pas tous récupérés : seul le sous-ensemble utilisé par la
démo l'est (détection LiDAR, feux tricolores, initialisation de pose). `make models-all` récupère
le catalogue complet, bien plus volumineux.

### 4. `make check`

Diagnostic en 8 points. Le plus important :

- **Réseau conteneur ↔ hôte** : l'IP vue depuis un conteneur `--network host` doit être
  identique à celle de la distro. Sinon les topics d'AWSIM n'atteindront jamais Autoware.
- **Pilote Vulkan** : au moins un ICD doit être présent. Le diagnostic indique s'il est
  matériel (simulation temps réel) ou logiciel (simulation au ralenti — cas de cette machine).

### 5. `make awsim` — le simulateur

Toujours lancé **avant** Autoware, comme sur un vrai véhicule : les capteurs d'abord.

```bash
make awsim                              # Vulkan, 1280x720
WIDTH=640 HEIGHT=480 make awsim         # plus petit = plus fluide
./scripts/30_run_awsim.sh --software    # force le rendu logiciel
```

Journal de Unity : `/tmp/awsim.log`.

#### ⚠️ Le rendu se fait sur le processeur

Constat mesuré sur cette machine, pas une hypothèse :

- AWSIM v2 est un build Unity 6 / URP **compilé pour Vulkan uniquement**. Le lancer en
  OpenGL échoue immédiatement : *« Forced GfxDevice 'OpenGL Core' was not built from
  editor, shaders will not be available »*.
- Or **WSL n'offre aucun pilote Vulkan matériel pour les GPU NVIDIA**. Le seul pilote
  Vulkan présent est `llvmpipe`, qui rend les images sur le processeur.
  (L'OpenGL de WSL, lui, est bien accéléré par le GPU — mais AWSIM ne sait pas s'en servir.)

Conséquence : AWSIM **démarre et fonctionne**, mais à quelques images par seconde.
Ce n'est pas rédhibitoire pour autant : Autoware tourne en **temps simulé**
(`use_sim_time`), calé sur l'horloge `/clock` publiée par AWSIM. La simulation se déroule
donc **au ralenti**, mais reste cohérente — la voiture roule, se localise et planifie
correctement, simplement plus lentement que la réalité.

Pour une simulation en temps réel, il faut un Ubuntu installé nativement (pas WSL) avec un
GPU NVIDIA : là, le pilote Vulkan matériel est disponible et la même procédure s'applique
telle quelle. À défaut, `make psim` (plan B ci-dessous) tourne en temps réel dès maintenant.

### 6. `make autoware`

Démarre le conteneur (réseau de l'hôte, GPU, affichage WSLg) et lance :

```bash
ros2 launch autoware_launch e2e_simulator.launch.xml \
  vehicle_model:=sample_vehicle \
  sensor_model:=awsim_sensor_kit \
  map_path:=/home/aw/autoware_data/maps/Shinjuku-Map/map
```

⏳ **Au tout premier lancement, comptez 10 à 30 minutes** : Autoware compile les moteurs
TensorRT des modèles de perception pour votre GPU. Ce n'est pas un blocage, et c'est fait
une fois pour toutes. Les lancements suivants prennent moins d'une minute.

Pour passer des arguments supplémentaires :

```bash
AW_LAUNCH_ARGS="perception:=false" make autoware
```

### 7. Conduire

1. Dans RViz, attendez que le nuage de points du LiDAR se **superpose** à la carte :
   c'est la localisation (NDT) qui a convergé. La pose initiale est fournie par le GNSS
   simulé, il n'y a normalement rien à faire.
2. Cliquez sur **`2D Goal Pose`** dans la barre d'outils, puis sur la carte à l'endroit
   voulu (maintenez et tirez pour donner l'orientation). Une trajectoire verte apparaît.
3. `make engage` — ou le bouton **AUTO** du panneau *AutowareStatePanel* dans RViz.

La voiture démarre. La vitesse maximale par défaut est de **15 km/h**.

---

## Plan B : `make psim` — la démo qui fonctionne ici

`make psim` lance le **planning simulator** d'Autoware : la même carte Nishi-Shinjuku, la
même pile de localisation, planification et contrôle, le même RViz — mais le véhicule est
simulé par Autoware lui-même. **Ni Unity, ni Vulkan, ni LiDAR à lancer de rayons.**

### En mode graphique (RViz)

1. `make psim`, puis attendre que RViz affiche la carte (**~1 minute**) et que la
   planification démarre.
2. Outil **`2D Pose Estimate`** : cliquer-glisser sur une route pour poser la voiture
   (le sens de la flèche doit suivre le sens de circulation).
3. Outil **`2D Goal Pose`** : cliquer-glisser plus loin sur une route. Une trajectoire
   apparaît.
4. Panneau **AutowareStatePanel** : cliquer sur **AUTO** dès que le bouton est actif.

Le panneau `RecognitionResultOnImage` affiche « No Image » : c'est attendu, il n'y a pas de
caméra dans ce mode. Le curseur `Set Velocity Limit` est à 0 km/h — ne le déplacer que pour
y mettre une valeur réelle, sinon la voiture s'immobilise.

> ⚠️ **Attendre que la trajectoire soit affichée avant de passer en AUTO.** Si l'on engage
> trop tôt, un diagnostic en erreur déclenche une manœuvre de sécurité (MRM) qui fixe la
> limite de vitesse à 0 : la voiture reste alors immobile et ne repart plus, même une fois
> le problème résolu. Dans ce cas, relancer `make psim`.

### En mode automatique (sans aucun clic)

```bash
make test
```

Le script utilise l'AD API d'Autoware : il pose la voiture sur la carte, attend que la
planification soit prête, définit un but à ~300 m, passe en mode autonome et mesure la
distance réellement parcourue. Résultat obtenu sur cette machine :

```
--- 4. Passage en mode autonome ---
PASSAGE EN AUTONOME ACCEPTE
--- 5. Observation du deplacement ---
messages recus : 3548
distance parcourue : 302.01 m
vitesse max : 4.31 m/s (15.5 km/h)
RESULTAT : le vehicule roule
```

Le véhicule s'est arrêté au but à **2 cm près** (`/api/routing/state` = `ARRIVED`).

Les coordonnées de départ et d'arrivée sont calculées sur la ligne centrale du plus long
tronçon routier de la carte ; elles se surchargent par variables d'environnement
(`START_X`, `GOAL_X`, `WATCH_SECONDS`…).

## Dépannage

| Symptôme | Cause et solution |
|---|---|
| AWSIM tourne à quelques images/seconde | Attendu : le rendu est logiciel (voir § 5). Réduisez la fenêtre : `WIDTH=640 HEIGHT=480 make awsim`. La simulation reste cohérente, simplement au ralenti. |
| `shaders will not be available` puis plantage | Vous avez lancé AWSIM en OpenGL (`--gl`). Ce build ne contient que des shaders Vulkan : utilisez `make awsim` sans option. |
| AWSIM se ferme aussitôt | Lisez `/tmp/awsim.log`. Vérifiez qu'un pilote Vulkan est présent : `ls /usr/share/vulkan/icd.d/` doit au minimum contenir `lvp_icd.json` (paquet `mesa-vulkan-drivers`). |
| `make topics` ne montre aucun topic AWSIM | (a) AWSIM n'est pas lancé ; (b) `ROS_LOCALHOST_ONLY` est défini quelque part — supprimez-le ; (c) le moteur Docker natif n'est pas actif → `docker context ls` doit montrer `awsim-native` sélectionné, sinon relancez `make docker-native`. |
| `make check` : « piles réseau différentes » | Vous utilisez Docker Desktop. Lancez `make docker-native`, puis rouvrez le terminal. |
| `make docker-native` : le service ne démarre pas | `sudo journalctl -u docker -n 50`. Souvent `docker.socket` non masquée ou un `dockerd` déjà en cours : `sudo systemctl mask docker.socket && sudo systemctl restart docker`. |
| Fenêtre RViz noire ou absente | `xhost +local:docker`, vérifiez que `echo $DISPLAY` renvoie `:0`, et que `/mnt/wslg` est bien monté dans le conteneur. |
| `CUDA out of memory` | Les 4 Go de VRAM sont partagés entre AWSIM, la perception et RViz. Réduisez la fenêtre d'AWSIM, ou lancez `AW_LAUNCH_ARGS="perception:=false" make autoware`. ⚠️ Sans perception, le moniteur d'état d'Autoware peut refuser le passage en autonome : dans ce cas, préférez `make psim`. |
| La localisation ne converge pas (nuage décalé) | Dans RViz, utilisez `2D Pose Estimate` pour replacer approximativement la voiture ; NDT affine ensuite tout seul. |
| Panneau `RecognitionResultOnImage` : **No Image** | Normal avec `make psim` : il n'y a pas de caméra, Autoware simule le véhicule et non les capteurs. Cette image ne peut venir que d'AWSIM. |
| Curseur `Set Velocity Limit` du panneau RViz | Il est à 0 km/h au démarrage. Le déplacer publie une limite de vitesse : à 0, la voiture ne bougera plus. Ne le toucher que pour y mettre une valeur voulue. |
| Le véhicule refuse de démarrer, `max_velocity: 0.0` | Une manœuvre de sécurité (MRM) s'est déclenchée — presque toujours parce qu'on est passé en AUTO avant que la planification ne soit prête. Elle laisse une limite de vitesse à zéro qui ne se purge pas. **Relancez Autoware** et attendez la trajectoire avant d'engager. Vérification : `make shell` puis `ros2 topic echo --once /planning/scenario_planning/max_velocity`. |
| Le véhicule refuse de démarrer | Il faut un but **et** le mode autonome disponible. Vérifiez : `ros2 topic echo --once /api/operation_mode/state` (`is_autonomous_mode_available: true`). |
| Topics visibles mais Autoware ne réagit pas | Incompatibilité possible entre distributions ROS. Éditez `AUTOWARE_IMAGE` dans `scripts/_common.sh` pour `…:universe-cuda-jazzy` et relancez. |
| Nuages de points hachés / messages perdus | Réglages DDS non appliqués : relancez `make setup`, puis `sysctl net.core.rmem_max` doit valoir 2147483647. |
| Topics visibles d'un côté seulement | Les deux moitiés doivent utiliser FastDDS. Vérifiez `echo $RMW_IMPLEMENTATION` (doit valoir `rmw_fastrtps_cpp`) et, dans le journal d'AWSIM, la ligne `RMW: rmw_fastrtps_cpp`. |

Commandes de diagnostic utiles :

```bash
make topics    # liste des topics ROS 2
make hz        # fréquence du LiDAR (doit être ~10 Hz)
make shell     # shell ROS 2 complet dans le conteneur
```

---

## Limites connues sur cette machine

AWSIM demande officiellement **Ubuntu 22.04 natif, une RTX 2080 Ti et 32 Go de RAM**.
Ici : Ubuntu 26.04 **dans WSL2**, une **GTX 1650 (4 Go)** et 15 Go alloués à WSL.

Ce qui a été constaté en pratique :

| Point | Constat |
|---|---|
| Rendu AWSIM | **Logiciel (processeur)**. Le build n'accepte que Vulkan, et WSL n'expose aucun Vulkan matériel NVIDIA. Simulation au ralenti mais fonctionnelle. |
| Démo HDRP / ray tracing | Hors de portée → variante *Lightweight* (URP). |
| Docker Desktop | Inutilisable pour ce projet (réseau isolé) → moteur Docker natif. |
| VRAM | 4 Go partagés entre la perception TensorRT et RViz. |
| Autoware | Aucun souci : tourne dans l'image officielle, avec le GPU. |

Pour une simulation **en temps réel**, il faudrait Ubuntu 22.04 installé nativement avec un
GPU NVIDIA : toute la procédure de ce dépôt s'y applique sans modification (le pilote
Vulkan matériel y est disponible, et `make docker-native` devient inutile).

En attendant, `make psim` fournit une démonstration de conduite autonome **en temps réel**
sur cette machine, sans Unity.

## Passer sur Ubuntu natif

Pour la démo AWSIM complète en temps réel, il faut un **Ubuntu 22.04 installé nativement**
(pas WSL, pas de machine virtuelle) avec un GPU NVIDIA — c'est la configuration officielle
d'AWSIM. Deux différences seulement par rapport à cette machine, et elles lèvent les deux
blocages :

- le pilote NVIDIA Linux fournit un **Vulkan matériel** → rendu fluide ;
- il fournit aussi la **vraie bibliothèque OptiX** → le LiDAR d'AWSIM fonctionne.

La procédure de ce dépôt s'y applique presque telle quelle :

| Étape | Sur Ubuntu natif |
|---|---|
| `make setup` | identique |
| `make docker-native` | **inutile** — installez Docker normalement (`apt install docker-ce`) ; il n'y a pas de Docker Desktop qui isole le réseau |
| `make download` | identique |
| `make awsim` | identique — le script détecte automatiquement le pilote Vulkan matériel |
| `make autoware` | identique |

Il faut aussi installer le pilote NVIDIA 570 ou plus récent et `libvulkan1`, puis redémarrer :

```bash
sudo add-apt-repository ppa:graphics-drivers/ppa && sudo apt update
sudo ubuntu-drivers autoinstall
sudo apt install libvulkan1
sudo reboot
```

---

## Références

- [Démo de démarrage AWSIM](https://autowarefoundation.github.io/AWSIM/GettingStarted/QuickStartDemo/)
- [Téléchargements AWSIM](https://autowarefoundation.github.io/AWSIM/Downloads/)
- [Documentation Autoware](https://docs.autoware.org/)
- [Images Docker Autoware](https://github.com/autowarefoundation/autoware/tree/main/docker)
- [Réglages DDS pour ROS 2](https://autowarefoundation.github.io/autoware-documentation/main/installation/additional-settings-for-developers/network-configuration/dds-settings/)
