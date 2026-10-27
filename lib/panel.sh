#!/usr/bin/env bash
# panel.sh — composição dinâmica do painel e layout responsivo.

PANEL_ALL=(header cpu mem swap disks net internet ports bench uptime battery temp services)
declare -A PANEL_ON=()

# Adiciona um token (ou preset) à composição do painel.
panel_add_token() {
  local tok=$1 t
  case $tok in
    all)
      for t in "${PANEL_ALL[@]}"; do PANEL_ON[$t]=1; done
      ;;
    compact|minimal)
      for t in header cpu mem swap disks net internet ports uptime battery temp; do
        PANEL_ON[$t]=1
      done
      ;;
    none) PANEL_ON=() ;;
    memory) PANEL_ON[mem]=1 ;;
    network|wifi) PANEL_ON[net]=1; PANEL_ON[internet]=1 ;;
    load) PANEL_ON[cpu]=1 ;;
    header|cpu|mem|swap|disks|net|internet|ports|bench|uptime|battery|temp|services)
      PANEL_ON[$tok]=1
      ;;
  esac
}

# Remove um token (ou preset) da composição do painel.
panel_del_token() {
  local tok=$1 t
  case $tok in
    all) PANEL_ON=() ;;
    compact|minimal)
      for t in header cpu mem swap disks net internet ports uptime battery temp; do
        unset 'PANEL_ON[$t]'
      done
      ;;
    memory) unset 'PANEL_ON[mem]' ;;
    network|wifi) unset 'PANEL_ON[net]'; unset 'PANEL_ON[internet]' ;;
    load) unset 'PANEL_ON[cpu]' ;;
    *) unset "PANEL_ON[$tok]" ;;
  esac
}

