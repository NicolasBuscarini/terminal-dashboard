#!/usr/bin/env bash
# disks.sh — detecção de discos, uso de filesystems, comando e linha do painel.

# -------------------------------------------------------------- dados de disco
declare -A disk_rota=() disk_tran=() disk_model=() disk_size=()
declare -A disk_main_mount=() disk_main_pct=() disk_main_used=() disk_mount_count=()
declare -A disk_rate_r=() disk_rate_w=()
declare -A fs_size=() fs_used=() fs_pct=() fs_mount=() fs_type=()
DISK_NAMES=()

disk_temp_c() {
  local disk=$1 target h t
  target=$(readlink -f "/sys/block/$disk/device" 2>/dev/null) || return 0
  [[ -n $target ]] || return 0
  for h in /sys/class/hwmon/hwmon*; do
    [[ -e $h/device && -r $h/temp1_input ]] || continue
    if [[ $(readlink -f "$h/device" 2>/dev/null) == "$target" ]]; then
      t=$(<"$h/temp1_input")
      [[ $t =~ ^[0-9]+$ ]] || continue
      printf '%d' $(( t / 1000 ))
      return 0
    fi
  done
}

list_block_devices() {
  if command -v lsblk >/dev/null 2>&1; then
    lsblk -dn -r -o NAME,TRAN 2>/dev/null
  else
    local d
    for d in /sys/block/*; do
      printf '%s \n' "${d##*/}"
    done
  fi
}

collect_disks() {
  local name tran rota model sectors
  DISK_NAMES=()
  while read -r name tran; do
    [[ -z $name ]] && continue
    case $name in
      loop*|zram*|sr*|ram*) continue ;;
    esac
    [[ -e /sys/block/$name/device ]] || continue
    sectors=$(cat "/sys/block/$name/size" 2>/dev/null || true)
    [[ $sectors =~ ^[0-9]+$ ]] || continue
    (( sectors > 0 )) || continue
    rota=$(cat "/sys/block/$name/queue/rotational" 2>/dev/null || true)
    model=$(cat "/sys/block/$name/device/model" 2>/dev/null || true)
    model=${model#"${model%%[![:space:]]*}"}
    model=${model%"${model##*[![:space:]]}"}
    DISK_NAMES+=("$name")
    disk_rota[$name]=$rota
    disk_tran[$name]=$tran
    disk_model[$name]=$model
    disk_size[$name]=$(( sectors * 512 ))
  done < <(list_block_devices)
}

# Uma única chamada a df para todos os sistemas de arquivos montados.
collect_fs_usage() {
  local src fstype size used pcent target dev
  fs_size=() fs_used=() fs_pct=() fs_mount=() fs_type=()
  while read -r src fstype size used pcent target; do
    [[ $src == /dev/* ]] || continue
    dev=${src##*/}
    fs_size[$dev]=$size
    fs_used[$dev]=$used
    fs_pct[$dev]=${pcent%\%}
    fs_mount[$dev]=$target
    fs_type[$dev]=$fstype
  done < <(df -B1 --output=source,fstype,size,used,pcent,target 2>/dev/null | tail -n +2)
}

# Escolhe, para o painel, a maior partição montada de cada disco.
collect_disk_mounts() {
  local disk=$1 part pname best=-1 count=0
  disk_main_mount[$disk]=''
  disk_main_pct[$disk]=''
  disk_main_used[$disk]=''
  for part in /sys/block/"$disk"/"$disk"*; do
    [[ -e $part ]] || continue
    pname=${part##*/}
    [[ -n ${fs_mount[$pname]:-} ]] || continue
    count=$(( count + 1 ))
    if (( ${fs_size[$pname]:-0} > best )); then
      best=${fs_size[$pname]:-0}
      disk_main_mount[$disk]=${fs_mount[$pname]}
      disk_main_pct[$disk]=${fs_pct[$pname]:-0}
      disk_main_used[$disk]=${fs_used[$pname]:-0}
    fi
  done
  disk_mount_count[$disk]=$count
}

disk_type_label() {
  local name=$1 rota=${disk_rota[$1]:-} tran=${disk_tran[$1]:-}
  case $tran in
    nvme) printf 'SSD NVMe'; return ;;
    mmc) printf 'eMMC'; return ;;
  esac
  if [[ $rota == 1 ]]; then
    printf 'HDD'
  else
    printf 'SSD'
  fi
  [[ -n $tran ]] && printf ' %s' "${tran^^}"
}

