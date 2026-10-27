#!/usr/bin/env bash
# panel.sh — monta o painel: amostragem, cabeçalho, CPU/RAM, discos e seções.

render_panel() {
  # Teste de internet em paralelo com a janela de amostragem.
  probe_pid=''
  if [[ $net_check != 0 ]]; then
    probe_file=$(mktemp 2>/dev/null) || probe_file=''
    if [[ -n $probe_file ]]; then
      timeout "$net_timeout" ping -n -c 1 -W 1 "$ping_host" >"$probe_file" 2>/dev/null &
      probe_pid=$!
    fi
  fi

  declare -A io_r1=() io_w1=() io_dr=() io_dw=()
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

  # ------------------------------------------------------------------ cabeçalho
  os_name=Linux
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_name=${PRETTY_NAME:-Linux}
  fi

  host=${HOSTNAME:-$(uname -n)}
  host=${host%%.*}
  name="$USER@$host"
  (( ${#name} > cols - 2 )) && name="${name:0:cols-3}${ch_ellipsis}"
  rest_line="$os_name  $dot  Linux $(uname -r)"
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

  printf -v sep2 '%*s' "$(( cols - 2 ))" ''
  sep2=${sep2// /$sep_strong}
  printf '  %s%s%s\n' "$C_DIM" "$sep2" "$C_RESET"

  # ------------------------------------------------------------------- CPU/RAM
  section 'PROCESSAMENTO'

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
  cpu_col=$(level_color "$cpu_pct")
  printf -v cpu_pct_str '%3d%%' "$cpu_pct"
  if (( compact )); then
    make_bar "$cpu_pct" 8
    emit_row 'CPU' "${cpu_col}${BAR}${C_RESET}  ${cpu_col}${cpu_pct_str}${C_RESET}   ${C_DIM}carga${C_RESET} ${load1}"
  else
    make_bar "$cpu_pct"
    emit_row 'CPU' "${cpu_col}${BAR}${C_RESET}  ${cpu_col}${cpu_pct_str}${C_RESET}   ${C_DIM}${core_label}${C_RESET} ${dot} ${C_DIM}carga${C_RESET} ${load1} ${load5} ${load15}"
  fi

  mem_total=0 mem_avail=0 swap_total=0 swap_free=0
  while read -r key val _; do
    case $key in
      MemTotal:) mem_total=$val ;;
      MemAvailable:) mem_avail=$val ;;
      SwapTotal:) swap_total=$val ;;
      SwapFree:) swap_free=$val ;;
    esac
  done < /proc/meminfo

  mem_total=$(( mem_total * 1024 ))
  mem_used=$(( mem_total - mem_avail * 1024 ))
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

  swap_total=$(( swap_total * 1024 ))
  swap_free=$(( swap_free * 1024 ))
  if (( swap_total > 0 )); then
    swap_used=$(( swap_total - swap_free ))
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

  # ------------------------------------------------------------------- discos
  section 'ARMAZENAMENTO'
  collect_disks
  collect_fs_usage
  if (( ${#DISK_NAMES[@]} == 0 )); then
    emit_row 'DISCOS' "${C_DIM}nenhum disco físico detectado${C_RESET}"
  else
    for disk in "${DISK_NAMES[@]}"; do
      collect_disk_mounts "$disk"
      render_disk_row "$disk"
    done
  fi

  render_network_section
  render_ports_row
  render_system_section

  printf '\n'
}
