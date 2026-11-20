# Demo case

[English](#english) · [Português (Brasil)](#português-brasil)

---

## English

One command that starts, on one computer, everything a portable demo needs: cold-monitor with its live dashboard and
Telegram alert, cold-monitor-edge for an ESP32 with a DS18B20 probe, and
[machine-telemetry](https://github.com/carloslpv/machine-telemetry) with its simulated PLCs and an ESP32 that reads a
motor's current with a clamp-on sensor ([esp32-node](https://github.com/carloslpv/machine-telemetry/tree/main/esp32-node)).

| What | Port |
| --- | --- |
| cold-monitor dashboard and API | 8090 |
| broker for the temperature ESP32 (cold-monitor-edge) | 1883 |
| bridge health and metrics | 8081 |
| broker for the current ESP32 (machine-telemetry) | 1884 |
| machine-telemetry API | 8080 |
| machine-telemetry Grafana | 3000 |

Do not start cold-monitor's `observability` profile at the same time: its Grafana also wants port 3000.

### First time

1. Clone the repositories side by side: `cold-monitor-backend`, `cold-monitor-dashboard`, `cold-monitor-infra`,
   `cold-monitor-edge` and `machine-telemetry`.
2. In each of `cold-monitor-infra`, `cold-monitor-edge` and `machine-telemetry`, copy `.env.example` to `.env` and
   fill it in. In cold-monitor-infra, also the Telegram bot (see the backend README). In machine-telemetry, also
   `MQTT_NODE_PASSWORD` (the current ESP32's password) and `MQTT_PORT=1884`. In cold-monitor-edge, only
   `MQTT_BRIDGE_PASSWORD`: the launcher passes the backend address, its key and the probe mapping.
3. Copy `maleta/maleta.env.example` to `maleta/maleta.env`. The probe's ROM code and the device id appear on the
   ESP32's serial monitor the first time it runs; fill them in then and run the launcher again.
4. Run it:

   ```bash
   maleta/maleta.sh            # Linux, macOS, Git Bash
   .\maleta\maleta.ps1         # Windows PowerShell, with Docker Desktop running
   ```

   The first run builds the images (it needs internet and takes a few minutes). It registers the demo probe as
   equipment `MALETA-01` with a 10 to 35 °C range, so room temperature is fine and a glass of ice sets off the alert.
5. Flash both ESP32 with the computer's address printed at the end: the temperature one (cold-monitor-edge) on port
   1883, with a reading interval of 5 s for a lively demo, and the current one (esp32-node) on port 1884.

After that, `maleta.sh` (or `maleta.ps1`) only starts what is already built, so it also works on a phone's hotspot.
`build` rebuilds after a `git pull`, `status` lists the containers and `down` stops everything, keeping the data.

The ESP32 boards have the broker address written in their configuration. A phone hotspot usually gives the computer
the same address every time, but not always: check the address printed at the end the day before a visit.

---

## Português (Brasil)

Um comando que sobe, num computador só, tudo o que a maleta de demonstração precisa: o cold-monitor com o dashboard
ao vivo e o alerta no Telegram, o cold-monitor-edge para o ESP32 com a sonda DS18B20, e o
[machine-telemetry](https://github.com/carloslpv/machine-telemetry) com os CLPs simulados e um ESP32 que lê a
corrente de um motor com sensor de garra ([esp32-node](https://github.com/carloslpv/machine-telemetry/tree/main/esp32-node)).

| O quê | Porta |
| --- | --- |
| dashboard e API do cold-monitor | 8090 |
| broker do ESP32 de temperatura (cold-monitor-edge) | 1883 |
| saúde e métricas da ponte | 8081 |
| broker do ESP32 de corrente (machine-telemetry) | 1884 |
| API do machine-telemetry | 8080 |
| Grafana do machine-telemetry | 3000 |

Não suba o perfil `observability` do cold-monitor junto: o Grafana dele também usa a porta 3000.

### Primeira vez

1. Clone os repositórios lado a lado: `cold-monitor-backend`, `cold-monitor-dashboard`, `cold-monitor-infra`,
   `cold-monitor-edge` e `machine-telemetry`.
2. Em `cold-monitor-infra`, `cold-monitor-edge` e `machine-telemetry`, copie `.env.example` para `.env` e preencha.
   No cold-monitor-infra, inclua o bot do Telegram (veja o README do backend). No machine-telemetry, inclua
   `MQTT_NODE_PASSWORD` (a senha do ESP32 de corrente) e `MQTT_PORT=1884`. No cold-monitor-edge, só
   `MQTT_BRIDGE_PASSWORD`: o endereço do backend, a chave e a sonda o script passa sozinho.
3. Copie `maleta/maleta.env.example` para `maleta/maleta.env`. O código ROM da sonda e o id do dispositivo aparecem
   no monitor serial do ESP32 na primeira vez que ele liga; preencha nessa hora e rode o script de novo.
4. Rode:

   ```bash
   maleta/maleta.sh            # Linux, macOS, Git Bash
   .\maleta\maleta.ps1         # Windows PowerShell, com o Docker Desktop aberto
   ```

   A primeira vez monta as imagens (precisa de internet e leva alguns minutos). O script cadastra a sonda da demo
   como o equipamento `MALETA-01`, com faixa de 10 a 35 °C: a temperatura ambiente fica dentro, e o copo com gelo
   dispara o alerta.
5. Grave os dois ESP32 com o endereço do computador que aparece no fim: o de temperatura (cold-monitor-edge) na porta
   1883, com intervalo de leitura de 5 s para a demo ficar viva, e o de corrente (esp32-node) na porta 1884.

Depois disso, `maleta.sh` (ou `maleta.ps1`) só liga o que já está montado, então funciona também no roteador do
celular. `build` remonta depois de um `git pull`, `status` mostra os containers e `down` desliga tudo, mantendo os
dados.

Os ESP32 guardam o endereço do broker na configuração deles. O roteador do celular costuma dar ao notebook o mesmo
endereço toda vez, mas nem sempre: confira o endereço que aparece no fim na véspera de uma visita.

### Roteiro da demo

1. Ligar o ventilador: no Grafana, a "Máquina sem CLP" passa para Produzindo e a corrente aparece no painel Motor.
   Desligar: a parada entra em "Últimas paradas" com o horário.
2. Sonda no copo com gelo: em menos de um minuto a temperatura passa abaixo de 10 °C, o painel muda de cor e o alerta
   chega no Telegram. Tirar do gelo: chega o aviso de volta à faixa.
3. Escolher uma das ensacadeiras no Grafana: "se a sua máquina já tem CLP, eu leio direto dele".
