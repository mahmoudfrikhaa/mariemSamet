#!/usr/bin/env bash
# Diagnostic complet de la machine avant de lancer AWSIM + Autoware.
# N'installe rien, ne modifie rien : lecture seule.
source "$(dirname "$0")/_common.sh"

FAIL=0
SOFT=0

title "1. Systeme"
info "$(. /etc/os-release && echo "$PRETTY_NAME")  |  noyau $(uname -r)"
if uname -r | grep -qi microsoft; then
  warn "WSL2 detecte : AWSIM n'est pas officiellement supporte ici (voir README)."
  SOFT=$((SOFT+1))
fi
MEM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
info "RAM allouee a WSL : ${MEM_GB} Go"
if [ "$MEM_GB" -lt 20 ]; then
  warn "Moins de 20 Go : copiez config/wslconfig.sample vers C:\\Users\\<vous>\\.wslconfig puis 'wsl --shutdown'."
  SOFT=$((SOFT+1))
else
  ok "RAM suffisante"
fi
DISK_GB=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc '0-9')
info "Espace libre sur \$HOME : ${DISK_GB} Go (il en faut ~40)"
[ "${DISK_GB:-0}" -lt 40 ] && { err "Espace disque insuffisant"; FAIL=$((FAIL+1)); } || ok "Disque OK"

title "2. GPU NVIDIA"
if need_cmd nvidia-smi; then
  nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader | sed 's/^/       /'
  VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
  if [ "${VRAM:-0}" -lt 6000 ]; then
    warn "Seulement ${VRAM} Mio de VRAM : la perception TensorRT et AWSIM vont se la partager (voir README, section VRAM)."
    SOFT=$((SOFT+1))
  else
    ok "VRAM confortable"
  fi
else
  err "nvidia-smi introuvable : pas de GPU NVIDIA visible."; FAIL=$((FAIL+1))
fi

