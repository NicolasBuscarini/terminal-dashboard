#!/usr/bin/env bash
# bench.sh — benchmark sequencial de escrita/leitura (sysinfo bench).

bench_help() {
  cat <<'HELP'
Uso: sysinfo bench [diretório]

Mede a velocidade sequencial de escrita e leitura no sistema de arquivos do
diretório indicado (padrão: $HOME). O teste grava um arquivo temporário de
SYSINFO_BENCH_SIZE MiB (padrão: 256), mede e apaga o arquivo.

Exemplos:
  sysinfo bench                 # testa o disco da sua home
  sysinfo bench /mnt/dados      # testa outro disco montado
  SYSINFO_BENCH_SIZE=1024 sysinfo bench
HELP
}

# ------------------------------------------------------------- sysinfo bench
show_bench() {
  local target=${1:-$HOME}
  case $target in
    -h|--help) bench_help; return 0 ;;
  esac

  if [[ ! -d $target ]]; then
    printf 'sysinfo bench: diretório não encontrado: %s\n' "$target" >&2
    exit 1
  fi
  if [[ ! -w $target ]]; then
    printf 'sysinfo bench: sem permissão de escrita em %s\n' "$target" >&2
    exit 1
  fi
  if ! command -v dd >/dev/null 2>&1; then
    printf 'sysinfo bench: comando "dd" não encontrado.\n' >&2
    exit 1
  fi

  local bytes=$(( bench_size * 1048576 ))
  local avail
  avail=$(df -B1 --output=avail "$target" 2>/dev/null | tail -n1)
  if [[ $avail =~ ^[0-9]+$ ]] && (( avail < bytes + 67108864 )); then
    printf 'sysinfo bench: espaço insuficiente em %s (precisa de ~%d MiB livres).\n' \
      "$target" "$(( bench_size + 64 ))" >&2
    exit 1
  fi

  bench_file=$(mktemp "$target/.sysinfo-bench.XXXXXX") || {
    printf 'sysinfo bench: não foi possível criar o arquivo temporário em %s.\n' "$target" >&2
    exit 1
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

  local desc=$target
  if [[ -n $disk ]]; then
    desc="$target ${dot} $disk ${dot} $(disk_type_label "$disk")"
  fi

  printf '\n  %s%sBENCHMARK SEQUENCIAL%s\n' "$C_DIM" "$C_BOLD" "$C_RESET"
  printf '  %s%s%s\n\n' "$C_DIM" "$desc" "$C_RESET"
  printf '  %sTestando %d MiB...%s\n' "$C_DIM" "$bench_size" "$C_RESET"

  local t1 t2 write_ns read_ns write_mb read_mb write_s read_s cached=0
  t1=$(date +%s%N)
  if ! dd if=/dev/zero of="$bench_file" bs=1M count="$bench_size" \
        conv=fdatasync status=none 2>/dev/null; then
    printf 'sysinfo bench: falha ao gravar em %s (disco cheio?).\n' "$target" >&2
    rm -f "$bench_file"
    bench_file=''
    exit 1
  fi
  t2=$(date +%s%N)
  write_ns=$(( t2 - t1 ))
  (( write_ns <= 0 )) && write_ns=1

  t1=$(date +%s%N)
  if ! dd if="$bench_file" of=/dev/null bs=1M iflag=direct status=none 2>/dev/null; then
    cached=1
    t1=$(date +%s%N)
    if ! dd if="$bench_file" of=/dev/null bs=1M status=none 2>/dev/null; then
      printf 'sysinfo bench: falha ao ler o arquivo de teste.\n' >&2
      rm -f "$bench_file"
      bench_file=''
      exit 1
    fi
  fi
  t2=$(date +%s%N)
  read_ns=$(( t2 - t1 ))
  (( read_ns <= 0 )) && read_ns=1

  write_mb=$(LC_ALL=C awk -v b="$bytes" -v n="$write_ns" 'BEGIN { printf "%d", b * 1000 / n }')
  read_mb=$(LC_ALL=C awk -v b="$bytes" -v n="$read_ns" 'BEGIN { printf "%d", b * 1000 / n }')
  write_s=$(LC_ALL=C awk -v n="$write_ns" 'BEGIN { printf "%.2f", n / 1000000000 }')
  read_s=$(LC_ALL=C awk -v n="$read_ns" 'BEGIN { printf "%.2f", n / 1000000000 }')

  printf '\n'
  printf '  %s%-8s%s %s%s%s   %s(%d MiB em %s s)%s\n' \
    "$C_DIM" 'Escrita' "$C_RESET" \
    "$C_GREEN" "$(fmt_speed "$write_mb")" "$C_RESET" \
    "$C_DIM" "$bench_size" "$write_s" "$C_RESET"
  if (( cached )); then
    printf '  %s%-8s%s %s%s%s   %s(%d MiB em %s s, do cache)%s\n' \
      "$C_DIM" 'Leitura*' "$C_RESET" \
      "$C_YELLOW" "$(fmt_speed "$read_mb")" "$C_RESET" \
      "$C_DIM" "$bench_size" "$read_s" "$C_RESET"
    printf '\n  %s* O_DIRECT indisponível neste sistema de arquivos; a leitura veio do cache.%s\n' \
      "$C_DIM" "$C_RESET"
  else
    printf '  %s%-8s%s %s%s%s   %s(%d MiB em %s s)%s\n' \
      "$C_DIM" 'Leitura' "$C_RESET" \
      "$C_GREEN" "$(fmt_speed "$read_mb")" "$C_RESET" \
      "$C_DIM" "$bench_size" "$read_s" "$C_RESET"
  fi
  printf '\n  %sArquivo temporário removido.%s\n\n' "$C_DIM" "$C_RESET"

  rm -f "$bench_file"
  bench_file=''
}
