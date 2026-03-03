#!/usr/bin/env bash
set -euo pipefail

# dcm2nii-resume.sh
# Wrapper para dcm2niiXL com controle de continuação.
# O dcm2niiXL já faz processamento paralelo internamente.
# Este script rastreia subpastas já processadas para permitir retomada.
#
# Uso: ./dcm2nii-resume.sh [opções] -o /destino /origem

# ============================================================================
# CONFIGURAÇÃO (valores default)
# ============================================================================
DCM2NIIX="dcm2niix"
SEARCH_DEPTH=10
NUM_CORES=0  # 0 = autodetect
MAIN_PID="$$"
UI_DISABLED=false
BUBBLE_TUI_BIN="./bin/dcm2nii-resume-tui"
INTERACTIVE_ARGS=()

# Arquivos de controle (serão definidos após parse do OUTPUT_DIR)
STATE_FILE=""
LOG_FILE=""
RAW_LOG_FILE=""
DONE_FILE=""
FAILED_FILE=""
LOCK_FILE=""
CONTROL_DIR=""
CLEANUP_DONE=false

restore_tty_mode() {
  if [ -t 0 ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
    stty sane < /dev/tty > /dev/tty 2>/dev/null || true
  fi
}

tui_rebuild_needed() {
  [ ! -x "$BUBBLE_TUI_BIN" ] && return 0

  local source_file
  for source_file in \
    "./go.mod" \
    "./go.sum" \
    "./cmd/dcm2nii-resume-tui/main.go"
  do
    if [ -f "$source_file" ] && [ "$source_file" -nt "$BUBBLE_TUI_BIN" ]; then
      return 0
    fi
  done

  return 1
}

# ============================================================================
# FUNÇÕES AUXILIARES
# ============================================================================

offer_bubbletea_install() {
  if $UI_DISABLED; then
    return 1
  fi

  if [ ! -t 0 ] || [ ! -t 1 ] || [ ! -t 2 ]; then
    return 1
  fi

  if ! tui_rebuild_needed; then
    return 0
  fi

  echo
  if [ -x "$BUBBLE_TUI_BIN" ]; then
    echo "Atualização detectada na TUI Bubble Tea. Recompilando..."
  else
    echo "Preparando interface full-screen (Bubble Tea)..."
  fi
  restore_tty_mode

  if ! command -v go >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      echo "Go não encontrado."
      read -r -p "Instalar Go via Homebrew para habilitar a TUI? [Y/n]: " choice < /dev/tty
      choice="${choice//$'\r'/}"
      choice="${choice:-Y}"
      if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "Instalando Go via Homebrew..."
        if ! brew install go; then
          echo "Falha ao instalar Go. Continuando em modo texto puro."
          return 1
        fi
      else
        echo "Instalação do Go recusada. Continuando em modo texto puro."
        return 1
      fi
    else
      echo "Go e Homebrew não encontrados. Continuando em modo texto puro."
      return 1
    fi
  fi

  echo "Compilando TUI Bubble Tea..."
  mkdir -p "$(dirname "$BUBBLE_TUI_BIN")"
  if go mod tidy && go build -o "$BUBBLE_TUI_BIN" ./cmd/dcm2nii-resume-tui; then
    echo "TUI Bubble Tea pronta."
    return 0
  fi

  echo "Falha ao compilar TUI Bubble Tea. Continuando em modo texto puro."
  return 1
}

maybe_launch_bubbletea_ui() {
  if $UI_DISABLED; then
    return 1
  fi

  if [ ! -t 0 ] || [ ! -t 1 ] || [ ! -t 2 ]; then
    return 1
  fi

  local tui_cmd="$BUBBLE_TUI_BIN"
  offer_bubbletea_install || return 1

  if [ -x "$tui_cmd" ]; then
    exec env DCM2NII_RESUME_SCRIPT="$0" "$tui_cmd" "$@"
  fi

  return 1
}

append_file_to_raw_log() {
  local source_file="$1"
  local lockdir="${RAW_LOG_FILE}.lock"
  [ -f "$source_file" ] || return 0

  acquire_lock "$lockdir"
  cat "$source_file" >> "$RAW_LOG_FILE"
  release_lock "$lockdir"
}

log() {
  local msg="$(date '+%Y-%m-%d %H:%M:%S') - $*"
  if [ -n "$LOG_FILE" ]; then
    echo "$msg" >> "$LOG_FILE"
  fi
  echo "$msg"
}

log_error() {
  local msg="$(date '+%Y-%m-%d %H:%M:%S') - ERRO: $*"
  if [ -n "$LOG_FILE" ]; then
    echo "$msg" >> "$LOG_FILE"
  fi
  echo "$msg" >&2
}

show_usage() {
  local exit_code="${1:-2}"
  cat <<EOF
Uso: $0 [opções] -o <destino> <origem>

Wrapper para dcm2niiXL com controle de continuação.
Processa diretórios DICOM em paralelo e permite retomada após interrupção.

Opções do script:
  -h, --help       Mostra esta ajuda e sai
  --dcm2niix CMD   Caminho para dcm2niix (padrão: dcm2niix no PATH)
  --depth N        Profundidade de busca em subpastas (padrão: 10)
  --cores N        Número de threads (padrão: 0 = autodetect)
  --no-ui          Força modo texto puro (sem Bubble Tea)

Interface rica:
  Em terminal interativo, o script prioriza a TUI full-screen em Bubble Tea
  (com ou sem parâmetros, exceto quando --no-ui é informado).
  Se o binário não estiver disponível, oferece preparação automática via Go/Homebrew.

Opções dcm2niix (com valores padrão):
  -z i|o|y|n     Compressão gzip (padrão: i)
  -v N           Verbosidade (padrão: 0)
  -f formato     Formato do nome do arquivo (padrão: %i-%n-%t-%p-%b-%d)
  -o destino     Diretório de saída (OBRIGATÓRIO)

Arquivos de controle (salvos em /destino/.dcm2nii-resume):
  dcm2nii-resume.log    Log detalhado
  dcm2nii-dcm2niix.log  Log bruto do dcm2niix
  dcm2nii-done.txt      Subpastas já convertidas (skip automático)
  dcm2nii-failed.txt    Subpastas que falharam
  dcm2nii-resume.state  Estado da última execução

Exemplos:
  # Sem parâmetros: modo interativo (pede campos necessários)
  $0

  $0 -o /Users/colliplanura/nifti /Volumes/AAA/AAA1
  
  # Com opções do script:
  $0 --dcm2niix /usr/bin/dcm2niix --depth 5 --cores 8 -o /saida /origem

  # Sobrescrevendo opções dcm2niix padrão:
  $0 -z n -v 2 -o /saida /origem

  # Forçar modo texto (sem dashboard):
  $0 --no-ui -o /saida /origem

  # Limpar estado e recomeçar do zero:
  rm -f /destino/.dcm2nii-resume/dcm2nii-done.txt /destino/.dcm2nii-resume/dcm2nii-failed.txt
  $0 -o /Users/colliplanura/nifti /Volumes/AAA/AAA1
EOF
  exit "$exit_code"
}

cleanup() {
  if $CLEANUP_DONE; then
    return 0
  fi
  CLEANUP_DONE=true

  restore_tty_mode
  # Mata processos filhos em background
  jobs -p | xargs -r kill 2>/dev/null || true
  wait 2>/dev/null || true
  [ -n "$LOCK_FILE" ] && rm -f "$LOCK_FILE"
  log "Script interrompido. Pode retomar executando novamente."
  if [ -n "$DONE_FILE" ]; then
    log "Subpastas já processadas: $(wc -l < "$DONE_FILE" 2>/dev/null | tr -d ' ' || echo 0)"
  fi
}

handle_signal() {
  local signal_name="$1"
  cleanup

  case "$signal_name" in
    INT)
      exit 130
      ;;
    TERM)
      exit 143
      ;;
    TSTP)
      exit 148
      ;;
    *)
      exit 1
      ;;
  esac
}

