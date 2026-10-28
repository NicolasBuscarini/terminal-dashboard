# terminal-dashboard

Repositório: <https://github.com/NicolasBuscarini/terminal-dashboard>

Painel de status do sistema exibido automaticamente ao abrir o terminal: **CPU**
(modelo, marca, núcleos/threads, frequência, iGPU e temperatura), memória, swap,
**slots e geração da RAM** (DDR4/DDR5, frequência, fabricante, part number e
temperatura), **placa de vídeo** (VRAM, uso, temperatura e tipo), **todos os
discos** (SSD/HDD, partições, uso, I/O ao vivo e temperatura), rede, Wi-Fi,
internet, **portas em escuta**, **benchmarks em cache** (disco sequencial, 4 KiB,
memória e CPU), uptime, bateria e temperatura.

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
  CPU      █▍░░░░░░░░░░░░   10%   4 núcleos · 8 threads · 57 °C
           Intel Core i5-8250U · iGPU UHD Graphics 620 · carga 0.97 0.95 0.92
  MEM      ███████▏░░░░░░   51%   3.7 GiB / 7.1 GiB
  SWAP     ░░░░░░░░░░░░░░    0%   332.0 KiB / 3.9 GiB

  ▌ MEMÓRIA RAM ────────────────────────────────────────────────────────────────
  RAM      DDR4 · 2400 MT/s · 2/2 slots · 8.0 GiB · 46 °C
           ChannelA-DIMM0  SODIMM  4.0 GiB  Samsung  DDR4-2400
           ChannelB-DIMM0  SODIMM  4.0 GiB  Samsung  DDR4-2400

  ▌ PLACA DE VÍDEO ─────────────────────────────────────────────────────────────
  GPU      Intel UHD Graphics 620 · integrada · i915
           VRAM compartilhada · uso n/d · temp n/d
  DEDICADA nenhuma placa dedicada detectada

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
  4K       E 29.1k IOPS · L 36.4k IOPS
  RAM      E 1.7 GB/s · L 3.6 GB/s
  CPU      1 thread 162 MB/s · 8 threads 586 MB/s

  ▌ SISTEMA ────────────────────────────────────────────────────────────────────
  UPTIME   no ar há 1h 3m · 309 processos · 1 usuário
  BATERIA  100% · cheia
  TEMP     60 °C

  sysinfo cpu · gpu · ram · disks · ports · bench · --help
