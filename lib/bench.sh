#!/usr/bin/env bash
# bench.sh — benchmarks sequencial, 4K, memória e CPU, com cache para o painel.

bench_help() {
  cat <<'HELP'
Uso: sysinfo bench [tipo] [diretório]

Tipos:
  seq (padrão)   escrita/leitura sequencial de blocos grandes
  4k             blocos de 4 KiB (IOPS e MB/s)
  mem            banda de memória via /dev/shm (tmpfs)
  cpu            throughput de SHA-256 em 1 e em N threads
  all            executa todos os testes acima

Sem tipo, testa o disco do diretório indicado (padrão: $HOME). O resultado de
cada teste fica em cache e é reaproveitado pelo painel; o painel só refaz a
medição sequencial quando o cache expira (SYSINFO_BENCH_TTL_DAYS, padrão: 7
dias). Os demais resultados aparecem no painel quando já existirem em cache.

Exemplos:
  sysinfo bench                 # sequencial na home
  sysinfo bench /mnt/dados      # sequencial em outro disco
  sysinfo bench 4k /mnt/dados   # blocos de 4 KiB no disco
  sysinfo bench mem             # banda de memória (/dev/shm)
  sysinfo bench cpu             # CPU com SHA-256
  sysinfo bench all             # todos os testes

Variáveis:
  SYSINFO_BENCH_SIZE=256        tamanho do teste sequencial (MiB)
  SYSINFO_BENCH_4K_SIZE=16      tamanho do teste de 4 KiB (MiB)
  SYSINFO_BENCH_MEM_SIZE=64     tamanho do teste de memória (MiB)
  SYSINFO_BENCH_CPU_SIZE=64     MiB por thread no teste de CPU
  SYSINFO_BENCH_CPU_THREADS=... threads do teste de CPU (padrão: nproc)
  SYSINFO_BENCH_TTL_DAYS=7      validade do cache usado pelo painel
HELP
}

# --------------------------------------------------------------- cache comum
declare -A BCACHE=()

# Grava "timestamp=..." seguido dos pares chave=valor recebidos.
bench_cache_write() {
  local file=$1
  shift
  mkdir -p "$bench_cache_dir" 2>/dev/null || return 0
  local tmp="$file.$$"
  {
    printf 'timestamp=%s\n' "$(date +%s)"
    printf '%s\n' "$@"
  } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  mv -f "$tmp" "$file" 2>/dev/null || rm -f "$tmp"
}

# Lê um cache para o array associativo BCACHE. Exige timestamp válido.
bench_cache_read() {
  BCACHE=()
  [[ -r $1 ]] || return 1
  local k v
  while IFS='=' read -r k v; do
    [[ -n $k ]] && BCACHE[$k]=$v
  done < "$1"
  [[ ${BCACHE[timestamp]:-} =~ ^[0-9]+$ ]] || return 1
  return 0
}

# Cache dentro da validade configurada?
bench_cache_fresh() {
  local ts=$1 age
  [[ $ts =~ ^[0-9]+$ ]] || return 1
  age=$(( $(date +%s) - ts ))
  (( age >= 0 && age <= bench_ttl_days * 86400 ))
}

# ------------------------------------------------------------ preparação comum
# Valida o diretório, o espaço livre e cria o arquivo temporário. Preenche
# BENCH_TARGET, BENCH_SIZE, BENCH_DISK, BENCH_TYPE e bench_file.
bench_prepare() {
  local target=${1:-$HOME}
  local size=${2:-$bench_size}
  local extra=${3:-64}

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
  if [[ $avail =~ ^[0-9]+$ ]] && (( avail < bytes + extra * 1048576 )); then
    BENCH_ERROR="espaço insuficiente em $target (precisa de ~$(( size + extra )) MiB livres)."
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
  return 0
}

