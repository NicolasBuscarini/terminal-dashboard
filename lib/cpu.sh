#!/usr/bin/env bash
# cpu.sh — modelo, núcleos/threads, frequência, cache, iGPU e temperatura da CPU.

CPU_LOADED=0

cpu_trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

cpu_reset() {
  CPU_MODEL='' CPU_MODEL_SHORT='' CPU_VENDOR_ID='' CPU_BRAND=''
  CPU_CORES=0 CPU_THREADS=0 CPU_SOCKETS=0
  CPU_FREQ_BASE=0 CPU_FREQ_MAX=0 CPU_FREQ_MIN=0 CPU_FREQ_CUR=0
  CPU_CACHE_L3=0 CPU_GOVERNOR=''
  CPU_TEMP='' CPU_TEMP_LABEL=''
  CPU_IGPU='' CPU_IGPU_DRIVER=''
}

# Remove sufixos de marketing para caber na linha do painel.
cpu_model_short() {
  local m=$1
  m=${m//(R)/}
  m=${m//(TM)/}
  m=${m// CPU/}
  m=${m%% @ *}
  m=${m% Processor}
  m=$(printf '%s' "$m" | tr -s ' ')
  cpu_trim "$m"
}

cpu_size_bytes() {
  local s=$1 n=0
  case $s in
    *K) n=${s%K} ;;
    *M) n=${s%M}; [[ $n =~ ^[0-9]+$ ]] && { printf '%d' $(( n * 1048576 )); return 0; } ;;
    *G) n=${s%G}; [[ $n =~ ^[0-9]+$ ]] && { printf '%d' $(( n * 1073741824 )); return 0; } ;;
  esac
  [[ $n =~ ^[0-9]+$ ]] && printf '%d' $(( n * 1024 )) || printf '0'
}

cpu_read_freq() {
  local dir=/sys/devices/system/cpu/cpu0/cpufreq
  local base=0 max=0 min=0 cur=0

  [[ -r $dir/base_frequency ]] && read -r base < "$dir/base_frequency"
  [[ -r $dir/cpuinfo_max_freq ]] && read -r max < "$dir/cpuinfo_max_freq"
  [[ -r $dir/cpuinfo_min_freq ]] && read -r min < "$dir/cpuinfo_min_freq"
  [[ -r $dir/scaling_cur_freq ]] && read -r cur < "$dir/scaling_cur_freq"

  (( max == 0 )) && [[ -r $dir/scaling_max_freq ]] && read -r max < "$dir/scaling_max_freq"
  (( cur == 0 )) && [[ -r $dir/cpuinfo_cur_freq ]] && read -r cur < "$dir/cpuinfo_cur_freq"

  CPU_FREQ_BASE=$(( base / 1000 ))
  CPU_FREQ_MAX=$(( max / 1000 ))
  CPU_FREQ_MIN=$(( min / 1000 ))
  CPU_FREQ_CUR=$(( cur / 1000 ))

  # Sem cpufreq (comum em ARM/VM), tenta o "@ 1.60GHz" do model name.
  if (( CPU_FREQ_BASE == 0 )) && [[ $CPU_MODEL =~ @[[:space:]]*([0-9]+([.,][0-9]+)?)[[:space:]]*GHz ]]; then
    local ghz=${BASH_REMATCH[1]//,/.}
    CPU_FREQ_BASE=$(awk -v g="$ghz" 'BEGIN { printf "%d", g * 1000 }')
  fi
}

# coretemp (Intel), k10temp/zenpower (AMD) e thermal_zone como fallback.
cpu_temp_detect() {
  CPU_TEMP='' CPU_TEMP_LABEL=''
  local base=${cpu_hwmon_dir:-/sys/class/hwmon}
  local h name input label val max=0 maxlabel='' pref=0 preflabel=''

  for h in "$base"/hwmon*; do
    [[ -r $h/name ]] || continue
    read -r name < "$h/name"
    case $name in
      coretemp|k10temp|zenpower|k8temp|cpu_thermal|soc_thermal) ;;
      *) continue ;;
    esac
    for input in "$h"/temp*_input; do
      [[ -r $input ]] || continue
      read -r val < "$input"
      [[ $val =~ ^-?[0-9]+$ ]] || continue
      (( val >= 1000 )) && val=$(( val / 1000 ))
      (( val <= 0 )) && continue

      label=''
      [[ -r ${input%_input}_label ]] && read -r label < "${input%_input}_label"
      case $label in
        'Package id 0'|'Physical id 0'|Tctl|Tdie|CPU|Package)
          (( val > pref )) && { pref=$val; preflabel=$label; }
          ;;
      esac
      (( val > max )) && { max=$val; maxlabel=$label; }
    done
  done

  if (( pref > 0 )); then
    CPU_TEMP=$pref CPU_TEMP_LABEL=$preflabel
  elif (( max > 0 )); then
    CPU_TEMP=$max CPU_TEMP_LABEL=$maxlabel
  fi

  if [[ -z $CPU_TEMP ]]; then
    local z type zmax=0 zlabel=''
    for z in "${cpu_thermal_dir:-/sys/class/thermal}"/thermal_zone*; do
      [[ -r $z/type && -r $z/temp ]] || continue
      read -r type < "$z/type"
      case $type in
        x86_pkg_temp|cpu-thermal|cpu_thermal|soc_thermal|soc-thermal) ;;
        *) continue ;;
      esac
      read -r val < "$z/temp"
      [[ $val =~ ^[0-9]+$ ]] || continue
      (( val >= 1000 )) && val=$(( val / 1000 ))
      (( val > zmax )) && { zmax=$val; zlabel=$type; }
    done
    (( zmax > 0 )) && { CPU_TEMP=$zmax; CPU_TEMP_LABEL=$zlabel; }
  fi
}