```

As barras ficam verdes até 60%, amarelas até 85% e vermelhas acima disso. As
barras usam sub-blocos (`▏▎▍▌▋▊▉`) para uma leitura mais suave. O sinal do Wi-Fi
usa a mesma lógica de cor (verde ≥ 60%, amarelo ≥ 35%, vermelho abaixo).

Linhas que não fazem sentido no seu hardware (bateria, temperatura, Wi-Fi) ou
cuja ferramenta não está instalada simplesmente não aparecem. O layout é
responsivo: em terminais estreitos as seções compactam, a tabela de portas vira
resumo e os discos perdem as partições; em terminais largos (≥ 96 colunas)
PROCESSAMENTO e SISTEMA dividem a mesma faixa. A RAM tem seção própria
(MEMÓRIA RAM) em qualquer largura.

## Composição do painel

A composição é definida por `SYSINFO_PANEL`. O padrão `all` liga todos os
tokens disponíveis:

| Token | Seção/linha |
| --- | --- |
| `header` | cabeçalho com usuário, host, distro e kernel |
| `cpu` | uso, núcleos/threads, temperatura, modelo e iGPU |
| `gpu` | GPUs detectadas: nome, tipo, VRAM, uso e temperatura |
| `mem` | uso da memória RAM (linha do PROCESSAMENTO) |
| `swap` | swap |
| `ram` | seção MEMÓRIA RAM: slots, geração DDR, frequência, fabricante e temperatura |
| `disks` | discos e partições (detalhado por padrão) |
| `net` | interface ativa, Wi-Fi/ethernet e taxas |
| `internet` | IP local e teste de conectividade |
| `ports` | portas em escuta (tabela por padrão) |
| `bench` | benchmarks em cache (sequencial, 4K, memória e CPU) |
| `uptime` | tempo no ar, processos e usuários |
| `battery` | bateria (se houver) |
| `temp` | temperatura (se disponível) |
| `services` | serviços systemd com falha (só aparece se houver) |

Presets prontos: `all`, `compact` (sem bench e serviços, mas com CPU e GPU),
`minimal` (alias) e `none` (painel vazio). Também há aliases: `memory` = `mem`, `network`/`wifi` =
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
| `SYSINFO_PANEL_CPU=full` | `full` | `full` mostra modelo/iGPU; `summary` só a linha de uso; `off` esconde |
| `SYSINFO_PANEL_GPU=full` | `full` | `full` mostra VRAM/uso/temp; `summary` uma linha por GPU; `off` esconde |
| `SYSINFO_PANEL_DISKS=full` | `full` | `full` mostra partições e uso; `summary` mostra uma linha por disco |
| `SYSINFO_PANEL_RAM=full` | `full` | `full` lista os slots; `summary` mostra só a linha-resumo; `off` esconde |
| `SYSINFO_PANEL_PORTS=table` | `table` | `table` lista as portas; `summary` mostra só a linha-resumo |
| `SYSINFO_PANEL_PORTS_MAX=0` | `0` | máximo de portas listadas no painel (`0` = todas) |
| `SYSINFO_PANEL_BENCH=auto` | `auto` | `auto` usa o cache e refaz quando expira; `live` mede sempre; `cache` nunca mede; `off` esconde |
| `SYSINFO_PANEL_BENCH_EXTRA=auto` | `auto` | `auto` mostra 4K/RAM/CPU com cache válido; `cache` mostra cache vencido; `off` esconde |
| `SYSINFO_BENCH_PANEL_SIZE=32` | `32` | tamanho do bench rápido do painel, em MiB |
| `SYSINFO_BENCH_TTL_DAYS=7` | `7` | validade do cache do bench, em dias |
| `SYSINFO_PANEL_HINT=0` | `1` | esconde o rodapé de dicas |

O painel nunca espera um benchmark lento ao abrir o terminal: ele usa os caches
em `${XDG_CACHE_HOME:-$HOME/.cache}/sysinfo` (`bench`, `bench-4k`, `bench-mem`,
`bench-cpu`) e só mede o sequencial de novo quando o cache não existe ou
expirou. `sysinfo bench` também grava nesses caches.


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

## Memória RAM

A RAM tem uma seção própria (**MEMÓRIA RAM**), logo depois de PROCESSAMENTO,
com uma linha-resumo de geração, frequência, slots ocupados e temperatura; com
`SYSINFO_PANEL_RAM=full` (padrão) também lista cada módulo. `SYSINFO_PANEL_RAM=off`
remove a seção, e o token `ram` continua disponível para a composição.

```bash
sysinfo ram                 # detalhes completos
sysinfo ram --update        # relê o DMI (pede sudo) e atualiza o cache
```

```
  MEMÓRIA RAM
  Fonte        dmidecode · cache há 2d
  Total        8.0 GiB instalados · 2/2 slots · todos preenchidos
  Tipo         DDR4 · 2400 MT/s (configurada) · 2666 MT/s (máxima)
  Formato      SODIMM · rank 1
  ECC          sem ECC
  Máximo      32.0 GiB suportados
  Temperatura  46 °C

  Slots
    ChannelA-DIMM0   SODIMM  4.0 GiB  Samsung  M471A5244CB0-CTD  DDR4-2400  1.2 V  rank 1
    ChannelB-DIMM0   SODIMM  4.0 GiB  Samsung  M471A5244CB0-CTD  DDR4-2400  1.2 V  rank 1
```

O `dmidecode` precisa de root. Para o painel nunca pedir senha ao abrir o
terminal, os detalhes ficam em cache:

```bash
sysinfo ram --update
# ou, se preferir chamar o sudo explicitamente:
sudo sysinfo ram --update
```

O cache fica em `${XDG_CACHE_HOME:-$HOME/.cache}/sysinfo/dmidecode-memory`
(permissão `600`, porque o dump contém números de série que **não** são
exibidos). Sem cache, o painel tenta o EDAC (`/sys/devices/system/edac`) para
tipo e slots e os sensores `hwmon` para temperatura; frequência e fabricante
só aparecem com o DMI.

Sensores de temperatura conhecidos: `spd5118` (DDR5) e `jc42` (DDR4). Muitos
notebooks não expõem esses sensores; nesse caso a linha de temperatura é
omitida. Para usar um dump já existente:

```bash
sudo env LC_ALL=C dmidecode -t memory > /tmp/ram.txt
SYSINFO_RAM_DMI_FILE=/tmp/ram.txt sysinfo ram
```

## Processador (CPU)

No painel, a linha da CPU mostra uso, núcleos físicos, threads e temperatura. Em
terminais com 70 colunas ou mais aparece uma segunda linha com o modelo, o vídeo
integrado e a carga média:

```
  CPU      █▍░░░░░░░░░░░░   10%   4 núcleos · 8 threads · 57 °C
           Intel Core i5-8250U · iGPU UHD Graphics 620 · carga 0.97 0.95 0.92