title "3. Rendu graphique (critique pour AWSIM)"
# AWSIM v2 est un build Unity compile pour Vulkan uniquement : c'est le pilote
# Vulkan qui determine si la simulation tourne en temps reel ou au ralenti.
ICDS=$(ls /usr/share/vulkan/icd.d/*.json /usr/local/share/vulkan/icd.d/*.json 2>/dev/null || true)
if [ -z "$ICDS" ]; then
  err "Aucun pilote Vulkan : AWSIM ne demarrera pas. Installez 'mesa-vulkan-drivers'."
  FAIL=$((FAIL+1))
else
  HW=$(echo "$ICDS" | grep -iE "dzn|nvidia" | head -1 || true)
  if [ -n "$HW" ]; then
    ok "Pilote Vulkan materiel : $(basename "$HW") -> simulation en temps reel possible"
  else
    warn "Vulkan logiciel uniquement (llvmpipe) : AWSIM tournera au ralenti."
    info "Normal sous WSL : aucun pilote Vulkan materiel NVIDIA n'y est disponible."
    info "Voir README > 'Le rendu se fait sur le processeur'."
    SOFT=$((SOFT+1))
  fi
fi
if need_cmd glxinfo; then
  # Sous WSL, Mesa n'utilise le GPU que si on lui impose le pilote D3D12 et
  # l'adaptateur NVIDIA ; sans cela il retombe silencieusement sur llvmpipe.
  GLREN=$(GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA \
          glxinfo -B 2>/dev/null | grep -i "OpenGL renderer" | cut -d: -f2- | xargs || true)
  if echo "$GLREN" | grep -qi "d3d12.*nvidia"; then
    ok "OpenGL materiel pour RViz : $GLREN"
  else
    warn "OpenGL sans acceleration ($GLREN) : RViz sera lent."
    SOFT=$((SOFT+1))
  fi
fi

title "4. Affichage WSLg / X11"
info "DISPLAY=${DISPLAY:-<vide>}  WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<vide>}"
[ -n "${DISPLAY:-}" ] && ok "DISPLAY defini" || { err "DISPLAY vide : aucune fenetre ne pourra s'ouvrir"; FAIL=$((FAIL+1)); }
[ -S /tmp/.X11-unix/X0 ] && ok "Socket X11 present (/tmp/.X11-unix/X0)" || { warn "Socket X11 introuvable"; SOFT=$((SOFT+1)); }

title "5. Docker"
if need_cmd docker && docker info >/dev/null 2>&1; then
  ok "Docker operationnel ($(docker --version | cut -d, -f1))"
  if docker info 2>/dev/null | grep -qi "Runtimes:.*nvidia"; then
    ok "Runtime nvidia enregistre"
  else
    err "Runtime nvidia absent : Autoware ne verra pas le GPU."; FAIL=$((FAIL+1))
  fi
  info "Test acces GPU depuis un conteneur..."
  # Image legere volontairement : utiliser l'image Autoware declencherait un
  # telechargement de 20 Go si elle n'est pas encore presente.
  if docker run --rm --gpus all ubuntu:24.04 nvidia-smi -L >/tmp/gpu_test.log 2>&1; then
    ok "GPU visible dans un conteneur : $(head -1 /tmp/gpu_test.log)"
  else
    warn "Test GPU non concluant (l'image n'est peut-etre pas encore telechargee) : $(tail -1 /tmp/gpu_test.log)"
    SOFT=$((SOFT+1))
  fi

  if [ "${DOCKER_CONTEXT:-}" = "awsim-native" ]; then
    ok "Moteur Docker natif utilise (contexte awsim-native)"
  else
    warn "Moteur Docker Desktop utilise : voir le point 6."
  fi

  title "6. Reseau conteneur <-> hote (critique pour DDS)"
  HOST_IP=$(ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
  CTR_IP=$(docker run --rm --network host alpine:3 ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
  info "IP de la distro WSL       : ${HOST_IP:-inconnue}"
  info "IP du conteneur --net host: ${CTR_IP:-inconnue}"
  if [ -n "${CTR_IP:-}" ] && [ "$HOST_IP" = "$CTR_IP" ]; then
    ok "Pile reseau partagee : AWSIM et Autoware se verront sur la loopback."
  else
    err "Piles reseau differentes : les topics AWSIM n'atteindront jamais Autoware."
    info "  Cause : Docker Desktop execute son moteur dans une autre distribution WSL."
    info "  Solution : ./scripts/11_setup_docker_native.sh  (ou : make docker-native)"
    FAIL=$((FAIL+1))
  fi
else
  err "Docker indisponible."; FAIL=$((FAIL+1))
fi

title "7. Reglages noyau pour DDS"
RMEM=$(sysctl -n net.core.rmem_max 2>/dev/null || echo 0)
info "net.core.rmem_max = $RMEM (cible : 2147483647)"
[ "$RMEM" -ge 134217728 ] && ok "Buffers reseau OK" || { warn "Trop petit : lancez scripts/10_setup_host.sh"; SOFT=$((SOFT+1)); }
if ip link show lo | head -1 | grep -q MULTICAST; then ok "Multicast actif sur lo"; else warn "Multicast inactif sur lo : lancez scripts/10_setup_host.sh"; SOFT=$((SOFT+1)); fi

title "8. Ressources telechargees"
if [ -n "$(find "$AWSIM_DIR" -maxdepth 3 -name '*.x86_64' 2>/dev/null | head -1)" ]; then
  ok "Binaire AWSIM present"
else
  info "AWSIM absent  -> scripts/20_download_awsim.sh"
fi
[ -f "$MAP_DIR/map/lanelet2_map.osm" ] && ok "Carte Shinjuku presente" || info "Carte absente -> scripts/21_download_map.sh"
[ -d "$ML_MODELS_DIR/lidar_centerpoint" ] && ok "Modeles ML presents" || info "Modeles absents -> scripts/22_download_models.sh"
docker image inspect "$AUTOWARE_IMAGE" >/dev/null 2>&1 && ok "Image Autoware presente" || info "Image Autoware absente -> make pull"

title "Resume"
if [ "$FAIL" -gt 0 ]; then
  err "$FAIL probleme(s) bloquant(s), $SOFT avertissement(s). Voir le README."
  exit 1
elif [ "$SOFT" -gt 0 ]; then
  warn "Aucun blocage, mais $SOFT point(s) d'attention."
else
  ok "Tout est vert."
fi
