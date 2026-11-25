#!/bin/bash
# Instala/atualiza o painel no Kindle, rodando do Mac (precisa de SSH por chave
# no Kindle: USBNetLite com a chave em /mnt/us/usbnetlite/etc/dropbear/authorized_keys).
#   bash kindle/instalar.sh [ip-do-kindle]
# Pode rodar de novo à vontade: só sobrescreve os arquivos do painel.
set -euo pipefail

KINDLE="${1:-192.168.18.183}"
AQUI="$(cd "$(dirname "$0")" && pwd)"
K="ssh -o ConnectTimeout=8 root@$KINDLE"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "== Kindle $KINDLE"
$K 'cat /etc/prettyversion.txt | head -1'

# 1) Cópia do navegador da Amazon com o título de janela trocado.
#    O binário pede ao gerenciador de janelas do Kindle a janela
#    "L:A_N:application_PC:TS_ID:com.lab126.browser_WT:true"; PC:TS reserva o
#    topo pras barras da Amazon. Trocamos por PC:NN (mesmo tamanho), que o
#    gerenciador trata como tela cheia. O original em /usr/bin/chromium fica
#    intacto (o navegador normal continua funcionando).
# (refaz se o navegador original mudar, ex.: depois de atualizar o firmware)
ORIGEM=$($K 'md5sum /chroot/usr/bin/chromium/bin/kindle_browser | cut -c1-32')
if [ "$($K 'cat /mnt/us/kdash/chromium/.origem 2>/dev/null' || true)" != "$ORIGEM" ]; then
  echo "== copiando o navegador (~66 MB, alguns minutos)"
  $K 'rm -rf /mnt/us/kdash/chromium && mkdir -p /mnt/us/kdash/chromium && cp -a /chroot/usr/bin/chromium/bin /mnt/us/kdash/chromium/'
  for f in kindle_browser libchromium.so; do
    echo "== ajustando $f"
    $K "cat /mnt/us/kdash/chromium/bin/$f" > "$TMP/$f"
    python3 - "$TMP/$f" <<'PY'
import sys
p = sys.argv[1]
b = open(p, 'rb').read()
velho = b'L:A_N:application_PC:TS_ID:com.lab126.browser_WT:true'
novo  = b'L:A_N:application_PC:NN_ID:com.lab126.browser_WT:true'
assert len(velho) == len(novo)
n = b.count(velho)
if n == 0:
    sys.exit('título não encontrado em ' + p + ' (firmware diferente?)')
open(p, 'wb').write(b.replace(velho, novo))
print('  trocado', n, 'vez(es)')
PY
    $K "cat > /mnt/us/kdash/chromium/bin/$f.novo && mv /mnt/us/kdash/chromium/bin/$f.novo /mnt/us/kdash/chromium/bin/$f && chmod +x /mnt/us/kdash/chromium/bin/$f" < "$TMP/$f"
  done
  echo "$ORIGEM" | $K 'cat > /mnt/us/kdash/chromium/.origem'
else
  echo "== navegador já preparado"
fi

# 2) Scripts do painel (em /mnt/us: atualiza sem mexer no sistema).
echo "== scripts"
$K 'mkdir -p /mnt/us/kdash/perfil'
for f in config.sh painel.sh sono.sh; do
  $K "cat > /mnt/us/kdash/$f && chmod +x /mnt/us/kdash/$f" < "$AQUI/kdash/$f"
done

# 3) Extensão do KUAL.
echo "== KUAL"
$K 'mkdir -p /mnt/us/extensions/KindleDash/bin'
for f in menu.json config.xml bin/iniciar.sh bin/parar.sh bin/nao_dormir.sh; do
  $K "cat > /mnt/us/extensions/KindleDash/$f" < "$AQUI/kual/KindleDash/$f"
done
$K 'chmod +x /mnt/us/extensions/KindleDash/bin/*.sh'

# 4) Job de boot (o / é somente leitura: remonta, grava, volta).
echo "== upstart"
$K 'mount -o remount,rw / && cat > /etc/upstart/kdash.conf; mount -o remount,ro /' < "$AQUI/upstart/kdash.conf"

echo "== pronto. Pra iniciar agora: KUAL → Painel Casa → Iniciar painel (ou reiniciar o Kindle)."