```

Para ver todos os detalhes:

```bash
sysinfo cpu                 # também aceita: processor, --cpu
```

```
  PROCESSADOR
  Modelo       Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz
  Marca        Intel
  Núcleos      4 núcleos · 8 threads
  Frequência   1.6 GHz (base) · 3.4 GHz (máx.)
  Atual        2.9 GHz
  Cache L3     6.0 MiB
  Governador   powersave
  Vídeo        Intel UHD Graphics 620 (i915)
  Temperatura  57 °C (Package id 0)
```

De onde vêm os dados (tudo sem root):

- modelo e marca: `/proc/cpuinfo` (`model name`/`Processor` e `vendor_id`),
  com `lscpu` como alternativa;
- núcleos, threads e soquetes: topologia em `/sys/devices/system/cpu/cpu*/topology`;
- frequência base, máxima e atual, cache L3 e governador: `cpufreq` e
  `/sys/devices/system/cpu/cpu0/cache`;
- temperatura: sensores `coretemp` (Intel), `k10temp`/`zenpower` (AMD) e, como
  alternativa, `thermal_zone` (`x86_pkg_temp`, `cpu-thermal`…);
- vídeo integrado: a mesma detecção da seção de GPU (`i915`, `amdgpu`, `xe`…).

Sem sensor de temperatura, a linha é omitida — nada de valor inventado. Em
`SYSINFO_PANEL_CPU=summary` o painel mostra só a linha de uso; `off` remove a
CPU da composição.

## Placa de vídeo (GPU)

A seção **PLACA DE VÍDEO** aparece em largura total logo depois de
PROCESSAMENTO. Ela lista todas as GPUs, com nome, marca, tipo, driver, VRAM,
uso e temperatura. Quando não há placa dedicada, isso fica explícito:

```
  ▌ PLACA DE VÍDEO ─────────────────────────────────────────────────────────────
  GPU      Intel UHD Graphics 620 · integrada · i915
           VRAM compartilhada · uso n/d · temp n/d
  DEDICADA nenhuma placa dedicada detectada
```

Com uma GPU dedicada, as métricas aparecem normalmente:

```
  GPU      AMD Radeon RX 6600 · dedicada · amdgpu
           VRAM 2.0 GiB / 8.0 GiB · uso 37% · temp 62 °C
```

```bash
sysinfo gpu                 # também aceita: video, vga, --gpu
```

```
  PLACAS DE VÍDEO

  GPU 1
  Nome         AMD Radeon RX 6600
  Marca        AMD
  Tipo         dedicada
  Driver       amdgpu
  VRAM         2.0 GiB / 8.0 GiB
  Uso          37%
  Temperatura  62 °C
  PCI          0000:03:00.0
```

Como a detecção funciona:

- **AMD/Intel e GPUs em geral**: `/sys/class/drm/card*` (vendor, device, driver,
  VRAM e uso); a temperatura vem do `hwmon` da placa;
- **NVIDIA**: `nvidia-smi` (nome, VRAM, uso, temperatura e PCI), com limite de
  1 s para nunca travar o terminal; se ele não existir, a GPU ainda aparece pelo
  sysfs/`lspci`;
- **nome do modelo**: `lspci`; sem ele, aparece o vendor/device PCI;
- **tipo**: `integrada`, `dedicada` ou `virtual` (virtio, VMware, VirtualBox,
  QEMU), inferido pelo vendor, driver e tamanho da VRAM.

VRAM, uso e temperatura só aparecem quando o driver expõe o dado. GPUs
integradas mostram `VRAM compartilhada`; sem sensor ou contador de uso, o campo
fica `n/d`. Em `SYSINFO_PANEL_GPU=summary` cada GPU ocupa uma linha; `off`
remove a seção. Sem nenhuma GPU detectada, o painel mostra `nenhuma GPU
detectada` em vez de esconder a seção.

## Benchmarks

O `sysinfo bench` tem quatro testes. Cada um grava um cache próprio em
`${XDG_CACHE_HOME:-$HOME/.cache}/sysinfo`, reaproveitado pelo painel:

| Tipo | O que mede | Cache |
| --- | --- | --- |
| `seq` (padrão) | escrita/leitura sequencial de blocos grandes | `bench` |
| `4k` | blocos de 4 KiB: IOPS e MB/s | `bench-4k` |
| `mem` | banda de escrita/leitura em `/dev/shm` (tmpfs) | `bench-mem` |
| `cpu` | throughput de SHA-256 em 1 e em N threads | `bench-cpu` |

```bash
sysinfo bench                 # sequencial na home
sysinfo bench /mnt/dados      # sequencial em outro disco
sysinfo bench 4k /mnt/dados   # blocos de 4 KiB no disco
sysinfo bench mem             # banda de memória (/dev/shm)
sysinfo bench cpu             # CPU com SHA-256
sysinfo bench all             # todos os testes acima
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