check_lock() {
  if [ -f "$LOCK_FILE" ]; then
    local pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      log_error "Outra instância está rodando (PID: $pid). Use 'kill $pid' para encerrar."
      exit 1
    else
      log "Removendo lock file órfão..."
      rm -f "$LOCK_FILE"
    fi
  fi
  echo $$ > "$LOCK_FILE"
}

check_dependencies() {
  if ! command -v "$DCM2NIIX" &>/dev/null; then
    log_error "dcm2niix não encontrado: $DCM2NIIX"
    log_error "Instale dcm2niix no PATH ou use --dcm2niix para especificar o caminho"
    exit 1
  fi
  DCM2NIIX="$(command -v "$DCM2NIIX")"
  log "Usando dcm2niix: $DCM2NIIX"
}

init_state_files() {
  # Arquivos de controle são salvos em uma pasta oculta dedicada
  # para não serem afetados por movimentação de .json/.nii.gz
  CONTROL_DIR="${OUTPUT_DIR}/.dcm2nii-resume"
  STATE_FILE="${CONTROL_DIR}/dcm2nii-resume.state"
  LOG_FILE="${CONTROL_DIR}/dcm2nii-resume.log"
  RAW_LOG_FILE="${CONTROL_DIR}/dcm2nii-dcm2niix.log"
  DONE_FILE="${CONTROL_DIR}/dcm2nii-done.txt"
  FAILED_FILE="${CONTROL_DIR}/dcm2nii-failed.txt"
  LOCK_FILE="${CONTROL_DIR}/dcm2nii-resume.lock"

  mkdir -p "$OUTPUT_DIR"

  # Migração automática do layout antigo (arquivos no root de saída)
  local legacy_done="${OUTPUT_DIR}/dcm2nii-done.txt"
  local legacy_failed="${OUTPUT_DIR}/dcm2nii-failed.txt"
  local legacy_state="${OUTPUT_DIR}/dcm2nii-resume.state"
  local legacy_log="${OUTPUT_DIR}/dcm2nii-resume.log"
  local legacy_raw_log="${OUTPUT_DIR}/dcm2nii-dcm2niix.log"
  local legacy_lock="${OUTPUT_DIR}/dcm2nii-resume.lock"

  mkdir -p "$CONTROL_DIR"
  [ -f "$legacy_done" ] && [ ! -f "$DONE_FILE" ] && mv "$legacy_done" "$DONE_FILE"
  [ -f "$legacy_failed" ] && [ ! -f "$FAILED_FILE" ] && mv "$legacy_failed" "$FAILED_FILE"
  [ -f "$legacy_state" ] && [ ! -f "$STATE_FILE" ] && mv "$legacy_state" "$STATE_FILE"
  [ -f "$legacy_log" ] && [ ! -f "$LOG_FILE" ] && mv "$legacy_log" "$LOG_FILE"
  [ -f "$legacy_raw_log" ] && [ ! -f "$RAW_LOG_FILE" ] && mv "$legacy_raw_log" "$RAW_LOG_FILE"
  [ -f "$legacy_lock" ] && [ ! -f "$LOCK_FILE" ] && mv "$legacy_lock" "$LOCK_FILE"

  touch "$DONE_FILE" "$FAILED_FILE" "$LOG_FILE" "$RAW_LOG_FILE"
}

