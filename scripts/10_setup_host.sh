#!/usr/bin/env bash
# Prepare la machine : paquets graphiques/outils + reglages reseau pour DDS.
# Demande le mot de passe sudo. Idempotent : peut etre relance sans risque.
source "$(dirname "$0")/_common.sh"

title "1. Paquets systeme"
PKGS=(mesa-utils vulkan-tools libvulkan1 x11-utils x11-xserver-utils unzip wget curl python3-venv jq)
MISSING=()
for p in "${PKGS[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
if [ ${#MISSING[@]} -eq 0 ]; then
  ok "Tous les paquets sont deja installes"
else
  info "Installation de : ${MISSING[*]}"
  sudo apt-get update
  sudo apt-get install -y "${MISSING[@]}"
  ok "Paquets installes"
fi

title "2. Client HuggingFace (telechargement des modeles de perception)"
# Installe a la demande par scripts/22_download_models.sh, dans un
# environnement Python local au projet (.venv) : rien a faire ici.
if [ -x "$PROJECT_DIR/.venv/bin/hf" ]; then
  ok "Client HuggingFace deja installe (.venv)"
else
  info "Sera installe automatiquement par 'make models'"
fi

title "3. Reglages noyau pour DDS"
# Gros nuages de points LiDAR = gros datagrammes fragmentes : sans ces reglages
# les messages arrivent tronques ou pas du tout.
sudo tee /etc/sysctl.d/60-ros2-dds.conf >/dev/null <<'SYSCTL'
# Reglages recommandes par la documentation Autoware (DDS settings)
net.core.rmem_max=2147483647
net.ipv4.ipfrag_time=3
net.ipv4.ipfrag_high_thresh=134217728
SYSCTL
sudo sysctl -q --system >/dev/null
ok "net.core.rmem_max = $(sysctl -n net.core.rmem_max)"

# Le multicast sur la loopback n'est pas persistant sous WSL : on le rejoue au besoin.
sudo ip link set lo multicast on
ok "Multicast active sur lo"

title "4. Variables d'environnement (~/.bashrc)"
MARK="# >>> AWSIM/Autoware (mariem_project) >>>"
if grep -qF "$MARK" "$HOME/.bashrc" 2>/dev/null; then
  ok "Bloc deja present dans ~/.bashrc"
else
  cat >> "$HOME/.bashrc" <<BASHRC

$MARK
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE="$PROJECT_DIR/config/fastdds.xml"
export FASTDDS_DEFAULT_PROFILES_FILE="\$FASTRTPS_DEFAULT_PROFILES_FILE"
unset ROS_LOCALHOST_ONLY
# Multicast loopback : rejoue une fois par demarrage de WSL (silencieux si sudo exige un mot de passe)
if [ ! -e /tmp/.ros2_lo_multicast ]; then
    sudo -n ip link set lo multicast on 2>/dev/null && touch /tmp/.ros2_lo_multicast
fi
# <<< AWSIM/Autoware (mariem_project) <<<
BASHRC
  ok "Bloc ajoute a ~/.bashrc"
fi

title "5. Rappel Windows"
info "Pour donner plus de RAM a WSL (recommande) :"
info "  1. copier $PROJECT_DIR/config/wslconfig.sample vers C:\\Users\\<vous>\\.wslconfig"
info "  2. dans PowerShell : wsl --shutdown"
info "  3. rouvrir le terminal Ubuntu"

title "Termine"
ok "Lancez maintenant : make check"
