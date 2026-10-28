#!/usr/bin/env bash
# procs.sh — processos que mais consomem CPU/memória, comando e seção do painel.
# A CPU é calculada pela diferença de ticks de /proc/<pid>/stat entre duas
# leituras, então não precisa de root nem de ferramentas externas.

declare -A PROC_T1=() PROC_T1_START=()
declare -A PROC_CPU10=() PROC_RSS=() PROC_MEM10=()
declare -A PROC_THREADS=() PROC_COMM=() PROC_STATE=()
PROC_PIDS=()
procs_t_start=0
procs_hz=0
procs_page=0

# Resolve HZ (ticks por segundo) e o tamanho da página uma única vez.
procs_init() {
  (( procs_hz > 0 )) && return 0
  procs_hz=$(getconf CLK_TCK 2>/dev/null) || procs_hz=100
  [[ $procs_hz =~ ^[0-9]+$ ]] && (( procs_hz > 0 )) || procs_hz=100
  procs_page=$(getconf PAGESIZE 2>/dev/null) || procs_page=4096
  [[ $procs_page =~ ^[0-9]+$ ]] && (( procs_page > 0 )) || procs_page=4096
}

# Lê todos os /proc/<pid>/stat em uma única passada do awk e imprime
# "pid<TAB>estado<TAB>ticks<TAB>threads<TAB>início<TAB>rss<TAB>nome".
# O nome pode conter espaços e parênteses: por isso é extraído entre o
# primeiro "(" e o último ")" antes de separar os campos numéricos.
procs_snapshot() {
  LC_ALL=C awk '
  {
    p = index($0, "("); if (p == 0) next
    match($0, /.*\)/); c = RLENGTH; if (c == 0) next
    comm = substr($0, p + 1, c - p - 1)
    rest = substr($0, c + 2)
    n = split(rest, f, " "); if (n < 22) next
    printf "%s\t%s\t%d\t%s\t%s\t%s\t%s\n", \
      $1, f[1], f[12] + f[13], f[18], f[20], f[22], comm
  }' /proc/[0-9]*/stat 2>/dev/null
}

# Primeira leitura: guarda os ticks de cada processo para o delta.
procs_sample_begin() {
  procs_init
  PROC_T1=() PROC_T1_START=() PROC_PIDS=()
  local pid state ticks threads start rss comm
  procs_t_start=$(date +%s%N)
  while IFS=$'\t' read -r pid state ticks threads start rss comm; do
    [[ -n $pid ]] || continue
    PROC_T1[$pid]=$ticks
    PROC_T1_START[$pid]=$start
    PROC_PIDS+=("$pid")
  done < <(procs_snapshot)
}

# Segunda leitura: calcula CPU (em décimos de % por núcleo), RSS e % de RAM.
procs_sample_end() {
  local t_end elapsed pid state ticks threads start rss comm
  local mem_total=0 key val _
  t_end=$(date +%s%N)
  elapsed=$(( t_end - procs_t_start ))
  (( elapsed <= 0 )) && elapsed=1

  while read -r key val _; do
    if [[ $key == MemTotal: ]]; then
      mem_total=$(( val * 1024 ))
      break
    fi
  done < /proc/meminfo

  PROC_CPU10=() PROC_RSS=() PROC_MEM10=()
  PROC_THREADS=() PROC_COMM=() PROC_STATE=()

  local delta
  while IFS=$'\t' read -r pid state ticks threads start rss comm; do
    [[ -n $pid ]] || continue
    # PID reutilizado durante a amostra: descarta para não misturar janelas.
    [[ ${PROC_T1_START[$pid]:-} == "$start" ]] || continue

    delta=$(( ticks - ${PROC_T1[$pid]:-ticks} ))
    (( delta < 0 )) && delta=0

    # delta de ticks / (HZ * tempo) em décimos de porcento, relativo a 1 núcleo.
    PROC_CPU10[$pid]=$(( delta * 1000 * 1000000000 / (procs_hz * elapsed) ))
    PROC_RSS[$pid]=$(( rss * procs_page ))
    PROC_MEM10[$pid]=$(( mem_total > 0 ? rss * procs_page * 1000 / mem_total : 0 ))
    PROC_THREADS[$pid]=$threads
    PROC_COMM[$pid]=${comm:-$pid}
    PROC_STATE[$pid]=$state
  done < <(procs_snapshot)
}