# Aproveita a detecção de GPU para dizer se existe vídeo integrado.
cpu_igpu_detect() {
  CPU_IGPU='' CPU_IGPU_DRIVER=''
  if declare -F gpu_integrated_name >/dev/null 2>&1; then
    gpu_detect
    CPU_IGPU=$(gpu_integrated_name 2>/dev/null || true)
    CPU_IGPU_DRIVER=$(gpu_integrated_driver 2>/dev/null || true)
    return 0
  fi

  # Fallback quando cpu.sh é usado sem gpu.sh.
  if command -v lspci >/dev/null 2>&1; then
    CPU_IGPU=$(LC_ALL=C lspci 2>/dev/null | awk -F': ' '
      /VGA compatible controller|Display controller/ { print $2; exit }')
  fi
}

cpu_detect() {
  (( CPU_LOADED )) && return 0
  CPU_LOADED=1
  cpu_reset

  local line key val
  while IFS= read -r line; do
    [[ $line == *:* ]] || continue
    key=$(cpu_trim "${line%%:*}")
    val=$(cpu_trim "${line#*:}")
    case $key in
      'model name') [[ -z $CPU_MODEL ]] && CPU_MODEL=$val ;;
      'vendor_id') [[ -z $CPU_VENDOR_ID ]] && CPU_VENDOR_ID=$val ;;
      Processor) [[ -z $CPU_MODEL ]] && CPU_MODEL=$val ;;
    esac
  done < /proc/cpuinfo

  CPU_THREADS=$(awk '/^processor[[:space:]]*:/ { n++ } END { print n + 0 }' /proc/cpuinfo 2>/dev/null)
  [[ $CPU_THREADS =~ ^[0-9]+$ ]] || CPU_THREADS=0

  # Núcleos físicos e soquetes pela topologia do sysfs.
  local -A cores_seen=() pkgs_seen=()
  local c core pkg online
  for c in /sys/devices/system/cpu/cpu[0-9]*; do
    [[ -d $c ]] || continue
    [[ ${c##*/} =~ ^cpu[0-9]+$ ]] || continue
    if [[ -r $c/online ]]; then
      read -r online < "$c/online"
      [[ $online == 0 ]] && continue
    fi
    [[ -r $c/topology/core_id && -r $c/topology/physical_package_id ]] || continue
    read -r core < "$c/topology/core_id"
    read -r pkg < "$c/topology/physical_package_id"
    [[ $core =~ ^[0-9]+$ && $pkg =~ ^[0-9]+$ ]] || continue
    cores_seen["$pkg:$core"]=1
    pkgs_seen["$pkg"]=1
  done

  CPU_CORES=${#cores_seen[@]}
  CPU_SOCKETS=${#pkgs_seen[@]}
  (( CPU_SOCKETS < 1 )) && CPU_SOCKETS=1
  if (( CPU_CORES < 1 )); then
    CPU_CORES=$(nproc 2>/dev/null || printf '1')
    CPU_THREADS=$CPU_CORES
    CPU_SOCKETS=1
  fi
  (( CPU_THREADS < CPU_CORES )) && CPU_THREADS=$CPU_CORES

  case $CPU_VENDOR_ID in
    GenuineIntel) CPU_BRAND=Intel ;;
    AuthenticAMD) CPU_BRAND=AMD ;;
    *ARM*|*arm*) CPU_BRAND=ARM ;;
    *) CPU_BRAND=$CPU_VENDOR_ID ;;
  esac

  if [[ -z $CPU_MODEL ]] && command -v lscpu >/dev/null 2>&1; then
    CPU_MODEL=$(LC_ALL=C lscpu 2>/dev/null | awk -F: '
      /^Model name/ { sub(/^[ \t]+/, "", $2); print $2; exit }')
  fi
  if [[ -z $CPU_BRAND ]]; then
    case $CPU_MODEL in
      *Intel*) CPU_BRAND=Intel ;;
      *AMD*) CPU_BRAND=AMD ;;
      *ARM*|*Cortex*) CPU_BRAND=ARM ;;
    esac
  fi
  CPU_MODEL_SHORT=$(cpu_model_short "$CPU_MODEL")

  cpu_read_freq

  local idx level size bytes
  for idx in /sys/devices/system/cpu/cpu0/cache/index*; do
    [[ -r $idx/level && -r $idx/size ]] || continue
    read -r level < "$idx/level"
    [[ $level == 3 ]] || continue
    read -r size < "$idx/size"
    bytes=$(cpu_size_bytes "$size")
    (( bytes > CPU_CACHE_L3 )) && CPU_CACHE_L3=$bytes
  done

  [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]] &&
    read -r CPU_GOVERNOR < /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

  cpu_temp_detect
  cpu_igpu_detect
}

