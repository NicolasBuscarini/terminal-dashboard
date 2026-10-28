#!/usr/bin/env bash
# gpu.sh — detecção de GPUs (sysfs, nvidia-smi e lspci) e seção do painel.

GPU_LOADED=0
GPU_COUNT=0
GPU_DEDICATED_COUNT=0
GPU_INTEGRATED_COUNT=0
GPU_VIRTUAL_COUNT=0

gpu_reset() {
  GPU_NAME=() GPU_VENDOR=() GPU_DRIVER=() GPU_TYPE=()
  GPU_VRAM_TOTAL=() GPU_VRAM_USED=() GPU_USAGE=() GPU_TEMP=()
  GPU_PCI=() GPU_SOURCE=()
  GPU_COUNT=0 GPU_DEDICATED_COUNT=0 GPU_INTEGRATED_COUNT=0 GPU_VIRTUAL_COUNT=0
}

gpu_trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

gpu_vendor_name() {
  case ${1,,} in
    0x8086) printf 'Intel' ;;
    0x1002|0x1022) printf 'AMD' ;;
    0x10de) printf 'NVIDIA' ;;
    0x13b5) printf 'ARM' ;;
    0x5143) printf 'Qualcomm' ;;
    0x1af4) printf 'Virtio' ;;
    0x15ad) printf 'VMware' ;;
    0x1234) printf 'QEMU' ;;
    0x80ee) printf 'VirtualBox' ;;
    '') printf 'desconhecida' ;;
    *) printf 'PCI %s' "$1" ;;
  esac
}

gpu_default_name() {
  local vendor=${1#0x} device=${2#0x}
  printf '%s GPU [%s:%s]' "$(gpu_vendor_name "$1")" "$vendor" "$device"
}

# Remove o prefixo do fabricante, o sufixo " [vendor:device]" do lspci -nn e
# prefere o primeiro modelo conhecido entre colchetes.
gpu_strip_name() {
  local line=$1 bracket rest
  line=${line% (rev *)}
  line=$(printf '%s' "$line" | sed \
    -e 's/ \[[0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\}\]$//' \
    -e 's/^Intel Corporation //' \
    -e 's/^Advanced Micro Devices, Inc\. \[AMD\/ATI\] //' \
    -e 's/^Advanced Micro Devices, Inc\. //' \
    -e 's/^NVIDIA Corporation //' \
    -e 's/^\[AMD\/ATI\] //')
  rest=$line
  while [[ $rest == *'['*']'* ]]; do
    bracket=${rest#*[}
    bracket=${bracket%%]*}
    case $bracket in
      *Graphics*|*Radeon*|*GeForce*|*Arc*) line=$bracket; break ;;
    esac
    rest=${rest#*]}
  done
  printf '%s' "$line"
}

gpu_pci_name() {
  local addr=$1 line
  command -v lspci >/dev/null 2>&1 || return 1
  line=$(LC_ALL=C lspci -s "$addr" 2>/dev/null | head -n1)
  [[ -n $line ]] || return 1
  line=${line#*: }
  gpu_strip_name "$line"
}

gpu_card_temp() {
  local card=$1 max=0 h input val
  for h in "$card"/device/hwmon/hwmon*; do
    [[ -d $h ]] || continue
    for input in "$h"/temp*_input; do
      [[ -r $input ]] || continue
      read -r val < "$input"
      [[ $val =~ ^-?[0-9]+$ ]] || continue
      (( val >= 1000 )) && val=$(( val / 1000 ))
      (( val > max )) && max=$val
    done
  done
  (( max > 0 )) && printf '%s' "$max"
}

gpu_card_vram() {
  local card=$1 total=0 used=0 f val
  for f in mem_info_vram_total mem_info_vis_vram_total; do
    [[ -r $card/device/$f ]] || continue
    read -r val < "$card/device/$f"
    [[ $val =~ ^[0-9]+$ ]] || continue
    (( val > total )) && total=$val
  done
  for f in mem_info_vram_used mem_info_vis_vram_used; do
    [[ -r $card/device/$f ]] || continue
    read -r val < "$card/device/$f"
    [[ $val =~ ^[0-9]+$ ]] || continue
    (( val > used )) && used=$val
  done
  printf '%s %s' "$total" "$used"
}

gpu_card_usage() {
  local card=$1 val
  [[ -r $card/device/gpu_busy_percent ]] || return 0
  read -r val < "$card/device/gpu_busy_percent"
  [[ $val =~ ^[0-9]+$ ]] && printf '%s' "$val"
}

gpu_classify() {
  local vendor=${1,,} driver=$2 vram=${3:-0} name=$4
  case $vendor in
    0x1af4|0x15ad|0x1234|0x80ee) printf 'virtual'; return 0 ;;
    0x10de) printf 'dedicada'; return 0 ;;
  esac
  case $driver in
    i915)
      case $name in *Arc*|*DG*) printf 'dedicada' ;; *) printf 'integrada' ;; esac
      return 0
      ;;
    xe)
      case $name in *Arc*|*DG*) printf 'dedicada' ;; *) printf 'integrada' ;; esac
      return 0
      ;;
    amdgpu|radeon)
      case $name in
        *'Radeon RX'*|*'Radeon Pro'*|*'Radeon VII'*|*'Radeon HD'*)
          printf 'dedicada'; return 0
          ;;
      esac
      (( vram >= 1073741824 )) && { printf 'dedicada'; return 0; }
      printf 'integrada'; return 0
      ;;
  esac
  case $vendor in
    0x8086) printf 'integrada' ;;
    0x1002) if (( vram >= 1073741824 )); then printf 'dedicada'; else printf 'integrada'; fi ;;
    *) printf 'desconhecida' ;;
  esac
}

