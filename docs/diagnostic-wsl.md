# Diagnostic technique : AWSIM + Autoware sous WSL2

Ce document rassemble les constats faits sur la machine de développement, avec les
commandes et les sorties qui les établissent. Il sert de justification aux choix
techniques du projet.

**Machine testée** — Windows 11 Pro (build 26200), WSL 2.6.1, Ubuntu 26.04 LTS,
NVIDIA GeForce GTX 1650 Max-Q (4 Go, pilote 610.88), 12 threads, 15 Go alloués à WSL.

---

## 1. Autoware ne peut pas être installé nativement

Autoware cible ROS 2 Humble, qui n'existe que pour Ubuntu 22.04. La distribution est en
26.04 : aucun paquet `ros-humble-*` n'est installable.

**Décision** : utiliser l'image Docker officielle pré-compilée
`ghcr.io/autowarefoundation/autoware:universe-cuda-humble`. Elle évite aussi la
compilation depuis les sources, qui demande environ 32 Go de RAM (la machine en a 15).

---

## 2. Docker Desktop isole le réseau des conteneurs

C'est le premier blocage rencontré, et il est éliminatoire pour une simulation distribuée.

```console
$ ip -4 -o addr show eth0 | awk '{print $4}'
172.18.140.148/20

$ docker run --rm --network host alpine:3 ip -4 -o addr show eth0 | awk '{print $4}'
192.168.65.3/24

$ docker run --rm --network host alpine:3 ping -c1 -W2 172.18.140.148
ping distro KO
```

Malgré `--network host`, le conteneur se retrouve sur le réseau de la distribution
`docker-desktop`, distincte de celle où tourne AWSIM — et il ne peut même pas la joindre.
Aucun échange DDS n'est possible : Autoware ne verrait jamais un seul topic d'AWSIM.

**Décision** : installer un moteur Docker natif dans la distribution Ubuntu
(`scripts/11_setup_docker_native.sh`). Après installation :

```console
$ docker run --rm --network host alpine:3 ip -4 -o addr show eth0 | awk '{print $4}'
172.18.140.148/20        # identique à l'hôte : pile réseau partagée
```

Pour ne pas casser Docker Desktop, le moteur natif écoute sur `/run/docker-native.sock`
(via un `drop-in` systemd sur `docker.socket`) et s'utilise par le contexte `awsim-native`.

---

## 3. AWSIM v2 communique en FastDDS, pas en CycloneDDS

Le journal d'AWSIM au démarrage :

```
ROS2 version: humble. Build type: standalone. RMW: rmw_fastrtps_cpp
```

Or l'image Autoware est configurée en CycloneDDS. Deux implémentations DDS différentes ne
s'apparient pas de façon fiable.

**Décision** : forcer `RMW_IMPLEMENTATION=rmw_fastrtps_cpp` des deux côtés, avec un profil
commun (`config/fastdds.xml`) qui désactive la mémoire partagée — elle ne traverse pas
proprement la frontière hôte/conteneur — et agrandit les tampons pour les nuages de points.

À noter : la documentation officielle d'AWSIM décrit une configuration CycloneDDS, héritée
de la version 1. Elle ne correspond plus au binaire v2.0.1.

---

## 4. Le binaire AWSIM n'accepte que Vulkan

Lancement avec `-force-glcore` :

```
Forcing GfxDevice: OpenGL Core
Forced GfxDevice 'OpenGL Core' was not built from editor, shaders will not be available
PlayerInitEngineGraphics: InitializeEngineGraphics failed
Caught fatal signal - signo:11
```

Le build Unity 6 / URP ne contient que les variantes de shaders Vulkan. L'option OpenGL
est donc définitivement fermée, quelle que soit la qualité du pilote GL.

## 5. WSL n'offre aucun pilote Vulkan matériel NVIDIA

```console
$ ls /usr/share/vulkan/icd.d/
asahi_icd.json  gfxstream_vk_icd.json  intel_hasvk_icd.json  intel_icd.json
lvp_icd.json  nouveau_icd.json  radeon_icd.json  virtio_icd.json
```

Aucun ICD NVIDIA, et pas de `dzn` (le pilote Mesa Vulkan-sur-Direct3D12) dans les paquets
Ubuntu. Le seul pilote utilisable est `lvp` (lavapipe), qui calcule les images sur le
processeur. AWSIM démarre bien avec, mais à quelques images par seconde :

```
[Vulkan init] Physical Device [0]: "llvmpipe (LLVM 21.1.8, 256 bits)"
Renderer: llvmpipe (LLVM 21.1.8, 256 bits)
```

Pour comparaison, l'**OpenGL** de WSL est, lui, bien accéléré — mais seulement si on le
demande explicitement, sinon Mesa retombe silencieusement sur llvmpipe :

```console
$ glxinfo -B | grep renderer
OpenGL renderer string: llvmpipe (LLVM 21.1.8, 256 bits)

$ GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA glxinfo -B | grep renderer
OpenGL renderer string: D3D12 (NVIDIA GeForce GTX 1650 with Max-Q Design)
```

C'est pourquoi le conteneur Autoware reçoit ces deux variables : RViz, lui, est en OpenGL
et profite donc du GPU.

---

## 6. Blocage décisif : le LiDAR d'AWSIM exige OptiX, indisponible sous WSL

AWSIM simule son LiDAR avec **RobotecGPULidar**, qui fait du lancer de rayons via NVIDIA
OptiX. Au démarrage :

