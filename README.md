# terminal-dashboard

Repositório: <https://github.com/NicolasBuscarini/terminal-dashboard>

Painel de status do sistema exibido automaticamente ao abrir o terminal: CPU,
memória, swap, **todos os discos** (SSD/HDD, partições, uso, I/O ao vivo e
temperatura), rede, Wi-Fi, internet, **portas em escuta**, **benchmark em cache**,
uptime, bateria e temperatura.

Por padrão o painel vem **completo** — todas as seções disponíveis. A composição
é configurável por variáveis de ambiente: dá para esconder o que não interessa,
trocar detalhes por resumos ou montar um painel só com o que você usa.

Feito em **bash puro** (sem `neofetch`, `fastfetch` ou plugins), lendo direto de
`/proc`, `/sys` e de ferramentas que já vêm no Ubuntu (`lsblk`, `df`, `ss`,
`iw`, `ping`, `systemctl`). Não atrasa o terminal de forma perceptível (~0,3 s,
sendo 0,25 s apenas a janela de amostragem de CPU/rede/disco). Na primeira
execução o benchmark rápido pode acrescentar alguns décimos; depois ele vem do
cache.

## Prévia

```
  nicolas-buscarini@nicolas-buscarini-Aspire-A315-53
  Ubuntu 26.04.1 LTS  ·  Linux 7.0.0-38-generic
  ══════════════════════════════════════════════════════════════════════════════

  ▌ PROCESSAMENTO ──────────────────────────────────────────────────────────────
  CPU      █▍░░░░░░░░░░░░   10%   8 núcleos · carga 0.97 0.95 0.92
  MEM      ███████▏░░░░░░   51%   3.7 GiB / 7.1 GiB
  SWAP     ░░░░░░░░░░░░░░    0%   332.0 KiB / 3.9 GiB

  ▌ ARMAZENAMENTO ──────────────────────────────────────────────────────────────
  sda        HDD SATA   931.5 GiB  WDC WD10SPZX-21Z
    ├─ sda1         vfat     100.0 MiB  sem montagem
    ├─ sda2         -         16.0 MiB  sem montagem
    ├─ sda3         ntfs     930.3 GiB  sem montagem
    └─ sda4         ntfs       1.0 GiB  sem montagem
    I/O agora  ocioso

  nvme0n1    SSD NVMe   465.7 GiB  WDC WDS500G2B0C-00PXH0  · 36 °C
    ├─ nvme0n1p1    vfat       1.0 GiB  ▏░░░░░░░   1%  /boot/efi
    └─ nvme0n1p2    ext4     464.7 GiB  ▍░░░░░░░   5%  /
    I/O agora  ocioso

  ▌ REDE ───────────────────────────────────────────────────────────────────────
  wlp2s0  BUSCA_5G · 5 GHz · sinal 100% · 433.3 Mbit/s   ↓ 353 B/s  ↑ 0 B/s
  STATUS   192.168.31.25 · Internet online (17 ms)

  ▌ PORTAS EM ESCUTA ───────────────────────────────────────────────────────────
  PORTA PROTO ENDEREÇO          TIPO    PROCESSO
  53    TCP   127.0.0.53%lo      sistema DNS
  631   TCP   127.0.0.1          sistema impressão
  8000  TCP   0.0.0.0            docker  portainer · portainer/portainer-ce:lts
  9443  TCP   0.0.0.0            docker  portainer · portainer/portainer-ce:lts
  40613 TCP   127.0.0.1          dev     code · terminal-dashboard (pid 17148)
  49374 TCP   127.0.0.1          dev     opencode · ~ (pid 5310)

  6 porta(s) · 2 docker · 2 dev · 2 sistema
  sistema = socket de root; sem root o ss não revela o processo.
  Para ver todos os donos: sudo ss -tulpn

  ▌ DESEMPENHO ─────────────────────────────────────────────────────────────────
  BENCH    E 774 MB/s · L 1.0 GB/s
           nvme0n1 SSD NVMe · agora

  ▌ SISTEMA ────────────────────────────────────────────────────────────────────
  UPTIME   no ar há 1h 3m · 309 processos · 1 usuário
  BATERIA  100% · cheia
  TEMP     60 °C

  sysinfo disks · ports · bench · --help
```

