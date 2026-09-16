#!/usr/bin/env bash
# Installe un moteur Docker NATIF dans cette distribution WSL.
#
# POURQUOI : Docker Desktop execute son moteur dans une autre distribution WSL.
# Un conteneur lance avec "--network host" s'y retrouve sur un reseau isole
# (192.168.65.x) qui ne peut meme pas joindre cette distribution : AWSIM et
# Autoware ne pourraient jamais echanger leurs topics ROS 2.
# Un moteur natif partage la pile reseau de cette distribution : la loopback
# devient commune, et le DDS fonctionne.
#
# NON DESTRUCTIF : Docker Desktop continue de fonctionner. Le moteur natif
# ecoute sur sa propre socket (/run/docker-native.sock) et est expose via
# un contexte Docker dedie ; la socket de Docker Desktop n'est pas touchee.
#
#   Basculer :  docker context use awsim-native   /   docker context use default
source "$(dirname "$0")/_common.sh"

CTX="awsim-native"
SOCK="/run/docker-native.sock"

[ "$(id -u)" -ne 0 ] || die "Ne pas lancer ce script en root : il utilise sudo quand il le faut."
sudo -v || die "Droits sudo necessaires."

title "1. Depot APT Docker"
. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
if ! curl -fsSL "https://download.docker.com/linux/ubuntu/dists/$CODENAME/Release" >/dev/null 2>&1; then
  warn "Pas de paquets Docker pour '$CODENAME' : repli sur 'noble' (24.04 LTS)."
  CODENAME="noble"
fi
info "Suite utilisee : $CODENAME"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
ok "Depot configure"

title "2. Installation du moteur"
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin iptables
ok "docker-ce installe"

title "3. Socket dediee (coexistence avec Docker Desktop)"
# Docker Desktop occupe deja /run/docker.sock, qui est justement l'adresse par
# defaut de l'unite docker.socket. Plutot que de masquer cette unite (ce qui
# empeche docker.service de demarrer, puisqu'il la requiert), on se contente
# de la faire ecouter ailleurs.
sudo systemctl unmask docker.socket 2>/dev/null || true
sudo rm -f /etc/systemd/system/docker.service.d/10-native-socket.conf
sudo mkdir -p /etc/systemd/system/docker.socket.d
sudo tee /etc/systemd/system/docker.socket.d/10-native-socket.conf >/dev/null <<UNIT
[Socket]
ListenStream=
ListenStream=$SOCK
UNIT
ok "Socket : $SOCK (Docker Desktop garde /run/docker.sock)"

title "4. Acces GPU (NVIDIA Container Toolkit)"
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
ok "Runtime nvidia enregistre"

title "5. Demarrage du service"
sudo systemctl daemon-reload
sudo systemctl enable docker.socket docker.service >/dev/null 2>&1 || true
sudo systemctl stop docker.service docker.socket 2>/dev/null || true
sudo systemctl start docker.socket
sudo systemctl start docker.service
sleep 3
sudo systemctl is-active --quiet docker || {
  err "Le service docker n'a pas demarre. Journal :"
  sudo journalctl -u docker -n 30 --no-pager | sed 's/^/       /'
  exit 1
}
[ -S "$SOCK" ] || die "Socket $SOCK absente alors que le service tourne."
ok "Moteur natif actif sur $SOCK"

title "6. Droits utilisateur"
if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  ok "Deja membre du groupe docker"
else
  sudo usermod -aG docker "$USER"
  warn "Ajoute au groupe 'docker' : fermez et rouvrez le terminal pour que ce soit pris en compte."
fi
sudo chgrp docker "$SOCK" 2>/dev/null || true
sudo chmod 660 "$SOCK" 2>/dev/null || true

title "7. Contexte Docker"
docker context inspect "$CTX" >/dev/null 2>&1 \
  && docker context update "$CTX" --docker "host=unix://$SOCK" >/dev/null \
  || docker context create "$CTX" --docker "host=unix://$SOCK" \
       --description "Moteur natif WSL (AWSIM/Autoware)" >/dev/null
ok "Contexte '$CTX' disponible"
info "Les scripts du projet l'utilisent automatiquement."
info "Manuellement : docker context use $CTX   (retour : docker context use default)"

title "8. Verification"
HOST_IP=$(ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1)
CTR_IP=$(docker --context "$CTX" run --rm --network host alpine:3 ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
info "IP distro    : $HOST_IP"
info "IP conteneur : ${CTR_IP:-echec}"
if [ "$HOST_IP" = "${CTR_IP:-}" ]; then
  ok "Pile reseau partagee : AWSIM et Autoware pourront communiquer."
else
  err "Les piles reseau different encore. Verifiez le journal : sudo journalctl -u docker -n 50"
  exit 1
fi
if docker --context "$CTX" run --rm --gpus all --runtime=nvidia ubuntu:24.04 nvidia-smi -L 2>/dev/null | head -1; then
  ok "GPU accessible depuis les conteneurs"
else
  warn "GPU non detecte dans un conteneur : verifiez 'nvidia-ctk runtime configure' et le pilote Windows."
fi

title "Termine"
ok "Relancez : make check"
