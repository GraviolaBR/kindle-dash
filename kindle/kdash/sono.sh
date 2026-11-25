#!/bin/sh
# Ciclo do painel (iniciado pelo upstart kdash.conf no boot, ou pelo KUAL):
# abre o painel → espera OCIOSO s sem toque (ou o "dormir agora" do cadeado)
# → mostra a versão "dormindo" → arma o despertador → suspende. O e-ink segue
# mostrando a última imagem sem gastar bateria. Acorda pelo botão de ligar ou
# pelo despertador (o toque fica desligado na suspensão) e recomeça.
# Baseado no kiosk-sleep.conf do higoorc/kindle-dash (MIT).
#
# Saídas de emergência (arquivos em /mnt/us, dá pra criar pelo KUAL ou SSH):
#   DESLIGAR_PAINEL — o ciclo para e o Kindle volta ao normal
#   NAO_DORMIR      — painel aberto, mas sem suspender (ex.: na tomada)

. /mnt/us/kdash/config.sh
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
LOG=/tmp/kdash.log
log() { echo "$(date '+%d/%m %H:%M:%S') $*" >> $LOG; }

GW=$(route -n 2>/dev/null | awk '$1=="0.0.0.0"{print $2; exit}')
[ -z "$GW" ] && GW=$SERVIDOR

enviar_bateria() {
    B=$(lipc-get-prop com.lab126.powerd battLevel 2>/dev/null)
    [ -z "$B" ] && return
    CARREGANDO=$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)
    CORPO="{\"state\":\"$B\",\"attributes\":{\"unit_of_measurement\":\"%\",\"friendly_name\":\"Kindle bateria\",\"device_class\":\"battery\",\"carregando\":${CARREGANDO:-0}}}"
    # O wget do BusyBox não faz POST: a requisição vai escrita à mão pelo nc.
    # O "sleep 2" segura a conexão até o nginx responder.
    ( printf 'POST /api/states/sensor.kindle_bateria HTTP/1.1\r\nHost: %s:%s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
        "$SERVIDOR" "$PORTA" "${#CORPO}" "$CORPO"; sleep 2 ) | nc "$SERVIDOR" "$PORTA" >/dev/null 2>&1
}

esperar_rede() {
    i=0
    while [ $i -lt 15 ]; do
        ping -c 1 -W 2 "$GW" >/dev/null 2>&1 && return 0
        sleep 2; i=$((i + 1))
    done
    log "rede não voltou"
}

# o descanso de tela da Amazon cobriria o painel
lipc-set-prop com.lab126.powerd preventScreenSaver 1

log "início"
while true; do
    [ -f /mnt/us/DESLIGAR_PAINEL ] && { log "DESLIGAR_PAINEL: saindo"; break; }
    lipc-set-prop com.lab126.powerd preventScreenSaver 1

    esperar_rede
    /mnt/us/kdash/painel.sh /
    enviar_bateria
    log "painel aberto"

    ocioso=0; n=0
    while [ $ocioso -lt $OCIOSO ] || [ -f /mnt/us/NAO_DORMIR ]; do
        [ -f /mnt/us/DESLIGAR_PAINEL ] && break
        # um toque qualquer zera o contador
        if timeout $CONSULTA dd if="$TOQUE" bs=16 count=1 >/dev/null 2>&1; then
            ocioso=0
        else
            ocioso=$((ocioso + CONSULTA))
        fi
        case "$(wget -q -O - "http://$SERVIDOR:$PORTA/api/states/input_boolean.kindle_dormir" 2>/dev/null)" in
            *'"state":"on"'*|*'"state": "on"'*) log "dormir agora (cadeado)"; [ -f /mnt/us/NAO_DORMIR ] || break ;;
        esac
        n=$((n + 1))
        [ $n -ge $BATERIA_A_CADA ] && { enviar_bateria; n=0; }
    done
    [ -f /mnt/us/DESLIGAR_PAINEL ] && continue

    # imagem "dormindo" e suspensão
    /mnt/us/kdash/painel.sh /dormir
    sleep 8
    echo 0 > $RTC/wakealarm 2>/dev/null
    echo +$DESPERTADOR > $RTC/wakealarm 2>/dev/null
    log "suspendendo"
    echo mem > /sys/power/state 2>/dev/null
    log "acordou"
done

lipc-set-prop com.lab126.powerd preventScreenSaver 0
killall kindle_browser >/dev/null 2>&1
lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1
