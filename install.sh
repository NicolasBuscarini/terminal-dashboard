#!/usr/bin/env bash
# Instala o sysinfo: comando em ~/.local/bin e gancho no ~/.bashrc.
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script="$project_dir/bin/sysinfo"
bashrc="${HOME}/.bashrc"
bin_dir="${HOME}/.local/bin"
marker_begin='# >>> sysinfo >>>'
marker_end='# <<< sysinfo <<<'

if [[ ! -f $script ]]; then
  printf 'erro: script não encontrado em %s\n' "$script" >&2
  exit 1
fi
if [[ ! -f $bashrc ]]; then
  printf 'erro: %s não encontrado\n' "$bashrc" >&2
  exit 1
fi

chmod +x "$script"

# 1) Comando disponível como "sysinfo"
mkdir -p "$bin_dir"
ln -sfn "$script" "$bin_dir/sysinfo"

# 2) Garante ~/.local/bin no PATH dos shells interativos
if ! grep -qF 'HOME/.local/bin' "$bashrc"; then
  cat >> "$bashrc" <<'EOF'

# Adiciona ~/.local/bin ao PATH (necessário para o comando sysinfo)
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
EOF
  printf 'PATH atualizado em %s\n' "$bashrc"
fi

# 3) Gancho que mostra o painel ao abrir o terminal
if grep -qF "$marker_begin" "$bashrc"; then
  printf 'O painel já estava configurado em %s (nada duplicado).\n' "$bashrc"
else
  cp -- "$bashrc" "${bashrc}.bak-sysinfo-$(date +%Y%m%d-%H%M%S)-$$"
  cat >> "$bashrc" <<EOF

$marker_begin
# Painel de status ao abrir o terminal. Remova este bloco para desativar.
if [ -t 1 ] && [ -x "\$HOME/.local/bin/sysinfo" ]; then
  "\$HOME/.local/bin/sysinfo"
fi
$marker_end
EOF
  printf 'Gancho adicionado em %s (backup criado).\n' "$bashrc"
fi

cat <<EOF

Instalado!

  Projeto:  $project_dir
  Comando:  sysinfo
  Gancho:   $bashrc

Abra um novo terminal para ver o painel, ou rode agora:

  sysinfo

Para desativar sem desinstalar:  SYSINFO_DISABLE=1
Para remover tudo:               $project_dir/uninstall.sh
EOF
