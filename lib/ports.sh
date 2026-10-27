#!/usr/bin/env bash
# ports.sh — portas em escuta, processos, containers e linha do painel.

# ---------------------------------------------------------------- portas
# Portas publicadas por containers: porta do host -> "container · imagem".
declare -A docker_port=()
collect_docker_ports() {
  docker_port=()
  [[ $docker_check == 0 ]] && return 0
  command -v docker >/dev/null 2>&1 || return 0
  [[ -S /var/run/docker.sock || -S ${XDG_RUNTIME_DIR:-/run/user/$UID}/docker.sock ]] || return 0
  local name image ports proj spec hp proto val
  local re_pub='^(.+):([0-9]+)->([0-9]+)/(tcp|udp)$'
  local re_range='^(.+):([0-9]+)-([0-9]+)->([0-9]+)-([0-9]+)/(tcp|udp)$'
  local -a specs
  while IFS=$'\t' read -r name image ports proj; do
    [[ -z $name ]] && continue
    [[ -n $proj ]] && name="$proj/$name"
    val="$name · $image"
    IFS=',' read -r -a specs <<< "$ports"
    for spec in "${specs[@]}"; do
      spec=${spec# }
      if [[ $spec =~ $re_pub ]]; then
        hp=${BASH_REMATCH[2]}
        proto=${BASH_REMATCH[4]}
        docker_port[$hp]="$val"
      elif [[ $spec =~ $re_range ]]; then
        hp=${BASH_REMATCH[2]}
        proto=${BASH_REMATCH[6]}
        docker_port[$hp]="$val"
      fi
    done
  done < <(timeout 1 docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Label "com.docker.compose.project"}}' 2>/dev/null)
}

# Instantâneo das portas em escuta: porta, endereço, proto, processo, pid.
listen_snapshot() {
  local lf=4
  local -a args=(-H -tlnp)
  if [[ ${1:-} == all ]]; then
    args=(-H -tulpn)
    lf=5
  fi
  ss "${args[@]}" 2>/dev/null | awk -v lf="$lf" '
    {
      local_addr = $lf
      n = split(local_addr, a, ":")
      port = a[n]
      addr = substr(local_addr, 1, length(local_addr) - length(port) - 1)
      proto = (lf == 5) ? toupper($1) : "TCP"
      name = ""
      pid = ""
      if (match($0, /users:\(\("/)) {
        rest = substr($0, RSTART + RLENGTH)
        split(rest, q, "\"")
        name = q[1]
        if (match(rest, /pid=[0-9]+/))
          pid = substr(rest, RSTART + 4, RLENGTH - 4)
      }
      printf "%s\t%s\t%s\t%s\t%s\n", port, addr, proto, name, pid
    }' | LC_ALL=C sort -t $'\t' -k1,1n -k3,3 -k2,2
}

# Descrição provável de portas bem conhecidas (usada quando o processo é root
# e o ss sem root não revela o dono do socket).
declare -A known_port_desc=(
  [22]='SSH' [25]='SMTP' [53]='DNS' [80]='HTTP' [111]='rpcbind' [323]='NTP'
  [443]='HTTPS' [631]='impressão' [1883]='MQTT' [1900]='UPnP' [2049]='NFS'
  [3306]='MySQL/MariaDB' [5353]='mDNS' [5432]='PostgreSQL' [5672]='RabbitMQ'
  [6379]='Redis' [9090]='Prometheus' [11434]='Ollama' [27017]='MongoDB'
)

PROC_NAME='' PROC_CMD='' PROC_CWD='' PROC_USER=''
proc_info() {
  local pid=$1
  PROC_NAME='' PROC_CMD='' PROC_CWD='' PROC_USER=''
  [[ -r /proc/$pid/comm ]] && read -r PROC_NAME < "/proc/$pid/comm"
  if [[ -r /proc/$pid/cmdline ]]; then
    PROC_CMD=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    PROC_CMD=${PROC_CMD% }
  fi
  PROC_CWD=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
  PROC_USER=$(ps -o user= -p "$pid" 2>/dev/null || true)
  PROC_USER=${PROC_USER// /}
}

# Classifica o processo pelo nome/comando e pelo diretório de trabalho.
port_kind() {
  local name=${1,,} cmd=${2,,} cwd=$3
  local hay="$name $cmd"
  if [[ $hay =~ (postgres|mysqld|mariadbd|redis-server|mongod|influxd|clickhouse|memcached) ]]; then
    printf 'banco'
  elif [[ -n $(proc_flavor "$cmd") ]]; then
    printf 'dev'
  elif [[ $name =~ ^(node|npm|npx|pnpm|yarn|bun|deno|vite|nuxt|nodemon|opencode|code|code-server|php|ruby|rails|puma|dotnet|java|gradle|mvn)$ ]] &&
       [[ -z $cwd || $cwd == "$HOME"* ]]; then
    printf 'dev'
  else
    printf 'usuário'
  fi
}

# "vite", "next", "django"... a partir da linha de comando.
proc_flavor() {
  local cmd=${1,,}
  case $cmd in
    *vite*) printf 'vite' ;;
    *next*) printf 'next' ;;
    *nuxt*) printf 'nuxt' ;;
    *webpack*) printf 'webpack' ;;
    *nodemon*) printf 'nodemon' ;;
    *uvicorn*) printf 'uvicorn' ;;
    *gunicorn*) printf 'gunicorn' ;;
    *flask*) printf 'flask' ;;
    *manage.py*) printf 'django' ;;
    *http.server*) printf 'http.server' ;;
    *tsx*) printf 'tsx' ;;
    *jupyter*) printf 'jupyter' ;;
    *opencode*) printf 'opencode' ;;
    *) printf '' ;;
  esac
}

