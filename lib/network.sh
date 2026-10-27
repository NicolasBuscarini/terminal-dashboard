#!/usr/bin/env bash
# network.sh — interface ativa, Wi-Fi, taxas e teste de internet.

# --------------------------------------------------------------------- rede
# Seção REDE: link ativo, SSID/banda/sinal, taxas e status da internet.
render_network_section() {
  section 'REDE'
  iface=$(awk '$2 == "00000000" { print $1; exit }' /proc/net/route 2>/dev/null)
  ip_addr=''
  if [[ -n $iface ]]; then
    if command -v ip >/dev/null 2>&1; then
      ip_addr=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{ print $4 }' | cut -d/ -f1)
    fi
    [[ -z $ip_addr ]] && ip_addr=$(hostname -I 2>/dev/null | awk '{ print $1 }')
  fi

  drx=$(( net_rx2 - net_rx1 ))
  dtx=$(( net_tx2 - net_tx1 ))
  rx_rate=$(( drx * 1000000000 / elapsed_ns ))
  tx_rate=$(( dtx * 1000000000 / elapsed_ns ))
  net_col=$C_GREEN
  if (( rx_rate > 1048576 || tx_rate > 1048576 )); then
    net_col=$C_YELLOW
  fi

  if [[ -n $iface ]]; then
    link_detail=''
    if [[ -d /sys/class/net/$iface/wireless ]]; then
      if command -v iw >/dev/null 2>&1; then
        iw_link=$(iw dev "$iface" link 2>/dev/null || true)
        if [[ -z $iw_link || $iw_link == *'Not connected'* ]]; then
          link_detail="${C_DIM}desconectado${C_RESET}"
        else
          ssid=$(awk -F': ' '/^[[:space:]]*SSID:/ { print $2; exit }' <<< "$iw_link")
          wifi_freq=$(awk -F': ' '/^[[:space:]]*freq:/ { print $2; exit }' <<< "$iw_link")
          sig_dbm=$(awk -F': ' '/^[[:space:]]*signal:/ { print $2; exit }' <<< "$iw_link")
          wifi_rate=$(awk -F': ' '/^[[:space:]]*(rx|tx) bitrate:/ { print $2; exit }' <<< "$iw_link")

          sig_dbm=${sig_dbm%% *}
          band=''
          if [[ $wifi_freq =~ ^[0-9] ]]; then
            freq_mhz=${wifi_freq%%.*}
            if (( freq_mhz < 3000 )); then
              band='2.4 GHz'
            elif (( freq_mhz < 5925 )); then
              band='5 GHz'
            else
              band='6 GHz'
            fi
          fi

          sig_pct=''
          sig_col=$C_DIM
          if [[ $sig_dbm =~ ^-?[0-9]+$ ]]; then
            sig_pct=$(( 2 * (sig_dbm + 100) ))
            (( sig_pct < 0 )) && sig_pct=0
            (( sig_pct > 100 )) && sig_pct=100
            sig_col=$(signal_color "$sig_pct")
          fi

          link_detail="${C_DIM}${ssid:-?}"
          [[ -n $band ]] && link_detail="$link_detail ${dot} ${band}"
          if [[ -n $sig_pct ]]; then
            link_detail="$link_detail ${dot} ${sig_col}sinal ${sig_pct}%${C_DIM}"
          fi
          [[ -n $wifi_rate ]] && link_detail="$link_detail ${dot} ${wifi_rate%% *} Mbit/s"
          link_detail="$link_detail${C_RESET}"
        fi
      fi
    elif [[ -r /sys/class/net/$iface/speed ]]; then
      link_speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null || true)
      if [[ $link_speed =~ ^[0-9]+$ ]] && (( link_speed > 0 )); then
        if (( link_speed >= 1000 )); then
          link_fmt="$(( link_speed / 1000 )) Gb/s"
        else
          link_fmt="${link_speed} Mb/s"
        fi
        link_duplex=$(cat "/sys/class/net/$iface/duplex" 2>/dev/null || true)
        link_detail="${C_DIM}${link_fmt}"
        [[ -n $link_duplex ]] && link_detail="$link_detail ${dot} ${link_duplex} duplex"
        link_detail="$link_detail${C_RESET}"
      fi
    fi

    if (( net_compact )); then
      if [[ -n ${ssid:-} ]]; then
        link_detail="${C_DIM}${ssid}${C_RESET}"
      else
        link_detail=''
      fi
    fi

    link_value="$C_BOLD$iface$C_RESET"
    [[ -n $link_detail ]] && link_value="$link_value  $link_detail"
    if (( net_compact )); then
      link_value="$link_value  ${net_col}${arrow_down}$(fmt_rate_short "$rx_rate")${C_RESET} ${net_col}${arrow_up}$(fmt_rate_short "$tx_rate")${C_RESET}"
    else
      link_value="$link_value   ${net_col}${arrow_down} $(fmt_bytes "$rx_rate")/s${C_RESET}  ${net_col}${arrow_up} $(fmt_bytes "$tx_rate")/s${C_RESET}"
    fi
    printf '  %s\n' "$link_value"
  else
    printf '  %s\n' "${C_DIM}sem conexão ativa${C_RESET}"
  fi

  status_line=''
  [[ -n $ip_addr ]] && status_line="$ip_addr"
  if [[ $net_check != 0 && -n $probe_pid ]]; then
    [[ -n $status_line ]] && status_line="$status_line ${dot} "
    if [[ -n $net_online ]]; then
      latency_ms=${net_latency%%.*}
      (( latency_ms == 0 )) && latency_ms='<1'
      status_line="$status_line${C_GREEN}Internet online${C_RESET} ${C_DIM}(${latency_ms} ms)${C_RESET}"
    else
      status_line="$status_line${C_RED}Internet sem resposta${C_RESET}"
    fi
  fi
  [[ -n $status_line ]] && emit_row 'STATUS' "$status_line"
}
