#!/bin/bash

LOG_DIR="$HOME/system_monitor_logs"
ALERT_LOG="$LOG_DIR/alerts.log"
STATE_DIR="$LOG_DIR/.state"

mkdir -p "$LOG_DIR" "$STATE_DIR"

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Función para registrar y mostrar alertas con prevención de inundación cuando sea 5 minutos
trigger_alert() {
    local alert_type="$1"
    local severity="$2"
    local message="$3"
    local state_file="$STATE_DIR/${alert_type}_last_time"
    local current_time=$(date +%s)
    local last_time=0

    if [ -f "$state_file" ]; then
        last_time=$(cat "$state_file")
    fi

    # Verificar el tiempo de los 5 minutos pero en segundos
    if (( current_time - last_time >= 300 )); then
        local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "$current_time" > "$state_file"
        echo "[$timestamp] $severity: $message" >> "$ALERT_LOG"

        if [ "$severity" == "CRITICAL" ]; then
            echo -e "${RED}[$timestamp] CRITICAL: $message${NC}"
        else
            echo -e "${YELLOW}[$timestamp] WARNING: $message${NC}"
        fi
    fi
}

# 1 Alerta de Memoria RAM cuando sea mayor 90%
ram_usage=$(free | awk '/Mem/{print int($3/$2 * 100)}')
if (( ram_usage > 90 )); then
    trigger_alert "RAM" "WARNING" "RAM usage is at ${ram_usage}% (Threshold: 90%)"
fi

# 2 Alerta de Carga de CPU revisandolo 3 veces
cpu_load=$(uptime | awk -F 'load average:' '{print $2}' | cut -d, -f1 | tr -d ' ')
cpu_high=$(awk -v load="$cpu_load" 'BEGIN {print (load > 5) ? 1 : 0}')
cpu_state_file="$STATE_DIR/cpu_streak"

if [ "$cpu_high" -eq 1 ]; then
    streak=0
    [ -f "$cpu_state_file" ] && streak=$(cat "$cpu_state_file")
    streak=$((streak + 1))
    echo "$streak" > "$cpu_state_file"

    if (( streak >= 3 )); then
        trigger_alert "CPU" "CRITICAL" "CPU load average > 5 for 3 consecutive checks (Current: $cpu_load)"
        echo "0" > "$cpu_state_file" # Resetear tras la alerta
    fi
else
    echo "0" > "$cpu_state_file"
fi

# 3. Alerta de Disco si la particion es mayor a 85
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if (( disk_usage > 85 )); then
    trigger_alert "DISK" "WARNING" "Root disk usage is at ${disk_usage}% (Threshold: 85%)"
fi

# 4. Alerta de Interfaz de Red Caída
down_interfaces=$(ip link show state DOWN | awk -F': ' '/^[0-9]/ {print $2}')
for iface in $down_interfaces; do
    trigger_alert "NET_${iface}" "CRITICAL" "Network interface $iface is DOWN"
done