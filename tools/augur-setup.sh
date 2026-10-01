#!/usr/bin/env bash
# =============================================================================
# augur-setup.sh — Balactorio: catálogo, índices, tableros y contexto en un Augur
# =============================================================================
# Uso:
#   tools/augur-setup.sh <endpoint> <email> [slug]
#   tools/augur-setup.sh http://localhost:8897 yo@ejemplo.com          (dev)
#   tools/augur-setup.sh https://augur.dcahomelab.com yo@ejemplo.com   (prod)
#
# Deja el proyecto `balactorio` (o el slug que se pase) de ese Augur listo para leer runs
# (Plan «Analítica de Runs», M5). Cuatro pasos, todos idempotentes:
#   1. `catalog.upsert` de cada evento que imprime tools/export_catalog.gd (el catálogo expandido de
#      resources/analyticsCatalog.json). NO borra eventos que ya no estén en el catálogo.
#   2. `propIndex.create` de checkpoints, result, card, factory y balance_id; «ya indexada» no es un
#      error. Los índices son GLOBALES al Augur (tope de 16 entre todos los proyectos).
#   3. Por cada tablero de tools/augur-boards.json: lo busca por nombre (`board.list`) y lo crea si no
#      está; dentro, busca cada gráfica por título (`board.get`) y hace `chart.update` si existe o
#      `chart.create` si no. NO borra gráficas ni tableros que ya no estén en el JSON, y cambiar un
#      título en el JSON crea una gráfica nueva (la vieja se borra a mano desde el dashboard).
#   4. `project.update {claude_context}` con el texto de tools/augur-context.md.
#
# La contraseña se pide con `read -s`: nunca por argumento (queda en el historial y en `ps`) ni por
# fichero. La API de gestión de Augur es sesión por cookie: el tarro va a un temporal que se borra al
# salir, pase lo que pase. Los pasos 2 y 4 piden rol owner en el proyecto (el 1 y el 3, editor).
#
# Necesita curl, jq y godot-4 (el export expande los enums desde factoryParams.json).
# Calcado de libraryVue/tools/augur-catalog.sh.
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOARDS_FILE="$ROOT_DIR/tools/augur-boards.json"
CONTEXT_FILE="$ROOT_DIR/tools/augur-context.md"

# Props que se indexan (paso 2) con su tipo de valor en Augur.
INDEXED_PROPS=(checkpoints:number result:string card:string factory:string balance_id:string)

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  sed -n '5,8p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi

ENDPOINT="${1%/}"
EMAIL="$2"
SLUG="${3:-balactorio}"
API="$ENDPOINT/index.php"

for bin in curl jq godot-4; do
  command -v "$bin" >/dev/null || { echo "Falta '$bin' en el PATH" >&2; exit 1; }
done
for f in "$BOARDS_FILE" "$CONTEXT_FILE"; do
  [ -s "$f" ] || { echo "Falta $f" >&2; exit 1; }
