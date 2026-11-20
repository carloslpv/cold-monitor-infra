#!/usr/bin/env bash
# Starts everything the demo case needs on one computer, with the ports sorted out:
#   cold-monitor (this repository)  dashboard and API on 8090
#   cold-monitor-edge               broker for the temperature ESP32 on 1883, bridge on 8081
#   machine-telemetry               broker for the current ESP32 on 1884, platform on 8080, Grafana on 3000
# and registers the demo probe, so its readings reach the dashboard and the Telegram alert.
#
# Usage: maleta/maleta.sh [up|build|down|status]
#   up      start (builds only the images that are missing, so it works offline after the first time)
#   build   rebuild every image from the current code, then start
#   down    stop everything; data is kept
#   status  containers and addresses
#
# The repositories are expected side by side (EDGE_DIR and MT_DIR override that):
#   cold-monitor-backend/  cold-monitor-dashboard/  cold-monitor-infra/  cold-monitor-edge/  machine-telemetry/
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INFRA="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$INFRA/.." && pwd)"
EDGE="${EDGE_DIR:-$ROOT/cold-monitor-edge}"
MT="${MT_DIR:-$ROOT/machine-telemetry}"
MT_MQTT_PORT=1884
CODE=MALETA-01

die() { echo "maleta: $*" >&2; exit 1; }

# value of KEY in an env file, without quotes; empty if absent
env_value() {
  [[ -f "$1" ]] || return 0
  sed -n "s/^$2=//p" "$1" | tail -n 1 | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/" | tr -d '\r'
}

check() {
  for dir in "$ROOT/cold-monitor-backend" "$ROOT/cold-monitor-dashboard" "$EDGE" "$MT"; do
    [[ -d "$dir" ]] || die "missing $dir: clone the repositories side by side (see maleta/README.md)"
  done
  for env in "$INFRA/.env" "$EDGE/.env" "$MT/.env"; do
    [[ -f "$env" ]] || die "missing $env: copy .env.example to .env there and fill it in (see maleta/README.md)"
  done
  [[ -f "$HERE/maleta.env" ]] || die "missing maleta/maleta.env: copy maleta/maleta.env.example and fill it in"
  [[ -n "$(env_value "$MT/.env" MQTT_NODE_PASSWORD)" ]] \
    || echo "warning: MQTT_NODE_PASSWORD is empty in $MT/.env, so the current ESP32 cannot log in"
}

lan_ip() {
  local ip=""
  if command -v ip > /dev/null; then
    ip=$(ip -4 route get 1.1.1.1 2> /dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n 1)
  fi
  if [[ -z "$ip" ]] && command -v ipconfig > /dev/null; then
    ip=$(ipconfig getifaddr en0 2> /dev/null || true)
  fi
  echo "${ip:-<IP deste computador>}"
}

wait_for() { # url, seconds, curl options...
  local url=$1 seconds=$2
  shift 2
  for _ in $(seq 1 "$seconds"); do
    if curl -fsS -o /dev/null "$@" "$url" 2> /dev/null; then return 0; fi
    sleep 1
  done
  return 1
}

# the demo probe's equipment id, registering it the first time (a device key may list and register equipment)
equipment_id() {
  local api=$1 key=$2 min=$3 max=$4 list id
  list=$(curl -fsS -H "X-API-Key: $key" "$api/equipment") || die "cannot list equipment at $api (DEVICE_API_KEY?)"
  id=$(printf '%s' "$list" | tr '{' '\n' | grep "\"code\":\"$CODE\"" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -n 1)
  if [[ -z "$id" ]]; then
    id=$(curl -fsS -H "X-API-Key: $key" -H 'Content-Type: application/json' "$api/equipment" -d \
      "{\"code\":\"$CODE\",\"name\":\"Sonda da maleta\",\"location\":\"Demonstração\",\"type\":\"COLD_ROOM\",\"minTemperature\":$min,\"maxTemperature\":$max}" \
      | sed -n 's/.*"id":"\([^"]*\)".*/\1/p') || die "cannot register $CODE"
    echo "registered $CODE ($min to $max °C)" >&2
  fi
  echo "$id"
}