update_ui_header() {
  return 0
}

detect_cores() {
  if [ "$NUM_CORES" -lt 1 ]; then
    NUM_CORES=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    if [ "$NUM_CORES" -lt 1 ]; then
      NUM_CORES=4
    fi
  fi
  log "Usando $NUM_CORES threads"
}

# Verifica se uma subpasta já foi processada
is_done() {
  local dir="$1"
  grep -Fxq "$dir" "$DONE_FILE" 2>/dev/null
}

# Lock usando mkdir (atômico e portável para macOS/Linux)
acquire_lock() {
  local lockdir="$1"
  # Remove arquivo de lock antigo (do código flock) se existir
  [ -f "$lockdir" ] && rm -f "$lockdir"
  while ! mkdir "$lockdir" 2>/dev/null; do
    sleep 0.1
  done
}

release_lock() {
  local lockdir="$1"
  rmdir "$lockdir" 2>/dev/null || rm -rf "$lockdir" 2>/dev/null || true
}

# Marca subpasta como processada (thread-safe com lock)
mark_done() {
  local dir="$1"
  local lockdir="${DONE_FILE}.lock"
  acquire_lock "$lockdir"
  echo "$dir" >> "$DONE_FILE"
  release_lock "$lockdir"
}

# Marca subpasta como falha (thread-safe)
mark_failed() {
  local dir="$1"
  local lockdir="${FAILED_FILE}.lock"
  acquire_lock "$lockdir"
  echo "$dir" >> "$FAILED_FILE"
  release_lock "$lockdir"
}