done
jq -e '.boards | type == "array" and length > 0' "$BOARDS_FILE" >/dev/null \
  || { echo "$BOARDS_FILE no es un JSON con .boards[]" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"
JAR="$WORK/cookies"
CATALOG_JSON="$WORK/catalog.json"

# ── 1a. El catálogo, exportado al formato de catalog.upsert (antes de pedir nada) ─
# Godot antepone su cabecera por stdout: el JSON empieza en la primera línea con `[`. El snap de
# godot-4 no lee /tmp, pero aquí solo escribe stdout y el que escribe en $WORK es el shell.
if ! timeout 120 godot-4 --headless --path "$ROOT_DIR" --script res://tools/export_catalog.gd \
     > "$WORK/export.out" 2> "$WORK/export.err"; then
  echo "tools/export_catalog.gd falló:" >&2
  tail -n 20 "$WORK/export.err" >&2
  exit 1
fi
sed -n '/^\[/,$p' "$WORK/export.out" > "$CATALOG_JSON"
if ! jq -e 'type == "array" and length > 0' "$CATALOG_JSON" >/dev/null 2>&1; then
  echo "tools/export_catalog.gd no ha devuelto un JSON válido (prueba a ejecutarlo a mano)" >&2
  exit 1
fi
TOTAL_EVENTS="$(jq 'length' "$CATALOG_JSON")"
TOTAL_CHARTS="$(jq '[.boards[].charts[]] | length' "$BOARDS_FILE")"
echo "Catálogo: $TOTAL_EVENTS eventos · tableros: $(jq '.boards | length' "$BOARDS_FILE") con $TOTAL_CHARTS gráficas"

# ── Sesión ─────────────────────────────────────────────────────────────────────
# `call` lee el cuerpo JSON por stdin → escribe la respuesta en $WORK/resp y devuelve el código HTTP.
# Reintenta los fallos de CONEXIÓN (no los HTTP: sin `-f`, un 4xx/5xx no es error de curl). Visto el
# 2026-10-01 contra prod: en ráfaga, alguna conexión al borde de Cloudflare muere en el handshake TLS
# (`SSL_ERROR_SYSCALL`) sin llegar al backend — una vez a las 13 peticiones, otra a las 24—, y con
# `set -e` eso tumbaba el script entero. Reintentar es seguro precisamente por eso: la petición no
# llegó a salir. Ojo: `--retry` también repite los 408/429/5xx, y ahí la petición sí llegó; un
# `chart.create` que devolviera 500 habiendo creado la gráfica saldría duplicado (se borra a mano).
# El cuerpo pasa por un fichero porque `@-` no se puede releer en un reintento, y se borra al
# momento: el del login lleva la contraseña.
call () {
  local body="$WORK/body" rc=0
  cat > "$body"
  curl -sS -o "$WORK/resp" -w '%{http_code}' -b "$JAR" -c "$JAR" \
    --connect-timeout 10 --retry 4 --retry-delay 1 --retry-all-errors \
    -H 'Content-Type: application/json' --data-binary @"$body" "$API" || rc=$?
  rm -f "$body"
  return "$rc"
}
resp () { cat "$WORK/resp"; }

# Sin terminal (p. ej. el `!` de Claude Code) `read` recibe EOF y `set -e` saldría sin decir nada.
if [ ! -t 0 ]; then
  echo "Hace falta una terminal interactiva para pedir la contraseña: ejecútalo en tu terminal." >&2
  exit 1
fi
read -r -s -p "Contraseña de $EMAIL en $ENDPOINT: " PASSWORD
echo
CODE="$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{action: "auth.login", email: $e, password: $p}' | call)"
unset PASSWORD
if [ "$CODE" != "200" ]; then
  echo "Login fallido (HTTP $CODE): $(resp)" >&2
  exit 1
fi
# Cerrar la sesión en el servidor también al salir por error (la cookie se borra con el temporal).
trap 'echo "{\"action\":\"auth.logout\"}" | call >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

FAILED=0
fail () { FAILED=$((FAILED + 1)); echo "  ✗ $*" >&2; }

# ── El proyecto ────────────────────────────────────────────────────────────────
CODE="$(echo '{"action":"project.list"}' | call)"
if [ "$CODE" != "200" ]; then
  echo "project.list falló (HTTP $CODE): $(resp)" >&2
  exit 1
fi
PROJECT_ID="$(jq -r --arg s "$SLUG" '.projects[] | select(.slug == $s) | .id' "$WORK/resp")"
if [ -z "$PROJECT_ID" ]; then
  echo "No hay proyecto '$SLUG' visible para $EMAIL en $ENDPOINT" >&2
  exit 1
fi
echo "Proyecto $SLUG → id $PROJECT_ID"

# ── 1b. Un upsert por evento ───────────────────────────────────────────────────
OK=0
while IFS= read -r event; do
  name="$(jq -r '.name' <<<"$event")"
  CODE="$(jq -c --argjson pid "$PROJECT_ID" '{action: "catalog.upsert", project_id: $pid} + .' <<<"$event" | call)"
  if [ "$CODE" = "200" ]; then OK=$((OK + 1)); else fail "catalog.upsert $name (HTTP $CODE): $(resp)"; fi
done < <(jq -c '.[]' "$CATALOG_JSON")
echo "1. Catálogo declarado: $OK / $TOTAL_EVENTS"

# ── 2. Índices de props ────────────────────────────────────────────────────────
CODE="$(jq -n --argjson pid "$PROJECT_ID" '{action: "propIndex.list", project_id: $pid}' | call)"
if [ "$CODE" = "200" ]; then cp "$WORK/resp" "$WORK/indexes.json"; else echo '{"indexes":[]}' > "$WORK/indexes.json"; fi
for entry in "${INDEXED_PROPS[@]}"; do
  prop="${entry%%:*}"
  type="${entry#*:}"
  status="$(jq -r --arg p "$prop" --arg t "$type" \
    '[.indexes[] | select((.prop | ascii_downcase) == ($p | ascii_downcase) and .value_type == $t) | .status][0] // ""' \
    "$WORK/indexes.json")"
  if [ "$status" = "ready" ] || [ "$status" = "building" ]; then
    echo "2. Índice $prop ($type): ya existe ($status)"
    continue
  fi
  CODE="$(jq -n --argjson pid "$PROJECT_ID" --arg p "$prop" --arg t "$type" \
    '{action: "propIndex.create", project_id: $pid, prop: $p, value_type: $t}' | call)"
  if [ "$CODE" = "202" ] || [ "$CODE" = "200" ]; then
    new_status="$(jq -r '.index.status' "$WORK/resp")"
    if [ "$new_status" = "failed" ]; then
      fail "propIndex.create $prop: failed — $(jq -r '.index.error' "$WORK/resp")"
    else
      echo "2. Índice $prop ($type): creado ($new_status)"
    fi
  elif [ "$CODE" = "400" ] && grep -q 'ya está indexada\|ya se está indexando' "$WORK/resp"; then
    echo "2. Índice $prop ($type): ya existe"
  else
    fail "propIndex.create $prop (HTTP $CODE): $(resp)"
  fi
done

# ── 3. Tableros y gráficas ─────────────────────────────────────────────────────
CODE="$(jq -n --argjson pid "$PROJECT_ID" '{action: "board.list", project_id: $pid}' | call)"
if [ "$CODE" != "200" ]; then
  echo "board.list falló (HTTP $CODE): $(resp)" >&2
  exit 1
fi
cp "$WORK/resp" "$WORK/boards.json"

CREATED=0
UPDATED=0
while IFS= read -r board; do
  bname="$(jq -r '.name' <<<"$board")"
  # El nombre es único por proyecto sin distinguir mayúsculas (collation de Augur).
  bid="$(jq -r --arg n "$bname" '[.boards[] | select((.name | ascii_downcase) == ($n | ascii_downcase)) | .id][0] // ""' "$WORK/boards.json")"
  if [ -z "$bid" ]; then
    CODE="$(jq -n --argjson pid "$PROJECT_ID" --arg n "$bname" '{action: "board.create", project_id: $pid, name: $n}' | call)"
    if [ "$CODE" != "200" ]; then
      fail "board.create «$bname» (HTTP $CODE): $(resp)"
      continue
    fi
    bid="$(jq -r '.board.id' "$WORK/resp")"
    echo "3. Tablero «$bname»: creado (id $bid)"
  else
    echo "3. Tablero «$bname»: ya existe (id $bid)"
  fi

  CODE="$(jq -n --argjson pid "$PROJECT_ID" --argjson bid "$bid" '{action: "board.get", project_id: $pid, board_id: $bid}' | call)"
  if [ "$CODE" != "200" ]; then
    fail "board.get «$bname» (HTTP $CODE): $(resp)"
    continue
  fi
  cp "$WORK/resp" "$WORK/board.json"

  while IFS= read -r chart; do
    title="$(jq -r '.title' <<<"$chart")"
    cid="$(jq -r --arg t "$title" '[.charts[] | select(.title == $t) | .id][0] // ""' "$WORK/board.json")"
    if [ -n "$cid" ]; then
      CODE="$(jq -c --argjson pid "$PROJECT_ID" --argjson cid "$cid" \
        '{action: "chart.update", project_id: $pid, chart_id: $cid, title, definition, note: (.note // null)}' <<<"$chart" | call)"
      if [ "$CODE" = "200" ]; then UPDATED=$((UPDATED + 1)); else fail "chart.update «$title» (HTTP $CODE): $(resp)"; fi
    else
      CODE="$(jq -c --argjson pid "$PROJECT_ID" --argjson bid "$bid" \
        '{action: "chart.create", project_id: $pid, board_id: $bid, title, definition, note: (.note // null)}' <<<"$chart" | call)"
      if [ "$CODE" = "200" ]; then CREATED=$((CREATED + 1)); else fail "chart.create «$title» (HTTP $CODE): $(resp)"; fi
    fi
  done < <(jq -c '.charts[]' <<<"$board")
done < <(jq -c '.boards[]' "$BOARDS_FILE")
echo "3. Gráficas: $CREATED creadas, $UPDATED actualizadas (de $TOTAL_CHARTS)"

# ── 4. Contexto para Claude ────────────────────────────────────────────────────
CODE="$(jq -n --argjson pid "$PROJECT_ID" --rawfile ctx "$CONTEXT_FILE" \
  '{action: "project.update", project_id: $pid, claude_context: $ctx}' | call)"
if [ "$CODE" = "200" ]; then
  echo "4. claude_context escrito ($(wc -c < "$CONTEXT_FILE") bytes)"
else
  fail "project.update claude_context (HTTP $CODE): $(resp)"
fi

if [ "$FAILED" -eq 0 ]; then
  echo "Listo: sin fallos."
else
  echo "Terminado con $FAILED fallo(s): revisa los ✗ de arriba." >&2
  exit 1
fi