gpu_add() {
  local name=$1 vendor=$2 driver=$3 type=$4 vram_total=$5 vram_used=$6
  local usage=$7 temp=$8 pci=$9 source=${10} i=$GPU_COUNT

  GPU_NAME[$i]=$name
  GPU_VENDOR[$i]=$vendor
  GPU_DRIVER[$i]=$driver
  GPU_TYPE[$i]=$type
  GPU_VRAM_TOTAL[$i]=$vram_total
  GPU_VRAM_USED[$i]=$vram_used
  GPU_USAGE[$i]=$usage
  GPU_TEMP[$i]=$temp
  GPU_PCI[$i]=$pci
  GPU_SOURCE[$i]=$source
  GPU_COUNT=$(( GPU_COUNT + 1 ))

  case $type in
    dedicada) GPU_DEDICATED_COUNT=$(( GPU_DEDICATED_COUNT + 1 )) ;;
    integrada) GPU_INTEGRATED_COUNT=$(( GPU_INTEGRATED_COUNT + 1 )) ;;
    virtual) GPU_VIRTUAL_COUNT=$(( GPU_VIRTUAL_COUNT + 1 )) ;;
  esac
}

gpu_nvidia_load() {
  command -v nvidia-smi >/dev/null 2>&1 || return 1

  local out name pci mem_total mem_used util temp before=$GPU_COUNT
  local query='name,pci.bus_id,memory.total,memory.used,utilization.gpu,temperature.gpu'
  if command -v timeout >/dev/null 2>&1; then
    out=$(timeout 1 nvidia-smi --query-gpu="$query" --format=csv,noheader,nounits 2>/dev/null) || return 1
  else
    out=$(nvidia-smi --query-gpu="$query" --format=csv,noheader,nounits 2>/dev/null) || return 1
  fi
  [[ -n $out ]] || return 1

  while IFS=',' read -r name pci mem_total mem_used util temp; do
    name=$(gpu_trim "$name")
    pci=$(gpu_trim "$pci")
    mem_total=$(gpu_trim "$mem_total")
    mem_used=$(gpu_trim "$mem_used")
    util=$(gpu_trim "$util")
    temp=$(gpu_trim "$temp")
    [[ -n $name ]] || continue

    [[ $mem_total =~ ^[0-9]+$ ]] || mem_total=0
    [[ $mem_used =~ ^[0-9]+$ ]] || mem_used=0
    [[ $util =~ ^[0-9]+$ ]] || util=''
    [[ $temp =~ ^[0-9]+$ ]] || temp=''
    if [[ $pci =~ ^0+:([0-9a-fA-F:.]+)$ ]]; then
      pci="0000:${BASH_REMATCH[1]}"
    fi

    gpu_add "$name" 'NVIDIA' 'nvidia' 'dedicada' \
      $(( mem_total * 1048576 )) $(( mem_used * 1048576 )) \
      "$util" "$temp" "$pci" 'nvidia-smi'
  done <<< "$out"

  (( GPU_COUNT > before ))
}

