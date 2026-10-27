#!/usr/bin/env bash
# memory.sh — detalhes dos módulos de RAM (dmidecode/EDAC) e temperatura.

RAM_DMI_AVAILABLE=0
RAM_EDAC_AVAILABLE=0
RAM_LOADED=0
RAM_DMI_SOURCE=''
RAM_DMI_AGE=0

memory_reset() {
  RAM_SLOTS_TOTAL=0 RAM_SLOTS_USED=0 RAM_SLOTS_FREE=0
  RAM_TOTAL_BYTES=0 RAM_MAX_BYTES=0
  RAM_TYPE='' RAM_FORM='' RAM_RANK='' RAM_ECC=''
  RAM_SPEED_MIN=0 RAM_SPEED_MAX=0
  RAM_SPEED_ADV_MIN=0 RAM_SPEED_ADV_MAX=0
  RAM_TEMP='' RAM_TEMP_COUNT=0
  RAM_LOCATOR=() RAM_SIZE=() RAM_MOD_TYPE=() RAM_MOD_SPEED=()
  RAM_MOD_CONF=() RAM_MOD_MANUF=() RAM_MOD_PART=() RAM_MOD_FORM=()
  RAM_MOD_RANK=() RAM_MOD_VOLT=() RAM_MOD_USED=()
}

memory_trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

# Limpa valores que o dmidecode usa para "não informado".
memory_clean() {
  local v
  v=$(memory_trim "$1")
  case ${v,,} in
    ''|unknown|'not specified'|'not provided'|'no module installed'|'no dimm')
      printf ''
      ;;
    *)
      printf '%s' "$v"
      ;;
  esac
}

memory_size_bytes() {
  local s=$1 n unit
  if [[ $s =~ ^[[:space:]]*([0-9]+)[[:space:]]*([KMGTP]i?B)$ ]]; then
    n=${BASH_REMATCH[1]}
    unit=${BASH_REMATCH[2]^^}
    case $unit in
      KB|KIB) printf '%d' $(( n * 1024 )) ;;
      MB|MIB) printf '%d' $(( n * 1048576 )) ;;
      GB|GIB) printf '%d' $(( n * 1073741824 )) ;;
      TB|TIB) printf '%d' $(( n * 1099511627776 )) ;;
      PB|PIB) printf '%d' $(( n * 1125899906842624 )) ;;
      *) printf '0' ;;
    esac
  else
    printf '0'
  fi
}

memory_speed_num() {
  local s=$1
  [[ $s =~ ^[[:space:]]*([0-9]+) ]] && printf '%s' "${BASH_REMATCH[1]}"
}

# --------------------------------------------------------------- parser DMI
_ram_m_reset() {
  _ram_m_size='' _ram_m_type='' _ram_m_speed='' _ram_m_conf=''
  _ram_m_manuf='' _ram_m_part='' _ram_m_locator='' _ram_m_form=''
  _ram_m_rank='' _ram_m_volt=''
}

_ram_a_reset() {
  _ram_a_max='' _ram_a_slots='' _ram_a_ecc=''
}