# ------------------------------------------------------- sequencial (blocos grandes)
# Executa a medição e preenche as variáveis BENCH_*. Em erro, retorna 1 e
# deixa a mensagem (sem o prefixo "sysinfo bench:") em BENCH_ERROR.
bench_run() {
  local target=${1:-$HOME}
  local size=${2:-$bench_size}
  bench_prepare "$target" "$size" 64 || return 1

  local bytes=$(( size * 1048576 ))
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

# ------------------------------------------------------------- 4 KiB (IOPS)
bench_run_4k() {
  local target=${1:-$HOME}
  local size=${2:-$bench_4k_size}
  bench_prepare "$target" "$size" 64 || return 1

  local bytes=$(( size * 1048576 ))
  local count=$(( bytes / 4096 ))
  local t1 t2 write_ns read_ns direct=1

  t1=$(date +%s%N)
  if ! dd if=/dev/zero of="$bench_file" bs=4k count="$count" \
        oflag=direct status=none 2>/dev/null; then
    direct=0
    t1=$(date +%s%N)
    if ! dd if=/dev/zero of="$bench_file" bs=4k count="$count" \
          conv=fdatasync status=none 2>/dev/null; then
      rm -f "$bench_file"
      bench_file=''
      BENCH_ERROR="falha ao gravar em $target (disco cheio?)."
      return 1
    fi
  fi
  t2=$(date +%s%N)
  write_ns=$(( t2 - t1 ))
  (( write_ns <= 0 )) && write_ns=1

  t1=$(date +%s%N)
  if ! dd if="$bench_file" of=/dev/null bs=4k count="$count" \
        iflag=direct status=none 2>/dev/null; then
    direct=0
    t1=$(date +%s%N)
    if ! dd if="$bench_file" of=/dev/null bs=4k count="$count" \
          status=none 2>/dev/null; then
      rm -f "$bench_file"
      bench_file=''
      BENCH_ERROR='falha ao ler o arquivo de teste.'
      return 1
    fi
  fi
  t2=$(date +%s%N)
  read_ns=$(( t2 - t1 ))
  (( read_ns <= 0 )) && read_ns=1

  BENCH_4K_SIZE=$size
  BENCH_4K_COUNT=$count
  BENCH_4K_DIRECT=$direct
  BENCH_4K_WRITE_IOPS=$(LC_ALL=C awk -v c="$count" -v n="$write_ns" 'BEGIN { printf "%d", c * 1000000000 / n }')
  BENCH_4K_READ_IOPS=$(LC_ALL=C awk -v c="$count" -v n="$read_ns" 'BEGIN { printf "%d", c * 1000000000 / n }')
  BENCH_4K_WRITE_MB=$(LC_ALL=C awk -v b="$bytes" -v n="$write_ns" 'BEGIN { printf "%d", b * 1000 / n }')
  BENCH_4K_READ_MB=$(LC_ALL=C awk -v b="$bytes" -v n="$read_ns" 'BEGIN { printf "%d", b * 1000 / n }')
  BENCH_4K_WRITE_S=$(LC_ALL=C awk -v n="$write_ns" 'BEGIN { printf "%.2f", n / 1000000000 }')
  BENCH_4K_READ_S=$(LC_ALL=C awk -v n="$read_ns" 'BEGIN { printf "%.2f", n / 1000000000 }')

  rm -f "$bench_file"
  bench_file=''
  return 0
}

# --------------------------------------------------------- memória (tmpfs)
bench_run_mem() {
  local dir=${1:-${SYSINFO_BENCH_MEM_DIR:-/dev/shm}}
  local size=$bench_mem_size

  BENCH_ERROR=''
  if [[ ! -d $dir ]]; then
    BENCH_ERROR="diretório não encontrado: $dir"
    return 1
  fi
  if [[ ! -w $dir ]]; then
    BENCH_ERROR="sem permissão de escrita em $dir"
    return 1
  fi

  # Não enche o /dev/shm: deixa uma folga para o restante do sistema.
  local avail max_mb
  avail=$(df -B1 --output=avail "$dir" 2>/dev/null | tail -n1)
  if [[ $avail =~ ^[0-9]+$ ]]; then
    max_mb=$(( (avail - 8 * 1048576) / 1048576 ))
    (( max_mb < 4 )) && {
      BENCH_ERROR="espaço insuficiente em $dir para o teste de memória."
      return 1
    }
    (( size > max_mb )) && size=$max_mb
  fi

  bench_prepare "$dir" "$size" 8 || return 1

  local bytes=$(( size * 1048576 ))
  local t1 t2 write_ns read_ns direct=1

  t1=$(date +%s%N)
  if ! dd if=/dev/zero of="$bench_file" bs=1M count="$size" \
        conv=fdatasync status=none 2>/dev/null; then
    rm -f "$bench_file"
    bench_file=''
    BENCH_ERROR="falha ao gravar em $dir."
    return 1
  fi
  t2=$(date +%s%N)
  write_ns=$(( t2 - t1 ))
  (( write_ns <= 0 )) && write_ns=1

  t1=$(date +%s%N)
  if ! dd if="$bench_file" of=/dev/null bs=1M iflag=direct status=none 2>/dev/null; then
    direct=0
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

  BENCH_MEM_DIR=$dir
  BENCH_MEM_SIZE=$size
  BENCH_MEM_DIRECT=$direct
  BENCH_MEM_WRITE_MB=$(LC_ALL=C awk -v b="$bytes" -v n="$write_ns" 'BEGIN { printf "%d", b * 1000 / n }')
  BENCH_MEM_READ_MB=$(LC_ALL=C awk -v b="$bytes" -v n="$read_ns" 'BEGIN { printf "%d", b * 1000 / n }')
  BENCH_MEM_WRITE_S=$(LC_ALL=C awk -v n="$write_ns" 'BEGIN { printf "%.2f", n / 1000000000 }')
  BENCH_MEM_READ_S=$(LC_ALL=C awk -v n="$read_ns" 'BEGIN { printf "%.2f", n / 1000000000 }')

  rm -f "$bench_file"
  bench_file=''
  return 0
}

# ------------------------------------------------------------- CPU (SHA-256)
bench_run_cpu() {
  local size=${1:-$bench_cpu_size}
  local threads=${SYSINFO_BENCH_CPU_THREADS:-$(nproc 2>/dev/null || printf '1')}

  BENCH_ERROR=''
  if ! command -v sha256sum >/dev/null 2>&1; then
    BENCH_ERROR='comando "sha256sum" não encontrado.'
    return 1
  fi
  [[ $threads =~ ^[0-9]+$ ]] || threads=1
  (( threads < 1 )) && threads=1
  (( threads > 256 )) && threads=256

  local t1 t2 single_ns multi_ns
  t1=$(date +%s%N)
  if ! dd if=/dev/zero bs=1M count="$size" status=none 2>/dev/null | sha256sum >/dev/null 2>&1; then
    BENCH_ERROR='falha ao executar o teste de CPU.'
    return 1
  fi
  t2=$(date +%s%N)
  single_ns=$(( t2 - t1 ))
  (( single_ns <= 0 )) && single_ns=1

  local -a pids=()
  local i pid fail=0
  t1=$(date +%s%N)
  for (( i = 0; i < threads; i++ )); do
    ( dd if=/dev/zero bs=1M count="$size" status=none 2>/dev/null | sha256sum >/dev/null 2>&1 ) &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait "$pid" || fail=1
  done
  t2=$(date +%s%N)
  if (( fail )); then
    BENCH_ERROR='falha ao executar o teste de CPU em paralelo.'
    return 1
  fi
  multi_ns=$(( t2 - t1 ))
  (( multi_ns <= 0 )) && multi_ns=1

  local single_bytes=$(( size * 1048576 ))
  local multi_bytes=$(( size * threads * 1048576 ))
  BENCH_CPU_SIZE=$size
  BENCH_CPU_THREADS=$threads
  BENCH_CPU_SINGLE_MB=$(LC_ALL=C awk -v b="$single_bytes" -v n="$single_ns" 'BEGIN { printf "%d", b * 1000 / n }')
  BENCH_CPU_MULTI_MB=$(LC_ALL=C awk -v b="$multi_bytes" -v n="$multi_ns" 'BEGIN { printf "%d", b * 1000 / n }')
  BENCH_CPU_SINGLE_S=$(LC_ALL=C awk -v n="$single_ns" 'BEGIN { printf "%.2f", n / 1000000000 }')
  BENCH_CPU_MULTI_S=$(LC_ALL=C awk -v n="$multi_ns" 'BEGIN { printf "%.2f", n / 1000000000 }')
  return 0
}

# -------------------------------------------------------- cache sequencial
bench_cache_load() {
  BC_TS='' BC_TARGET='' BC_DISK='' BC_TYPE='' BC_SIZE=''
  BC_WRITE_MB='' BC_READ_MB='' BC_READ_S='' BC_CACHED=0
  bench_cache_read "$bench_cache_file" || return 1
  BC_TS=${BCACHE[timestamp]:-}
  BC_TARGET=${BCACHE[target]:-}
  BC_DISK=${BCACHE[disk]:-}
  BC_TYPE=${BCACHE[type]:-}
  BC_SIZE=${BCACHE[size]:-}
  BC_WRITE_MB=${BCACHE[write_mb]:-}
  BC_READ_MB=${BCACHE[read_mb]:-}
  BC_READ_S=${BCACHE[read_s]:-}
  BC_CACHED=${BCACHE[cached]:-0}
  [[ $BC_TS =~ ^[0-9]+$ && $BC_WRITE_MB =~ ^[0-9]+$ && $BC_READ_MB =~ ^[0-9]+$ ]] || return 1
  return 0
}

bench_cache_save() {
  [[ -n ${BENCH_TARGET:-} && -n ${BENCH_WRITE_MB:-} ]] || return 0
  bench_cache_write "$bench_cache_file" \
    "target=$BENCH_TARGET" \
    "disk=$BENCH_DISK" \
    "type=$BENCH_TYPE" \
    "size=$BENCH_SIZE" \
    "write_mb=$BENCH_WRITE_MB" \
    "read_mb=$BENCH_READ_MB" \
    "read_s=$BENCH_READ_S" \
    "cached=$BENCH_CACHED"
}

# --------------------------------------------------------------- cache 4K
bench_4k_cache_load() {
  BC4_TS='' BC4_TARGET='' BC4_DISK='' BC4_TYPE='' BC4_SIZE=''
  BC4_WRITE_IOPS='' BC4_READ_IOPS='' BC4_WRITE_MB='' BC4_READ_MB=''
  BC4_DIRECT=1
  bench_cache_read "$bench_4k_cache_file" || return 1
  BC4_TS=${BCACHE[timestamp]:-}
  BC4_TARGET=${BCACHE[target]:-}
  BC4_DISK=${BCACHE[disk]:-}
  BC4_TYPE=${BCACHE[type]:-}
  BC4_SIZE=${BCACHE[size]:-}
  BC4_WRITE_IOPS=${BCACHE[write_iops]:-}
  BC4_READ_IOPS=${BCACHE[read_iops]:-}
  BC4_WRITE_MB=${BCACHE[write_mb]:-}
  BC4_READ_MB=${BCACHE[read_mb]:-}
  BC4_DIRECT=${BCACHE[direct]:-1}
  [[ $BC4_TS =~ ^[0-9]+$ && $BC4_WRITE_IOPS =~ ^[0-9]+$ && $BC4_READ_IOPS =~ ^[0-9]+$ ]] || return 1
  return 0
}

bench_4k_cache_save() {
  [[ -n ${BENCH_4K_WRITE_IOPS:-} ]] || return 0
  bench_cache_write "$bench_4k_cache_file" \
    "target=$BENCH_TARGET" \
    "disk=$BENCH_DISK" \
    "type=$BENCH_TYPE" \
    "size=$BENCH_4K_SIZE" \
    "write_iops=$BENCH_4K_WRITE_IOPS" \
    "read_iops=$BENCH_4K_READ_IOPS" \
    "write_mb=$BENCH_4K_WRITE_MB" \
    "read_mb=$BENCH_4K_READ_MB" \
    "direct=$BENCH_4K_DIRECT"
}

# -------------------------------------------------------------- cache memória
bench_mem_cache_load() {
  BCM_TS='' BCM_DIR='' BCM_SIZE='' BCM_WRITE_MB='' BCM_READ_MB='' BCM_DIRECT=1
  bench_cache_read "$bench_mem_cache_file" || return 1
  BCM_TS=${BCACHE[timestamp]:-}
  BCM_DIR=${BCACHE[dir]:-}
  BCM_SIZE=${BCACHE[size]:-}
  BCM_WRITE_MB=${BCACHE[write_mb]:-}
  BCM_READ_MB=${BCACHE[read_mb]:-}
  BCM_DIRECT=${BCACHE[direct]:-1}
  [[ $BCM_TS =~ ^[0-9]+$ && $BCM_WRITE_MB =~ ^[0-9]+$ && $BCM_READ_MB =~ ^[0-9]+$ ]] || return 1
  return 0
}

bench_mem_cache_save() {
  [[ -n ${BENCH_MEM_WRITE_MB:-} ]] || return 0
  bench_cache_write "$bench_mem_cache_file" \
    "dir=$BENCH_MEM_DIR" \
    "size=$BENCH_MEM_SIZE" \
    "write_mb=$BENCH_MEM_WRITE_MB" \
    "read_mb=$BENCH_MEM_READ_MB" \
    "direct=$BENCH_MEM_DIRECT"
}

# ---------------------------------------------------------------- cache CPU
bench_cpu_cache_load() {
  BCC_TS='' BCC_SIZE='' BCC_THREADS='' BCC_SINGLE_MB='' BCC_MULTI_MB=''
  bench_cache_read "$bench_cpu_cache_file" || return 1
  BCC_TS=${BCACHE[timestamp]:-}
  BCC_SIZE=${BCACHE[size]:-}
  BCC_THREADS=${BCACHE[threads]:-}
  BCC_SINGLE_MB=${BCACHE[single_mb]:-}
  BCC_MULTI_MB=${BCACHE[multi_mb]:-}
  [[ $BCC_TS =~ ^[0-9]+$ && $BCC_SINGLE_MB =~ ^[0-9]+$ && $BCC_MULTI_MB =~ ^[0-9]+$ ]] || return 1
  return 0
}

bench_cpu_cache_save() {
  [[ -n ${BENCH_CPU_SINGLE_MB:-} ]] || return 0
  bench_cache_write "$bench_cpu_cache_file" \
    "size=$BENCH_CPU_SIZE" \
    "threads=$BENCH_CPU_THREADS" \
    "single_mb=$BENCH_CPU_SINGLE_MB" \
    "multi_mb=$BENCH_CPU_MULTI_MB"
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

# ------------------------------------------------------------- impressão CLI
bench_print_seq() {
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

bench_print_4k() {
  local desc=$BENCH_TARGET
  if [[ -n $BENCH_DISK ]]; then
    desc="$BENCH_TARGET ${dot} $BENCH_DISK ${dot} $BENCH_TYPE"
  fi

  printf '\n  %s%sBENCHMARK 4K (blocos de 4 KiB)%s\n' "$C_DIM" "$C_BOLD" "$C_RESET"
  printf '  %s%s%s\n\n' "$C_DIM" "$desc" "$C_RESET"
  printf '  %sTestando %d MiB em %d blocos...%s\n' \
    "$C_DIM" "$BENCH_4K_SIZE" "$BENCH_4K_COUNT" "$C_RESET"

  printf '\n'
  printf '  %s%-8s%s %s%s IOPS%s   %s%s%s   %s(%s s)%s\n' \
    "$C_DIM" 'Escrita' "$C_RESET" \
    "$C_GREEN" "$(fmt_iops "$BENCH_4K_WRITE_IOPS")" "$C_RESET" \
    "$C_DIM" "$(fmt_speed "$BENCH_4K_WRITE_MB")" "$C_RESET" \
    "$C_DIM" "$BENCH_4K_WRITE_S" "$C_RESET"
  printf '  %s%-8s%s %s%s IOPS%s   %s%s%s   %s(%s s)%s\n' \
    "$C_DIM" 'Leitura' "$C_RESET" \
    "$C_GREEN" "$(fmt_iops "$BENCH_4K_READ_IOPS")" "$C_RESET" \
    "$C_DIM" "$(fmt_speed "$BENCH_4K_READ_MB")" "$C_RESET" \
    "$C_DIM" "$BENCH_4K_READ_S" "$C_RESET"

  if (( ! BENCH_4K_DIRECT )); then
    printf '\n  %s* O_DIRECT indisponível neste sistema de arquivos; o teste usou o cache.%s\n' \
      "$C_DIM" "$C_RESET"
  fi
  printf '\n  %sArquivo temporário removido.%s\n\n' "$C_DIM" "$C_RESET"
}

bench_print_mem() {
  local fstype='' title='BENCHMARK DE MEMÓRIA'
  if command -v stat >/dev/null 2>&1; then
    fstype=$(stat -f -c %T "$BENCH_MEM_DIR" 2>/dev/null)
    [[ $fstype == tmpfs ]] && title+=' (tmpfs)'
  fi
  printf '\n  %s%s%s%s\n' "$C_DIM" "$C_BOLD" "$title" "$C_RESET"
  printf '  %s%s %s %d MiB%s\n\n' \
    "$C_DIM" "$BENCH_MEM_DIR" "$dot" "$BENCH_MEM_SIZE" "$C_RESET"

  printf '  %s%-8s%s %s%s%s   %s(%s s)%s\n' \
    "$C_DIM" 'Escrita' "$C_RESET" \
    "$C_GREEN" "$(fmt_speed "$BENCH_MEM_WRITE_MB")" "$C_RESET" \
    "$C_DIM" "$BENCH_MEM_WRITE_S" "$C_RESET"
  printf '  %s%-8s%s %s%s%s   %s(%s s)%s\n' \
    "$C_DIM" 'Leitura' "$C_RESET" \
    "$C_GREEN" "$(fmt_speed "$BENCH_MEM_READ_MB")" "$C_RESET" \
    "$C_DIM" "$BENCH_MEM_READ_S" "$C_RESET"

  if (( ! BENCH_MEM_DIRECT )); then
    printf '\n  %s* O_DIRECT indisponível em %s; a leitura veio do cache.%s\n' \
      "$C_DIM" "$BENCH_MEM_DIR" "$C_RESET"
  fi
  printf '\n  %sArquivo temporário removido.%s\n\n' "$C_DIM" "$C_RESET"
}

bench_print_cpu() {
  printf '\n  %s%sBENCHMARK DE CPU (SHA-256)%s\n' "$C_DIM" "$C_BOLD" "$C_RESET"
  if declare -F cpu_detect >/dev/null 2>&1; then
    cpu_detect
    [[ -n ${CPU_MODEL_SHORT:-} ]] && printf '  %s%s%s\n' "$C_DIM" "$CPU_MODEL_SHORT" "$C_RESET"
  fi
  local multi_label="${BENCH_CPU_THREADS} threads"
  (( BENCH_CPU_THREADS == 1 )) && multi_label='1 thread'
  printf '  %s%d MiB por thread %s %s%s\n\n' \
    "$C_DIM" "$BENCH_CPU_SIZE" "$dot" "$multi_label" "$C_RESET"
  printf '  %s%-10s%s %s%s%s   %s(%s s)%s\n' \
    "$C_DIM" '1 thread' "$C_RESET" \
    "$C_GREEN" "$(fmt_speed "$BENCH_CPU_SINGLE_MB")" "$C_RESET" \
    "$C_DIM" "$BENCH_CPU_SINGLE_S" "$C_RESET"
  printf '  %s%-10s%s %s%s%s   %s(%s s)%s\n' \
    "$C_DIM" "$multi_label" "$C_RESET" \
    "$C_GREEN" "$(fmt_speed "$BENCH_CPU_MULTI_MB")" "$C_RESET" \
    "$C_DIM" "$BENCH_CPU_MULTI_S" "$C_RESET"
  printf '\n  %sQuanto maior, melhor. O resultado varia com a carga e o governador da CPU.%s\n\n' \
    "$C_DIM" "$C_RESET"
}

# ------------------------------------------------------------- sysinfo bench
show_bench() {
  local kind=seq target=$HOME target_set=0 arg
  for arg in "$@"; do
    case $arg in
      -h|--help) bench_help; return 0 ;;
      seq|sequential|disco|disk) kind=seq ;;
      4k|small|iops) kind=4k ;;
      mem|memory|ram) kind=mem ;;
      cpu|processor) kind=cpu ;;
      all|tudo) kind=all ;;
      *)
        target=$arg
        target_set=1
        ;;
    esac
  done

  local rc=0
  case $kind in
    seq)
      if ! bench_run "$target" "$bench_size"; then
        printf 'sysinfo bench: %s\n' "$BENCH_ERROR" >&2
        exit 1
      fi
      bench_cache_save
      bench_print_seq
      ;;
    4k)
      if ! bench_run_4k "$target" "$bench_4k_size"; then
        printf 'sysinfo bench: %s\n' "$BENCH_ERROR" >&2
        exit 1
      fi
      bench_4k_cache_save
      bench_print_4k
      ;;
    mem)
      local mem_dir=/dev/shm
      (( target_set )) && mem_dir=$target
      if ! bench_run_mem "$mem_dir"; then
        printf 'sysinfo bench: %s\n' "$BENCH_ERROR" >&2
        exit 1
      fi
      bench_mem_cache_save
      bench_print_mem
      ;;
    cpu)
      if ! bench_run_cpu "$bench_cpu_size"; then
        printf 'sysinfo bench: %s\n' "$BENCH_ERROR" >&2
        exit 1
      fi
      bench_cpu_cache_save
      bench_print_cpu
      ;;
    all)
      if bench_run "$target" "$bench_size"; then
        bench_cache_save
        bench_print_seq
      else
        printf 'sysinfo bench (sequencial): %s\n' "$BENCH_ERROR" >&2
        rc=1
      fi
      if bench_run_4k "$target" "$bench_4k_size"; then
        bench_4k_cache_save
        bench_print_4k
      else
        printf 'sysinfo bench (4K): %s\n' "$BENCH_ERROR" >&2
        rc=1
      fi
      if bench_run_mem /dev/shm; then
        bench_mem_cache_save
        bench_print_mem
      else
        printf 'sysinfo bench (memória): %s\n' "$BENCH_ERROR" >&2
        rc=1
      fi
      if bench_run_cpu "$bench_cpu_size"; then
        bench_cpu_cache_save
        bench_print_cpu
      else
        printf 'sysinfo bench (CPU): %s\n' "$BENCH_ERROR" >&2
        rc=1
      fi
      ;;
  esac
  return $rc
}