As barras ficam verdes até 60%, amarelas até 85% e vermelhas acima disso. As
barras usam sub-blocos (`▏▎▍▌▋▊▉`) para uma leitura mais suave. O sinal do Wi-Fi
usa a mesma lógica de cor (verde ≥ 60%, amarelo ≥ 35%, vermelho abaixo).

Linhas que não fazem sentido no seu hardware (bateria, temperatura, Wi-Fi) ou
cuja ferramenta não está instalada simplesmente não aparecem. O layout é
responsivo: em terminais estreitos as seções compactam, a tabela de portas vira
resumo e os discos perdem as partições; em terminais largos (≥ 96 colunas)
PROCESSAMENTO e SISTEMA dividem a mesma faixa.

## Composição do painel

A composição é definida por `SYSINFO_PANEL`. O padrão `all` liga todos os
tokens disponíveis:

| Token | Seção/linha |
| --- | --- |
| `header` | cabeçalho com usuário, host, distro e kernel |
| `cpu` | uso de CPU, núcleos e carga média |
| `mem` | memória RAM |
| `swap` | swap |
| `disks` | discos e partições (detalhado por padrão) |
| `net` | interface ativa, Wi-Fi/ethernet e taxas |
| `internet` | IP local e teste de conectividade |
| `ports` | portas em escuta (tabela por padrão) |
| `bench` | benchmark sequencial em cache |
| `uptime` | tempo no ar, processos e usuários |
| `battery` | bateria (se houver) |
| `temp` | temperatura (se disponível) |
| `services` | serviços systemd com falha (só aparece se houver) |

Presets prontos: `all`, `compact` (sem bench e serviços), `minimal` (alias) e
`none` (painel vazio). Também há aliases: `memory` = `mem`, `network`/`wifi` =
`net,internet`, `load` = `cpu`.

```bash
# só o essencial, em uma linha por seção
SYSINFO_PANEL=compact sysinfo

# composição sob medida
SYSINFO_PANEL=header,cpu,mem,disks,ports sysinfo

# painel completo menos o benchmark e os serviços
SYSINFO_PANEL_HIDE=bench,services sysinfo
```

Para tornar a escolha permanente, exporte antes do bloco `# >>> sysinfo >>>` no
`~/.bashrc`:

```bash
export SYSINFO_PANEL=compact
```

### Layout e detalhes

| Variável | Padrão | Efeito |
| --- | --- | --- |
| `SYSINFO_PANEL_COLUMNS=auto` | `auto` | `auto`, `1` ou `2`; em `auto`, duas colunas a partir de 96 colunas |
| `SYSINFO_PANEL_DISKS=full` | `full` | `full` mostra partições e uso; `summary` mostra uma linha por disco |
| `SYSINFO_PANEL_PORTS=table` | `table` | `table` lista as portas; `summary` mostra só a linha-resumo |
| `SYSINFO_PANEL_PORTS_MAX=0` | `0` | máximo de portas listadas no painel (`0` = todas) |
| `SYSINFO_PANEL_BENCH=auto` | `auto` | `auto` usa o cache e refaz quando expira; `live` mede sempre; `cache` nunca mede; `off` esconde |
| `SYSINFO_BENCH_PANEL_SIZE=32` | `32` | tamanho do bench rápido do painel, em MiB |
| `SYSINFO_BENCH_TTL_DAYS=7` | `7` | validade do cache do bench, em dias |
| `SYSINFO_PANEL_HINT=0` | `1` | esconde o rodapé de dicas |

O painel nunca espera um benchmark lento ao abrir o terminal: ele usa o cache em
`${XDG_CACHE_HOME:-$HOME/.cache}/sysinfo/bench` e só mede de novo quando o cache
não existe ou expirou. `sysinfo bench` também grava nesse cache.


## Discos