_ram_flush_module() {
  [[ -n $_ram_m_size ]] || return 0

  local size_str=$_ram_m_size bytes=0 used=0 i
  if [[ $size_str != *'No Module Installed'* && $size_str != *Unknown* ]]; then
    bytes=$(memory_size_bytes "$size_str")
  fi
  (( bytes > 0 )) && used=1

  i=${#RAM_LOCATOR[@]}
  RAM_LOCATOR[$i]=$(memory_clean "$_ram_m_locator")
  [[ -z ${RAM_LOCATOR[$i]} ]] && RAM_LOCATOR[$i]="DIMM$(( i + 1 ))"
  RAM_SIZE[$i]=$bytes
  RAM_MOD_TYPE[$i]=$(memory_clean "$_ram_m_type")
  RAM_MOD_SPEED[$i]=$(memory_speed_num "$_ram_m_speed")
  RAM_MOD_CONF[$i]=$(memory_speed_num "$_ram_m_conf")
  RAM_MOD_MANUF[$i]=$(memory_clean "$_ram_m_manuf")
  RAM_MOD_PART[$i]=$(memory_clean "$_ram_m_part")
  RAM_MOD_FORM[$i]=$(memory_clean "$_ram_m_form")
  RAM_MOD_RANK[$i]=$(memory_clean "$_ram_m_rank")
  RAM_MOD_VOLT[$i]=$(memory_clean "$_ram_m_volt")
  RAM_MOD_USED[$i]=$used

  if (( used )); then
    RAM_SLOTS_USED=$(( RAM_SLOTS_USED + 1 ))
    RAM_TOTAL_BYTES=$(( RAM_TOTAL_BYTES + bytes ))
  fi

  _ram_m_reset
}

_ram_flush_array() {
  local b
  if [[ -n $_ram_a_max ]]; then
    b=$(memory_size_bytes "$_ram_a_max")
    (( b > 0 )) && RAM_MAX_BYTES=$b
  fi
  if [[ $(memory_trim "$_ram_a_slots") =~ ^[0-9]+$ ]]; then
    RAM_SLOTS_TOTAL=$(memory_trim "$_ram_a_slots")
  fi
  [[ -n $_ram_a_ecc ]] && RAM_ECC=$(memory_trim "$_ram_a_ecc")
  _ram_a_reset
}

# Lê a saída de "dmidecode -t memory" (em inglês; LC_ALL=C).
memory_parse_dmi() {
  local file=$1 line key val in_dev=0 in_arr=0

  _ram_m_reset
  _ram_a_reset

  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      'Memory Device')
        _ram_flush_module
        _ram_flush_array
        in_dev=1
        in_arr=0
        ;;
      'Physical Memory Array')
        _ram_flush_module
        _ram_flush_array
        in_dev=0
        in_arr=1
        ;;
      '')
        ;;
      [[:space:]]*)
        key=${line#"${line%%[![:space:]]*}"}
        key=${key%%:*}
        val=${line#*:}
        if (( in_dev )); then
          case $key in
            Size) _ram_m_size=$val ;;
            Type) _ram_m_type=$val ;;
            Speed) _ram_m_speed=$val ;;
            'Configured Memory Speed') _ram_m_conf=$val ;;
            Manufacturer) _ram_m_manuf=$val ;;
            'Part Number') _ram_m_part=$val ;;
            Locator) _ram_m_locator=$val ;;
            'Bank Locator') [[ -z $_ram_m_locator ]] && _ram_m_locator=$val ;;
            'Form Factor') _ram_m_form=$val ;;
            Rank) _ram_m_rank=$val ;;
            'Configured Voltage') _ram_m_volt=$val ;;
            'Minimum Voltage') [[ -z $_ram_m_volt ]] && _ram_m_volt=$val ;;
          esac
        elif (( in_arr )); then
          case $key in
            'Maximum Capacity') _ram_a_max=$val ;;
            'Number Of Devices') _ram_a_slots=$val ;;
            'Error Correction Type') _ram_a_ecc=$val ;;
          esac
        fi
        ;;
    esac
  done < "$file"

  _ram_flush_module
  _ram_flush_array
}

