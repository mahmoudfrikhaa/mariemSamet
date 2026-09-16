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
  *) die "Option inconnue : $MODE (attendu : --software, --gl)" ;;
esac

# Un pilote Vulkan materiel a-t-il ete installe entre-temps (dzn, NVIDIA) ?
# 'ls' echoue si aucun fichier ne correspond : sans le '|| true', set -e arrete le script.
HW_ICD=$(ls /usr/share/vulkan/icd.d/*dzn* /usr/local/share/vulkan/icd.d/*dzn* \
              /usr/share/vulkan/icd.d/nvidia* 2>/dev/null | head -1 || true)
if [ "$MODE" = "auto" ] && [ -n "$HW_ICD" ]; then
  export VK_ICD_FILENAMES="$HW_ICD"
  info "Pilote Vulkan materiel detecte : $HW_ICD"
fi

# Le LiDAR d'AWSIM (RobotecGPULidar) s'appuie sur NVIDIA OptiX. Sous WSL,
# libnvoptix.so.1 est bien present dans /usr/lib/wsl/lib, mais son SONAME est
# libnvoptix_loader.so.1 : ldconfig ne l'indexe donc pas sous le nom que
# recherche OptiX, et optixInit() echoue avec OPTIX_ERROR_LIBRARY_NOT_FOUND
# (ce qui desactive purement et simplement le LiDAR). Ce chemin explicite
# resout le probleme.
export LD_LIBRARY_PATH="/usr/lib/wsl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
LOG="/tmp/awsim.log"

title "Lancement d'AWSIM"
info "Binaire    : $BIN"
info "Rendu      : ${GFX[*]} en ${WIDTH}x${HEIGHT}"
info "DDS        : $RMW_IMPLEMENTATION (profil : $FASTRTPS_DEFAULT_PROFILES_FILE)"
info "OptiX      : /usr/lib/wsl/lib (LiDAR GPU)"
info "Journal    : $LOG"
if [ -z "${VK_ICD_FILENAMES:-}" ] && [ -z "$HW_ICD" ]; then
  warn "Aucun pilote Vulkan materiel : rendu logiciel, quelques images/seconde."
  info "La simulation reste coherente (Autoware suit l'horloge /clock d'AWSIM),"
  info "mais elle se deroule au ralenti. Reduisez la fenetre pour gagner un peu :"
  info "  WIDTH=640 HEIGHT=480 make awsim"
fi
info "Fermez la fenetre AWSIM (ou Ctrl+C ici) pour arreter."

exec "$BIN" "${GFX[@]}" \
  -screen-width "$WIDTH" -screen-height "$HEIGHT" -screen-fullscreen 0 \
  -logFile "$LOG"
