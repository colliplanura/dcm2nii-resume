#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/dcm2nii-resume.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

IN_DIR="$TMP_ROOT/in"
OUT_DIR="$TMP_ROOT/out"
mkdir -p "$IN_DIR/a" "$IN_DIR/b" "$OUT_DIR"

FAKE_DCM2NIIX="$TMP_ROOT/fake_dcm2niix"
cat > "$FAKE_DCM2NIIX" <<'EOF'
#!/usr/bin/env bash
out_dir=""
last_arg="${!#}"
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then
    out_dir="$arg"
    break
  fi
  prev="$arg"
done

base="$(basename "$last_arg")"
[ -n "$out_dir" ] && mkdir -p "$out_dir"

if [[ "$base" == "a" ]]; then
  [ -n "$out_dir" ] && {
    touch "$out_dir/${base}.nii.gz"
    touch "$out_dir/${base}.json"
  }
  exit 0
elif [[ "$base" == "b" ]]; then
  [ -n "$out_dir" ] && {
    touch "$out_dir/${base}.nii.gz"
    touch "$out_dir/${base}.json"
  }
  exit 2
else
  [ -n "$out_dir" ] && {
    touch "$out_dir/${base}.nii.gz"
    touch "$out_dir/${base}.json"
  }
  exit 2
fi
EOF
chmod +x "$FAKE_DCM2NIIX"

RUN1_LOG="$TMP_ROOT/run1.log"
RUN2_LOG="$TMP_ROOT/run2.log"

"$SCRIPT" --no-ui --dcm2niix "$FAKE_DCM2NIIX" --cores 1 -o "$OUT_DIR" "$IN_DIR" >"$RUN1_LOG" 2>&1 || true
"$SCRIPT" --no-ui --dcm2niix "$FAKE_DCM2NIIX" --cores 1 -o "$OUT_DIR" "$IN_DIR" >"$RUN2_LOG" 2>&1 || true

CONTROL_DIR="$OUT_DIR/.dcm2nii-resume"
DONE_FILE="$CONTROL_DIR/dcm2nii-done.txt"
FAILED_FILE="$CONTROL_DIR/dcm2nii-failed.txt"

if [[ ! -f "$DONE_FILE" ]]; then
  echo "ERRO: DONE file não foi criado"
  exit 1
fi

DONE_COUNT="$(wc -l < "$DONE_FILE" | tr -d ' ')"
if [[ "$DONE_COUNT" -ne 3 ]]; then
  echo "ERRO: esperado DONE_COUNT=3, atual=$DONE_COUNT"
  echo "Conteúdo do DONE file:"
  cat "$DONE_FILE" || true
  exit 1
fi

if [[ -f "$FAILED_FILE" ]] && [[ -s "$FAILED_FILE" ]]; then
  echo "ERRO: FAILED file deveria estar vazio para retorno 2 tratado como done"
  cat "$FAILED_FILE" || true
  exit 1
fi

# Simula movimentação de outputs por limitação de espaço
mkdir -p "$TMP_ROOT/archive"
find "$OUT_DIR" -maxdepth 1 -type f \( -name '*.nii.gz' -o -name '*.json' \) -exec mv {} "$TMP_ROOT/archive/" \;

# Terceira execução deve continuar funcionando só com arquivos de controle
RUN3_LOG="$TMP_ROOT/run3.log"
"$SCRIPT" --no-ui --dcm2niix "$FAKE_DCM2NIIX" --cores 1 -o "$OUT_DIR" "$IN_DIR" >"$RUN3_LOG" 2>&1 || true

if ! grep -q "A processar: 0" "$RUN3_LOG"; then
  echo "ERRO: após mover .json/.nii.gz, controle de continuação falhou"
  grep -E "Já processadas|A processar|Nada a processar" "$RUN3_LOG" || true
  exit 1
fi

if ! grep -q "A processar: 0" "$RUN2_LOG"; then
  echo "ERRO: segunda execução não zerou pendências"
  grep -E "Já processadas|A processar|Nada a processar" "$RUN2_LOG" || true
  exit 1
fi

if ! grep -q "Nada a processar" "$RUN2_LOG"; then
  echo "ERRO: segunda execução deveria indicar nada a processar"
  grep -E "Já processadas|A processar|Nada a processar" "$RUN2_LOG" || true
  exit 1
fi

echo "OK: smoke test de continuação aprovado"