# "123" (décimos) -> "12.3%".
procs_fmt_cpu() {
  local c=${1:-0}
  (( c < 0 )) && c=0
  printf '%d.%d%%' $(( c / 10 )) $(( c % 10 ))
}

# Lista "pid<TAB>cpu10<TAB>rss" dos N maiores por cpu ou mem (RSS).
procs_top() {
  local key=$1 count=$2 pid
  local -a lines=()
  for pid in "${PROC_PIDS[@]}"; do
    [[ -n ${PROC_RSS[$pid]:-} ]] || continue
    lines+=("$pid"$'\t'"${PROC_CPU10[$pid]:-0}"$'\t'"${PROC_RSS[$pid]:-0}")
  done
  (( ${#lines[@]} == 0 )) && return 0

  if [[ $key == mem ]]; then
    printf '%s\n' "${lines[@]}" | LC_ALL=C sort -t $'\t' -k3,3nr | head -n "$count"
  else
    printf '%s\n' "${lines[@]}" | LC_ALL=C sort -t $'\t' -k2,2nr | head -n "$count"
  fi
}

# ---------------------------------------------------------------- painel
# Monta a linha do painel: "firefox 12.3% · code 4.5% · Xorg 2.1%".
procs_panel_line() {
  local key=$1 count=$2 pid cpu10 rss name out=''
  while IFS=$'\t' read -r pid cpu10 rss; do
    [[ -n $pid ]] || continue
    name=${PROC_COMM[$pid]:-$pid}
    if [[ $key == mem ]]; then
      out+="${out:+ $dot }${name} $(fmt_bytes "$rss")"
    else
      out+="${out:+ $dot }${name} $(procs_fmt_cpu "$cpu10")"
    fi
  done < <(procs_top "$key" "$count")
  printf '%s' "$out"
}

# Seção PROCESSOS: as linhas CPU e MEM usam a amostra feita em render_panel.
render_procs_section() {
  panel_on procs || return 0
  [[ $panel_procs == off ]] && return 0
  (( ${#PROC_PIDS[@]} > 0 )) || return 0

  local n=3
  if [[ $panel_procs == summary ]]; then
    n=1
  else
    (( compact )) && n=2
    (( cols >= 100 )) && n=4
  fi

  local maxw=$(( cols - 11 ))
  (( maxw < 1 )) && maxw=1
  local cpu_line mem_line
  cpu_line=$(procs_panel_line cpu "$n")
  mem_line=$(procs_panel_line mem "$n")
  [[ -n $cpu_line$mem_line ]] || return 0

  section 'PROCESSOS'
  [[ -n $cpu_line ]] && emit_row 'CPU' "$(fit_text "$cpu_line" "$maxw")"
  [[ -n $mem_line ]] && emit_row 'MEM' "$(fit_text "$mem_line" "$maxw")"
}

# ---------------------------------------------------------------- comando
procs_help() {
  cat <<'HELP'
Uso: sysinfo procs [opções]

Mostra os processos que mais consomem CPU (padrão) ou memória. A CPU é
relativa a um núcleo, como no top: um processo usando várias threads pode
passar de 100%. Não precisa de root: lê /proc.

Opções:
  -n, --top N      quantidade de processos (padrão: SYSINFO_PROCS_TOP ou 10)
  -d, --delay S    janela de amostragem em segundos (padrão: 0.5)
  -m, --mem        ordena por memória residente (RSS)
  -h, --help       mostra esta ajuda

A memória é o RSS atual. A CPU vem da diferença de ticks entre duas leituras
de /proc/<pid>/stat, então processos muito curtos podem aparecer com 0%.
HELP
}

show_procs() {
  local top=$procs_top delay_s=$procs_delay sort=cpu
  while (( $# > 0 )); do
    case $1 in
      -n|--top)
        if (( $# < 2 )); then
          printf 'sysinfo procs: --top exige um número.\n' >&2
          return 2
        fi
        top=$2
        shift 2
        ;;
      --top=*) top=${1#*=}; shift ;;
      -d|--delay)
        if (( $# < 2 )); then
          printf 'sysinfo procs: --delay exige um valor em segundos.\n' >&2
          return 2
        fi
        delay_s=$2
        shift 2
        ;;
      --delay=*) delay_s=${1#*=}; shift ;;
      -m|--mem|--memory) sort=mem; shift ;;
      -h|--help) procs_help; return 0 ;;
      *)
        printf 'sysinfo procs: opção desconhecida: %s\n' "$1" >&2
        return 2
        ;;
    esac
  done

  if ! [[ $top =~ ^[0-9]+$ ]] || (( top < 1 )); then
    printf 'sysinfo procs: --top deve ser um inteiro maior que zero.\n' >&2
    return 2
  fi
  (( top > 200 )) && top=200

  if ! [[ $delay_s =~ ^[0-9]+([.,][0-9]+)?$ ]]; then
    printf 'sysinfo procs: --delay deve ser um número em segundos.\n' >&2
    return 2
  fi
  delay_s=${delay_s/,/.}
  if ! LC_ALL=C awk -v d="$delay_s" 'BEGIN { exit !(d >= 0.05 && d <= 10) }'; then
    printf 'sysinfo procs: --delay deve ficar entre 0.05 e 10 segundos.\n' >&2
    return 2
  fi

  procs_sample_begin
  sleep "$delay_s"
  procs_sample_end

  local title='PROCESSOS · MAIS CPU'
  [[ $sort == mem ]] && title='PROCESSOS · MAIS MEMÓRIA'
  printf '\n  %s%s%s\n' "$C_BOLD" "$title" "$C_RESET"
  printf '  %s%d processos · amostra de %s s%s\n\n' \
    "$C_DIM" "${#PROC_PIDS[@]}" "$delay_s" "$C_RESET"

  local pid cpu10 rss mem10 cpu_col mem_col cpu_str mem_str name maxw
  if (( cols < 60 )); then
    printf '  %s%-7s %8s %8s %s%s\n' "$C_DIM" 'PID' 'CPU%' 'MEM%' 'PROCESSO' "$C_RESET"
  elif (( cols < 80 )); then
    printf '  %s%-7s %8s %8s %10s %s%s\n' "$C_DIM" 'PID' 'CPU%' 'MEM%' 'RSS' 'PROCESSO' "$C_RESET"
  else
    printf '  %s%-7s %8s %8s %10s %4s  %s%s\n' "$C_DIM" 'PID' 'CPU%' 'MEM%' 'RSS' 'EST' 'PROCESSO' "$C_RESET"
  fi

  while IFS=$'\t' read -r pid cpu10 rss; do
    [[ -n $pid ]] || continue
    mem10=${PROC_MEM10[$pid]:-0}
    name=${PROC_COMM[$pid]:-$pid}
    cpu_col=$(level_color $(( cpu10 / 10 )))
    mem_col=$(level_color $(( mem10 / 10 )))
    printf -v cpu_str '%5d.%d%%' $(( cpu10 / 10 )) $(( cpu10 % 10 ))
    printf -v mem_str '%5d.%d%%' $(( mem10 / 10 )) $(( mem10 % 10 ))

    if (( cols < 60 )); then
      maxw=$(( cols - 28 ))
      (( maxw < 1 )) && maxw=1
      name=$(fit_text "$name" "$maxw")
      printf '  %-7s %s%s%s %s%s%s %s\n' \
        "$pid" "$cpu_col" "$cpu_str" "$C_RESET" \
        "$mem_col" "$mem_str" "$C_RESET" "$name"
    elif (( cols < 80 )); then
      maxw=$(( cols - 39 ))
      (( maxw < 1 )) && maxw=1
      name=$(fit_text "$name" "$maxw")
      printf '  %-7s %s%s%s %s%s%s %10s %s\n' \
        "$pid" "$cpu_col" "$cpu_str" "$C_RESET" \
        "$mem_col" "$mem_str" "$C_RESET" "$(fmt_bytes "$rss")" "$name"
    else
      maxw=$(( cols - 45 ))
      (( maxw < 1 )) && maxw=1
      name=$(fit_text "$name" "$maxw")
      printf '  %-7s %s%s%s %s%s%s %10s %4s  %s%s%s %s\n' \
        "$pid" "$cpu_col" "$cpu_str" "$C_RESET" \
        "$mem_col" "$mem_str" "$C_RESET" "$(fmt_bytes "$rss")" \
        "${PROC_THREADS[$pid]:-0}" "$C_DIM" "${PROC_STATE[$pid]:-?}" "$C_RESET" "$name"
    fi
  done < <(procs_top "$sort" "$top")

  if (( cols >= 80 )); then
    printf '\n  %sEST: R executando · S dormindo · D I/O · I ocioso · Z zumbi · T parado%s\n' \
      "$C_DIM" "$C_RESET"
  fi
  printf '\n'
}
