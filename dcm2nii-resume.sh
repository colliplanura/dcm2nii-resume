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

# Arquivos de controle (serão definidos após parse do OUTPUT_DIR)
STATE_FILE=""
LOG_FILE=""
DONE_FILE=""
FAILED_FILE=""
LOCK_FILE=""

# ============================================================================
# FUNÇÕES AUXILIARES
# ============================================================================
log() {
  local msg="$(date '+%Y-%m-%d %H:%M:%S') - $*"
  if [ -n "$LOG_FILE" ]; then
    echo "$msg" | tee -a "$LOG_FILE"
  else
    echo "$msg"
  fi
}

log_error() {
  local msg="$(date '+%Y-%m-%d %H:%M:%S') - ERRO: $*"
  if [ -n "$LOG_FILE" ]; then
    echo "$msg" | tee -a "$LOG_FILE" >&2
  else
    echo "$msg" >&2
  fi
}

show_usage() {
  cat <<EOF
Uso: $0 [opções] -o <destino> <origem>

Wrapper para dcm2niiXL com controle de continuação.
Processa diretórios DICOM em paralelo e permite retomada após interrupção.

Opções do script:
  --dcm2niix CMD   Caminho para dcm2niix (padrão: dcm2niix no PATH)
  --depth N        Profundidade de busca em subpastas (padrão: 10)
  --cores N        Número de threads (padrão: 0 = autodetect)

Opções dcm2niix (com valores padrão):
  -z i|o|y|n     Compressão gzip (padrão: i)
  -v N           Verbosidade (padrão: 0)
  -f formato     Formato do nome do arquivo (padrão: %i-%n-%t-%p-%b-%d)
  -o destino     Diretório de saída (OBRIGATÓRIO)

Arquivos de controle (salvos no diretório de saída):
  dcm2nii-resume.log    Log detalhado
  dcm2nii-done.txt      Subpastas já convertidas (skip automático)
  dcm2nii-failed.txt    Subpastas que falharam
  dcm2nii-resume.state  Estado da última execução

Exemplos:
  $0 -o /Users/colliplanura/nifti /Volumes/AAA/AAA1
  
  # Com opções do script:
  $0 --dcm2niix /usr/bin/dcm2niix --depth 5 --cores 8 -o /saida /origem

  # Sobrescrevendo opções dcm2niix padrão:
  $0 -z n -v 2 -o /saida /origem

  # Limpar estado e recomeçar do zero:
  rm -f /destino/dcm2nii-done.txt /destino/dcm2nii-failed.txt
  $0 -o /Users/colliplanura/nifti /Volumes/AAA/AAA1
EOF
  exit 2
}

cleanup() {
  # Mata processos filhos em background
  jobs -p | xargs -r kill 2>/dev/null || true
  wait 2>/dev/null || true
  [ -n "$LOCK_FILE" ] && rm -f "$LOCK_FILE"
  log "Script interrompido. Pode retomar executando novamente."
  if [ -n "$DONE_FILE" ]; then
    log "Subpastas já processadas: $(wc -l < "$DONE_FILE" 2>/dev/null | tr -d ' ' || echo 0)"
  fi
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
  log "Usando dcm2niix: $(command -v "$DCM2NIIX")"
}

init_state_files() {
  # Arquivos de controle são salvos no diretório de saída
  STATE_FILE="${OUTPUT_DIR}/dcm2nii-resume.state"
  LOG_FILE="${OUTPUT_DIR}/dcm2nii-resume.log"
  DONE_FILE="${OUTPUT_DIR}/dcm2nii-done.txt"
  FAILED_FILE="${OUTPUT_DIR}/dcm2nii-failed.txt"
  LOCK_FILE="${OUTPUT_DIR}/dcm2nii-resume.lock"
  
  mkdir -p "$OUTPUT_DIR"
  touch "$DONE_FILE" "$FAILED_FILE" "$LOG_FILE"
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

# Marca subpasta como processada (thread-safe com lock)
mark_done() {
  local dir="$1"
  (
    flock -x 200
    echo "$dir" >> "$DONE_FILE"
  ) 200>"${DONE_FILE}.lock"
}

# Marca subpasta como falha (thread-safe)
mark_failed() {
  local dir="$1"
  (
    flock -x 201
    echo "$dir" >> "$FAILED_FILE"
  ) 201>"${FAILED_FILE}.lock"
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
  
  mkdir -p "$OUTPUT_DIR"
}

# Processa uma única subpasta
process_subdir() {
  local dir="$1"
  local rel_path="${dir#$INPUT_DIR/}"
  
  # Skip se já processado
  if is_done "$dir"; then
    return 0
  fi
  
  log "PROCESSANDO: $rel_path"
  
  local start_time=$(date +%s)
  
  # Executa dcm2niix com -d 0 (só processa o diretório atual, não subpastas)
  if "$DCM2NIIX" -d 0 "${ARGS[@]}" "$dir" >> "$LOG_FILE" 2>&1; then
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    log "SUCESSO: $rel_path (${elapsed}s)"
    mark_done "$dir"
    return 0
  else
    local exit_code=$?
    log "FALHA: $rel_path (código: $exit_code)"
    mark_failed "$dir"
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
  
  # Conta diretórios
  local all_dirs=$(find "$INPUT_DIR" -maxdepth "$SEARCH_DEPTH" -type d 2>/dev/null)
  total_found=$(echo "$all_dirs" | wc -l | tr -d ' ')
  
  log "Encontradas $total_found subpastas"
  
  # Filtra diretórios já processados e conta
  local dirs_to_process=()
  while IFS= read -r dir; do
    if is_done "$dir"; then
      total_skip=$((total_skip + 1))
    else
      dirs_to_process+=("$dir")
      total_process=$((total_process + 1))
    fi
  done <<< "$all_dirs"
  
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
  wait
  
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
ARGS=${ARGS[*]}
EOF
}

# ============================================================================
# EXECUÇÃO PRINCIPAL
# ============================================================================
main() {
  if [ $# -lt 1 ]; then
    show_usage
  fi
  
  # Parse argumentos
  parse_args "$@"
  
  # Setup (init_state_files primeiro pois define os caminhos dos arquivos de controle)
  init_state_files
  trap cleanup INT TERM
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
