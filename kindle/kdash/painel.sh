#!/bin/sh
# Abre o painel em tela cheia: uma cópia do navegador do Kindle (Chromium 75)
# em /mnt/us/kdash/chromium/bin, com o título de janela trocado de
# "..._PC:TS_..." (aplicativo com barra de status e de endereço da Amazon) para
# "..._PC:NN_..." (sem barras) — ver preparar-navegador.sh.
# Uso: painel.sh [caminho]   (ex.: painel.sh /dormir)

. /mnt/us/kdash/config.sh

URL="http://$SERVIDOR:$PORTA${1:-/}"

# fecha o navegador da Amazon e a instância anterior do painel
lipc-set-prop com.lab126.appmgrd stop app://com.lab126.browser >/dev/null 2>&1
killall kindle_browser >/dev/null 2>&1
sleep 1

export DISPLAY=:0
# o Kindle roda em UTC; sem isto a hora da página sai +3 h
export TZ="<-03>3"
export XDG_CONFIG_HOME=/mnt/us/kdash/perfil/
export LD_LIBRARY_PATH=/mnt/us/kdash/chromium/bin:/usr/bin/chromium/lib:/usr/bin/chromium/usr/lib:/usr/lib/

# Mesmas opções do /usr/bin/browser da Amazon, menos as barras; janela do
# tamanho da tela (536x724 com escala 2 = 1072x1448).
chroot /chroot /mnt/us/kdash/chromium/bin/kindle_browser \
  --no-zygote --no-sandbox --single-process --skia-resource-cache-limit-mb=64 \
  --disable-gpu --in-process-gpu --disable-gpu-sandbox --disable-gpu-compositing \
  --force-device-scale-factor=2 --js-flags=jitless \
  --content-shell-hide-toolbar --content-shell-host-window-cord=0,0 \
  --content-shell-host-window-size=536x724 \
  --force-gpu-mem-available-mb=40 --enable-low-end-device-mode --enable-low-res-tiling \
  --disable-site-isolation-trials --enable-grayscale-mode \
  "$URL" > /tmp/kdash-navegador.log 2>&1 &
