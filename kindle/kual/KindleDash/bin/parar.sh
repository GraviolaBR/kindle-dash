#!/bin/sh
# Para o ciclo e volta à tela inicial. Fica parado até "Iniciar painel"
# (inclusive depois de reiniciar o Kindle).
touch /mnt/us/DESLIGAR_PAINEL
[ -f /tmp/kdash.pid ] && kill "$(cat /tmp/kdash.pid)" 2>/dev/null
rm -f /tmp/kdash.pid
killall kindle_browser 2>/dev/null
# devolve a luz frontal de antes do painel (no painel ela fica apagada)
[ -f /mnt/us/kdash/luz.salva ] && cat /mnt/us/kdash/luz.salva > /sys/class/backlight/bl/brightness 2>/dev/null
lipc-set-prop com.lab126.powerd preventScreenSaver 0
lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