cpu_freq_label() {
  local base=${CPU_FREQ_BASE:-0} max=${CPU_FREQ_MAX:-0}
  if (( base > 0 && max > 0 && base != max )); then
    printf '%s (base) · %s (máx.)' "$(fmt_freq_mhz "$base")" "$(fmt_freq_mhz "$max")"
  elif (( max > 0 )); then
    fmt_freq_mhz "$max"
  elif (( base > 0 )); then
    fmt_freq_mhz "$base"
  fi
}

cpu_field() {
  printf '  %s%-12s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2"
}

cpu_help() {
  cat <<'HELP'
Uso: sysinfo cpu

Mostra o processador: modelo, marca (Intel/AMD), núcleos físicos e threads,
soquetes, frequência base/máxima, cache L3, governador, vídeo integrado (iGPU)
e temperatura.

Não precisa de root: lê /proc/cpuinfo, /sys/devices/system/cpu, os sensores
hwmon/thermal e, se existir, o lspci para o nome da iGPU.

Opções:
  -h, --help   mostra esta ajuda
HELP
}

show_cpu() {
  local arg
  for arg in "$@"; do
    case $arg in
      -h|--help) cpu_help; return 0 ;;
      '') ;;
      *)
        printf 'sysinfo cpu: opção desconhecida: %s\n' "$arg" >&2
        return 2
        ;;
    esac
  done

  cpu_detect

  printf '\n  %s%sPROCESSADOR%s\n' "$C_DIM" "$C_BOLD" "$C_RESET"
  cpu_field 'Modelo' "${CPU_MODEL:-desconhecido}"
  cpu_field 'Marca' "${CPU_BRAND:-desconhecida}"

  local cores_line
  if (( CPU_CORES == 1 )); then
    cores_line='1 núcleo'
  else
    cores_line="${CPU_CORES} núcleos"
  fi
  cores_line+=" · ${CPU_THREADS} threads"
  (( CPU_SOCKETS > 1 )) && cores_line+=" · ${CPU_SOCKETS} soquetes"
  cpu_field 'Núcleos' "$cores_line"

  local freq
  freq=$(cpu_freq_label)
  [[ -n $freq ]] && cpu_field 'Frequência' "$freq"
  (( CPU_FREQ_CUR > 0 )) && cpu_field 'Atual' "$(fmt_freq_mhz "$CPU_FREQ_CUR")"
  (( CPU_CACHE_L3 > 0 )) && cpu_field 'Cache L3' "$(fmt_bytes "$CPU_CACHE_L3")"
  [[ -n $CPU_GOVERNOR ]] && cpu_field 'Governador' "$CPU_GOVERNOR"

  if [[ -n $CPU_IGPU ]]; then
    local igpu=$CPU_IGPU
    [[ -n $CPU_IGPU_DRIVER ]] && igpu+=" ($CPU_IGPU_DRIVER)"
    cpu_field 'Vídeo' "$igpu"
  elif (( ${GPU_DEDICATED_COUNT:-0} > 0 )); then
    cpu_field 'Vídeo' 'sem vídeo integrado · GPU dedicada presente'
  else
    cpu_field 'Vídeo' 'sem vídeo integrado detectado'
  fi

  if [[ -n $CPU_TEMP ]]; then
    local temp="${CPU_TEMP} °C"
    [[ -n $CPU_TEMP_LABEL ]] && temp+=" ($CPU_TEMP_LABEL)"
    cpu_field 'Temperatura' "$temp"
  fi

  printf '\n'
}