```
  BENCHMARK 4K (blocos de 4 KiB)
  /home/nicolas-buscarini · nvme0n1 · SSD NVMe

  Testando 16 MiB em 4096 blocos...

  Escrita  29.1k IOPS   116 MB/s   (0.14 s)
  Leitura  36.4k IOPS   145 MB/s   (0.11 s)

  Arquivo temporário removido.
```

```
  BENCHMARK DE MEMÓRIA (tmpfs)
  /dev/shm · 64 MiB

  Escrita  1.7 GB/s   (0.04 s)
  Leitura  3.6 GB/s   (0.02 s)

  Arquivo temporário removido.
```

```
  BENCHMARK DE CPU (SHA-256)
  Intel Core i5-8250U
  64 MiB por thread · 8 threads

  1 thread   162 MB/s   (0.39 s)
  8 threads  586 MB/s   (0.87 s)

  Quanto maior, melhor. O resultado varia com a carga e o governador da CPU.
```

O teste sequencial grava um arquivo temporário de `SYSINFO_BENCH_SIZE` MiB
(padrão 256), mede e apaga. A leitura usa `O_DIRECT` para não vir do cache; se o
sistema de arquivos não suportar, cai para leitura normal e marca com `*`. O
teste `4k` faz o mesmo com blocos de 4 KiB (`SYSINFO_BENCH_4K_SIZE`, padrão 16
MiB) e reporta IOPS.

O teste `mem` usa `/dev/shm` (tmpfs) e reduz o tamanho automaticamente se faltar
espaço, deixando uma folga de 8 MiB (`SYSINFO_BENCH_MEM_SIZE`, padrão 64 MiB).
O teste `cpu` usa `sha256sum` em `SYSINFO_BENCH_CPU_SIZE` MiB por thread (padrão
64) e roda uma vez com 1 thread e outra com `nproc` threads
(`SYSINFO_BENCH_CPU_THREADS` sobrescreve).

