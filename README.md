# terminal-dashboard

Repositório: <https://github.com/NicolasBuscarini/terminal-dashboard>

Painel de status do sistema exibido automaticamente ao abrir o terminal: CPU,
memória, swap, **todos os discos** (SSD/HDD, uso, I/O ao vivo e temperatura),
rede, Wi-Fi, internet, portas em escuta, uptime, bateria e temperatura.

Feito em **bash puro** (sem `neofetch`, `fastfetch` ou plugins), lendo direto de
`/proc`, `/sys` e de ferramentas que já vêm no Ubuntu (`lsblk`, `df`, `ss`,
`iw`, `ping`, `systemctl`). Não atrasa o terminal de forma perceptível (~0,3 s,
sendo 0,25 s apenas a janela de amostragem de CPU/rede/disco).

## Prévia

```
  nicolas-buscarini@nicolas-buscarini-Aspire-A315-53
  Ubuntu 26.04.1 LTS  ·  Linux 7.0.0-38-generic
  ══════════════════════════════════════════════════════════════════════════════

  ▌ PROCESSAMENTO ──────────────────────────────────────────────────────────────
  CPU      ███░░░░░░░░░░░   22%   8 núcleos · carga 0.97 1.05 0.91
  MEM      █████▉░░░░░░░░   42%   3.0 GiB / 7.1 GiB
  SWAP     ░░░░░░░░░░░░░░    0%   0 B / 3.9 GiB

  ▌ ARMAZENAMENTO ──────────────────────────────────────────────────────────────
  sda      HDD SATA  931.5 GiB  sem montagem
  nvme0n1  SSD NVMe  465.7 GiB ▍░░░░░░░  5%  / +1        ocioso

  ▌ REDE ───────────────────────────────────────────────────────────────────────
  wlp2s0  BUSCA_5G · 5 GHz · sinal 100% · 433.3 Mbit/s   ↓ 1.1 KiB/s  ↑ 0 B/s
  STATUS   192.168.31.25 · Internet online (22 ms)
  PORTAS   8000·9443 portainer  40613 code  49374 opencode  53·631 sistema

  ▌ SISTEMA ────────────────────────────────────────────────────────────────────
  UPTIME   no ar há 34m · 295 processos · 1 usuário
  BATERIA  100% · cheia
  TEMP     56 °C
```

As barras ficam verdes até 60%, amarelas até 85% e vermelhas acima disso. As
barras usam sub-blocos (`▏▎▍▌▋▊▉`) para uma leitura mais suave. O sinal do Wi-Fi
usa a mesma lógica de cor (verde ≥ 60%, amarelo ≥ 35%, vermelho abaixo).

Linhas que não fazem sentido no seu hardware (bateria, temperatura, Wi-Fi) ou
cuja ferramenta não está instalada simplesmente não aparecem. Em terminais
estreitos (< 70 colunas) o layout compacta automaticamente.

## Discos

Cada disco físico aparece com nome, tipo (**SSD**/**HDD** + barramento), tamanho,
uso da maior partição montada e I/O de leitura/escrita em tempo real.

Para ver partições, sistema de arquivos, ponto de montagem e temperatura:

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

Por que não aparece no painel? Um benchmark a cada terminal aberto seria lento e
desgastaria o disco sem necessidade. Por isso ele é sob demanda.

## Portas em escuta

O painel mostra as portas **TCP** em escuta, sem repetir IPv4/IPv6, agrupadas
por origem: containers Docker, processos seus (com o nome do programa) e
serviços do sistema.

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
| `SYSINFO_BENCH_SIZE=256` | `256` | tamanho do benchmark, em MiB (8 a 4096) |
| `SYSINFO_DISKS_DELAY=0.3` | `0.3` | janela de amostragem de I/O em `sysinfo disks` |
| `SYSINFO_DOCKER_CHECK=0` | `1` | não consulta o Docker ao listar portas |

Exemplos:

```bash
# barras mais largas e amostragem mais curta
export SYSINFO_BAR_WIDTH=20
export SYSINFO_DELAY=0.1

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
│   ├── config.sh      # variáveis, cores, caracteres e largura
│   ├── ui.sh          # formatação, barras e linhas
│   ├── system.sh      # CPU/rede/I/O e seção SISTEMA
│   ├── disks.sh       # discos, filesystems e "sysinfo disks"
│   ├── network.sh     # interface, Wi-Fi, taxas e internet
│   ├── ports.sh       # portas, processos, containers e TIPO
│   ├── bench.sh       # benchmark sequencial
│   └── panel.sh       # montagem do painel
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