panel_config_init() {
  PANEL_ON=()
  local tok
  for tok in ${panel_mode//,/ }; do panel_add_token "$tok"; done
  for tok in ${panel_hide//,/ }; do panel_del_token "$tok"; done
}

panel_on() { [[ -n ${PANEL_ON[$1]:-} ]]; }

panel_any() {
  local t
  for t in "$@"; do
    [[ -n ${PANEL_ON[$t]:-} ]] && return 0
  done
  return 1
}

# Remove códigos SGR para medir a largura visível de uma linha.
strip_ansi() {
  local s=$1 out=''
  while [[ $s == *$'\033['* ]]; do
    out+=${s%%$'\033['*}
    s=${s#*$'\033['}
    s=${s#*m}
  done
  printf '%s' "$out$s"
}

# Renderiza uma seção em largura reduzida e modo compacto (subshell).
render_block() {
  local fn=$1 width=$2
  (
    cols=$width
    compact=1
    narrow=1
    net_compact=1
    "$fn"
  )
}

# Imprime dois blocos lado a lado, preenchendo o menor com linhas vazias.
print_columns() {
  local left=$1 right=$2 width=$3
  local -a L=() R=()
  mapfile -t L <<< "$left"
  mapfile -t R <<< "$right"
  local n=${#L[@]} i l r plain pad
  (( ${#R[@]} > n )) && n=${#R[@]}
  for (( i = 0; i < n; i++ )); do
    l=${L[i]:-}
    r=${R[i]:-}
    if [[ -n $r ]]; then
      plain=$(strip_ansi "$l")
      pad=$(( width - ${#plain} ))
      (( pad < 0 )) && pad=0
      printf '%s%*s  %s\n' "$l" "$pad" '' "$r"
    else
      printf '%s\n' "$l"
    fi
  done
}

# ------------------------------------------------------------------ cabeçalho
render_header() {
  panel_on header || return 0

  local os_name=Linux
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_name=${PRETTY_NAME:-Linux}
  fi

  local host=${HOSTNAME:-$(uname -n)}
  host=${host%%.*}
  local name="$USER@$host"
  (( ${#name} > cols - 2 )) && name="${name:0:cols-3}${ch_ellipsis}"
  local rest_line="$os_name  $dot  Linux $(uname -r)"
  if (( ${#rest_line} > cols - 2 )); then
    rest_line="${rest_line:0:cols-3}${ch_ellipsis}"
  fi

  if (( ${#name} + ${#rest_line} + 7 <= cols )); then
    printf '\n  %s%s%s%s  %s  %s%s\n' \
      "$C_BOLD$C_ACCENT" "$name" "$C_RESET" "$C_DIM" "$dot" "$rest_line" "$C_RESET"
  else
    printf '\n  %s%s%s\n' "$C_BOLD$C_ACCENT" "$name" "$C_RESET"
    printf '  %s%s%s\n' "$C_DIM" "$rest_line" "$C_RESET"
  fi

  local sep2
  printf -v sep2 '%*s' "$(( cols - 2 ))" ''
  sep2=${sep2// /$sep_strong}
  printf '  %s%s%s\n' "$C_DIM" "$sep2" "$C_RESET"
}

# --------------------------------------------------------------- CPU/MEM/SWAP
render_cpu_row() {
  local dt di cpu_pct cores core_label load1 load5 load15 _
  dt=$(( cpu_t2 - cpu_t1 ))
  di=$(( cpu_i2 - cpu_i1 ))
  cpu_pct=0
  (( dt > 0 )) && cpu_pct=$(( (dt - di) * 100 / dt ))

  cores=$(nproc 2>/dev/null || printf '1')
  if (( cores == 1 )); then
    core_label='1 núcleo'
  else
    core_label="$cores núcleos"
  fi
  read -r load1 load5 load15 _ < /proc/loadavg
  local cpu_col cpu_pct_str
  cpu_col=$(level_color "$cpu_pct")
  printf -v cpu_pct_str '%3d%%' "$cpu_pct"
  if (( compact )); then
    make_bar "$cpu_pct" 8
    emit_row 'CPU' "${cpu_col}${BAR}${C_RESET}  ${cpu_col}${cpu_pct_str}${C_RESET}   ${C_DIM}carga${C_RESET} ${load1}"
  else
    make_bar "$cpu_pct"
    emit_row 'CPU' "${cpu_col}${BAR}${C_RESET}  ${cpu_col}${cpu_pct_str}${C_RESET}   ${C_DIM}${core_label}${C_RESET} ${dot} ${C_DIM}carga${C_RESET} ${load1} ${load5} ${load15}"
  fi
}

render_mem_row() {
  local mem_total=0 mem_avail=0 swap_total=0 swap_free=0 key val _
  while read -r key val _; do
    case $key in
      MemTotal:) mem_total=$val ;;
      MemAvailable:) mem_avail=$val ;;
      SwapTotal:) swap_total=$val ;;
      SwapFree:) swap_free=$val ;;
    esac
  done < /proc/meminfo

  mem_total=$(( mem_total * 1024 ))
  local mem_used=$(( mem_total - mem_avail * 1024 ))
  local mem_pct mem_col mem_pct_str
  mem_pct=$(pct "$mem_used" "$mem_total")
  mem_col=$(level_color "$mem_pct")
  printf -v mem_pct_str '%3d%%' "$mem_pct"
  if (( compact )); then
    make_bar "$mem_pct" 8
    emit_row 'MEM' "${mem_col}${BAR}${C_RESET}  ${mem_col}${mem_pct_str}${C_RESET}   $(fmt_pair "$mem_used" "$mem_total")"
  else
    make_bar "$mem_pct"
    emit_row 'MEM' "${mem_col}${BAR}${C_RESET}  ${mem_col}${mem_pct_str}${C_RESET}   $(fmt_bytes "$mem_used") / $(fmt_bytes "$mem_total")"
  fi
}

render_swap_row() {
  local swap_total=0 swap_free=0 key val _
  while read -r key val _; do
    case $key in
      SwapTotal:) swap_total=$val ;;
      SwapFree:) swap_free=$val ;;
    esac
  done < /proc/meminfo

  swap_total=$(( swap_total * 1024 ))
  swap_free=$(( swap_free * 1024 ))
  if (( swap_total > 0 )); then
    local swap_used=$(( swap_total - swap_free ))
    local swap_pct swap_col swap_pct_str
    swap_pct=$(pct "$swap_used" "$swap_total")
    swap_col=$(level_color "$swap_pct")
    printf -v swap_pct_str '%3d%%' "$swap_pct"
    if (( compact )); then
      make_bar "$swap_pct" 8
      emit_row 'SWAP' "${swap_col}${BAR}${C_RESET}  ${swap_col}${swap_pct_str}${C_RESET}   $(fmt_pair "$swap_used" "$swap_total")"
    else
      make_bar "$swap_pct"
      emit_row 'SWAP' "${swap_col}${BAR}${C_RESET}  ${swap_col}${swap_pct_str}${C_RESET}   $(fmt_bytes "$swap_used") / $(fmt_bytes "$swap_total")"
    fi
  else
    emit_row 'SWAP' "${C_DIM}desativada${C_RESET}"
  fi
}

render_processing_section() {
  panel_any cpu mem swap || return 0
  section 'PROCESSAMENTO'
  panel_on cpu && render_cpu_row
  panel_on mem && render_mem_row
  panel_on swap && render_swap_row
}

# ---------------------------------------------------------------- armazenamento
render_storage_section() {
  panel_on disks || return 0
  section 'ARMAZENAMENTO'
  collect_disks
  collect_fs_usage
  if (( ${#DISK_NAMES[@]} == 0 )); then
    emit_row 'DISCOS' "${C_DIM}nenhum disco físico detectado${C_RESET}"
    return
  fi

  local disk first=1
  for disk in "${DISK_NAMES[@]}"; do
    collect_disk_mounts "$disk"
    if [[ $panel_disks == full ]] && (( cols >= 70 )); then
      (( first )) || printf '\n'
      render_disk_detail "$disk" "${disk_rate_r[$disk]:-0}" "${disk_rate_w[$disk]:-0}"
    else
      render_disk_row "$disk"
    fi
    first=0
  done
}

# ------------------------------------------------------------------- benchmark
render_bench_row() {
  [[ $panel_bench == off ]] && return 0

  local have_cache=0 age=0
  if bench_cache_load; then
    have_cache=1
    age=$(( $(date +%s) - BC_TS ))
  fi

  local refresh=0
  case $panel_bench in
    live) refresh=1 ;;
    auto) (( have_cache == 0 || age > bench_ttl_days * 86400 )) && refresh=1 ;;
  esac

  if (( refresh )); then
    if bench_run "$HOME" "$bench_panel_size"; then
      bench_cache_save
      BC_TS=$(date +%s)
      BC_TARGET=$BENCH_TARGET
      BC_DISK=$BENCH_DISK
      BC_TYPE=$BENCH_TYPE
      BC_SIZE=$BENCH_SIZE
      BC_WRITE_MB=$BENCH_WRITE_MB
      BC_READ_MB=$BENCH_READ_MB
      BC_READ_S=$BENCH_READ_S
      BC_CACHED=$BENCH_CACHED
      have_cache=1
      age=0
    fi
  fi

  if (( ! have_cache )); then
    emit_row 'BENCH' "${C_DIM}sem medição ${dot} rode \"sysinfo bench\"${C_RESET}"
    return
  fi

  local src=''
  [[ -n $BC_DISK ]] && src="$BC_DISK"
  [[ -n $BC_TYPE ]] && src+="${src:+ }$BC_TYPE"
  local age_str
  age_str=$(fmt_age "$age")

  if (( compact || cols < 84 )); then
    local rd="L $(fmt_speed "$BC_READ_MB")"
    (( BC_CACHED )) && rd+="*"
    emit_row 'BENCH' "${C_GREEN}E $(fmt_speed "$BC_WRITE_MB")${C_RESET} ${dot} ${C_GREEN}${rd}${C_RESET}"
    if [[ -n $src ]]; then
      printf '  %s%-8s%s %s\n' "$C_DIM" '' "$C_RESET" "${C_DIM}${src} ${dot} ${age_str}${C_RESET}"
    fi
  else
    local rd="Leitura $(fmt_speed "$BC_READ_MB")"
    (( BC_CACHED )) && rd+=" (cache)"
    local tail="${age_str}"
    [[ -n $src ]] && tail="${src} ${dot} ${age_str}"
    emit_row 'BENCH' "${C_GREEN}Escrita $(fmt_speed "$BC_WRITE_MB")${C_RESET} ${dot} ${C_GREEN}${rd}${C_RESET}   ${C_DIM}${tail}${C_RESET}"
  fi
}

render_bench_section() {
  panel_on bench || return 0
  [[ $panel_bench == off ]] && return 0
  section 'DESEMPENHO'
  render_bench_row
}

# ===================================================================== painel
render_panel() {
  panel_config_init

  # Só espera a janela de amostragem se alguma linha precisar de taxas.
  local sample=0
  panel_any cpu net disks && sample=1

  # Teste de internet em paralelo com a janela de amostragem.
  probe_pid=''
  if [[ $net_check != 0 ]] && panel_any internet net; then
    probe_file=$(mktemp 2>/dev/null) || probe_file=''
    if [[ -n $probe_file ]]; then
      timeout "$net_timeout" ping -n -c 1 -W 1 "$ping_host" >"$probe_file" 2>/dev/null &
      probe_pid=$!
    fi
  fi

  if (( sample )); then
    declare -A io_r1=() io_w1=() io_dr=() io_dw=()
    local n r w t_start t_end
    t_start=$(date +%s%N)
    read -r cpu_t1 cpu_i1 <<< "$(cpu_snapshot)"
    read -r net_rx1 net_tx1 <<< "$(net_snapshot)"
    while read -r n r w; do io_r1[$n]=$r; io_w1[$n]=$w; done < <(disk_io_snapshot)

    sleep "$delay"

    read -r cpu_t2 cpu_i2 <<< "$(cpu_snapshot)"
    read -r net_rx2 net_tx2 <<< "$(net_snapshot)"
    while read -r n r w; do
      io_dr[$n]=$(( (r - ${io_r1[$n]:-$r}) * 512 ))
      io_dw[$n]=$(( (w - ${io_w1[$n]:-$w}) * 512 ))
    done < <(disk_io_snapshot)
    t_end=$(date +%s%N)
    elapsed_ns=$(( t_end - t_start ))
    (( elapsed_ns <= 0 )) && elapsed_ns=250000000

    disk_rate_r=() disk_rate_w=()
    for n in "${!io_dr[@]}"; do
      disk_rate_r[$n]=$(LC_ALL=C awk -v b="${io_dr[$n]}" -v n="$elapsed_ns" \
        'BEGIN { if (n <= 0) n = 1; printf "%d", b * 1000000000 / n }')
      disk_rate_w[$n]=$(LC_ALL=C awk -v b="${io_dw[$n]}" -v n="$elapsed_ns" \
        'BEGIN { if (n <= 0) n = 1; printf "%d", b * 1000000000 / n }')
    done
  else
    cpu_t1=0 cpu_i1=0 cpu_t2=0 cpu_i2=0
    net_rx1=0 net_tx1=0 net_rx2=0 net_tx2=0
    elapsed_ns=250000000
    disk_rate_r=() disk_rate_w=()
  fi

  net_online=''
  net_latency=''
  if [[ -n $probe_pid ]]; then
    wait "$probe_pid" 2>/dev/null || true
    if [[ -s $probe_file ]]; then
      net_latency=$(sed -n 's/.*time=\([0-9.]*\).*/\1/p' "$probe_file" | head -n1)
      [[ -n $net_latency ]] && net_online=1
    fi
    rm -f "$probe_file"
    probe_file=''
  fi

  render_header

  # Em terminais largos, PROCESSAMENTO e SISTEMA dividem a primeira faixa.
  local two_cols=0
  if [[ $panel_columns != 1 ]] && panel_any cpu mem swap && panel_any uptime battery temp services; then
    if [[ $panel_columns == 2 ]]; then
      (( cols >= 90 )) && two_cols=1
    else
      (( cols >= 96 )) && two_cols=1
    fi
  fi

  if (( two_cols )); then
    local w=$(( (cols - 6) / 2 ))
    local left right
    left=$(render_block render_processing_section "$w")
    right=$(render_block render_system_section "$w")
    print_columns "$left" "$right" "$w"
    render_storage_section
    render_network_section
    render_ports_section
    render_bench_section
  else
    render_processing_section
    render_storage_section
    render_network_section
    render_ports_section
    render_bench_section
    render_system_section
  fi

  if (( panel_hint )) && (( ${#PANEL_ON[@]} > 0 )); then
    printf '\n  %s%s%s\n' "$C_DIM" 'sysinfo disks · ports · bench · --help' "$C_RESET"
  fi
  printf '\n'
}