short_path() {
  local p=$1 max=${2:-28}
  [[ -z $p ]] && return 0
  if [[ $p == "$HOME" ]]; then
    p='~'
  elif [[ $p == "$HOME"/* ]]; then
    p="~${p#"$HOME"}"
  fi
  if (( ${#p} > max )); then
    p="…${p:${#p}-max}"
  fi
  printf '%s' "$p"
}

kind_color() {
  case $1 in
    docker) printf '%s' "$C_CYAN" ;;
    dev) printf '%s' "$C_GREEN" ;;
    banco) printf '%s' "$C_YELLOW" ;;
    sistema) printf '%s' "$C_DIM" ;;
    *) printf '%s' "$C_BOLD" ;;
  esac
}

# Junta até 4 portas de um array: "8000·9443·+2".
join_ports() {
  local -n _jp=$1
  local out='' i
  for i in "${!_jp[@]}"; do
    if (( i >= 4 )); then
      out+="·+$(( ${#_jp[@]} - 4 ))"
      break
    fi
    out+="${out:+·}${_jp[$i]}"
  done
  printf '%s' "$out"
}

show_ports() {
  local all=0 verbose=0 arg
  for arg in "$@"; do
    case $arg in
      -a|--all) all=1 ;;
      -v|--verbose) verbose=1 ;;
      '') ;;
      *)
        printf 'sysinfo ports: opção desconhecida: %s\n' "$arg" >&2
        exit 2
        ;;
    esac
  done

  if ! command -v ss >/dev/null 2>&1; then
    printf 'sysinfo: comando "ss" não encontrado (instale o pacote iproute2).\n' >&2
    exit 1
  fi

  collect_docker_ports

  local title='PORTAS EM ESCUTA (TCP)'
  (( all )) && title='PORTAS EM ESCUTA (TCP + UDP)'

  printf '\n  %s%s%s\n\n' "$C_BOLD" "$title" "$C_RESET"
  printf '  %s%-5s %-5s %-18s %-7s %s%s\n' "$C_DIM" 'PORTA' 'PROTO' 'ENDEREÇO' 'TIPO' 'PROCESSO' "$C_RESET"

  local snap='tcp'
  (( all )) && snap='all'
  local detail_max=$(( cols - 41 ))
  (( detail_max < 24 )) && detail_max=24

  local total=0 n_docker=0 n_dev=0 n_banco=0 n_sys=0 n_user=0
  local port addr proto name pid kind detail col flavor label proj avail base
  local -A seen=()
  while IFS=$'\t' read -r port addr proto name pid; do
    [[ -z $port ]] && continue
    # O mesmo socket aparece em IPv4 e IPv6: conta uma vez só.
    [[ -n ${seen[$port/$proto]:-} ]] && continue
    seen[$port/$proto]=1
    total=$(( total + 1 ))

    if [[ -n ${docker_port[$port]:-} ]]; then
      kind='docker'
      detail=${docker_port[$port]}
      n_docker=$(( n_docker + 1 ))
    elif [[ -n $pid ]]; then
      proc_info "$pid"
      kind=$(port_kind "$PROC_NAME" "$PROC_CMD" "$PROC_CWD")
      flavor=$(proc_flavor "$PROC_CMD")
      label=$PROC_NAME
      [[ -n $flavor && $flavor != "$PROC_NAME" ]] && label="$PROC_NAME ($flavor)"
      if [[ -z $PROC_CWD ]]; then
        proj=''
      elif [[ $PROC_CWD == "$HOME" ]]; then
        proj='~'
      else
        proj=${PROC_CWD##*/}
      fi
      base=" (pid $pid)"
      avail=$(( detail_max - ${#label} - ${#base} - 3 ))
      (( avail < 8 )) && avail=8
      (( ${#proj} > avail )) && proj="…${proj:${#proj}-avail+1}"
      detail="$label"
      [[ -n $proj ]] && detail+=" · $proj"
      detail+="$base"
      case $kind in
        dev) n_dev=$(( n_dev + 1 )) ;;
        banco) n_banco=$(( n_banco + 1 )) ;;
        *) n_user=$(( n_user + 1 )) ;;
      esac
    else
      kind='sistema'
      detail=${known_port_desc[$port]:-root}
      n_sys=$(( n_sys + 1 ))
    fi

    col=$(kind_color "$kind")
    (( ${#addr} > 18 )) && addr="${addr:0:17}${ch_ellipsis}"
    (( ${#detail} > detail_max )) && detail="${detail:0:detail_max-1}${ch_ellipsis}"
    printf '  %-5s %-5s %-18s %s%-7s%s %s\n' \
      "$port" "$proto" "$addr" "$col" "$kind" "$C_RESET" "$detail"

    if (( verbose )) && [[ -n $pid ]]; then
      printf '  %s         ↳ %s%s\n' "$C_DIM" "$(short_path "$PROC_CWD" 60)" "$C_RESET"
      printf '  %s           %s%s\n' "$C_DIM" "${PROC_CMD:0:cols-14}" "$C_RESET"
    fi
  done < <(listen_snapshot "$snap")

  if (( total == 0 )); then
    printf '  %snenhuma porta em escuta%s\n' "$C_DIM" "$C_RESET"
  else
    printf '\n  %s%d porta(s)%s' "$C_BOLD" "$total" "$C_RESET"
    (( n_docker > 0 )) && printf ' %s· %d docker%s' "$C_DIM" "$n_docker" "$C_RESET"
    (( n_dev > 0 )) && printf ' %s· %d dev%s' "$C_DIM" "$n_dev" "$C_RESET"
    (( n_banco > 0 )) && printf ' %s· %d banco%s' "$C_DIM" "$n_banco" "$C_RESET"
    (( n_user > 0 )) && printf ' %s· %d usuário%s' "$C_DIM" "$n_user" "$C_RESET"
    (( n_sys > 0 )) && printf ' %s· %d sistema%s' "$C_DIM" "$n_sys" "$C_RESET"
    printf '\n'
  fi
  if (( n_sys > 0 )); then
    printf '  %ssistema = socket de root; sem root o ss não revela o processo.%s\n' "$C_DIM" "$C_RESET"
    printf '  %sPara ver todos os donos: sudo ss -tulpn%s\n' "$C_DIM" "$C_RESET"
  fi
  (( verbose )) || printf '  %sUse -v para ver diretório e linha de comando dos processos.%s\n' "$C_DIM" "$C_RESET"
  printf '\n'
}

# Linha PORTAS do painel: agrupa por container, processos seus e sistema.
render_ports_row() {
  if command -v ss >/dev/null 2>&1; then
    collect_docker_ports

    declare -A seen_port=()
    all_ports=() dock_ports=() dev_ports=() dev_names=() sys_ports=()
    port_count=0
    while IFS=$'\t' read -r port _addr proto name pid; do
      [[ -z $port ]] && continue
      [[ -n ${seen_port[$port]:-} ]] && continue
      seen_port[$port]=1
      all_ports+=("$port")
      port_count=$(( port_count + 1 ))
      if [[ -n ${docker_port[$port]:-} ]]; then
        dock_ports+=("$port")
      elif [[ -n $pid ]]; then
        dev_ports+=("$port")
        dev_names+=("$name")
      else
        sys_ports+=("$port")
      fi
    done < <(listen_snapshot)

    # Lista simples, usada quando a versão detalhada não couber na largura.
    max_show=$(( (cols - 24) / 5 ))
    (( max_show < 2 )) && max_show=2
    (( max_show > 5 )) && max_show=5
    port_show=''
    shown=0
    for port in "${all_ports[@]}"; do
      (( shown >= max_show )) && break
      port_show="${port_show:+$port_show }$port"
      shown=$(( shown + 1 ))
    done
    port_more=''
    (( port_count > shown )) && port_more=" +$(( port_count - shown ))"
    port_compact="${C_BOLD}${port_show}${C_RESET}${C_DIM}${port_more} ${dot} ${port_count} em escuta${C_RESET}"

    if (( port_count == 0 )); then
      emit_row 'PORTAS' "${C_DIM}nenhuma em escuta${C_RESET}"
    elif (( compact )); then
      emit_row 'PORTAS' "$port_compact"
    else
      segments=()
      plain_segments=()

      if (( ${#dock_ports[@]} > 0 )); then
        dock_label='docker'
        first_dock=${docker_port[${dock_ports[0]}]%% · *}
        same_dock=1
        for port in "${dock_ports[@]}"; do
          [[ ${docker_port[$port]%% · *} == "$first_dock" ]] || same_dock=0
        done
        (( same_dock )) && dock_label=$first_dock
        dock_str=$(join_ports dock_ports)
        segments+=("${C_BOLD}${dock_str}${C_RESET} ${C_DIM}${dock_label}${C_RESET}")
        plain_segments+=("${dock_str} ${dock_label}")
      fi

      if (( ${#dev_ports[@]} > 0 )); then
        dev_seg=''
        dev_plain=''
        shown=0
        for i in "${!dev_ports[@]}"; do
          if (( shown >= 3 )); then
            dev_seg+="  +$(( ${#dev_ports[@]} - shown ))"
            dev_plain+="  +$(( ${#dev_ports[@]} - shown ))"
            break
          fi
          dev_seg+="${dev_seg:+  }${C_BOLD}${dev_ports[$i]}${C_RESET} ${C_DIM}${dev_names[$i]}${C_RESET}"
          dev_plain+="${dev_plain:+  }${dev_ports[$i]} ${dev_names[$i]}"
          shown=$(( shown + 1 ))
        done
        segments+=("$dev_seg")
        plain_segments+=("$dev_plain")
      fi

      if (( ${#sys_ports[@]} > 0 )); then
        sys_str=$(join_ports sys_ports)
        segments+=("${C_BOLD}${sys_str}${C_RESET} ${C_DIM}sistema${C_RESET}")
        plain_segments+=("${sys_str} sistema")
      fi

      port_line=''
      port_plain=''
      for i in "${!segments[@]}"; do
        port_line+="${port_line:+  }${segments[$i]}"
        port_plain+="${port_plain:+  }${plain_segments[$i]}"
      done
      if (( ${#port_plain} + 11 > cols )); then
        emit_row 'PORTAS' "$port_compact"
      else
        emit_row 'PORTAS' "$port_line"
      fi
    fi
  fi
}
