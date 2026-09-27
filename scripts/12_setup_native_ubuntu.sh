#!/usr/bin/env bash
# Installation pour un Ubuntu INSTALLE NATIVEMENT (pas WSL) avec GPU NVIDIA.
# Remplace a la fois 10_setup_host.sh et 11_setup_docker_native.sh :
#   - paquets systeme (Vulkan, X11, venv...)
#   - Docker (paquets Ubuntu) + NVIDIA Container Toolkit
#   - reglages reseau pour DDS
# Demande le mot de passe sudo : a lancer dans un vrai terminal.
# Idempotent : peut etre relance sans risque.
source "$(dirname "$0")/_common.sh"

[ "$(id -u)" -ne 0 ] || die "Ne pas lancer ce script en root : il utilise sudo quand il le faut."
uname -r | grep -qi microsoft && die "WSL detecte : utilisez plutot 'make setup' puis 'make docker-native'."
sudo -v || die "Droits sudo necessaires."

title "1. Paquets systeme + Docker"
sudo apt-get update
sudo apt-get install -y \
  mesa-utils vulkan-tools libvulkan1 x11-utils x11-xserver-utils \
  unzip wget curl jq python3-venv \
  docker.io docker-compose-v2
ok "Paquets installes"

title "2. NVIDIA Container Toolkit (acces GPU depuis Docker)"
if ! need_cmd nvidia-ctk; then
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg --yes
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y nvidia-container-toolkit
fi
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl enable --now docker >/dev/null 2>&1 || true
sudo systemctl restart docker
ok "Runtime nvidia enregistre, Docker demarre"

title "3. Droits utilisateur"
if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  ok "Deja membre du groupe docker"
else
  sudo usermod -aG docker "$USER"
  warn "Ajoute au groupe 'docker' : fermez la session (ou redemarrez) pour que ce soit pris en compte partout."
fi

title "4. Reglages noyau pour DDS"
sudo tee /etc/sysctl.d/60-ros2-dds.conf >/dev/null <<'SYSCTL'
# Reglages recommandes par la documentation Autoware (DDS settings)
net.core.rmem_max=2147483647
net.ipv4.ipfrag_time=3
net.ipv4.ipfrag_high_thresh=134217728
SYSCTL
sudo sysctl -q --system >/dev/null
ok "net.core.rmem_max = $(sysctl -n net.core.rmem_max)"
sudo ip link set lo multicast on
ok "Multicast active sur lo"

title "5. Verification"
if sudo docker run --rm --gpus all ubuntu:24.04 nvidia-smi -L 2>/dev/null | head -1; then
  ok "GPU accessible depuis les conteneurs"
else
  warn "GPU non detecte dans un conteneur : verifiez 'sudo nvidia-ctk runtime configure --runtime=docker'."
fi

title "Termine"
ok "Lancez maintenant : make check"
