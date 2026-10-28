#!/usr/bin/env bash
# config.sh — versão, variáveis de ambiente, cores, caracteres e largura.
# Sourced por bin/sysinfo; não execute diretamente.

version=2.5.0
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

# ------------------------------------------------------------- painel/composição
# all | compact | lista de: header cpu mem swap disks net internet ports bench
#                        uptime battery temp services
panel_mode=${SYSINFO_PANEL:-all}
panel_hide=${SYSINFO_PANEL_HIDE:-}

panel_cpu=${SYSINFO_PANEL_CPU:-full}
case $panel_cpu in
  full|summary|off) ;;
  *) panel_cpu=full ;;
esac

panel_gpu=${SYSINFO_PANEL_GPU:-full}
case $panel_gpu in
  full|summary|off) ;;
  *) panel_gpu=full ;;
esac

panel_disks=${SYSINFO_PANEL_DISKS:-full}
[[ $panel_disks == full || $panel_disks == summary ]] || panel_disks=full

panel_ports=${SYSINFO_PANEL_PORTS:-table}
[[ $panel_ports == table || $panel_ports == summary ]] || panel_ports=table

panel_bench=${SYSINFO_PANEL_BENCH:-auto}
case $panel_bench in
  auto|live|cache|off) ;;
  *) panel_bench=auto ;;
esac

panel_ram=${SYSINFO_PANEL_RAM:-full}
case $panel_ram in
  full|summary|off) ;;
  *) panel_ram=full ;;
esac

panel_columns=${SYSINFO_PANEL_COLUMNS:-auto}
case $panel_columns in
  auto|1|2) ;;
  *) panel_columns=auto ;;
esac

panel_hint=${SYSINFO_PANEL_HINT:-1}
[[ $panel_hint == 0 ]] || panel_hint=1

panel_ports_max=${SYSINFO_PANEL_PORTS_MAX:-0}
[[ $panel_ports_max =~ ^[0-9]+$ ]] || panel_ports_max=0
(( panel_ports_max > 999 )) && panel_ports_max=999

bench_panel_size=${SYSINFO_BENCH_PANEL_SIZE:-32}
[[ $bench_panel_size =~ ^[0-9]+$ ]] || bench_panel_size=32
(( bench_panel_size < 8 )) && bench_panel_size=8
(( bench_panel_size > 4096 )) && bench_panel_size=4096

bench_ttl_days=${SYSINFO_BENCH_TTL_DAYS:-7}
[[ $bench_ttl_days =~ ^[0-9]+$ ]] || bench_ttl_days=7
(( bench_ttl_days > 3650 )) && bench_ttl_days=3650

bench_cache_dir=${SYSINFO_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/sysinfo}
bench_cache_file=$bench_cache_dir/bench

# Cache do dmidecode com os detalhes dos módulos de RAM. O painel nunca pede
# senha: usa o cache criado por "sysinfo ram --update".
memory_cache_dir=$bench_cache_dir
memory_cache_file=$memory_cache_dir/dmidecode-memory
memory_hwmon_dir=${SYSINFO_RAM_HWMON_DIR:-/sys/class/hwmon}
memory_edac_dir=${SYSINFO_RAM_EDAC_DIR:-/sys/devices/system/edac/mc}

# Sensores do processador e dispositivos de vídeo (sysfs).
cpu_hwmon_dir=${SYSINFO_CPU_HWMON_DIR:-/sys/class/hwmon}
cpu_thermal_dir=${SYSINFO_CPU_THERMAL_DIR:-/sys/class/thermal}
gpu_drm_dir=${SYSINFO_GPU_DRM_DIR:-/sys/class/drm}

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
