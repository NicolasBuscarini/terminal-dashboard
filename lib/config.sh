#!/usr/bin/env bash
# config.sh — versão, variáveis de ambiente, cores, caracteres e largura.
# Sourced por bin/sysinfo; não execute diretamente.

version=2.2.0
probe_file=''
bench_file=''

# ---------------------------------------------------------------- configuração
delay=${SYSINFO_DELAY:-0.25}
[[ $delay =~ ^[0-9]+([.,][0-9]+)?$ ]] || delay=0.25
delay=${delay/,/.}

bar_w=${SYSINFO_BAR_WIDTH:-14}
[[ $bar_w =~ ^[0-9]+$ ]] || bar_w=14
(( bar_w < 6 )) && bar_w=6
(( bar_w > 40 )) && bar_w=40

net_check=${SYSINFO_NET_CHECK:-1}
if [[ $net_check != 0 ]] && { ! command -v ping >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; }; then
  net_check=0
fi
net_timeout=${SYSINFO_NET_TIMEOUT:-0.5}
[[ $net_timeout =~ ^[0-9]+([.,][0-9]+)?$ ]] || net_timeout=0.5
net_timeout=${net_timeout/,/.}
ping_host=${SYSINFO_PING_HOST:-1.1.1.1}

bench_size=${SYSINFO_BENCH_SIZE:-256}
[[ $bench_size =~ ^[0-9]+$ ]] || bench_size=256
(( bench_size < 8 )) && bench_size=8
(( bench_size > 4096 )) && bench_size=4096

disks_delay=${SYSINFO_DISKS_DELAY:-0.3}
[[ $disks_delay =~ ^[0-9]+([.,][0-9]+)?$ ]] || disks_delay=0.3
disks_delay=${disks_delay/,/.}

docker_check=${SYSINFO_DOCKER_CHECK:-1}

# --------------------------------------------------------------------- cores
C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_ACCENT=''
if [[ -t 1 && ${TERM:-} != dumb && -z ${NO_COLOR:-} && -z ${SYSINFO_NO_COLOR:-} ]]; then
  esc=$'\033'
  if [[ ${TERM:-} == *256color* ]]; then
    C_ACCENT="${esc}[38;5;81m"
    C_GREEN="${esc}[38;5;114m"
    C_YELLOW="${esc}[38;5;221m"
    C_RED="${esc}[38;5;203m"
    C_CYAN="${esc}[38;5;117m"
  else
    C_ACCENT="${esc}[36m"
    C_GREEN="${esc}[32m"
    C_YELLOW="${esc}[33m"
    C_RED="${esc}[31m"
    C_CYAN="${esc}[36m"
  fi
  C_RESET="${esc}[0m"
  C_BOLD="${esc}[1m"
  C_DIM="${esc}[2m"
fi

# ---------------------------------------------------------- caracteres/estilo
utf8=0
locale_name=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
if [[ $locale_name == *[Uu][Tt][Ff]-8* || $locale_name == *[Uu][Tt][Ff]8* ]]; then
  utf8=1
  ch_full='█' ch_empty='░' sep_ch='─' sep_strong='═' ch_section='▌'
  ch_ellipsis='…' arrow_down='↓' arrow_up='↑' dot='·'
  ch_partial=(▏ ▎ ▍ ▌ ▋ ▊ ▉)
  ch_branch=('├─' '└─')
else
  ch_full='#' ch_empty='-' sep_ch='-' sep_strong='=' ch_section='|'
  ch_ellipsis='~' arrow_down='v' arrow_up='^' dot='|'
  ch_partial=()
  ch_branch=('|-' '`-')
fi

# ------------------------------------------------------------------- largura
cols=${COLUMNS:-}
if [[ ! $cols =~ ^[0-9]+$ ]] || (( cols <= 0 )); then
  cols=$(tput cols 2>/dev/null) || cols=80
  [[ $cols =~ ^[0-9]+$ ]] || cols=80
fi
(( cols > 100 )) && cols=100
(( cols < 40 )) && cols=40

# Modos de layout para terminais estreitos.
narrow=0
(( cols < 70 )) && narrow=1
compact=0
(( cols < 70 )) && compact=1
net_compact=0
(( cols < 78 )) && net_compact=1
