#!/usr/bin/env bash
# system.sh — amostragem de CPU/rede/I/O e seção SISTEMA do painel.

cpu_snapshot() {
  local -a v
  local i total=0
  read -r -a v < /proc/stat
  for i in 1 2 3 4 5 6 7 8; do
    total=$(( total + ${v[i]:-0} ))
  done
  printf '%d %d\n' "$total" $(( ${v[4]:-0} + ${v[5]:-0} ))
}

net_snapshot() {
  awk 'NR > 2 {
         gsub(":", " ")
         if ($1 != "lo") { rx += $2; tx += $10 }
       }
       END { printf "%d %d\n", rx, tx }' /proc/net/dev 2>/dev/null
}

disk_io_snapshot() {
  awk '$3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z]+|hd[a-z]+|vd[a-z]+|xvd[a-z]+|mmcblk[0-9]+)$/ {
         print $3, $6, $10
       }' /proc/diskstats 2>/dev/null
}

count_procs() {
  local -a p=(/proc/[0-9]*)
  printf '%d' "${#p[@]}"
}

# ------------------------------------------------------------------- sistema
# Seção SISTEMA: uptime, processos, usuários, bateria, temperatura e falhas.
render_system_section() {
  section 'SISTEMA'

  up_s=0
  if [[ -r /proc/uptime ]]; then
    read -r up_raw _ < /proc/uptime
    up_s=${up_raw%%.*}
  fi
  up_d=$(( up_s / 86400 ))
  up_h=$(( (up_s % 86400) / 3600 ))
  up_m=$(( (up_s % 3600) / 60 ))
  if (( up_d > 0 )); then
    up_fmt="${up_d}d ${up_h}h ${up_m}m"
  elif (( up_h > 0 )); then
    up_fmt="${up_h}h ${up_m}m"
  elif (( up_m > 0 )); then
    up_fmt="${up_m}m"
  else
    up_fmt="${up_s}s"
  fi

  user_count=$(who 2>/dev/null | awk '!seen[$1]++ { n++ } END { print n + 0 }')
  proc_count=$(count_procs)
  if (( user_count == 1 )); then
    user_label='1 usuário'
  else
    user_label="$user_count usuários"
  fi
  if (( compact )); then
    emit_row 'UPTIME' "no ar há ${up_fmt} ${dot} ${proc_count} proc"
  else
    emit_row 'UPTIME' "no ar há ${up_fmt} ${dot} ${proc_count} processos ${dot} ${user_label}"
  fi

  bat_path=''
  for bat in /sys/class/power_supply/BAT*; do
    if [[ -r $bat/capacity ]]; then
      bat_path=$bat
      break
    fi
  done
  if [[ -n $bat_path ]]; then
    bat_cap=$(<"$bat_path/capacity")
    bat_status=$(cat "$bat_path/status" 2>/dev/null || true)
    case $bat_status in
      Charging) bat_status_pt='carregando' ;;
      Discharging) bat_status_pt='descarregando' ;;
      Full) bat_status_pt='cheia' ;;
      'Not charging') bat_status_pt='na tomada' ;;
      *) bat_status_pt=${bat_status,,} ;;
    esac
    if [[ $bat_status == Discharging ]] && (( bat_cap <= 15 )); then
      bat_col=$C_RED
    elif [[ $bat_status == Discharging ]] && (( bat_cap <= 30 )); then
      bat_col=$C_YELLOW
    else
      bat_col=$C_GREEN
    fi
    emit_row 'BATERIA' "${bat_col}${bat_cap}%${C_RESET} ${dot} ${C_DIM}${bat_status_pt}${C_RESET}"
  fi

  temp_c=0
  for zone in /sys/class/thermal/thermal_zone*/temp; do
    [[ -r $zone ]] || continue
    zone_temp=$(<"$zone")
    [[ $zone_temp =~ ^[0-9]+$ ]] || continue
    (( zone_temp > 1000 )) && zone_temp=$(( zone_temp / 1000 ))
    (( zone_temp > temp_c )) && temp_c=$zone_temp
  done
  if (( temp_c > 0 )); then
    if (( temp_c >= 80 )); then
      temp_col=$C_RED
    elif (( temp_c >= 65 )); then
      temp_col=$C_YELLOW
    else
      temp_col=$C_GREEN
    fi
    emit_row 'TEMP' "${temp_col}${temp_c} °C${C_RESET}"
  fi

  if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
    failed_output=$(systemctl --failed --no-legend --no-pager 2>/dev/null || true)
    if [[ -n $failed_output ]]; then
      IFS=$'\t' read -r failed_count failed_names < <(printf '%s\n' "$failed_output" | awk '
        { count++; if (count <= 3) names = names (names == "" ? "" : ", ") $1 }
        END { printf "%d\t%s\n", count, names }')
      (( failed_count > 3 )) && failed_names="$failed_names +$(( failed_count - 3 ))"
      emit_row 'SERVIÇOS' "${C_RED}${failed_count} com falha${C_RESET} ${dot} ${C_DIM}${failed_names}${C_RESET}"
    fi
  fi
}