```
[info]: RGL Version 0.18.0
[info]: Built against OptiX SDK version: 7.2.0
[critical]: Optix Error: optixInit() -> 7804 (OPTIX_ERROR_LIBRARY_NOT_FOUND)
RGLException: ... Disabling LidarSensor components.
```

Première piste : la bibliothèque existe pourtant, mais `ldconfig` ne l'indexe pas sous le
nom attendu, car son `SONAME` est différent de son nom de fichier.

```console
$ ls -la /usr/lib/wsl/lib/libnvoptix*
-r-xr-xr-x 2 root root 14224 libnvoptix.so.1
lrwxrwxrwx 1 root root    15 libnvoptix_loader.so.1 -> libnvoptix.so.1

$ objdump -p /usr/lib/wsl/lib/libnvoptix.so.1 | grep SONAME
  SONAME               libnvoptix_loader.so.1
```

Avec `LD_LIBRARY_PATH=/usr/lib/wsl/lib`, la bibliothèque se charge et l'erreur change :

```
Optix Error: optixInit() -> 7805 (OPTIX_ERROR_ENTRY_SYMBOL_NOT_FOUND)
```

Elle est chargée, mais n'expose pas l'API. Vérification directe :

```console
$ LD_LIBRARY_PATH=/usr/lib/wsl/lib python3 -c "
import ctypes; h=ctypes.CDLL('libnvoptix.so.1')
print(hasattr(h,'optixQueryFunctionTable'))"
False
```

Ce fichier de 14 Ko n'est qu'un **chargeur dxcore** : il n'exporte que `dxcore_*`. La vraie
implémentation OptiX présente dans le magasin de pilotes est `nvoptix.dll` — une
bibliothèque **Windows** de 48 Mo, inutilisable depuis Linux :

```console
$ ls /usr/lib/wsl/drivers/nvmii.inf_amd64_*/ | grep -i optix
libnvoptix_loader.so.1     # 16 Ko, chargeur
nvoptix.bin
nvoptix.dll                # 48 Mo, code Windows
```

Aucune bibliothèque du magasin n'exporte `optixQueryFunctionTable`.

**Conclusion** : sous WSL2, le LiDAR d'AWSIM ne peut pas fonctionner. Sans nuage de points,
Autoware ne peut ni se localiser (NDT) ni percevoir son environnement. La démo AWSIM
complète nécessite un **Ubuntu installé nativement** avec un GPU NVIDIA.

---

## Synthèse des décisions

| Problème | Décision |
|---|---|
| ROS 2 Humble indisponible sur Ubuntu 26.04 | Image Docker Autoware pré-compilée |
| Docker Desktop isole le réseau | Moteur Docker natif, contexte `awsim-native` |
| AWSIM parle FastDDS | `RMW_IMPLEMENTATION=rmw_fastrtps_cpp` + profil commun |
| AWSIM exige Vulkan | Variante *Lightweight* (URP), rendu logiciel lavapipe |
| RViz en rendu logiciel | `GALLIUM_DRIVER=d3d12` + adaptateur NVIDIA dans le conteneur |
| LiDAR AWSIM impossible (OptiX) | Démonstration via le *planning simulator* d'Autoware ; AWSIM réservé à une installation Ubuntu native |

---

## 7. Résultat validé : conduite autonome avec le planning simulator

Faute de pouvoir faire tourner AWSIM, la démonstration s'appuie sur le *planning simulator*
d'Autoware, qui rejoue la même pile logicielle sur la même carte, avec un véhicule simulé
par Autoware lui-même.

Mesure obtenue par `make test` (scénario entièrement automatisé via l'AD API) :

```
--- 1. Initialisation de la localisation ---   success=True
--- 2. Definition de l itineraire ---          success=True
--- 3. Attente que la planification produise une trajectoire ---
mode autonome disponible
--- 4. Passage en mode autonome ---            PASSAGE EN AUTONOME ACCEPTE
--- 5. Observation du deplacement ---
messages recus : 3548
distance parcourue : 302.01 m
vitesse max : 4.31 m/s (15.5 km/h)
RESULTAT : le vehicule roule
```

Vérifications complémentaires :

| Mesure | Valeur |
|---|---|
| Nœuds ROS 2 actifs | 102 |
| Topics | 557 |
| Fréquence de `/planning/trajectory` | 10 Hz |
| Fréquence de `/control/command/control_cmd` | 33 Hz |
| Position finale vs but | écart de 2 cm |
| `/api/routing/state` | `ARRIVED` |
| RViz | OpenGL 4.2 matériel, ~9 images/s |

### Piège rencontré : la manœuvre de sécurité collante

En passant en mode autonome **avant** que la planification ne publie une trajectoire stable,
le graphe de diagnostics passe en erreur (`/adapi/mrm_request/delegate` STALE) et déclenche
une MRM « arrêt confortable ». Celle-ci publie une limite de vitesse de 0 m/s sur
`/planning/scenario_planning/max_velocity_candidates`. Le sélecteur retient le minimum des
candidats : la limite reste donc à zéro même après le retour de la MRM à `NORMAL`, et la
purge manuelle (`clear_velocity_limit`) ne la lève pas.

```console
$ ros2 topic echo --once /planning/scenario_planning/max_velocity
max_velocity: 0.0
$ ros2 topic echo --once /planning/scenario_planning/max_velocity_candidates
max_velocity: 0.0
sender: mrm_comfortable_stop_operator
```

**Remède** : attendre `is_autonomous_mode_available: true` *et* une trajectoire publiée à
10 Hz avant d'engager — c'est ce que fait `scripts/91_test_autonomous_drive.sh`. Si la
limite est déjà bloquée à zéro, relancer Autoware.