Por padrão o painel mostra cada disco físico com nome, tipo (**SSD**/**HDD** +
barramento), tamanho, modelo, temperatura, todas as partições (sistema de
arquivos, tamanho, uso e ponto de montagem) e I/O de leitura/escrita em tempo
real. Em terminais com menos de 70 colunas, ou com
`SYSINFO_PANEL_DISKS=summary`, ele cai para uma linha por disco.

Para ver os detalhes sob demanda:

```bash
sysinfo disks
```

```
  DISCOS E PARTIÇÕES

  sda        HDD SATA   931.5 GiB  WDC WD10SPZX-21Z
    ├─ sda1         vfat     100.0 MiB  sem montagem
    ├─ sda2         -         16.0 MiB  sem montagem
    ├─ sda3         ntfs     930.3 GiB  sem montagem
    └─ sda4         ntfs       1.0 GiB  sem montagem
    I/O agora  ocioso

  nvme0n1    SSD NVMe   465.7 GiB  WDC WDS500G2B0C-00PXH0  · 35 °C
    ├─ nvme0n1p1    vfat       1.0 GiB  ▏░░░░░░░   1%  /boot/efi
    └─ nvme0n1p2    ext4     464.7 GiB  ▍░░░░░░░   5%  /
    I/O agora  ↓ 0 B/s  ↑ 1.5 GiB/s
```

Como o tipo é detectado:

- `SSD NVMe` / `HDD SATA` etc. vêm de `lsblk` (`TRAN`) + `/sys/block/*/queue/rotational`;
- a temperatura é lida de `/sys/class/hwmon` (funciona no NVMe; no HDD depende do
  driver `drivetemp`);
- se `smartctl` estiver instalado, `sysinfo disks` também mostra a saúde SMART e
  usa a temperatura dele como alternativa (precisa de root para o HDD).

O HDD de 1 TB deste notebook está **sem montagem** no momento, por isso aparece
como `sem montagem` — nada é lido dele, apenas o I/O do dispositivo.

## Benchmark de velocidade

Mede escrita e leitura sequencial no sistema de arquivos de um diretório:

```bash
sysinfo bench                 # testa a home
sysinfo bench /mnt/dados      # testa outro disco montado
SYSINFO_BENCH_SIZE=1024 sysinfo bench
```

```
  BENCHMARK SEQUENCIAL
  /home/nicolas-buscarini · nvme0n1 · SSD NVMe

  Testando 64 MiB...

  Escrita  717 MB/s   (64 MiB em 0.09 s)
  Leitura  884 MB/s   (64 MiB em 0.08 s)

  Arquivo temporário removido.
```

O teste grava um arquivo temporário de `SYSINFO_BENCH_SIZE` MiB (padrão 256),
mede e apaga. A leitura usa `O_DIRECT` para não vir do cache; se o sistema de
arquivos não suportar, cai para leitura normal e marca com `*`.

No painel, o benchmark usa um cache compartilhado com o comando acima. Com
`SYSINFO_PANEL_BENCH=auto` (padrão), ele só mede quando o cache não existe ou
passou de `SYSINFO_BENCH_TTL_DAYS` dias; a medição do painel é rápida
(`SYSINFO_BENCH_PANEL_SIZE`, padrão 32 MiB). Use `live` para medir a cada
abertura, `cache` para nunca medir no painel ou `off` para esconder a seção.

## Portas em escuta

O painel mostra as portas **TCP** em escuta em uma tabela, sem repetir
IPv4/IPv6, agrupadas por origem: containers Docker, processos seus (com o nome
do programa) e serviços do sistema. Em terminais com menos de 50 colunas, ou com
`SYSINFO_PANEL_PORTS=summary`, ele troca a tabela por uma linha-resumo.

```bash
sysinfo ports          # TCP
sysinfo ports --all    # TCP + UDP
sysinfo ports -v       # + diretório e linha de comando de cada processo
```

```
  PORTAS EM ESCUTA (TCP)

  PORTA PROTO ENDEREÇO          TIPO    PROCESSO
  53    TCP   127.0.0.53%lo      sistema DNS
  631   TCP   127.0.0.1          sistema impressão
  8000  TCP   0.0.0.0            docker  portainer · portainer/portainer-ce:lts
  9443  TCP   0.0.0.0            docker  portainer · portainer/portainer-ce:lts
  40613 TCP   127.0.0.1          dev     code · terminal-dashboard (pid 17148)
  49374 TCP   127.0.0.1          dev     opencode · ~ (pid 5310)

  6 porta(s) · 2 docker · 2 dev · 2 sistema
  sistema = socket de root; sem root o ss não revela o processo.
  Para ver todos os donos: sudo ss -tulpn
  Use -v para ver diretório e linha de comando dos processos.
```

A coluna **TIPO** classifica cada porta:

| Tipo | Significado |
| --- | --- |
| `docker` | porta publicada por um container (`docker ps`), com nome e imagem |
| `dev` | servidor/ferramenta de desenvolvimento seu (Vite, Next, Uvicorn, `python -m http.server`, VS Code, opencode…) |
| `banco` | PostgreSQL, MySQL/MariaDB, Redis, MongoDB etc. |
| `usuário` | outro processo seu que não parece ser de desenvolvimento |
| `sistema` | socket de root; o `ss` sem root não mostra o dono, então o tipo vem de uma tabela de portas conhecidas (DNS, CUPS, SSH, NTP…) |

Com `-v` aparece o diretório de trabalho e a linha de comando:

```
  40613 TCP   127.0.0.1          dev     code · terminal-dashboard (pid 17148)
           ↳ ~/Code/terminal-dashboard
             /usr/share/code/code --type=utility --utility-sub-type=node.mojom.
```

O nome do processo só aparece para sockets do seu usuário — é uma limitação do
`ss` sem root. Para ver todos: `sudo ss -tulpn`.

## Instalação

```bash
cd ~/Code/terminal-dashboard
./install.sh
```

O instalador:

1. deixa o script executável;
2. cria o comando `sysinfo` em `~/.local/bin/sysinfo` (symlink);
3. garante `~/.local/bin` no `PATH` do `~/.bashrc`;
4. adiciona um bloco identificado ao final do `~/.bashrc`, com backup
   `~/.bashrc.bak-sysinfo-<data>-<pid>` antes de qualquer alteração.

Depois disso, abra um terminal novo. Para testar na hora:

```bash
sysinfo
```

## Comandos

| Comando | Efeito |
| --- | --- |
| `sysinfo` | painel (usado no `.bashrc`) |
| `sysinfo disks` | discos, partições, uso, I/O e temperatura |
| `sysinfo ports [--all] [-v]` | portas em escuta, processo/container e detalhes |
| `sysinfo bench [dir]` | benchmark sequencial no diretório |
| `sysinfo --help` / `--version` | ajuda / versão |

## Configuração

Tudo por variáveis de ambiente. Para tornar uma opção permanente, coloque o
`export` no `~/.bashrc` **antes** do bloco `# >>> sysinfo >>>`:

| Variável | Padrão | Efeito |
| --- | --- | --- |
| `SYSINFO_DISABLE=1` | — | não mostra o painel |
| `SYSINFO_DELAY=0.25` | `0.25` | segundos de amostragem de CPU/rede/disco |
| `SYSINFO_BAR_WIDTH=14` | `14` | largura das barras de CPU/MEM/SWAP (6 a 40) |
| `SYSINFO_NO_COLOR=1` | — | sem cores (`NO_COLOR` também funciona) |
| `SYSINFO_NET_CHECK=0` | `1` | desativa o teste de internet |
| `SYSINFO_NET_TIMEOUT=0.5` | `0.5` | tempo máximo do teste de internet (s) |
| `SYSINFO_PING_HOST=1.1.1.1` | `1.1.1.1` | host usado no teste de internet |
| `SYSINFO_BENCH_SIZE=256` | `256` | tamanho do benchmark do CLI, em MiB (8 a 4096) |
| `SYSINFO_DISKS_DELAY=0.3` | `0.3` | janela de amostragem de I/O em `sysinfo disks` |
| `SYSINFO_DOCKER_CHECK=0` | `1` | não consulta o Docker ao listar portas |
| `SYSINFO_PANEL=all` | `all` | composição: `all`, `compact`, `none` ou lista de tokens |
| `SYSINFO_PANEL_HIDE=...` | — | tokens removidos da composição |
| `SYSINFO_PANEL_COLUMNS=auto` | `auto` | `auto`, `1` ou `2` colunas |
| `SYSINFO_PANEL_DISKS=full` | `full` | `full` (partições) ou `summary` |
| `SYSINFO_PANEL_PORTS=table` | `table` | `table` (lista) ou `summary` |
| `SYSINFO_PANEL_PORTS_MAX=0` | `0` | máximo de portas listadas (`0` = todas) |
| `SYSINFO_PANEL_BENCH=auto` | `auto` | `auto`, `live`, `cache` ou `off` |
| `SYSINFO_BENCH_PANEL_SIZE=32` | `32` | tamanho do bench rápido do painel, em MiB |
| `SYSINFO_BENCH_TTL_DAYS=7` | `7` | validade do cache do bench, em dias |
| `SYSINFO_PANEL_HINT=0` | `1` | esconde o rodapé de dicas |
| `SYSINFO_CACHE_DIR=...` | `~/.cache/sysinfo` | diretório do cache do bench |

Exemplos:

```bash
# barras mais largas e amostragem mais curta
export SYSINFO_BAR_WIDTH=20
export SYSINFO_DELAY=0.1

# painel enxuto, sem benchmark e sem serviços
export SYSINFO_PANEL=compact
export SYSINFO_PANEL_HIDE=bench,services

# não enviar ping a cada terminal aberto
export SYSINFO_NET_CHECK=0

# desativar temporariamente (sem mexer no .bashrc)
SYSINFO_DISABLE=1 bash
```

O teste de internet envia **um** pacote ICMP para `1.1.1.1` a cada terminal
aberto, em paralelo com a amostragem de CPU/rede/disco. Se você não quiser esse
tráfego, use `SYSINFO_NET_CHECK=0`.

Observação: o painel aparece em todo shell interativo do bash, inclusive em
subshells (`bash` dentro de `bash`). Se quiser apenas no primeiro shell do
terminal, troque a chamada no `~/.bashrc` por:

```bash
if [ -t 1 ] && [ "${SHLVL:-1}" -le 1 ] && [ -x "$HOME/.local/bin/sysinfo" ]; then
  "$HOME/.local/bin/sysinfo"
fi
```

## Desinstalação

```bash
~/Code/terminal-dashboard/uninstall.sh
```

Remove o bloco do `~/.bashrc` (com backup), o symlink do comando e mantém o
projeto no disco. Para apagar o projeto também:

```bash
rm -rf ~/Code/terminal-dashboard
```

## Estrutura

```
terminal-dashboard/
├── bin/sysinfo        # entrypoint: argumentos, ajuda e despacho
├── lib/
│   ├── config.sh      # variáveis, cores, caracteres, largura e painel
│   ├── ui.sh          # formatação, barras e linhas
│   ├── system.sh      # seção SISTEMA (uptime, bateria, temperatura, serviços)
│   ├── disks.sh       # discos, filesystems e "sysinfo disks"
│   ├── network.sh     # interface, Wi-Fi, taxas e internet
│   ├── ports.sh       # portas, processos, containers e TIPO
│   ├── bench.sh       # benchmark sequencial e cache
│   └── panel.sh       # composição dinâmica, CPU/RAM/SWAP e layout
├── install.sh         # instala comando + gancho no .bashrc
├── uninstall.sh       # remove comando + gancho
└── README.md
```

O entrypoint resolve o próprio symlink (`readlink -f`) antes de carregar `lib/`,
então `~/.local/bin/sysinfo` continua funcionando normalmente. Cada arquivo tem
uma responsabilidade única e pode ser testado isoladamente com `bash -n`.

## Requisitos

- Linux (usa `/proc` e `/sys`)
- bash 4+ e coreutils (`awk`, `dd`, `df`, `nproc`, `tput`, `sort`)
- `util-linux` (`lsblk`) para detectar discos e partições
- Terminal com suporte a UTF-8 para as barras; sem UTF-8 ele cai
  automaticamente para `#`, `-` e `|`

Ferramentas opcionais (cada linha correspondente é omitida se faltar):

| Ferramenta | Pacote | Usada para |
| --- | --- | --- |
| `ss` | `iproute2` | portas em escuta |
| `docker` | `docker-ce`/`docker.io` | nome do container e imagem nas portas publicadas |
| `iw` | `iw` | SSID, banda, sinal e taxa do Wi-Fi |
| `ping` | `iputils-ping` | teste de internet |
| `systemctl` | `systemd` | serviços com falha (só aparece se houver) |
| `smartctl` | `smartmontools` | saúde SMART e temperatura de HDD em `sysinfo disks` |
