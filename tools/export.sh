#!/usr/bin/env bash
# Exporta las builds públicas de Balactorio (Linux y Windows, x86_64) a builds/ con la clave de
# Augur de prod embebida (Plan «Builds Públicas con Consentimiento», M2).
#
# La clave vive FUERA del repo, en ~/.config/augur/balactorio-release.key (chmod 600, una línea);
# AUGUR_RELEASE_KEY_FILE apunta a otra ruta si hace falta. El script la vuelca en
# res://augur_release.cfg, que export_presets.cfg mete en el .pck (include_filter) y que el juego
# solo lee en build exportada (Main._augur_settings()). El .cfg está en .gitignore y se BORRA al
# salir, pase lo que pase (trap), para que la clave no se quede en el working tree.
#
# Uso: tools/export.sh        (desde cualquier sitio; no imprime la clave)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_FILE="${AUGUR_RELEASE_KEY_FILE:-$HOME/.config/augur/balactorio-release.key}"
ENDPOINT="https://augur.dcahomelab.com"
CFG="$REPO/augur_release.cfg"
GODOT="${GODOT:-godot-4}"

if [[ ! -r "$KEY_FILE" ]]; then
	echo "ERROR: no se puede leer la clave de Augur de prod en '$KEY_FILE'." >&2
	echo "       Crea el fichero con la write_key del proyecto balactorio en prod (una línea) y" >&2
	echo "       'chmod 600', o apunta AUGUR_RELEASE_KEY_FILE a otra ruta." >&2
	exit 1
fi

# Sin saltos de línea ni espacios: el fichero se escribió con echo y trae '\n'.
KEY="$(tr -d '[:space:]' < "$KEY_FILE")"
if [[ -z "$KEY" ]]; then
	echo "ERROR: '$KEY_FILE' está vacío." >&2
	exit 1
fi

# Desde aquí el .cfg existe: se borra al salir, también si el export falla o se corta con Ctrl+C.
trap 'rm -f "$CFG"' EXIT
( umask 077; printf '[augur]\n\nwrite_key="%s"\nendpoint="%s"\n' "$KEY" "$ENDPOINT" > "$CFG" )
unset KEY

mkdir -p "$REPO/builds/linux" "$REPO/builds/windows"
cd "$REPO"
# El --import primero: en un checkout recién clonado .godot/ no existe y el export fallaría.
timeout 300 "$GODOT" --headless --path . --import
timeout 300 "$GODOT" --headless --path . --export-release "Linux" builds/linux/Balactorio.x86_64
timeout 300 "$GODOT" --headless --path . --export-release "Windows Desktop" builds/windows/Balactorio.exe

for f in builds/linux/Balactorio.x86_64 builds/windows/Balactorio.exe; do
	if [[ ! -s "$f" ]]; then
		echo "ERROR: el export no ha dejado $f." >&2
		exit 1
	fi
done
echo "Builds listas:"
ls -lh builds/linux builds/windows
