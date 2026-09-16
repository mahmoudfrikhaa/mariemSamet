#!/usr/bin/env bash
# Telecharge et installe le binaire de la demo AWSIM (~811 Mo).
# Version "Lightweight" (pipeline URP) : la version standard est en HDRP et
# exige du ray tracing materiel, indisponible sous WSL.
source "$(dirname "$0")/_common.sh"

URL="https://github.com/autowarefoundation/AWSIM/releases/download/${AWSIM_VERSION}/${AWSIM_ZIP}"
CACHE="$HOME/Downloads/awsim"
mkdir -p "$CACHE" "$AWSIM_DIR"

title "AWSIM ${AWSIM_VERSION} (${AWSIM_ZIP})"

BIN=$(find "$AWSIM_DIR" -maxdepth 2 -name '*.x86_64' 2>/dev/null | head -1)
if [ -n "$BIN" ] && [ "${FORCE:-0}" != "1" ]; then
  ok "Deja installe : $BIN"
  info "(FORCE=1 pour retelecharger)"
  exit 0
fi

info "Telechargement depuis $URL"
wget -c -O "$CACHE/$AWSIM_ZIP" "$URL"

info "Decompression vers $AWSIM_DIR"
unzip -q -o "$CACHE/$AWSIM_ZIP" -d "$AWSIM_DIR"

# Le zip contient un dossier racine : on remonte le binaire s'il est imbrique.
BIN=$(find "$AWSIM_DIR" -maxdepth 3 -name '*.x86_64' | head -1)
[ -n "$BIN" ] || die "Aucun binaire *.x86_64 trouve dans l'archive."
chmod +x "$BIN"
chmod -R +x "$(dirname "$BIN")"/*_Data/Plugins 2>/dev/null || true

ok "Installe : $BIN"
info "Taille sur disque : $(du -sh "$AWSIM_DIR" | cut -f1)"
info "Lancement : make awsim"