# Consolida tipo/formato/rank mais comuns e as frequências dos módulos usados.
memory_finalize() {
  local i t s best bestn
  local -A type_count=() form_count=() rank_count=()

  if (( RAM_SLOTS_TOTAL == 0 )); then
    RAM_SLOTS_TOTAL=${#RAM_LOCATOR[@]}
  fi
  (( RAM_SLOTS_TOTAL < ${#RAM_LOCATOR[@]} )) && RAM_SLOTS_TOTAL=${#RAM_LOCATOR[@]}
  RAM_SLOTS_FREE=$(( RAM_SLOTS_TOTAL - RAM_SLOTS_USED ))
  (( RAM_SLOTS_FREE < 0 )) && RAM_SLOTS_FREE=0

  RAM_SPEED_MIN=0 RAM_SPEED_MAX=0
  RAM_SPEED_ADV_MIN=0 RAM_SPEED_ADV_MAX=0

  for i in "${!RAM_LOCATOR[@]}"; do
    (( ${RAM_MOD_USED[$i]:-0} )) || continue

    t=${RAM_MOD_TYPE[$i]:-}
    [[ -n $t ]] && type_count[$t]=$(( ${type_count[$t]:-0} + 1 ))
    t=${RAM_MOD_FORM[$i]:-}
    [[ -n $t ]] && form_count[$t]=$(( ${form_count[$t]:-0} + 1 ))
    t=${RAM_MOD_RANK[$i]:-}
    [[ -n $t ]] && rank_count[$t]=$(( ${rank_count[$t]:-0} + 1 ))

    s=${RAM_MOD_CONF[$i]:-0}
    (( s > 0 )) || s=${RAM_MOD_SPEED[$i]:-0}
    if (( s > 0 )); then
      (( RAM_SPEED_MIN == 0 || s < RAM_SPEED_MIN )) && RAM_SPEED_MIN=$s
      (( s > RAM_SPEED_MAX )) && RAM_SPEED_MAX=$s
    fi

    s=${RAM_MOD_SPEED[$i]:-0}
    if (( s > 0 )); then
      (( RAM_SPEED_ADV_MIN == 0 || s < RAM_SPEED_ADV_MIN )) && RAM_SPEED_ADV_MIN=$s
      (( s > RAM_SPEED_ADV_MAX )) && RAM_SPEED_ADV_MAX=$s
    fi
  done

  best='' bestn=0
  for t in "${!type_count[@]}"; do
    if (( type_count[$t] > bestn )); then bestn=${type_count[$t]}; best=$t; fi
  done
  RAM_TYPE=$best

  best='' bestn=0
  for t in "${!form_count[@]}"; do
    if (( form_count[$t] > bestn )); then bestn=${form_count[$t]}; best=$t; fi
  done
  RAM_FORM=$best

  best='' bestn=0
  for t in "${!rank_count[@]}"; do
    if (( rank_count[$t] > bestn )); then bestn=${rank_count[$t]}; best=$t; fi
  done
  RAM_RANK=$best
}

# Temperatura dos módulos via hwmon (spd5118 em DDR5, jc42 em DDR4 etc.).
memory_temp_detect() {
  RAM_TEMP='' RAM_TEMP_COUNT=0
  local base=${memory_hwmon_dir:-/sys/class/hwmon}
  local h name input val max=0
  for h in "$base"/hwmon*; do
    [[ -r $h/name ]] || continue
    name=$(<"$h/name")
    case $name in
      spd5118|jc42|jc42-*|dimmtemp|dimm*) ;;
      *) continue ;;
    esac
    for input in "$h"/temp*_input; do
      [[ -r $input ]] || continue
      val=$(<"$input")
      [[ $val =~ ^-?[0-9]+$ ]] || continue
      (( val > 1000 )) && val=$(( val / 1000 ))
      (( val > max )) && max=$val
      RAM_TEMP_COUNT=$(( RAM_TEMP_COUNT + 1 ))
    done
  done
  (( max > 0 )) && RAM_TEMP=$max
}

# Fallback sem root: EDAC expõe tipo e tamanho dos DIMMs em sistemas ECC.
memory_edac_load() {
  local base=${memory_edac_dir:-/sys/devices/system/edac/mc}
  local d label loc type size i=0
  memory_reset

  for d in "$base"/mc*/dimm*; do
    [[ -d $d ]] || continue
    size=0
    [[ -r $d/size_mb ]] && size=$(<"$d/size_mb")
    [[ $size =~ ^[0-9]+$ ]] || size=0

    label=$(cat "$d/dimm_label" 2>/dev/null || true)
    loc=$(cat "$d/dimm_location" 2>/dev/null || true)
    type=$(cat "$d/dimm_mem_type" 2>/dev/null || true)

    RAM_LOCATOR[$i]=$(memory_clean "$label")
    [[ -z ${RAM_LOCATOR[$i]} ]] && RAM_LOCATOR[$i]=$(memory_clean "$loc")
    [[ -z ${RAM_LOCATOR[$i]} ]] && RAM_LOCATOR[$i]="DIMM$(( i + 1 ))"
    RAM_SIZE[$i]=$(( size * 1048576 ))
    RAM_MOD_TYPE[$i]=$(memory_clean "$type")
    RAM_MOD_SPEED[$i]='' RAM_MOD_CONF[$i]=''
    RAM_MOD_MANUF[$i]='' RAM_MOD_PART[$i]=''
    RAM_MOD_FORM[$i]='' RAM_MOD_RANK[$i]='' RAM_MOD_VOLT[$i]=''

    if (( size > 0 )); then
      RAM_MOD_USED[$i]=1
      RAM_SLOTS_USED=$(( RAM_SLOTS_USED + 1 ))
      RAM_TOTAL_BYTES=$(( RAM_TOTAL_BYTES + size * 1048576 ))
    else
      RAM_MOD_USED[$i]=0
    fi
    i=$(( i + 1 ))
  done

  (( i > 0 )) || return 1
  RAM_EDAC_AVAILABLE=1
  RAM_DMI_SOURCE='edac'
  memory_finalize
  return 0
}

# --------------------------------------------------------------- cache DMI
# Quando o comando roda via sudo, o cache é criado por root; devolve o dono
# para o usuário que chamou o sudo conseguir ler nas próximas execuções.
memory_cache_owner_fix() {
  [[ -n ${SUDO_UID:-} && -n ${SUDO_GID:-} ]] || return 0
  [[ -e $memory_cache_dir ]] && chown "$SUDO_UID:$SUDO_GID" "$memory_cache_dir" 2>/dev/null || true
  [[ -e $memory_cache_file ]] && chown "$SUDO_UID:$SUDO_GID" "$memory_cache_file" 2>/dev/null || true
}

memory_dmi_fetch_quiet() {
  local tmp rc=0
  command -v dmidecode >/dev/null 2>&1 || return 1
  tmp=$(mktemp "${TMPDIR:-/tmp}/sysinfo-dmi.XXXXXX") || return 1

  if (( EUID == 0 )); then
    LC_ALL=C dmidecode -t memory >"$tmp" 2>/dev/null || rc=$?
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n env LC_ALL=C dmidecode -t memory >"$tmp" 2>/dev/null || rc=$?
  else
    rc=1
  fi

  if (( rc != 0 )) || [[ ! -s $tmp ]]; then
    rm -f "$tmp"
    return 1
  fi

  mkdir -p "$memory_cache_dir" 2>/dev/null || { rm -f "$tmp"; return 1; }
  chmod 700 "$memory_cache_dir" 2>/dev/null || true
  mv -f "$tmp" "$memory_cache_file" 2>/dev/null || { rm -f "$tmp"; return 1; }
  chmod 600 "$memory_cache_file" 2>/dev/null || true
  memory_cache_owner_fix
  return 0
}

# Atualização explícita: pode pedir senha do sudo (chamada por "sysinfo ram -u").
memory_dmi_refresh() {
  local tmp rc=0

  if ! command -v dmidecode >/dev/null 2>&1; then
    printf 'sysinfo ram: "dmidecode" não encontrado (instale o pacote dmidecode).\n' >&2
    return 1
  fi

  tmp=$(mktemp "${TMPDIR:-/tmp}/sysinfo-dmi.XXXXXX") || return 1
  if (( EUID == 0 )); then
    LC_ALL=C dmidecode -t memory >"$tmp" || rc=$?
  elif command -v sudo >/dev/null 2>&1; then
    sudo env LC_ALL=C dmidecode -t memory >"$tmp" || rc=$?
  else
    printf 'sysinfo ram: é preciso root para ler o DMI (use sudo).\n' >&2
    rc=1
  fi

  if (( rc != 0 )) || [[ ! -s $tmp ]]; then
    rm -f "$tmp"
    (( rc != 0 )) || rc=1
    return "$rc"
  fi

  mkdir -p "$memory_cache_dir" 2>/dev/null || { rm -f "$tmp"; return 1; }
  chmod 700 "$memory_cache_dir" 2>/dev/null || true
  mv -f "$tmp" "$memory_cache_file" 2>/dev/null || { rm -f "$tmp"; return 1; }
  chmod 600 "$memory_cache_file" 2>/dev/null || true
  memory_cache_owner_fix

  printf 'sysinfo ram: detalhes atualizados em %s\n' "$memory_cache_file"
  RAM_LOADED=0
  return 0
}

memory_dmi_load() {
  local file='' src=''

  RAM_DMI_SOURCE='' RAM_DMI_AGE=0

  if [[ -n ${SYSINFO_RAM_DMI_FILE:-} ]]; then
    [[ -r $SYSINFO_RAM_DMI_FILE ]] || return 1
    file=$SYSINFO_RAM_DMI_FILE
    src='arquivo'
  elif [[ -r $memory_cache_file ]]; then
    file=$memory_cache_file
    src='cache'
    RAM_DMI_AGE=$(( $(date +%s) - $(stat -c %Y "$file" 2>/dev/null || printf '0') ))
    (( RAM_DMI_AGE < 0 )) && RAM_DMI_AGE=0
  elif memory_dmi_fetch_quiet; then
    file=$memory_cache_file
    src='auto'
  fi

  [[ -n $file ]] || return 1

  memory_reset
  memory_parse_dmi "$file"
  memory_finalize
  (( RAM_SLOTS_TOTAL > 0 || RAM_TOTAL_BYTES > 0 )) || return 1

  RAM_DMI_AVAILABLE=1
  RAM_DMI_SOURCE=$src
  return 0
}

memory_load() {
  (( RAM_LOADED )) && return 0
  RAM_LOADED=1
  RAM_DMI_AVAILABLE=0
  RAM_EDAC_AVAILABLE=0
  memory_reset

  if ! memory_dmi_load; then
    memory_edac_load || true
  fi
  memory_temp_detect

  (( RAM_DMI_AVAILABLE || RAM_EDAC_AVAILABLE )) && return 0
  return 1
}

# ---------------------------------------------------------------- formatação
memory_speed_label() {
  local conf=${1:-0} adv=${2:-0}
  if (( conf > 0 && adv > 0 && conf != adv )); then
    printf '%s MT/s (configurada) · %s MT/s (máxima)' "$conf" "$adv"
  elif (( conf > 0 )); then
    printf '%s MT/s' "$conf"
  elif (( adv > 0 )); then
    printf '%s MT/s' "$adv"
  fi
}

memory_ecc_label() {
  case ${RAM_ECC:-} in
    '') ;;
    None) printf 'sem ECC' ;;
    'Single-bit ECC') printf 'ECC single-bit' ;;
    'Multi-bit ECC') printf 'ECC multi-bit' ;;
    *) printf '%s' "$RAM_ECC" ;;
  esac
}