No painel, com `SYSINFO_PANEL_BENCH=auto` (padrão), só o teste sequencial é
medido quando o cache não existe ou passou de `SYSINFO_BENCH_TTL_DAYS` dias; a
medição do painel é rápida (`SYSINFO_BENCH_PANEL_SIZE`, padrão 32 MiB). Os
testes `4k`, `mem` e `cpu` aparecem no painel apenas quando já existe cache
válido — rode `sysinfo bench all` uma vez para preenchê-los. Use
`SYSINFO_PANEL_BENCH_EXTRA=cache` para mostrar também caches vencidos ou `off`
para esconder os extras. `SYSINFO_PANEL_BENCH=live` refaz o sequencial a cada
abertura; `cache` nunca mede no painel e `off` esconde a seção.

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
| `sysinfo cpu` | modelo, marca, núcleos/threads, frequência, iGPU e temperatura |
| `sysinfo gpu` | GPUs, tipo, VRAM, uso, temperatura e PCI |
| `sysinfo disks` | discos, partições, uso, I/O e temperatura |
| `sysinfo ram [--update]` | slots, geração, frequência, fabricante e temperatura da RAM |
| `sysinfo ports [--all] [-v]` | portas em escuta, processo/container e detalhes |
| `sysinfo bench [tipo] [dir]` | benchmark: `seq` (padrão), `4k`, `mem`, `cpu` ou `all` |
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
| `SYSINFO_BENCH_SIZE=256` | `256` | tamanho do benchmark sequencial, em MiB (8 a 4096) |
| `SYSINFO_BENCH_4K_SIZE=16` | `16` | tamanho do benchmark de 4 KiB, em MiB (4 a 512) |
| `SYSINFO_BENCH_MEM_SIZE=64` | `64` | tamanho do benchmark de memória, em MiB (16 a 2048) |
| `SYSINFO_BENCH_CPU_SIZE=64` | `64` | MiB por thread no benchmark de CPU (8 a 1024) |
| `SYSINFO_BENCH_CPU_THREADS=...` | `nproc` | número de threads do benchmark de CPU |
| `SYSINFO_DISKS_DELAY=0.3` | `0.3` | janela de amostragem de I/O em `sysinfo disks` |
| `SYSINFO_DOCKER_CHECK=0` | `1` | não consulta o Docker ao listar portas |
| `SYSINFO_PANEL=all` | `all` | composição: `all`, `compact`, `none` ou lista de tokens |
| `SYSINFO_PANEL_HIDE=...` | — | tokens removidos da composição |
| `SYSINFO_PANEL_COLUMNS=auto` | `auto` | `auto`, `1` ou `2` colunas |
| `SYSINFO_PANEL_CPU=full` | `full` | `full` (modelo/iGPU), `summary` ou `off` |
| `SYSINFO_PANEL_GPU=full` | `full` | `full` (VRAM/uso/temp), `summary` ou `off` |
| `SYSINFO_PANEL_DISKS=full` | `full` | `full` (partições) ou `summary` |
| `SYSINFO_PANEL_RAM=full` | `full` | `full` (slots), `summary` ou `off` |
| `SYSINFO_PANEL_PORTS=table` | `table` | `table` (lista) ou `summary` |
| `SYSINFO_PANEL_PORTS_MAX=0` | `0` | máximo de portas listadas (`0` = todas) |
| `SYSINFO_PANEL_BENCH=auto` | `auto` | `auto`, `live`, `cache` ou `off` |
| `SYSINFO_PANEL_BENCH_EXTRA=auto` | `auto` | `auto` (cache válido), `cache` (cache vencido) ou `off` |
| `SYSINFO_BENCH_PANEL_SIZE=32` | `32` | tamanho do bench rápido do painel, em MiB |
| `SYSINFO_BENCH_TTL_DAYS=7` | `7` | validade do cache do bench, em dias |
| `SYSINFO_PANEL_HINT=0` | `1` | esconde o rodapé de dicas |
| `SYSINFO_CACHE_DIR=...` | `~/.cache/sysinfo` | diretório dos caches dos benchmarks e da RAM |
| `SYSINFO_RAM_DMI_FILE=...` | — | dump de `dmidecode -t memory` para os detalhes de RAM |
| `SYSINFO_CPU_HWMON_DIR=...` | `/sys/class/hwmon` | diretório dos sensores da CPU (útil em testes) |
| `SYSINFO_CPU_THERMAL_DIR=...` | `/sys/class/thermal` | diretório das zonas térmicas (alternativa) |
| `SYSINFO_GPU_DRM_DIR=...` | `/sys/class/drm` | diretório dos dispositivos DRM/GPU (útil em testes) |

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
│   ├── cpu.sh         # modelo, núcleos/threads, frequência, iGPU e temperatura
│   ├── gpu.sh         # GPUs, VRAM, uso, temperatura e seção do painel
│   ├── memory.sh      # slots, tipo, frequência e temperatura da RAM
│   ├── disks.sh       # discos, filesystems e "sysinfo disks"
│   ├── network.sh     # interface, Wi-Fi, taxas e internet
│   ├── ports.sh       # portas, processos, containers e TIPO
│   ├── bench.sh       # benchmarks sequencial, 4K, memória e CPU + caches
│   └── panel.sh       # composição dinâmica, CPU/RAM/SWAP, GPU e layout
├── install.sh         # instala comando + gancho no .bashrc
├── uninstall.sh       # remove comando + gancho
└── README.md
```

O entrypoint resolve o próprio symlink (`readlink -f`) antes de carregar `lib/`,
então `~/.local/bin/sysinfo` continua funcionando normalmente. Cada arquivo tem
uma responsabilidade única e pode ser testado isoladamente com `bash -n`.

## Requisitos

- Linux (usa `/proc` e `/sys`)
- bash 4+ e coreutils (`awk`, `dd`, `df`, `mktemp`, `nproc`, `sha256sum`,
  `tput`, `sort`)
- `util-linux` (`lsblk`) para detectar discos e partições
- `/dev/shm` (tmpfs) para o benchmark de memória; sem ele, use
  `sysinfo bench mem /outro/diretorio`
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
| `dmidecode` | `dmidecode` | slots, geração, frequência e fabricante da RAM em `sysinfo ram` |
| `lspci` | `pciutils` | nome/modelo das GPUs em `sysinfo gpu` |
| `nvidia-smi` | driver NVIDIA | VRAM, uso e temperatura de GPUs NVIDIA |

A temperatura da RAM depende do sensor exposto pelo hardware (`spd5118` em
DDR5, `jc42` em DDR4); sem sensor, a linha é omitida. O mesmo vale para a CPU
(`coretemp`, `k10temp`, `zenpower` ou `thermal_zone`) e para a GPU (`hwmon` da
placa ou `nvidia-smi`).