preparse_ui_flags() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-ui)
        UI_DISABLED=true
        ;;
    esac
    shift
  done
}

prompt_with_default_cli() {
  local label="$1"
  local default_value="$2"
  local value
  read -r -p "$label [$default_value]: " value
  if [ -z "$value" ]; then
    value="$default_value"
  fi
  printf '%s' "$value"
}

prompt_required_cli() {
  local label="$1"
  local value=""
  while [ -z "$value" ]; do
    read -r -p "$label: " value
  done
  printf '%s' "$value"
}

collect_interactive_args() {
  local input_dir output_dir dcm2niix_cmd depth cores gzip verbosity filename_format
  echo "Modo interativo (texto puro)"
  input_dir="$(prompt_required_cli "Diretorio de origem (DICOM)")"
  output_dir="$(prompt_required_cli "Diretorio de destino (NIfTI)")"
  dcm2niix_cmd="$(prompt_with_default_cli "Caminho dcm2niix" "$DCM2NIIX")"
  depth="$(prompt_with_default_cli "Profundidade de busca" "$SEARCH_DEPTH")"
  cores="$(prompt_with_default_cli "Numero de threads (0=auto)" "$NUM_CORES")"
  gzip="$(prompt_with_default_cli "Compressao -z (i/o/y/n)" "i")"
  verbosity="$(prompt_with_default_cli "Verbosidade -v" "0")"
  filename_format="$(prompt_with_default_cli "Formato -f" "%i-%n-%t-%p-%b-%d")"

  INTERACTIVE_ARGS=(
    "--dcm2niix" "$dcm2niix_cmd"
    "--depth" "$depth"
    "--cores" "$cores"
    "-z" "$gzip"
    "-v" "$verbosity"
    "-f" "$filename_format"
    "-o" "$output_dir"
    "$input_dir"
  )
}

# Parse argumentos para extrair origem e opções
parse_args() {
  ARGS=()
  OUTPUT_DIR=""
  INPUT_DIR=""
  local has_z=false
  local has_v=false
  local has_f=false
  
  while [ $# -gt 0 ]; do
    case "$1" in
      --dcm2niix)
        DCM2NIIX="$2"
        shift 2
        ;;
      --depth)
        SEARCH_DEPTH="$2"
        shift 2
        ;;
      --cores)
        NUM_CORES="$2"
        shift 2
        ;;
      --no-ui)
        UI_DISABLED=true
        shift
        ;;
      -o)
        OUTPUT_DIR="$2"
        ARGS+=("-o" "$2")
        shift 2
        ;;
      -d)
        # Ignora -d pois controlamos via --depth
        shift 2
        ;;
      -z)
        has_z=true
        ARGS+=("-z" "$2")
        shift 2
        ;;
      -v)
        has_v=true
        ARGS+=("-v" "$2")
        shift 2
        ;;
      -f)
        has_f=true
        ARGS+=("-f" "$2")
        shift 2
        ;;
      -*)
        ARGS+=("$1")
        if [ $# -gt 1 ] && [[ ! "$2" =~ ^- ]]; then
          ARGS+=("$2")
          shift
        fi
        shift
        ;;
      *)
        INPUT_DIR="$1"
        shift
        ;;
    esac
  done
  
  # Aplica valores padrão para opções dcm2niix não especificadas
  $has_z || ARGS+=("-z" "i")
  $has_v || ARGS+=("-v" "0")
  $has_f || ARGS+=("-f" "%i-%n-%t-%p-%b-%d")
  
  if [ -z "$INPUT_DIR" ]; then
    log_error "Diretório de origem não especificado"
    show_usage
  fi
  
  if [ -z "$OUTPUT_DIR" ]; then
    log_error "Diretório de saída não especificado (use -o)"
    show_usage
  fi
  
  if [ ! -d "$INPUT_DIR" ]; then
    log_error "Diretório de origem não existe: $INPUT_DIR"
    exit 1
  fi

  update_ui_header
  
  mkdir -p "$OUTPUT_DIR"
}

