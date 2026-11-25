# kindle-dash

Kindle Paperwhite 4 (10ª geração, firmware 5.17.1, jailbreak WinterBreak) como
painel de toque e-ink do Home Assistant de casa: carro, usina, vendas, TVs e
avisos falados no Echo.

Adaptado de [higoorc/kindle-dash](https://github.com/higoorc/kindle-dash) (MIT),
feito para o Paperwhite 1. Daquele projeto ficaram o proxy com o token no
servidor, o ciclo de sono (dorme sem toque, acorda pelo botão) e o envio da
bateria. A página e a parte do Kindle foram reescritas para o firmware 5.17.
(A página estática antiga, "Smart Home Display" alimentada pelo Apps Script,
está no histórico do git até o commit `f37daaa`.)

## Como funciona

```
Kindle (Wi-Fi WINDSOR, 192.168.18.183)          Servidor (bagshotserver, 192.168.18.167)
  Chromium 75 em tela cheia ── HTTP :8124 ──▶  kindle-ui (nginx, network_mode host)
   └ kindle-ui/html/index.html                  ├ serve a página
  /mnt/us/kdash/sono.sh (upstart kdash.conf)    └ /api/* liberadas ──▶ Home Assistant :8123
   ├ abre o painel, espera 3 min sem toque          (token posto pelo nginx)
   ├ consulta input_boolean.kindle_dormir / kindle_sair
   ├ envia sensor.kindle_bateria (~1 min)
   └ arma o despertador e suspende (a página já trocou pra "DORMINDO")
```

- **Página** (`kindle-ui/html/index.html`): um HTML só, preto e branco, alvos
  grandes, 536×724 px CSS (tela 1072×1448 com escala 2). Lê
  `/api/states/<entidade>` e chama `/api/services/script/<script>`. Atualiza a
  cada 1 min acordado e 3 s depois de cada toque. Com 170 s sem toque (ou no
  toque do cadeado) a própria página passa pro modo "DORMINDO", sem botões; o
  `sono.sh` suspende aos 180 s e o e-ink congela essa imagem. (Reabrir o
  navegador em `/dormir` antes de suspender não dava tempo de desenhar: a tela
  ficava em branco. `/dormir` continua existindo só pra teste.)
- **Proxy** (`kindle-ui/nginx.conf.template`): o token de longa duração do HA
  fica só no `.env` do servidor. O nginx **não** repassa a API inteira: só ler
  as entidades da página, chamar os scripts da lista e gravar a bateria do
  Kindle. Todo o resto de `/api/` dá 403. Botão ou sensor novo na página →
  incluir no template também.
- **No HA** (repo `homeassistant`, `config/packages/kindle.yaml`):
  `input_boolean.kindle_dormir` / `kindle_sair` + automação que os desliga 15 s
  depois, scripts `kindle_dormir` (cadeado) e `kindle_sair` (botão Sair do
  rodapé) e scripts de desligar as TVs. O
  `sensor.kindle_bateria` é criado pelo próprio Kindle (POST na API).
- **No Kindle**:
  - O navegador do 5.17 é um **Chromium 75** (`/usr/bin/chromium`, dentro do
    chroot `/chroot`), e não o WebKit antigo do PW1. O original abre a janela
    com o título `L:A_N:application_PC:TS_ID:com.lab126.browser_WT:true`, e o
    gerenciador de janelas (awesome com regras da Amazon,
    `/etc/xdg/awesome/lab126_*.lua`) reserva o topo pras barras de status e de
    endereço (`PC:TS`). O `instalar.sh` copia o navegador para
    `/mnt/us/kdash/chromium` e troca `PC:TS` por `PC:NN` no binário (mesmo
    tamanho): sem barras, tela cheia. O navegador normal do Kindle fica intacto.
  - `painel.sh` abre essa cópia direto (`--content-shell-host-window-size=536x724`).
  - `sono.sh` é o ciclo; `config.sh` tem IP, toque (`/dev/input/event2`,
    goodix), relógio do despertador (`rtc0`) e tempos.
  - `/etc/upstart/kdash.conf` inicia o ciclo no boot.
  - KUAL → **Painel Casa**: Iniciar / Parar (volta ao Kindle normal) / Não
    dormir (na tomada) / Voltar a dormir sozinho.

## Instalação

### Servidor

O deploy é automático: push na `main` → runner self-hosted (`/opt/actions-runner/kindle-dash`)
copia pra `/srv/apps/kindle-dash` e sobe o `kindle-ui`. Uma vez só:

1. Token: no HA, seu usuário → Segurança → **Tokens de acesso de longa duração**
   → criar "Kindle". Colar no servidor (o arquivo é 600):
   ```bash
   ssh -t servidor 'umask 077; read -rsp "Token: " T; printf "KINDLE_HA_TOKEN=%s\nHA_URL=http://127.0.0.1:8123\n" "$T" > /srv/apps/kindle-dash/.env; echo'
   ```
2. Firewall: só o Kindle acessa a 8124 (o Mac testa pelo Tailscale):
   `sudo ufw allow from 192.168.18.183 to any port 8124 proto tcp comment 'kindle-dash'`.
   Reserve o IP do Kindle no roteador (MAC `08:84:9d:a6:c4:cb`).

Testar no Mac: `http://100.110.104.47:8124` (mesma página do Kindle).

### Kindle

Pré-requisitos (já feitos neste Kindle): jailbreak WinterBreak, KUAL + MRPI,
**USBNetLite** (`Update_usbnetlite_1.0.M_install_khf.bin`, KUAL → Helper →
Install MR Packages), SSH por chave (`/mnt/us/usbnetlite/etc/dropbear/authorized_keys`,
login por senha desligado em `/mnt/us/usbnetlite/etc/config`) e atualizações
da Amazon bloqueadas (pasta `/mnt/us/update.bin.tmp.partial`).

Do Mac, com o Kindle acordado no Wi-Fi WINDSOR:

```bash
bash kindle/instalar.sh            # ou: bash kindle/instalar.sh <ip-do-kindle>
```

Depois: KUAL → Painel Casa → Iniciar painel (ou reiniciar o Kindle).

## Uso

| Na tela | Quer dizer | Fazer |
|---|---|---|
| Cadeado **AO VIVO** | painel acordado | tocar em qualquer botão; cada toque também atualiza |
| Cadeado **DORMINDO** | imagem congelada, Kindle suspenso | apertar o **botão de ligar** e esperar uns segundos |
| Quer dormir já | — | tocar no cadeado AO VIVO |
| Sair do painel | — | botão **Sair** no rodapé (confirma) → volta ao Kindle normal. Voltar: KUAL → Painel Casa → Iniciar painel |

Suspende depois de 3 min sem toque e acorda sozinho a cada 12 h. A bateria
aparece no rodapé e no HA (`sensor.kindle_bateria`).

## Wi-Fi

O Kindle só deve ter a rede **WINDSOR** salva. Com a "bagshot" (Google Nest,
192.168.86.x) também salva, ao acordar ele entrava nela e não alcançava o
servidor — ela foi esquecida em 25/11. Ainda assim o `sono.sh` desliga o Wi-Fi
pelo `wifid` antes de suspender e religa ao acordar (`wifid enable`,
`cmd ensureConnection`): suspendendo direto pelo kernel, o 5.17 não religa
sozinho. Sem o servidor respondendo, ele mantém a imagem "DORMINDO" na tela e
tenta de novo a cada 30 s, em vez de abrir uma página de erro.

## Manutenção

- **SSH:** `ssh root@192.168.18.183` (só com o Kindle acordado).
- **Log:** `/tmp/kdash.log` (ciclo) e `/tmp/kdash-navegador.log` (Chromium). Somem ao reiniciar.
- **Ver a tela do Kindle do Mac:** `ssh root@<ip> 'dd if=/dev/fb0 bs=1088 count=1448' > tela.raw`
  e converter (8 bits cinza, 1088×1448, cortar pra 1072 de largura).
- **Firmware:** se um dia atualizar, o `instalar.sh` percebe o navegador
  novo e refaz a cópia; se o título da janela mudar, ele avisa e para.
- **Apê novo:** trocar `SERVIDOR` em `kindle/kdash/config.sh` (e rodar o
  `instalar.sh`) e a regra do ufw.
