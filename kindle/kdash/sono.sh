#!/bin/sh
# Ciclo do painel (iniciado pelo upstart kdash.conf no boot, ou pelo KUAL):
# abre o painel → espera OCIOSO s sem toque (ou o "dormir agora" do cadeado)
# → mostra a versão "dormindo" → arma o despertador → suspende. O e-ink segue
# mostrando a última imagem sem gastar bateria. Acorda pelo botão de ligar ou
# pelo despertador (o toque fica desligado na suspensão) e recomeça.
# Baseado no kiosk-sleep.conf do higoorc/kindle-dash (MIT).
#
# Saídas de emergência (arquivos em /mnt/us, dá pra criar pelo KUAL ou SSH):
#   DESLIGAR_PAINEL — o ciclo para e o Kindle volta ao normal (o botão "Sair"
#                     da página cria este arquivo)
#   NAO_DORMIR      — painel aberto, mas sem suspender (ex.: na tomada)

. /mnt/us/kdash/config.sh
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
LOG=/tmp/kdash.log
log() { echo "$(date '+%d/%m %H:%M:%S') $*" >> $LOG; }

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

# Liga o Wi-Fi pelo serviço da Amazon e espera o servidor responder (até ~90 s).
# Necessário no firmware 5.17: suspendendo direto pelo kernel (echo mem), o
# wifid não religa sozinho ao acordar.
servidor_responde() {
    wget -q -T 3 -O /dev/null "http://$SERVIDOR:$PORTA/api/states/weather.casa" 2>/dev/null
}
esperar_rede() {
    servidor_responde && return 0
    lipc-set-prop com.lab126.wifid enable 1 2>/dev/null
    lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null
    i=0
    while [ $i -lt 30 ]; do
        [ $((i % 10)) -eq 0 ] && lipc-set-prop com.lab126.cmd ensureConnection "wifi" 2>/dev/null
        servidor_responde && { log "rede ok (${i}x3s)"; return 0; }
        sleep 3; i=$((i + 1))
    done
    log "servidor não respondeu"
    return 1
}

# um ciclo só (iniciar.sh e o upstart checam este PID)
PIDF=/tmp/kdash.pid
if [ -f $PIDF ] && kill -0 "$(cat $PIDF)" 2>/dev/null; then exit 0; fi
echo $$ > $PIDF

# o descanso de tela da Amazon cobriria o painel
lipc-set-prop com.lab126.powerd preventScreenSaver 1

log "início"
while true; do
    [ -f /mnt/us/DESLIGAR_PAINEL ] && { log "DESLIGAR_PAINEL: saindo"; break; }
    lipc-set-prop com.lab126.powerd preventScreenSaver 1

    # sem rede, mantém a imagem atual (não abre página de erro) e tenta de novo
    if ! esperar_rede; then sleep 30; continue; fi
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
        case "$(wget -q -O - "http://$SERVIDOR:$PORTA/api/states/input_boolean.kindle_sair" 2>/dev/null)" in
            *'"state":"on"'*) log "sair (botão da página)"; touch /mnt/us/DESLIGAR_PAINEL; break ;;
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
    lipc-set-prop com.lab126.wifid enable 0 2>/dev/null
    sleep 1
    echo mem > /sys/power/state 2>/dev/null
    log "acordou"
done

rm -f $PIDF
lipc-set-prop com.lab126.powerd preventScreenSaver 0
killall kindle_browser >/dev/null 2>&1
lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1
