#!/usr/bin/env bash
# Fonctions et variables partagees par tous les scripts du projet.
# Ne pas executer directement : ce fichier est "source"-e par les autres.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
export PROJECT_DIR

# --- Emplacements des ressources telechargees -------------------------------
export AWSIM_DIR="${AWSIM_DIR:-$HOME/awsim}"
export AW_DATA_DIR="${AW_DATA_DIR:-$HOME/autoware_data}"
export MAP_DIR="$AW_DATA_DIR/maps/Shinjuku-Map"
export ML_MODELS_DIR="$AW_DATA_DIR/ml_models"

# --- Versions figees (verifiees le 2026-09-15) ------------------------------
export AWSIM_VERSION="v2.0.1"
export AWSIM_MAP_VERSION="v2.0.0"
export AWSIM_ZIP="AWSIM-Demo-Lightweight.zip"   # version URP, sans ray tracing
export AUTOWARE_IMAGE="${AUTOWARE_IMAGE:-ghcr.io/autowarefoundation/autoware:universe-cuda-humble}"

# --- DDS --------------------------------------------------------------------
# AWSIM v2 embarque ros2-for-unity compile avec FastDDS : les deux cotes de la
# simulation doivent utiliser la meme implementation (verifie dans le journal
# d'AWSIM : "RMW: rmw_fastrtps_cpp").
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE="$PROJECT_DIR/config/fastdds.xml"
export FASTDDS_DEFAULT_PROFILES_FILE="$FASTRTPS_DEFAULT_PROFILES_FILE"
unset ROS_LOCALHOST_ONLY || true

# --- Moteur Docker ------------------------------------------------------------
# Docker Desktop isole ses conteneurs dans une autre distribution WSL : le DDS
# entre AWSIM et Autoware n'y passe pas. Si le moteur natif a ete installe
# (scripts/11_setup_docker_native.sh), on l'utilise automatiquement.
if [ -z "${DOCKER_CONTEXT:-}" ] && command -v docker >/dev/null 2>&1; then
  if docker context inspect awsim-native >/dev/null 2>&1; then
    export DOCKER_CONTEXT=awsim-native
  fi
fi

# --- Affichage --------------------------------------------------------------
if [ -t 1 ]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_BLU=$'\e[34m'; C_BLD=$'\e[1m'; C_RST=$'\e[0m'
else
  C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_BLD=''; C_RST=''
fi

title() { printf '\n%s=== %s ===%s\n' "$C_BLD$C_BLU" "$*" "$C_RST"; }
ok()    { printf '%s  OK  %s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn()  { printf '%s ATTN %s %s\n' "$C_YEL" "$C_RST" "$*"; }
err()   { printf '%s ERR  %s %s\n' "$C_RED" "$C_RST" "$*"; }
info()  { printf '       %s\n' "$*"; }
die()   { err "$*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }
