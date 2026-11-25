#!/bin/sh
if [ "$1" = "ligar" ]; then touch /mnt/us/NAO_DORMIR; else rm -f /mnt/us/NAO_DORMIR; fi
