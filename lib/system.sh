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
# Seção SISTEMA: uptime, processos, usuários, sessão, bateria, temperatura e falhas.
render_system_section() {
  panel_any uptime battery temp services session || return 0

  # Monta o conteúdo primeiro para não imprimir uma seção vazia quando o
  # hardware/ferramenta não existe (ex.: só "battery" num desktop).
  local body
  body=$(
  if panel_on uptime; then
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
  fi

  if panel_on session; then
    sess_desktop=${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}}
    sess_desktop=${sess_desktop##*:}
    case ${sess_desktop,,} in
      gnome) sess_desktop='GNOME' ;;
      kde|plasma) sess_desktop='KDE' ;;
      xfce) sess_desktop='XFCE' ;;
      mate) sess_desktop='MATE' ;;
      cinnamon) sess_desktop='Cinnamon' ;;
      sway) sess_desktop='Sway' ;;
      ubuntu) sess_desktop='Ubuntu' ;;
    esac
    sess_type=${XDG_SESSION_TYPE:-}
    case $sess_type in
      wayland) sess_type='Wayland' ;;
      x11) sess_type='X11' ;;
      tty) sess_type='TTY' ;;
    esac
    sess_term=${TERM_PROGRAM:-${TERM:-}}
    sess_line=''
    [[ -n $sess_desktop ]] && sess_line=$sess_desktop
    [[ -n $sess_type ]] && sess_line+="${sess_line:+ $dot }$sess_type"
    if (( ! compact )) && [[ -n $sess_term ]]; then
      sess_line+="${sess_line:+ $dot }$sess_term"
    fi
    if [[ -n $sess_line ]]; then
      sess_line=$(fit_text "$sess_line" "$(( cols - 11 ))")
      emit_row 'SESSÃO' "$sess_line"
    fi
  fi

  if panel_on battery; then
    bat_path=''
    for bat in "${battery_dir:-/sys/class/power_supply}"/BAT*; do
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

      # Saúde: capacidade cheia atual em relação à de projeto.
      bat_health=''
      bat_full=0 bat_design=0
      if [[ -r $bat_path/charge_full && -r $bat_path/charge_full_design ]]; then
        bat_full=$(<"$bat_path/charge_full")
        bat_design=$(<"$bat_path/charge_full_design")
      elif [[ -r $bat_path/energy_full && -r $bat_path/energy_full_design ]]; then
        bat_full=$(<"$bat_path/energy_full")
        bat_design=$(<"$bat_path/energy_full_design")
      fi
      if [[ $bat_full =~ ^[0-9]+$ && $bat_design =~ ^[0-9]+$ ]] && (( bat_design > 0 && bat_full > 0 )); then
        bat_health=$(( bat_full * 100 / bat_design ))
        (( bat_health > 100 )) && bat_health=100
      fi

      # Tempo restante (descarga) ou até a carga completa, quando o driver
      # expõe potência/corrente.
      bat_minutes=''
      if [[ $bat_status == Discharging || $bat_status == Charging ]]; then
        bat_now=0 bat_power=0 bat_limit=0
        if [[ -r $bat_path/energy_now && -r $bat_path/power_now ]]; then
          bat_now=$(<"$bat_path/energy_now")
          bat_power=$(<"$bat_path/power_now")
          [[ -r $bat_path/energy_full ]] && bat_limit=$(<"$bat_path/energy_full")
        elif [[ -r $bat_path/charge_now && -r $bat_path/current_now ]]; then
          bat_now=$(<"$bat_path/charge_now")
          bat_power=$(<"$bat_path/current_now")
          [[ -r $bat_path/charge_full ]] && bat_limit=$(<"$bat_path/charge_full")
        fi
        [[ $bat_power =~ ^-?[0-9]+$ ]] || bat_power=0
        (( bat_power < 0 )) && bat_power=$(( -bat_power ))
        if [[ $bat_now =~ ^[0-9]+$ ]] && (( bat_power > 0 && bat_now > 0 )); then
          if [[ $bat_status == Charging && $bat_limit =~ ^[0-9]+$ ]] && (( bat_limit > bat_now )); then
            bat_minutes=$(( (bat_limit - bat_now) * 60 / bat_power ))
          elif [[ $bat_status == Discharging ]]; then
            bat_minutes=$(( bat_now * 60 / bat_power ))
          fi
        fi
      fi

      bat_time=''
      if [[ $bat_minutes =~ ^[0-9]+$ ]] && (( bat_minutes > 0 )); then
        if (( bat_minutes >= 60 )); then
          bat_time="~$(( bat_minutes / 60 ))h $(( bat_minutes % 60 ))m"
        else
          bat_time="~${bat_minutes}m"
        fi
        if [[ $bat_status == Charging ]]; then
          bat_time+=' para cheia'
        else
          bat_time+=' restantes'
        fi
      fi

      bat_extra=''
      [[ -n $bat_time ]] && bat_extra+=" ${dot} ${C_DIM}${bat_time}${C_RESET}"
      if [[ -n $bat_health ]] && (( ! compact )); then
        if (( bat_health >= 80 )); then
          bat_health_col=$C_GREEN
        elif (( bat_health >= 60 )); then
          bat_health_col=$C_YELLOW
        else
          bat_health_col=$C_RED
        fi
        bat_extra+=" ${dot} ${C_DIM}saúde ${bat_health_col}${bat_health}%${C_RESET}"
      fi

      if (( compact )); then
        emit_row 'BATERIA' "${bat_col}${bat_cap}%${C_RESET} ${dot} ${C_DIM}${bat_status_pt}${C_RESET}"
      else
        emit_row 'BATERIA' "${bat_col}${bat_cap}%${C_RESET} ${dot} ${C_DIM}${bat_status_pt}${C_RESET}${bat_extra}"
      fi
    fi
  fi

  if panel_on temp; then
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
  fi

  if panel_on services; then
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
  fi
  )

  [[ -n $body ]] || return 0
  section 'SISTEMA'
  printf '%s\n' "$body"
}
