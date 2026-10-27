#!/usr/bin/env bash
# Remove o gancho do ~/.bashrc e o comando ~/.local/bin/sysinfo.
set -euo pipefail

bashrc="${HOME}/.bashrc"
bin_dir="${HOME}/.local/bin"
marker_begin='# >>> sysinfo >>>'
marker_end='# <<< sysinfo <<<'

if [[ -f $bashrc ]] && grep -qF "$marker_begin" "$bashrc"; then
  cp -- "$bashrc" "${bashrc}.bak-sysinfo-$(date +%Y%m%d-%H%M%S)-$$"
  tmp=$(mktemp)
  awk -v b="$marker_begin" -v e="$marker_end" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  ' "$bashrc" > "$tmp"
  cat "$tmp" > "$bashrc"
  rm -f "$tmp"
  printf 'Gancho removido de %s (backup criado).\n' "$bashrc"
else
  printf 'Nenhum gancho do sysinfo encontrado em %s.\n' "$bashrc"
fi

if [[ -e "$bin_dir/sysinfo" || -L "$bin_dir/sysinfo" ]]; then
  rm -f "$bin_dir/sysinfo"
  printf 'Comando removido de %s.\n' "$bin_dir/sysinfo"
fi

printf 'Pronto. Abra um novo terminal para confirmar.\n'
