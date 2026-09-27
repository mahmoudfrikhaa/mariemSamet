#!/usr/bin/env bash
# Telecharge les modeles de perception (TensorRT/ONNX) depuis HuggingFace.
# Par defaut : uniquement le sous-ensemble utilise par la demo AWSIM.
#   --all  : telecharge l'integralite du catalogue Autoware (tres volumineux).
source "$(dirname "$0")/_common.sh"

# Le client HuggingFace est installe dans un environnement Python local au
# projet : aucun droit administrateur necessaire.
VENV="$PROJECT_DIR/.venv"
if [ ! -x "$VENV/bin/hf" ]; then
  title "Installation du client HuggingFace (environnement local)"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet "huggingface_hub[cli]"
  ok "Installe dans $VENV"
fi
HF="$VENV/bin/hf"
[ -x "$HF" ] || die "Client HuggingFace introuvable apres installation."

# Format : depot:revision[:dossier_destination]
CORE_MODELS=(
  # v3.0 et non v4.1 : v4.1 range chaque variante dans un sous-dossier (tiny/,
  # base/...), alors que l'image universe-cuda-humble cherche encore les
  # fichiers a plat (centerpoint_tiny_ml_package.param.yaml...). Verifie le
  # 2026-09-26 : avec v4.1 le lancement d'Autoware echoue immediatement.
  "lidar_centerpoint:v3.0"              # detection d'objets 3D sur le LiDAR (detecteur par defaut)
  "tensorrt_yolox:v1.0"                 # detection image, sert aussi aux feux tricolores
  "traffic_light_fine_detector:v3.0"    # localisation fine des feux
  "traffic_light_classifier:v4.0"       # couleur/forme des feux
  "yabloc_pose_initializer:v1.0"        # initialisation de la pose
)
EXTRA_MODELS=(
  "lidar_transfusion:v2.1"
  "image_projection_based_fusion:v5.0"
  "lidar_apollo_instance_segmentation:v1.0"
  "bevfusion:v2.0"
)

MODELS=("${CORE_MODELS[@]}")
if [ "${1:-}" = "--all" ]; then
  MODELS+=("${EXTRA_MODELS[@]}")
  warn "Mode --all : plusieurs dizaines de Go vont etre telecharges."
fi

mkdir -p "$ML_MODELS_DIR"
title "Modeles de perception -> $ML_MODELS_DIR"

for entry in "${MODELS[@]}"; do
  IFS=: read -r repo rev dest <<<"$entry"
  dest="${dest:-$repo}"
  target="$ML_MODELS_DIR/$dest"
  if [ -d "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ] && [ "${FORCE:-0}" != "1" ]; then
    ok "$repo ($rev) deja present"
    continue
  fi
  info "Telechargement de $repo@$rev ..."
  "$HF" download "AutowareFoundation/$repo" --revision "$rev" --local-dir "$target" >/dev/null
  ok "$repo ($rev)"
done

info "Taille totale : $(du -sh "$ML_MODELS_DIR" | cut -f1)"
ok "Modeles prets"
