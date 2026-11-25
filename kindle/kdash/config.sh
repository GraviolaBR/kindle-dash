# Configuração do painel no Kindle (lida pelos outros scripts).
SERVIDOR=192.168.18.167   # IP do servidor na rede de casa (Wi-Fi WINDSOR) — trocar no apê novo
PORTA=8124                # kindle-ui
TOQUE=/dev/input/event2   # touchscreen do PW4 (goodix-ts)
RTC=/sys/class/rtc/rtc0   # relógio que acorda o aparelho (bd71827)
OCIOSO=180                # segundos sem toque até dormir
CONSULTA=5                # granularidade da espera / consulta do "dormir agora"
BATERIA_A_CADA=12         # envia a bateria a cada CONSULTA*BATERIA_A_CADA s (~1 min)
OCIOSO_ACORDAR=35         # depois de acordar (botão ou despertador), sem toque volta a dormir em 35 s
DESPERTADOR=900           # acorda sozinho a cada 15 min pra atualizar os dados na tela
DESPERTADOR_NOITE=3600    # ... e de hora em hora entre NOITE_INICIO e NOITE_FIM (economia)
NOITE_INICIO=0            # hora (Brasília)
NOITE_FIM=6