gpu_sysfs_load() {
  local nvidia_ok=$1
  local card base addr vendor device class driver name type vram_total vram_used usage temp
  local -A seen=()

  for card in "${gpu_drm_dir:-/sys/class/drm}"/card[0-9]*; do
    base=${card##*/}
    [[ $base =~ ^card[0-9]+$ ]] || continue
    [[ -e $card/device ]] || continue

    addr=$(basename "$(readlink -f "$card/device" 2>/dev/null)" 2>/dev/null)
    [[ -n $addr ]] || addr=$base
    [[ -n ${seen[$addr]:-} ]] && continue

    vendor=$(cat "$card/device/vendor" 2>/dev/null || true)
    device=$(cat "$card/device/device" 2>/dev/null || true)
    class=$(cat "$card/device/class" 2>/dev/null || true)
    [[ ${class,,} == 0x03* ]] || continue
    if (( nvidia_ok )) && [[ ${vendor,,} == 0x10de ]]; then
      continue
    fi

    driver=''
    if [[ -e $card/device/driver ]]; then
      driver=$(basename "$(readlink -f "$card/device/driver" 2>/dev/null)" 2>/dev/null)
    fi
    name=$(gpu_pci_name "$addr" 2>/dev/null || true)
    [[ -n $name ]] || name=$(gpu_default_name "$vendor" "$device")

    vram_total=0 vram_used=0
    read -r vram_total vram_used < <(gpu_card_vram "$card")
    usage=$(gpu_card_usage "$card")
    temp=$(gpu_card_temp "$card")
    type=$(gpu_classify "$vendor" "$driver" "$vram_total" "$name")

    gpu_add "$name" "$(gpu_vendor_name "$vendor")" "$driver" "$type" \
      "$vram_total" "$vram_used" "$usage" "$temp" "$addr" 'sysfs'
    seen[$addr]=1
  done
}

# Fallback quando o driver não expõe card DRM (mostra só nome/marca).
gpu_lspci_load() {
  command -v lspci >/dev/null 2>&1 || return 1

  local line addr rest name vendor device type before=$GPU_COUNT
  while IFS= read -r line; do
    case $line in
      *'VGA compatible controller'*|*'3D controller'*|*'Display controller'*) ;;
      *) continue ;;
    esac

    addr=${line%% *}
    rest=${line#*: }
    name=$(gpu_strip_name "$rest")
    vendor='' device=''
    if [[ $line =~ \[([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\] ]]; then
      vendor="0x${BASH_REMATCH[1]}"
      device="0x${BASH_REMATCH[2]}"
    fi
    [[ -n $name ]] || name=$(gpu_default_name "$vendor" "$device")

    type=$(gpu_classify "$vendor" '' 0 "$name")
    gpu_add "$name" "$(gpu_vendor_name "$vendor")" '' "$type" \
      0 0 '' '' "$addr" 'lspci'
  done < <(LC_ALL=C lspci -D -nn 2>/dev/null)

  (( GPU_COUNT > before ))
}

gpu_detect() {
  (( GPU_LOADED )) && return 0
  GPU_LOADED=1
  gpu_reset

  local nvidia_ok=0
  gpu_nvidia_load && nvidia_ok=1
  gpu_sysfs_load "$nvidia_ok"
  (( GPU_COUNT == 0 )) && gpu_lspci_load

  return 0
}

gpu_display_name() {
  local i=$1 name=${GPU_NAME[$i]:-} brand=${GPU_VENDOR[$i]:-}
  case $brand in
    ''|desconhecida|PCI*) brand='' ;;
  esac
  if [[ -n $brand && $name != *"$brand"* ]]; then
    name="$brand $name"
  fi
  printf '%s' "$name"
}

gpu_vram_label() {
  local i=$1 total=${GPU_VRAM_TOTAL[$i]:-0} used=${GPU_VRAM_USED[$i]:-0}
  if (( total > 0 )); then
    if (( used > 0 )); then
      printf '%s / %s' "$(fmt_bytes "$used")" "$(fmt_bytes "$total")"
    else
      fmt_bytes "$total"
    fi
  else
    case ${GPU_TYPE[$i]:-} in
      integrada) printf 'compartilhada' ;;
      virtual) printf 'virtual' ;;
      *) printf 'n/d' ;;
    esac
  fi
}

gpu_usage_label() {
  local usage=${GPU_USAGE[$1]:-}
  [[ -n $usage ]] && printf '%s%%' "$usage" || printf 'n/d'
}

gpu_temp_label() {
  local temp=${GPU_TEMP[$1]:-}
  [[ -n $temp ]] && printf '%s °C' "$temp" || printf 'n/d'
}

gpu_integrated_name() {
  gpu_detect
  local i
  for i in "${!GPU_NAME[@]}"; do
    [[ ${GPU_TYPE[$i]:-} == integrada ]] || continue
    gpu_display_name "$i"
    return 0
  done
  return 1
}

gpu_integrated_driver() {
  gpu_detect
  local i
  for i in "${!GPU_NAME[@]}"; do
    [[ ${GPU_TYPE[$i]:-} == integrada ]] || continue
    printf '%s' "${GPU_DRIVER[$i]:-}"
    return 0
  done
  return 1
}

