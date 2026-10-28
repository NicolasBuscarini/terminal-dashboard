#!/usr/bin/env bash
# ui.sh — formatação de números, cores por nível, barras e linhas do painel.

# ------------------------------------------------------------------- helpers
fmt_bytes() {
  local b=$1 t i=0
  local -a units=(B KiB MiB GiB TiB)
  if (( b < 1024 )); then
    printf '%d B' "$b"
    return
  fi
  t=$(( b * 10 ))
  while (( i < 4 && t >= 10240 )); do
    t=$(( t / 1024 ))
    i=$(( i + 1 ))
  done
  printf '%d.%d %s' $(( t / 10 )) $(( t % 10 )) "${units[i]}"
}

# Par usado/total compacto: "3.0/7.1 GiB" quando as unidades coincidem.
fmt_pair() {
  local u t
  u=$(fmt_bytes "$1")
  t=$(fmt_bytes "$2")
  if [[ ${u##* } == ${t##* } ]]; then
    printf '%s/%s' "${u% *}" "$t"
  else
    printf '%s' "$u"
  fi
}

# Formato compacto para I/O de disco: 12.3M, 1.2G, 300K.
fmt_rate_short() {
  local b=$1
  if (( b >= 1073741824 )); then
    printf '%d.%dG' $(( b / 1073741824 )) $(( (b % 1073741824) * 10 / 1073741824 ))
  elif (( b >= 1048576 )); then
    printf '%d.%dM' $(( b / 1048576 )) $(( (b % 1048576) * 10 / 1048576 ))
  elif (( b >= 1024 )); then
    printf '%dK' $(( b / 1024 ))
  else
    printf '%dB' "$b"
  fi
}

# MB/s inteiro -> "812 MB/s" ou "1.8 GB/s" (usado no benchmark).
fmt_speed() {
  local mb=$1
  if (( mb >= 1000 )); then
    printf '%d.%d GB/s' $(( mb / 1000 )) $(( (mb % 1000) / 100 ))
  else
    printf '%d MB/s' "$mb"
  fi
}

# MHz -> "1.6 GHz" ou "800 MHz" (CPU/GPU).
fmt_freq_mhz() {
  local mhz=$1
  if (( mhz >= 1000 )); then
    printf '%d.%d GHz' $(( mhz / 1000 )) $(( (mhz % 1000) / 100 ))
  else
    printf '%d MHz' "$mhz"
  fi
}

# Cor por temperatura em °C (verde < 65, amarelo < 80, vermelho acima).
temp_color() {
  local t=$1
  if (( t >= 80 )); then
    printf '%s' "$C_RED"
  elif (( t >= 65 )); then
    printf '%s' "$C_YELLOW"
  else
    printf '%s' "$C_GREEN"
  fi
}

# Trunca texto simples (sem ANSI) para no máximo "max" colunas.
fit_text() {
  local s=$1 max=$2
  (( max < 1 )) && { printf ''; return 0; }
  if (( ${#s} > max )); then
    printf '%s%s' "${s:0:max-1}" "$ch_ellipsis"
  else
    printf '%s' "$s"
  fi
}

pct() {
  local used=$1 total=$2
  if (( total <= 0 )); then
    printf '0'
    return
  fi
  printf '%d' $(( used * 100 / total ))
}

level_color() {
  local p=$1
  if (( p >= 85 )); then
    printf '%s' "$C_RED"
  elif (( p >= 60 )); then
    printf '%s' "$C_YELLOW"
  else
    printf '%s' "$C_GREEN"
  fi
}

signal_color() {
  local p=$1
  if (( p >= 60 )); then
    printf '%s' "$C_GREEN"
  elif (( p >= 35 )); then
    printf '%s' "$C_YELLOW"
  else
    printf '%s' "$C_RED"
  fi
}

# Monta a barra em $BAR. Segundo argumento opcional: largura.
BAR=''
make_bar() {
  local p=$1 w=${2:-$bar_w} eighths full rem i
  (( p < 0 )) && p=0
  (( p > 100 )) && p=100
  if (( utf8 )); then
    eighths=$(( p * w * 8 / 100 ))
    full=$(( eighths / 8 ))
    rem=$(( eighths % 8 ))
    (( p > 0 && eighths == 0 )) && rem=1
    (( full > w )) && full=$w
    BAR=''
    for (( i = 0; i < full; i++ )); do BAR+="$ch_full"; done
    if (( rem > 0 && full < w )); then
      BAR+="${ch_partial[rem-1]}"
      (( full++ ))
    fi
    for (( i = full; i < w; i++ )); do BAR+="$ch_empty"; done
  else
    full=$(( p * w / 100 ))
    (( p > 0 && full == 0 )) && full=1
    (( full > w )) && full=$w
    printf -v _full '%*s' "$full" ''
    printf -v _empty '%*s' "$(( w - full ))" ''
    _full=${_full// /$ch_full}
    _empty=${_empty// /$ch_empty}
    BAR="$_full$_empty"
  fi
}

emit_row() {
  printf '  %s%-8s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2"
}

section() {
  local title=$1 rule_width rule
  rule_width=$(( cols - 5 - ${#title} ))
  (( rule_width < 0 )) && rule_width=0
  printf -v rule '%*s' "$rule_width" ''
  rule=${rule// /$sep_ch}
  printf '\n  %s%s%s %s%s%s %s%s%s\n' \
    "$C_ACCENT" "$ch_section" "$C_RESET" \
    "$C_BOLD" "$title" "$C_RESET" \
    "$C_DIM" "$rule" "$C_RESET"
}