ram_field() {
  printf '  %s%-12s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2"
}

# Linhas de RAM do painel (abaixo de MEM/SWAP).
render_ram_rows() {
  panel_on ram || return 0
  [[ $panel_ram == off ]] && return 0
  memory_load || true

  local temp='' speed='' summary=''
  [[ -n $RAM_TEMP ]] && temp="${RAM_TEMP} °C"
  (( RAM_SPEED_MAX > 0 )) && speed="${RAM_SPEED_MAX} MT/s"

  if (( RAM_DMI_AVAILABLE || RAM_EDAC_AVAILABLE )); then
    if (( compact )); then
      summary=${RAM_TYPE:-RAM}
      (( cols >= 50 )) && [[ -n $speed ]] && summary+=" · $speed"
      summary+=" · ${RAM_SLOTS_USED}/${RAM_SLOTS_TOTAL}"
      [[ -n $temp ]] && summary+=" · $temp"
    else
      summary=${RAM_TYPE:-RAM}
      [[ -n $speed ]] && summary+=" · $speed"
      summary+=" · ${RAM_SLOTS_USED}/${RAM_SLOTS_TOTAL} slots"
      if (( RAM_SLOTS_FREE > 0 )); then
        summary+=" (${RAM_SLOTS_FREE} livre"
        (( RAM_SLOTS_FREE > 1 )) && summary+='s'
        summary+=')'
      fi
      (( RAM_TOTAL_BYTES > 0 )) && summary+=" · $(fmt_bytes "$RAM_TOTAL_BYTES")"
      [[ -n $temp ]] && summary+=" · $temp"
    fi
    emit_row 'RAM' "$summary"

    if [[ $panel_ram == full ]] && (( ! compact )) && (( cols >= 70 )); then
      local i loc form size manuf modtype modspeed detail avail
      for i in "${!RAM_LOCATOR[@]}"; do
        (( ${RAM_MOD_USED[$i]:-0} )) || continue
        loc=${RAM_LOCATOR[$i]:-DIMM$(( i + 1 ))}
        form=${RAM_MOD_FORM[$i]:-}
        size=$(fmt_bytes "${RAM_SIZE[$i]:-0}")
        manuf=${RAM_MOD_MANUF[$i]:-}
        modtype=${RAM_MOD_TYPE[$i]:-}
        modspeed=${RAM_MOD_CONF[$i]:-${RAM_MOD_SPEED[$i]:-}}

        detail="$loc"
        [[ -n $form ]] && detail+="  $form"
        detail+="  $size"
        [[ -n $manuf ]] && detail+="  $manuf"
        [[ -n $modtype ]] && detail+="  $modtype"
        [[ -n $modspeed ]] && detail+="-${modspeed}"
        avail=$(( cols - 11 ))
        (( ${#detail} > avail )) && detail="${detail:0:avail-1}…"
        emit_row '' "$detail"
      done
    fi
  else
    local hint='detalhes com: sysinfo ram --update'
    (( cols < 60 )) && hint='sysinfo ram -u'
    if [[ -n $temp ]]; then
      emit_row 'RAM' "${C_DIM}${temp} · ${hint}${C_RESET}"
    else
      emit_row 'RAM' "${C_DIM}${hint}${C_RESET}"
    fi
  fi
}

# --------------------------------------------------------------- sysinfo ram
ram_help() {
  cat <<'HELP'
Uso: sysinfo ram [--update]

Mostra os módulos de memória: slots preenchidos/livres, geração (DDR4/DDR5),
frequência configurada e máxima, fabricante, part number, rank, tensão,
capacidade máxima suportada e temperatura (quando o sensor existe).

O dmidecode exige root. O painel nunca pede senha: ele usa um cache criado por
"sysinfo ram --update". Sem cache, tenta as informações do EDAC e os
sensores de temperatura via hwmon.

Opções:
  -u, --update   relê o DMI com sudo e atualiza o cache
  -h, --help     mostra esta ajuda

Exemplos:
  sysinfo ram --update
  sysinfo ram
  SYSINFO_PANEL_RAM=summary sysinfo
HELP
}

show_ram() {
  local update=0 arg

  for arg in "$@"; do
    case $arg in
      -u|--update) update=1 ;;
      -h|--help) ram_help; return 0 ;;
      '') ;;
      *)
        printf 'sysinfo ram: opção desconhecida: %s\n' "$arg" >&2
        return 2
        ;;
    esac
  done

  if (( update )); then
    memory_dmi_refresh || return 1
  fi
  memory_load || true

  printf '\n  %s%sMEMÓRIA RAM%s\n' "$C_DIM" "$C_BOLD" "$C_RESET"

  if (( ! RAM_DMI_AVAILABLE && ! RAM_EDAC_AVAILABLE )); then
    local total_kb=0 key val _
    while read -r key val _; do
      [[ $key == MemTotal: ]] && total_kb=$val
    done < /proc/meminfo
    ram_field 'Total' "$(fmt_bytes $(( total_kb * 1024 ))) (visível ao sistema)"
    [[ -n $RAM_TEMP ]] && ram_field 'Temperatura' "${RAM_TEMP} °C"
    printf '\n  %sSlots, tipo e frequência exigem root (dmidecode).%s\n' "$C_DIM" "$C_RESET"
    if command -v dmidecode >/dev/null 2>&1; then
      printf '  %sAtualize com: sysinfo ram --update%s\n\n' "$C_DIM" "$C_RESET"
    else
      printf '  %sInstale o dmidecode: sudo apt install dmidecode%s\n\n' "$C_DIM" "$C_RESET"
    fi
    return 0
  fi

  local src=''
  case $RAM_DMI_SOURCE in
    cache) src="dmidecode · cache $(fmt_age "$RAM_DMI_AGE")" ;;
    auto) src='dmidecode (lido agora)' ;;
    arquivo) src="dmidecode · ${SYSINFO_RAM_DMI_FILE}" ;;
    edac) src='EDAC (sem root)' ;;
    *) src='desconhecida' ;;
  esac
  ram_field 'Fonte' "$src"

  local total_line type_line form_line speeds ecc max_line temp_line
  total_line="$(fmt_bytes "$RAM_TOTAL_BYTES") instalados"
  if (( RAM_SLOTS_TOTAL > 0 )); then
    total_line+=" · ${RAM_SLOTS_USED}/${RAM_SLOTS_TOTAL} slots"
    if (( RAM_SLOTS_FREE > 0 )); then
      total_line+=" · ${RAM_SLOTS_FREE} livre"
      (( RAM_SLOTS_FREE > 1 )) && total_line+='s'
    else
      total_line+=' · todos preenchidos'
    fi
  fi
  ram_field 'Total' "$total_line"

  type_line=${RAM_TYPE:-desconhecido}
  speeds=$(memory_speed_label "$RAM_SPEED_MAX" "$RAM_SPEED_ADV_MAX")
  [[ -n $speeds ]] && type_line+=" · $speeds"
  ram_field 'Tipo' "$type_line"

  form_line=${RAM_FORM:-'-'}
  [[ -n $RAM_RANK ]] && form_line+=" · rank $RAM_RANK"
  ram_field 'Formato' "$form_line"

  ecc=$(memory_ecc_label)
  [[ -n $ecc ]] && ram_field 'ECC' "$ecc"
  (( RAM_MAX_BYTES > 0 )) && ram_field 'Máximo' "$(fmt_bytes "$RAM_MAX_BYTES") suportados"

  temp_line=$RAM_TEMP
  if [[ -n $temp_line ]]; then
    temp_line+=' °C'
    (( RAM_TEMP_COUNT > 1 )) && temp_line+=" (${RAM_TEMP_COUNT} sensores)"
    ram_field 'Temperatura' "$temp_line"
  fi

  printf '\n  %sSlots%s\n' "$C_BOLD" "$C_RESET"
  local i loc detail size form manuf part mt ms volt rank
  for i in "${!RAM_LOCATOR[@]}"; do
    loc=${RAM_LOCATOR[$i]:-DIMM$(( i + 1 ))}
    if (( ${RAM_MOD_USED[$i]:-0} )); then
      size=$(fmt_bytes "${RAM_SIZE[$i]:-0}")
      form=${RAM_MOD_FORM[$i]:-}
      manuf=${RAM_MOD_MANUF[$i]:-}
      part=${RAM_MOD_PART[$i]:-}
      mt=${RAM_MOD_TYPE[$i]:-}
      ms=${RAM_MOD_CONF[$i]:-${RAM_MOD_SPEED[$i]:-}}
      volt=${RAM_MOD_VOLT[$i]:-}
      rank=${RAM_MOD_RANK[$i]:-}

      detail=$size
      [[ -n $form ]] && detail="$form  $detail"
      [[ -n $manuf ]] && detail+="  $manuf"
      [[ -n $part ]] && detail+="  $part"
      [[ -n $mt ]] && detail+="  $mt"
      [[ -n $ms ]] && detail+="-$ms"
      [[ -n $volt ]] && detail+="  $volt"
      [[ -n $rank ]] && detail+="  rank $rank"

      printf '    %s%-16s%s %s\n' "$C_BOLD" "$loc" "$C_RESET" "$detail"
    else
      printf '    %s%-16s (vazio)%s\n' "$C_DIM" "$loc" "$C_RESET"
    fi
  done

  if [[ $RAM_DMI_SOURCE == cache ]]; then
    printf '\n  %sAtualize os detalhes: sysinfo ram --update%s\n' "$C_DIM" "$C_RESET"
  elif [[ $RAM_DMI_SOURCE == edac ]]; then
    printf '\n  %sSem root, frequência e fabricante não estão disponíveis.%s\n' "$C_DIM" "$C_RESET"
    printf '  %sAtualize com: sysinfo ram --update%s\n' "$C_DIM" "$C_RESET"
  fi
  printf '\n'
}