# the broker users of cold-monitor-edge's Mosquitto, from the passwords in its .env and in maleta.env
edge_users() {
  local file="$EDGE/mosquitto/passwd" bridge device password
  bridge=$(env_value "$EDGE/.env" MQTT_BRIDGE_PASSWORD)
  device=$(env_value "$HERE/maleta.env" COLD_DEVICE_ID)
  password=$(env_value "$HERE/maleta.env" COLD_DEVICE_PASSWORD)
  if [[ -f "$file" ]] && { [[ -z "$device" ]] || grep -q "^$device:" "$file"; }; then return 0; fi
  [[ -n "$bridge" ]] || die "MQTT_BRIDGE_PASSWORD is empty in $EDGE/.env"
  echo "creating the broker users of cold-monitor-edge"
  docker run --rm -v "$EDGE/mosquitto:/mosquitto/config" -e B="$bridge" -e D="$device" -e P="$password" \
    eclipse-mosquitto:2 sh -c '
      touch /mosquitto/config/passwd
      mosquitto_passwd -b /mosquitto/config/passwd bridge "$B"
      if [ -n "$D" ]; then mosquitto_passwd -b /mosquitto/config/passwd "$D" "$P"; fi
      chmod 0700 /mosquitto/config/passwd'
}

up() {
  local build=() key port api min max probe id ip
  [[ "${1:-}" == "build" ]] && build=(--build)
  check
  key=$(env_value "$INFRA/.env" DEVICE_API_KEY)
  port=$(env_value "$INFRA/.env" DASHBOARD_PORT)
  port=${port:-8090}
  api="http://localhost:$port/api/v1"

  echo "== cold-monitor"
  (cd "$INFRA" && docker compose up -d "${build[@]}")
  wait_for "$api/equipment" 180 -H "X-API-Key: $key" || die "the cold-monitor API did not answer at $api"

  min=$(env_value "$HERE/maleta.env" PROBE_MIN)
  max=$(env_value "$HERE/maleta.env" PROBE_MAX)
  id=$(equipment_id "$api" "$key" "${min:-10}" "${max:-35}")
  probe=$(env_value "$HERE/maleta.env" PROBE)
  [[ -n "$probe" ]] || echo "warning: PROBE is empty in maleta/maleta.env, so the bridge drops the probe's readings"

  echo "== cold-monitor-edge"
  edge_users
  # these win over the edge's .env: the backend is this computer's cold-monitor, with its key and the demo probe
  (cd "$EDGE" && BACKEND_URL="http://host.docker.internal:$port" BACKEND_API_KEY="$key" \
    BRIDGE_PROBES="${probe:+$probe=$id}" docker compose up -d "${build[@]}")

  echo "== machine-telemetry"
  (cd "$MT" && MQTT_PORT=$MT_MQTT_PORT docker compose up -d "${build[@]}")
  wait_for http://localhost:3000/api/health 180 || echo "warning: Grafana did not answer on port 3000 yet"

  ip=$(lan_ip)
  cat << EOF

Maleta pronta / demo case ready.
  Temperatura (cold-monitor):   http://$ip:$port        (no notebook: http://localhost:$port)
  Máquinas (Grafana):           http://$ip:3000         (no notebook: http://localhost:3000)
  ESP32 de temperatura, broker: mqtt://$ip:1883
  ESP32 de corrente, broker:    mqtt://$ip:$MT_MQTT_PORT
Se o IP mudou desde a gravação dos ESP32, ajuste o broker no menuconfig deles (ou fixe o IP do notebook).
EOF
}

# the edge's compose requires the key even to stop or list; it is the same one up passes
edge_compose() {
  (cd "$EDGE" && BACKEND_API_KEY="$(env_value "$INFRA/.env" DEVICE_API_KEY)" docker compose "$@")
}

down() {
  (cd "$MT" && docker compose down)
  edge_compose down
  (cd "$INFRA" && docker compose down)
}

status() {
  local format='table {{.Service}}\t{{.Status}}\t{{.Ports}}'
  echo "== cold-monitor-infra"
  (cd "$INFRA" && docker compose ps --format "$format")
  echo "== cold-monitor-edge"
  edge_compose ps --format "$format"
  echo "== machine-telemetry"
  (cd "$MT" && docker compose ps --format "$format")
}

case "${1:-up}" in
  up) up ;;
  build) up build ;;
  down) down ;;
  status) status ;;
  *) die "unknown command '$1': use up, build, down or status" ;;
esac
