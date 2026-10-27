#!/usr/bin/env bash
# bench.sh — benchmark sequencial e cache usado pelo painel.

bench_help() {
  cat <<'HELP'
Uso: sysinfo bench [diretório]

Mede a velocidade sequencial de escrita e leitura no sistema de arquivos do
diretório indicado (padrão: $HOME). O teste grava um arquivo temporário de
SYSINFO_BENCH_SIZE MiB (padrão: 256), mede e apaga o arquivo.

O resultado fica em cache e é reaproveitado pelo painel. O painel só refaz a
medição quando o cache expira (SYSINFO_BENCH_TTL_DAYS, padrão: 7 dias).

Exemplos:
  sysinfo bench                 # testa o disco da sua home
  sysinfo bench /mnt/dados      # testa outro disco montado
  SYSINFO_BENCH_SIZE=1024 sysinfo bench
HELP
}

# Executa a medição e preenche as variáveis BENCH_*. Em erro, retorna 1 e
# deixa a mensagem (sem o prefixo "sysinfo bench:") em BENCH_ERROR.
bench_run() {
  local target=${1:-$HOME}
  local size=${2:-$bench_size}
  BENCH_ERROR=''
  BENCH_TARGET=$target
  BENCH_SIZE=$size
  BENCH_DISK='' BENCH_TYPE=''
  BENCH_WRITE_MB='' BENCH_READ_MB='' BENCH_WRITE_S='' BENCH_READ_S=''
  BENCH_CACHED=0

  if [[ ! -d $target ]]; then
    BENCH_ERROR="diretório não encontrado: $target"
    return 1
  fi
  if [[ ! -w $target ]]; then
    BENCH_ERROR="sem permissão de escrita em $target"
    return 1
  fi
  if ! command -v dd >/dev/null 2>&1; then
    BENCH_ERROR='comando "dd" não encontrado.'
    return 1
  fi

  local bytes=$(( size * 1048576 ))
  local avail
  avail=$(df -B1 --output=avail "$target" 2>/dev/null | tail -n1)
  if [[ $avail =~ ^[0-9]+$ ]] && (( avail < bytes + 67108864 )); then
    BENCH_ERROR="espaço insuficiente em $target (precisa de ~$(( size + 64 )) MiB livres)."
    return 1
  fi

  bench_file=$(mktemp "$target/.sysinfo-bench.XXXXXX") || {
    bench_file=''
    BENCH_ERROR="não foi possível criar o arquivo temporário em $target."
    return 1
  }

  collect_disks
  local src dev disk='' d
  src=$(df --output=source "$target" 2>/dev/null | tail -n1)
  dev=${src##*/}
  for d in "${DISK_NAMES[@]}"; do
    if [[ -e "/sys/block/$d/$dev" ]]; then
      disk=$d
      break
    fi
  done
  if [[ -z $disk && -n $src ]] && command -v lsblk >/dev/null 2>&1; then
    disk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1)
  fi
  BENCH_DISK=$disk
  [[ -n $disk ]] && BENCH_TYPE=$(disk_type_label "$disk")

  local t1 t2 write_ns read_ns
  t1=$(date +%s%N)
  if ! dd if=/dev/zero of="$bench_file" bs=1M count="$size" \
        conv=fdatasync status=none 2>/dev/null; then
    rm -f "$bench_file"
    bench_file=''
    BENCH_ERROR="falha ao gravar em $target (disco cheio?)."
    return 1
  fi
  t2=$(date +%s%N)
  write_ns=$(( t2 - t1 ))
  (( write_ns <= 0 )) && write_ns=1

  t1=$(date +%s%N)
  if ! dd if="$bench_file" of=/dev/null bs=1M iflag=direct status=none 2>/dev/null; then
    BENCH_CACHED=1
    t1=$(date +%s%N)
    if ! dd if="$bench_file" of=/dev/null bs=1M status=none 2>/dev/null; then
      rm -f "$bench_file"
      bench_file=''
      BENCH_ERROR='falha ao ler o arquivo de teste.'
      return 1
    fi
  fi
  t2=$(date +%s%N)
  read_ns=$(( t2 - t1 ))
  (( read_ns <= 0 )) && read_ns=1

  BENCH_WRITE_MB=$(LC_ALL=C awk -v b="$bytes" -v n="$write_ns" 'BEGIN { printf "%d", b * 1000 / n }')
  BENCH_READ_MB=$(LC_ALL=C awk -v b="$bytes" -v n="$read_ns" 'BEGIN { printf "%d", b * 1000 / n }')
  BENCH_WRITE_S=$(LC_ALL=C awk -v n="$write_ns" 'BEGIN { printf "%.2f", n / 1000000000 }')
  BENCH_READ_S=$(LC_ALL=C awk -v n="$read_ns" 'BEGIN { printf "%.2f", n / 1000000000 }')

  rm -f "$bench_file"
  bench_file=''
  return 0
}