# ------------------------------------------------------------- sysinfo disks
show_disks() {
  collect_disks
  collect_fs_usage
  if (( ${#DISK_NAMES[@]} == 0 )); then
    printf '\n  %snenhum disco físico detectado.%s\n\n' "$C_DIM" "$C_RESET"
    return
  fi

  local disk
  for disk in "${DISK_NAMES[@]}"; do
    collect_disk_mounts "$disk"
  done

  # Amostra de I/O por disco.
  local -A r1=() w1=() rr=() rw=()
  local n r w t1 t2 elapsed db dw
  while read -r n r w; do r1[$n]=$r; w1[$n]=$w; done < <(disk_io_snapshot)
  t1=$(date +%s%N)
  sleep "$disks_delay"
  t2=$(date +%s%N)
  elapsed=$(( t2 - t1 ))
  (( elapsed <= 0 )) && elapsed=300000000
  while read -r n r w; do
    db=$(( (r - ${r1[$n]:-$r}) * 512 ))
    dw=$(( (w - ${w1[$n]:-$w}) * 512 ))
    rr[$n]=$(LC_ALL=C awk -v b="$db" -v n="$elapsed" 'BEGIN { if (n <= 0) n = 1; printf "%d", b * 1000000000 / n }')
    rw[$n]=$(LC_ALL=C awk -v b="$dw" -v n="$elapsed" 'BEGIN { if (n <= 0) n = 1; printf "%d", b * 1000000000 / n }')
  done < <(disk_io_snapshot)

  printf '\n  %s%sDISCOS E PARTIÇÕES%s\n' "$C_DIM" "$C_BOLD" "$C_RESET"

  local type size model temp temp_col type_col health health_col
  local -a parts=()
  local part pname psize fstype mnt ppct i branch bar_col
  for disk in "${DISK_NAMES[@]}"; do
    type=$(disk_type_label "$disk")
    size=$(fmt_bytes "${disk_size[$disk]}")
    model=${disk_model[$disk]}
    temp=$(disk_temp_c "$disk")

    # Fallback opcional para temperatura via smartctl (ex.: HDD com drivetemp off).
    if [[ -z $temp ]] && command -v smartctl >/dev/null 2>&1; then
      temp=$(smartctl -A -n standby "/dev/$disk" 2>/dev/null | awk '/^Temperature:/ { print $2; exit }')
    fi

    case $type in
      SSD*) type_col=$C_CYAN ;;
      HDD*) type_col=$C_YELLOW ;;
      *) type_col=$C_DIM ;;
    esac

    printf '\n  %s%-9s%s  %s%-9s%s  %s%9s%s' \
      "$C_BOLD" "$disk" "$C_RESET" \
      "$type_col" "$type" "$C_RESET" \
      "$C_DIM" "$size" "$C_RESET"
    [[ -n $model ]] && printf '  %s%s%s' "$C_DIM" "$model" "$C_RESET"
    if [[ -n $temp ]]; then
      if (( temp >= 70 )); then
        temp_col=$C_RED
      elif (( temp >= 55 )); then
        temp_col=$C_YELLOW
      else
        temp_col=$C_GREEN
      fi
      printf '  %s·%s %s%s °C%s' "$C_DIM" "$C_RESET" "$temp_col" "$temp" "$C_RESET"
    fi
    printf '\n'

    if command -v smartctl >/dev/null 2>&1; then
      health=$(smartctl -H -n standby "/dev/$disk" 2>/dev/null \
        | sed -n 's/^SMART overall-health self-assessment test result: *//p' | head -n1)
      if [[ -n $health ]]; then
        if [[ $health == PASSED ]]; then health_col=$C_GREEN; else health_col=$C_RED; fi
        printf '    %sSaúde%s  %s%s%s\n' "$C_DIM" "$C_RESET" "$health_col" "$health" "$C_RESET"
      fi
    fi

    parts=()
    for part in /sys/block/"$disk"/"$disk"*; do
      [[ -e $part ]] && parts+=("${part##*/}")
    done
    if (( ${#parts[@]} > 0 )); then
      mapfile -t parts < <(printf '%s\n' "${parts[@]}" | sort -V)
    fi

    for i in "${!parts[@]}"; do
      pname=${parts[$i]}
      if (( i == ${#parts[@]} - 1 )); then
        branch=${ch_branch[1]}
      else
        branch=${ch_branch[0]}
      fi

      psize=$(cat "/sys/block/$disk/$pname/size" 2>/dev/null || true)
      [[ $psize =~ ^[0-9]+$ ]] || psize=0
      psize=$(( psize * 512 ))

      mnt=${fs_mount[$pname]:-}
      fstype=${fs_type[$pname]:-}
      if [[ -z $fstype ]]; then
        fstype=$(lsblk -rno FSTYPE "/dev/$pname" 2>/dev/null || true)
      fi
      [[ -z $fstype ]] && fstype='-'

      printf '    %s%s%s %-12s %-7.7s %10s  ' \
        "$C_DIM" "$branch" "$C_RESET" \
        "$pname" "$fstype" "$(fmt_bytes "$psize")"

      if [[ -n $mnt ]]; then
        ppct=${fs_pct[$pname]:-0}
        bar_col=$(level_color "$ppct")
        make_bar "$ppct" 8
        printf '%s%s%s %s%3d%%%s  %s%s%s\n' \
          "$bar_col" "$BAR" "$C_RESET" \
          "$bar_col" "$ppct" "$C_RESET" \
          "$C_DIM" "$mnt" "$C_RESET"
      else
        printf '%s%s%s\n' "$C_DIM" 'sem montagem' "$C_RESET"
      fi
    done

    if (( ${rr[$disk]:-0} == 0 && ${rw[$disk]:-0} == 0 )); then
      printf '    %sI/O agora%s  %socioso%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"
    else
      printf '    %sI/O agora%s  %s%s%s %s/s  %s%s%s %s/s\n' \
        "$C_DIM" "$C_RESET" \
        "$C_GREEN" "$arrow_down" "$C_RESET" "$(fmt_bytes "${rr[$disk]:-0}")" \
        "$C_YELLOW" "$arrow_up" "$C_RESET" "$(fmt_bytes "${rw[$disk]:-0}")"
    fi
  done

  printf '\n'
}

# ===================================================================== painel
render_disk_row() {
  local disk=$1
  local type size mnt pct_v bar_col io_str mount_disp type_col
  local rr rw
  type=$(disk_type_label "$disk")
  size=$(fmt_bytes "${disk_size[$disk]}")
  case $type in
    SSD*) type_col=$C_CYAN ;;
    HDD*) type_col=$C_YELLOW ;;
    *) type_col=$C_DIM ;;
  esac

  mnt=${disk_main_mount[$disk]:-}
  if [[ -z $mnt ]]; then
    if (( narrow )); then
      printf '  %s%-8s%s %s%-4s%s  %s\n' \
        "$C_BOLD" "$disk" "$C_RESET" \
        "$type_col" "${type%% *}" "$C_RESET" \
        "${C_DIM}sem montagem${C_RESET}"
    else
      printf '  %s%-8s%s %s%-9s%s %s%-9s%s  %s\n' \
        "$C_BOLD" "$disk" "$C_RESET" \
        "$type_col" "$type" "$C_RESET" \
        "$C_DIM" "$size" "$C_RESET" \
        "${C_DIM}sem montagem${C_RESET}"
    fi
    return
  fi

  pct_v=${disk_main_pct[$disk]}
  bar_col=$(level_color "$pct_v")
  mount_disp=$mnt
  if (( ${disk_mount_count[$disk]:-1} > 1 )); then
    mount_disp="$mount_disp +$(( disk_mount_count[$disk] - 1 ))"
  fi
  if (( ${#mount_disp} > 10 )); then
    mount_disp="${mount_disp:0:9}${ch_ellipsis}"
  fi

  if (( narrow )); then
    make_bar "$pct_v" 6
    printf '  %s%-8s%s %s%-4s%s %s%s%s%3d%%%s  %s\n' \
      "$C_BOLD" "$disk" "$C_RESET" \
      "$type_col" "${type%% *}" "$C_RESET" \
      "$bar_col" "$BAR" "$bar_col" "$pct_v" "$C_RESET" \
      "$mount_disp"
    return
  fi

  make_bar "$pct_v" 8
  rr=${disk_rate_r[$disk]:-0}
  rw=${disk_rate_w[$disk]:-0}
  if (( rr == 0 && rw == 0 )); then
    io_str="${C_DIM}ocioso${C_RESET}"
  else
    io_str="${C_DIM}${arrow_down}${C_RESET} $(fmt_rate_short "$rr")/s  ${C_DIM}${arrow_up}${C_RESET} $(fmt_rate_short "$rw")/s"
  fi

  printf '  %s%-8s%s %s%-9s%s %s%-9s%s %s%s%s%3d%%%s  %s%-10s%s  %s\n' \
    "$C_BOLD" "$disk" "$C_RESET" \
    "$type_col" "$type" "$C_RESET" \
    "$C_DIM" "$size" "$C_RESET" \
    "$bar_col" "$BAR" "$bar_col" "$pct_v" "$C_RESET" \
    "$C_DIM" "$mount_disp" "$C_RESET" \
    "$io_str"
}