# Linhas da seção PLACA DE VÍDEO do painel.
render_gpu_section() {
  panel_on gpu || return 0
  [[ $panel_gpu == off ]] && return 0
  gpu_detect

  section 'PLACA DE VÍDEO'
  local maxw=$(( cols - 11 ))
  (( maxw < 1 )) && maxw=1

  if (( GPU_COUNT == 0 )); then
    emit_row 'GPU' "${C_DIM}nenhuma GPU detectada${C_RESET}"
    return 0
  fi

  local i name type driver line detail brand
  for i in "${!GPU_NAME[@]}"; do
    name=$(gpu_display_name "$i")
    brand=${GPU_VENDOR[$i]:-}
    if (( compact )) && (( cols < 45 )); then
      case $brand in
        Intel|AMD|NVIDIA) name=${name#"$brand" } ;;
      esac
    fi
    type=${GPU_TYPE[$i]:-desconhecida}
    driver=${GPU_DRIVER[$i]:-}

    if [[ $panel_gpu == summary ]] || (( compact )); then
      line="$name · $type"
      (( ${GPU_VRAM_TOTAL[$i]:-0} > 0 )) && line+=" · $(gpu_vram_label "$i")"
      [[ -n ${GPU_USAGE[$i]:-} ]] && line+=" · ${GPU_USAGE[$i]}%"
      [[ -n ${GPU_TEMP[$i]:-} ]] && line+=" · ${GPU_TEMP[$i]} °C"
      line=$(fit_text "$line" "$maxw")
      emit_row 'GPU' "$line"
    else
      line="$name · $type"
      [[ -n $driver ]] && line+=" · $driver"
      line=$(fit_text "$line" "$maxw")
      emit_row 'GPU' "$line"

      detail="VRAM $(gpu_vram_label "$i") · uso $(gpu_usage_label "$i") · temp $(gpu_temp_label "$i")"
      detail=$(fit_text "$detail" "$maxw")
      emit_row '' "${C_DIM}${detail}${C_RESET}"
    fi
  done

  if (( GPU_DEDICATED_COUNT == 0 )); then
    local msg='nenhuma placa dedicada detectada'
    (( cols < 50 )) && msg='nenhuma dedicada'
    emit_row 'DEDICADA' "${C_DIM}$(fit_text "$msg" "$maxw")${C_RESET}"
  fi
}

gpu_help() {
  cat <<'HELP'
Uso: sysinfo gpu

Mostra todas as GPUs detectadas: nome, marca, tipo (integrada, dedicada ou
virtual), driver, VRAM, uso, temperatura e endereço PCI. Se não houver GPU
dedicada, informa isso explicitamente.

Fontes: /sys/class/drm (AMD/Intel e VRAM/uso/temperatura), nvidia-smi (NVIDIA)
e lspci (nome do modelo). Não precisa de root.

Opções:
  -h, --help   mostra esta ajuda
HELP
}

show_gpu() {
  local arg
  for arg in "$@"; do
    case $arg in
      -h|--help) gpu_help; return 0 ;;
      '') ;;
      *)
        printf 'sysinfo gpu: opção desconhecida: %s\n' "$arg" >&2
        return 2
        ;;
    esac
  done

  gpu_detect

  printf '\n  %s%sPLACAS DE VÍDEO%s\n' "$C_DIM" "$C_BOLD" "$C_RESET"

  if (( GPU_COUNT == 0 )); then
    printf '  %sNenhuma GPU detectada.%s\n' "$C_DIM" "$C_RESET"
    printf '  %sDica: instale pciutils (lspci); para NVIDIA, o nvidia-smi.%s\n\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  local i vram
  for i in "${!GPU_NAME[@]}"; do
    printf '\n  %sGPU %d%s\n' "$C_BOLD" "$(( i + 1 ))" "$C_RESET"
    gpu_field 'Nome' "$(gpu_display_name "$i")"
    gpu_field 'Marca' "${GPU_VENDOR[$i]:-desconhecida}"
    gpu_field 'Tipo' "${GPU_TYPE[$i]:-desconhecida}"
    [[ -n ${GPU_DRIVER[$i]:-} ]] && gpu_field 'Driver' "${GPU_DRIVER[$i]}"

    vram=$(gpu_vram_label "$i")
    [[ $vram == compartilhada ]] && vram='compartilhada (memória do sistema)'
    gpu_field 'VRAM' "$vram"
    gpu_field 'Uso' "$(gpu_usage_label "$i")"
    gpu_field 'Temperatura' "$(gpu_temp_label "$i")"
    [[ -n ${GPU_PCI[$i]:-} ]] && gpu_field 'PCI' "${GPU_PCI[$i]}"
  done

  if (( GPU_DEDICATED_COUNT == 0 )); then
    printf '\n  %sNenhuma placa dedicada detectada.%s\n' "$C_DIM" "$C_RESET"
  fi
  printf '\n'
}

gpu_field() {
  printf '  %s%-12s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2"
}