# Processa uma única subpasta
process_subdir() {
  local dir="$1"
  local rel_path="${dir#$INPUT_DIR/}"
  local cmd_log_file
  local exit_code=0
  
  # Skip se já processado
  if is_done "$dir"; then
    return 0
  fi
  
  log "PROCESSANDO: $rel_path"
  
  local start_time=$(date +%s)
  cmd_log_file="$(mktemp)"
  
  # Executa dcm2niix com -d 0 (só processa o diretório atual, não subpastas)
  if "$DCM2NIIX" -d 0 "${ARGS[@]}" "$dir" > "$cmd_log_file" 2>&1; then
    exit_code=0
  else
    exit_code=$?
  fi

  if [ "$exit_code" -eq 0 ]; then
    append_file_to_raw_log "$cmd_log_file"
    rm -f "$cmd_log_file"
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    log "SUCESSO: $rel_path (${elapsed}s)"
    mark_done "$dir"
    return 0
  else
    append_file_to_raw_log "$cmd_log_file"
    rm -f "$cmd_log_file"
    case $exit_code in
      2)
        # Sem imagens DICOM válidas - marca silenciosamente como processado
        mark_done "$dir"
        ;;
      *)
        log "FALHA: $rel_path (código: $exit_code)"
        mark_failed "$dir"
        ;;
    esac
    return $exit_code
  fi
}

# Loop principal de processamento paralelo
process_all() {
  local total_found=0
  local total_skip=0
  local total_process=0
  local n_jobs=0
  
  log "Listando subpastas em: $INPUT_DIR (profundidade: $SEARCH_DEPTH)"
  log "Aguarde, varredura em andamento..."
  
  # Busca diretórios mostrando progresso
  local tmpfile=$(mktemp)
  local count=0
  while IFS= read -r dir; do
    echo "$dir" >> "$tmpfile"
    count=$((count + 1))
    if [ $((count % 100)) -eq 0 ]; then
      printf "\r  Encontradas: %d subpastas..." "$count" >&2
    fi
  done < <(find "$INPUT_DIR" -maxdepth "$SEARCH_DEPTH" -type d 2>/dev/null)
  printf "\r  Encontradas: %d subpastas (concluído)\n" "$count" >&2
  
  total_found=$count
  log "Varredura concluída: $total_found subpastas encontradas"
  
  # Filtra diretórios já processados e conta
  local dirs_to_process=()
  log "Verificando subpastas já processadas..."
  count=0
  while IFS= read -r dir; do
    count=$((count + 1))
    if [ $((count % 100)) -eq 0 ]; then
      printf "\r  Verificando: %d/%d..." "$count" "$total_found" >&2
    fi
    if is_done "$dir"; then
      total_skip=$((total_skip + 1))
    else
      dirs_to_process+=("$dir")
      total_process=$((total_process + 1))
    fi
  done < "$tmpfile"
  printf "\r  Verificação concluída: %d/%d                    \n" "$count" "$total_found" >&2
  rm -f "$tmpfile"
  
  log "Já processadas (skip): $total_skip"
  log "A processar: $total_process"
  
  if [ "$total_process" -eq 0 ]; then
    log "Nada a processar. Todas as subpastas já foram convertidas."
    return 0
  fi
  
  log "Iniciando conversão com $NUM_CORES threads..."
  
  local processed=0
  for dir in "${dirs_to_process[@]}"; do
    # Processa em background
    process_subdir "$dir" &
    
    # Controle de jobs paralelos
    n_jobs=$(jobs -pr | wc -l)
    while [ "$n_jobs" -ge "$NUM_CORES" ]; do
      sleep 0.4
      n_jobs=$(jobs -pr | wc -l)
    done
    
    processed=$((processed + 1))
    if [ $((processed % 100)) -eq 0 ]; then
      log "Progresso: $processed/$total_process subpastas iniciadas"
    fi
  done
  
  # Aguarda todos os jobs terminarem
  log "Aguardando conclusão dos jobs restantes..."
  while :; do
    n_jobs=$(jobs -pr | wc -l)
    [ "$n_jobs" -eq 0 ] && break
    sleep 0.4
  done

  if ! wait; then
    log "Alguns jobs retornaram erro; veja detalhes no log e em $FAILED_FILE"
  fi
  
  log "Processamento paralelo concluído"
}

