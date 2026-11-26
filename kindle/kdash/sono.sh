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
curto=0
while true; do
    [ -f /mnt/us/DESLIGAR_PAINEL ] && { log "DESLIGAR_PAINEL: saindo"; break; }
    lipc-set-prop com.lab126.powerd preventScreenSaver 1

    # sem rede, mantém a imagem atual (não abre página de erro) e tenta de novo
    if ! esperar_rede; then sleep 30; continue; fi
    # Na primeira volta (ou se o navegador morreu) abre o painel. Depois de
    # acordar o navegador segue aberto e a própria página se recarrega:
    # reabrir aqui fazia a tela inicial do Kindle piscar.
    # (PID do navegador do painel, não do navegador da Amazon, que tem o mesmo nome)
    NAV=$(cat /tmp/kdash-navegador.pid 2>/dev/null)
    if [ -z "$NAV" ] || ! kill -0 "$NAV" 2>/dev/null; then
        /mnt/us/kdash/painel.sh /
        log "painel aberto"
    else
        log "painel já aberto (a página recarrega sozinha)"
    fi
    enviar_bateria

    # Depois de acordar, sem toque volta a dormir em OCIOSO_ACORDAR (o
    # despertador de 15 min só atualiza a tela); com um toque vale o OCIOSO.
    # A página faz o mesmo do lado dela (25 s / 170 s) pra trocar pra "DORMINDO".
    ocioso=0; n=0; semrede=0
    if [ "$curto" = 1 ]; then limite=$OCIOSO_ACORDAR; else limite=$OCIOSO; fi
    while [ $ocioso -lt $limite ] || [ -f /mnt/us/NAO_DORMIR ]; do
        [ -f /mnt/us/DESLIGAR_PAINEL ] && break
        # um toque qualquer zera o contador
        if timeout $CONSULTA dd if="$TOQUE" bs=16 count=1 >/dev/null 2>&1; then
            ocioso=0; limite=$OCIOSO
        else
            ocioso=$((ocioso + CONSULTA))
        fi
        R=$(wget -q -T 4 -O - "http://$SERVIDOR:$PORTA/api/states/input_boolean.kindle_dormir" 2>/dev/null)
        case "$R" in
            *'"state":"on"'*|*'"state": "on"'*) log "dormir agora (cadeado)"; [ -f /mnt/us/NAO_DORMIR ] || break ;;
        esac
        # Wi-Fi caiu com o Kindle acordado (a tela fica com traços): depois de
        # ~30 s sem servidor, religa pelo wifid — sem isto ninguém religava.
        if [ -z "$R" ]; then
            semrede=$((semrede + 1))
            if [ $semrede -ge 6 ]; then
                log "sem servidor há ~30 s: religando Wi-Fi"
                esperar_rede; semrede=0
            fi
        else
            semrede=0
        fi
        case "$(wget -q -O - "http://$SERVIDOR:$PORTA/api/states/input_boolean.kindle_sair" 2>/dev/null)" in
            *'"state":"on"'*) log "sair (botão da página)"; touch /mnt/us/DESLIGAR_PAINEL; break ;;
        esac
        n=$((n + 1))
        [ $n -ge $BATERIA_A_CADA ] && { enviar_bateria; n=0; }
    done
    [ -f /mnt/us/DESLIGAR_PAINEL ] && continue

    # A página já se trocou sozinha pra versão "dormindo" (cadeado ou tempo sem
    # toque); espera o e-ink terminar de desenhar e suspende.
    sleep 4
    # Madrugada: não atualiza; acorda só às NOITE_FIM (botão continua acordando).
    set -- $(TZ="<-03>3" date '+%H %M %S')
    H=${1#0}; M=${2#0}; S=${3#0}
    if [ "$H" -ge "$NOITE_INICIO" ] && [ "$H" -lt "$NOITE_FIM" ]; then
        ESPERA=$(( (NOITE_FIM - H) * 3600 - M * 60 - S ))
    else
        ESPERA=$DESPERTADOR
    fi
    echo 0 > $RTC/wakealarm 2>/dev/null
    echo +$ESPERA > $RTC/wakealarm 2>/dev/null
    log "suspendendo (acorda em $((ESPERA / 60)) min)"
    lipc-set-prop com.lab126.wifid enable 0 2>/dev/null
    sleep 1
    echo mem > /sys/power/state 2>/dev/null
    log "acordou"
    curto=1
    # SSH (USBNetLite/dropbear): conexões abertas na hora da suspensão ficam
    # penduradas — o relógio do prazo para enquanto o Kindle dorme — e, somadas,
    # fazem o dropbear recusar as novas ("connection closed" antes da troca de
    # chaves; aconteceu em 25/11). Ao acordar, mata tudo menos o processo principal.
    MESTRE=$(cat /mnt/us/usbnetlite/run/sshd.pid 2>/dev/null)
    for P in $(pidof dropbear); do [ "$P" != "$MESTRE" ] && kill "$P" 2>/dev/null; done
done

rm -f $PIDF
lipc-set-prop com.lab126.powerd preventScreenSaver 0
killall kindle_browser >/dev/null 2>&1
lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1
