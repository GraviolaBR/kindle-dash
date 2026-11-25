#!/bin/sh
rm -f /mnt/us/DESLIGAR_PAINEL
pgrep -f /mnt/us/kdash/sono.sh >/dev/null 2>&1 || nohup /mnt/us/kdash/sono.sh >/dev/null 2>&1 &