# Gera relatório final
generate_report() {
  local done_count=$(wc -l < "$DONE_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  local failed_count=$(wc -l < "$FAILED_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  local output_count=$(find "$OUTPUT_DIR" -name "*.nii*" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
  
  log "============================================"
  log "RELATÓRIO FINAL"
  log "============================================"
  log "Subpastas processadas: $done_count"
  log "Subpastas com falha: $failed_count"
  log "Arquivos NIfTI gerados: $output_count"
  log "Log bruto dcm2niix: $RAW_LOG_FILE"
  log "============================================"
  
  if [ "$failed_count" -gt 0 ]; then
    log "Para ver falhas: cat $FAILED_FILE"
  fi
  
  # Salva estado
  cat > "$STATE_FILE" <<EOF
LAST_RUN=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
SOURCE=$INPUT_DIR
DESTINATION=$OUTPUT_DIR
DONE_COUNT=$done_count
FAILED_COUNT=$failed_count
OUTPUT_COUNT=$output_count
ARGS="${ARGS[*]}"
EOF
}

# ============================================================================
# EXECUÇÃO PRINCIPAL
# ============================================================================
main() {
  trap 'handle_signal INT' INT
  trap 'handle_signal TERM' TERM
  trap 'handle_signal TSTP' TSTP

  local arg
  for arg in "$@"; do
    case "$arg" in
      -h|--help)
        show_usage 0
        ;;
    esac
  done

  preparse_ui_flags "$@"
  restore_tty_mode
  if ! maybe_launch_bubbletea_ui "$@"; then
    if ! $UI_DISABLED; then
      log "Bubble Tea indisponível ou bootstrap não concluído. Seguindo em modo texto puro."
    fi
    :
  fi

  if [ $# -lt 1 ]; then
    if [ ! -t 0 ]; then
      show_usage
    fi
    collect_interactive_args
    parse_args "${INTERACTIVE_ARGS[@]}"
  else
    parse_args "$@"
  fi
  
  # Setup (init_state_files primeiro pois define os caminhos dos arquivos de controle)
  init_state_files
  check_lock
  check_dependencies
  detect_cores

  log "============================================"
  log "INICIANDO CONVERSÃO DICOM → NIfTI"
  log "============================================"
  log "Origem: $INPUT_DIR"
  log "Destino: $OUTPUT_DIR"
  log "Opções: ${ARGS[*]}"
  log "Threads: $NUM_CORES"
  log "============================================"
  
  # Processa
  process_all
  
  # Relatório
  generate_report
  
  rm -f "$LOCK_FILE"
  log "Conversão concluída!"
}

main "$@"
