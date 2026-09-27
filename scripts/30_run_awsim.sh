#!/usr/bin/env bash
# Lance le simulateur AWSIM. A demarrer TOUJOURS AVANT Autoware
# (meme ordre que sur un vrai vehicule : les capteurs d'abord).
#
# AWSIM v2 est un build Unity 6 / URP compile pour VULKAN uniquement :
# l'option -force-glcore echoue ("shaders will not be available"), meme si
# l'OpenGL de WSL est, lui, accelere materiellement.
# Sous WSL il n'existe aucun pilote Vulkan materiel pour les GPU NVIDIA :
# le rendu se fait donc en logiciel (llvmpipe), sur le processeur.
#
# Usage :
#   scripts/30_run_awsim.sh                 # Vulkan (auto : materiel si dispo, sinon logiciel)
#   scripts/30_run_awsim.sh --software      # force le rendu logiciel (llvmpipe)
#   scripts/30_run_awsim.sh --gl            # tente OpenGL (echoue sur ce build : diagnostic)
#   scripts/30_run_awsim.sh --nvidia        # PC hybride : rendu sur le GPU NVIDIA (gros GPU uniquement)
#   scripts/30_run_awsim.sh --igpu          # PC hybride : rendu sur le GPU integre Intel
#   WIDTH=640 HEIGHT=480 scripts/30_run_awsim.sh
source "$(dirname "$0")/_common.sh"

BIN=$(find "$AWSIM_DIR" -maxdepth 3 -name '*.x86_64' 2>/dev/null | head -1)
[ -n "$BIN" ] || die "Binaire AWSIM introuvable dans $AWSIM_DIR. Lancez : make awsim-dl"
[ -x "$BIN" ] || chmod +x "$BIN"

MODE="${1:-auto}"
GFX=(-force-vulkan)
case "$MODE" in
  auto) ;;
  --software) export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json ;;
  --gl) GFX=(-force-glcore) ;;
  --nvidia|--igpu) ;;
  *) die "Option inconnue : $MODE (attendu : --software, --gl, --nvidia, --igpu)" ;;
esac

# PC portable hybride (Intel + NVIDIA) avec peu de VRAM : rendu Unity sur le
# GPU Intel, pour laisser tout le GPU NVIDIA au LiDAR (OptiX/CUDA, qui choisit
# toujours le GPU NVIDIA) et a la perception d'Autoware. Mesure sur une
# GTX 1650 4 Go : rendu NVIDIA = 3,7 Go de VRAM et LiDAR en "out of memory" ;
# rendu Intel = 0,5 Go de VRAM et LiDAR fonctionnel.
IGPU_ICD=/usr/share/vulkan/icd.d/intel_icd.json
VRAM_MIB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || true)
if [ "$IS_WSL" = 0 ] && [ -f "$IGPU_ICD" ] && lspci 2>/dev/null | grep -qiE 'vga.*intel'; then
  if [ "$MODE" = "--igpu" ] || { [ "$MODE" = "auto" ] && [ "${VRAM_MIB:-99999}" -lt 8000 ]; }; then
    MODE=igpu
  fi
fi

# Un pilote Vulkan materiel a-t-il ete installe entre-temps (dzn, NVIDIA) ?
# 'ls' echoue si aucun fichier ne correspond : sans le '|| true', set -e arrete le script.
HW_ICD=$(ls /usr/share/vulkan/icd.d/*dzn* /usr/local/share/vulkan/icd.d/*dzn* \
              /usr/share/vulkan/icd.d/nvidia* 2>/dev/null | head -1 || true)
if [ "$MODE" = "igpu" ]; then
  export VK_ICD_FILENAMES="$IGPU_ICD"
  info "Rendu sur le GPU integre Intel : le GPU NVIDIA reste libre pour le LiDAR et Autoware."
elif { [ "$MODE" = "auto" ] || [ "$MODE" = "--nvidia" ]; } && [ -n "$HW_ICD" ]; then
  export VK_ICD_FILENAMES="$HW_ICD"
  info "Pilote Vulkan materiel detecte : $HW_ICD"
fi

if [ "$IS_WSL" = 1 ]; then
  # Le LiDAR d'AWSIM (RobotecGPULidar) s'appuie sur NVIDIA OptiX. Sous WSL,
  # libnvoptix.so.1 est bien present dans /usr/lib/wsl/lib, mais son SONAME est
  # libnvoptix_loader.so.1 : ldconfig ne l'indexe donc pas sous le nom que
  # recherche OptiX, et optixInit() echoue avec OPTIX_ERROR_LIBRARY_NOT_FOUND
  # (ce qui desactive purement et simplement le LiDAR). Ce chemin explicite
  # resout le probleme.
  export LD_LIBRARY_PATH="/usr/lib/wsl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  OPTIX_INFO="/usr/lib/wsl/lib (LiDAR GPU)"
else
  # Ubuntu natif : le pilote NVIDIA fournit OptiX via ldconfig. Sur un PC
  # portable hybride (Intel + NVIDIA en mode on-demand) dont on veut le rendu
  # sur le GPU NVIDIA, on le demande explicitement (PRIME render offload).
  if [ "$MODE" != "igpu" ]; then
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
  fi
  OPTIX_INFO="$(ldconfig -p | grep -q libnvoptix.so.1 && echo "libnvoptix.so.1 (pilote NVIDIA)" || echo "ABSENT : le LiDAR ne fonctionnera pas")"
fi

WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
LOG="/tmp/awsim.log"
# Reglages de la simulation (trafic, position de depart...) : voir config/awsim-config.json.
AWSIM_CONFIG="${AWSIM_CONFIG:-$PROJECT_DIR/config/awsim-config.json}"

title "Lancement d'AWSIM"
info "Binaire    : $BIN"
info "Rendu      : ${GFX[*]} en ${WIDTH}x${HEIGHT}"
info "DDS        : $RMW_IMPLEMENTATION (profil : $FASTRTPS_DEFAULT_PROFILES_FILE)"
info "OptiX      : $OPTIX_INFO"
info "Journal    : $LOG"
info "Config     : $AWSIM_CONFIG"
if [ -z "${VK_ICD_FILENAMES:-}" ] && [ -z "$HW_ICD" ]; then
  warn "Aucun pilote Vulkan materiel : rendu logiciel, quelques images/seconde."
  info "La simulation reste coherente (Autoware suit l'horloge /clock d'AWSIM),"
  info "mais elle se deroule au ralenti. Reduisez la fenetre pour gagner un peu :"
  info "  WIDTH=640 HEIGHT=480 make awsim"
fi
info "Fermez la fenetre AWSIM (ou Ctrl+C ici) pour arreter."

exec "$BIN" "${GFX[@]}" \
  -screen-width "$WIDTH" -screen-height "$HEIGHT" -screen-fullscreen 0 \
  -logFile "$LOG" \
  --json_path "$AWSIM_CONFIG"
