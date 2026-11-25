#!/bin/sh
# Para o ciclo e volta à tela inicial. Fica parado até "Iniciar painel"
# (inclusive depois de reiniciar o Kindle).
touch /mnt/us/DESLIGAR_PAINEL
pkill -f /mnt/us/kdash/sono.sh 2>/dev/null
killall kindle_browser 2>/dev/null
lipc-set-prop com.lab126.powerd preventScreenSaver 0
lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
