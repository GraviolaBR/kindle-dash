#!/bin/sh
# sono.sh sai sozinho se já houver um ciclo rodando (/tmp/kdash.pid)
rm -f /mnt/us/DESLIGAR_PAINEL
nohup /mnt/us/kdash/sono.sh >/dev/null 2>&1 &