# Cache do último benchmark, compartilhado entre o painel e "sysinfo bench".
bench_cache_load() {
  BC_TS='' BC_TARGET='' BC_DISK='' BC_TYPE='' BC_SIZE=''
  BC_WRITE_MB='' BC_READ_MB='' BC_READ_S='' BC_CACHED=0
  [[ -r $bench_cache_file ]] || return 1
  local k v
  while IFS='=' read -r k v; do
    case $k in
      timestamp) BC_TS=$v ;;
      target) BC_TARGET=$v ;;
      disk) BC_DISK=$v ;;
      type) BC_TYPE=$v ;;
      size) BC_SIZE=$v ;;
      write_mb) BC_WRITE_MB=$v ;;
      read_mb) BC_READ_MB=$v ;;
      read_s) BC_READ_S=$v ;;
      cached) BC_CACHED=$v ;;
    esac
  done < "$bench_cache_file"
  [[ $BC_TS =~ ^[0-9]+$ && $BC_WRITE_MB =~ ^[0-9]+$ && $BC_READ_MB =~ ^[0-9]+$ ]] || return 1
  return 0
}

bench_cache_save() {
  [[ -n ${BENCH_TARGET:-} && -n ${BENCH_WRITE_MB:-} ]] || return 0
  mkdir -p "$bench_cache_dir" 2>/dev/null || return 0
  local tmp="$bench_cache_file.$$"
  {
    printf 'timestamp=%s\n' "$(date +%s)"
    printf 'target=%s\n' "$BENCH_TARGET"
    printf 'disk=%s\n' "$BENCH_DISK"
    printf 'type=%s\n' "$BENCH_TYPE"
    printf 'size=%s\n' "$BENCH_SIZE"
    printf 'write_mb=%s\n' "$BENCH_WRITE_MB"
    printf 'read_mb=%s\n' "$BENCH_READ_MB"
    printf 'read_s=%s\n' "$BENCH_READ_S"
    printf 'cached=%s\n' "$BENCH_CACHED"
  } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  mv -f "$tmp" "$bench_cache_file" 2>/dev/null || rm -f "$tmp"
}

# Idade legível: "agora", "há 12m", "há 3h", "há 2d".
fmt_age() {
  local s=${1:-0}
  (( s < 0 )) && s=0
  if (( s < 60 )); then
    printf 'agora'
  elif (( s < 3600 )); then
    printf 'há %dm' $(( s / 60 ))
  elif (( s < 86400 )); then
    printf 'há %dh' $(( s / 3600 ))
  else
    printf 'há %dd' $(( s / 86400 ))
  fi
}

# ------------------------------------------------------------- sysinfo bench
show_bench() {
  local target=${1:-$HOME}
  case $target in
    -h|--help) bench_help; return 0 ;;
  esac

  if ! bench_run "$target" "$bench_size"; then
    printf 'sysinfo bench: %s\n' "$BENCH_ERROR" >&2
    exit 1
  fi
  bench_cache_save

  local desc=$BENCH_TARGET
  if [[ -n $BENCH_DISK ]]; then
    desc="$BENCH_TARGET ${dot} $BENCH_DISK ${dot} $BENCH_TYPE"
  fi

  printf '\n  %s%sBENCHMARK SEQUENCIAL%s\n' "$C_DIM" "$C_BOLD" "$C_RESET"
  printf '  %s%s%s\n\n' "$C_DIM" "$desc" "$C_RESET"
  printf '  %sTestando %d MiB...%s\n' "$C_DIM" "$BENCH_SIZE" "$C_RESET"

  printf '\n'
  printf '  %s%-8s%s %s%s%s   %s(%d MiB em %s s)%s\n' \
    "$C_DIM" 'Escrita' "$C_RESET" \
    "$C_GREEN" "$(fmt_speed "$BENCH_WRITE_MB")" "$C_RESET" \
    "$C_DIM" "$BENCH_SIZE" "$BENCH_WRITE_S" "$C_RESET"
  if (( BENCH_CACHED )); then
    printf '  %s%-8s%s %s%s%s   %s(%d MiB em %s s, do cache)%s\n' \
      "$C_DIM" 'Leitura*' "$C_RESET" \
      "$C_YELLOW" "$(fmt_speed "$BENCH_READ_MB")" "$C_RESET" \
      "$C_DIM" "$BENCH_SIZE" "$BENCH_READ_S" "$C_RESET"
    printf '\n  %s* O_DIRECT indisponível neste sistema de arquivos; a leitura veio do cache.%s\n' \
      "$C_DIM" "$C_RESET"
  else
    printf '  %s%-8s%s %s%s%s   %s(%d MiB em %s s)%s\n' \
      "$C_DIM" 'Leitura' "$C_RESET" \
      "$C_GREEN" "$(fmt_speed "$BENCH_READ_MB")" "$C_RESET" \
      "$C_DIM" "$BENCH_SIZE" "$BENCH_READ_S" "$C_RESET"
  fi
  printf '\n  %sArquivo temporário removido.%s\n\n' "$C_DIM" "$C_RESET"
}
