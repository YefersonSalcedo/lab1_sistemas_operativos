#!/bin/bash
#
# Autores: Yeferson Alexis Salcedo Preciado
#          Jhoan Esteban Echeverri Villa
#
# Tarea 2: Alert System Implementation
#
# Que hace este script:
#   Revisa el estado actual del sistema (RAM, carga de CPU, disco e
#   interfaces de red) y dispara alertas cuando se superan ciertos
#   umbrales. Todas las alertas quedan registradas en un log, con
#   proteccion anti-flooding (no repite la misma alerta antes de 5
#   minutos) y salida coloreada en consola (rojo = critico, amarillo =
#   advertencia).
#
# Uso:
#   ./alert_system.sh   Corre una sola revision de todos los umbrales

LOG_DIR="$HOME/system_monitor_logs"
ALERT_LOG="$LOG_DIR/alerts.log"
STATE_DIR="$LOG_DIR/.state"

mkdir -p "$LOG_DIR" "$STATE_DIR"

# Colores para salida en consola
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para registrar y mostrar alertas en consola
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

# Función para registrar los estados estables en el log de forma silenciosa
log_info() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] INFO: $message" >> "$ALERT_LOG"
}

# 1. Alerta de Memoria RAM (> 90%)
ram_usage=$(free | awk '/Mem/{print int($3/$2 * 100)}')
if (( ram_usage > 90 )); then
    trigger_alert "RAM" "WARNING" "RAM usage is at ${ram_usage}% (Threshold: 90%)"
else
    log_info "RAM OK (${ram_usage}%)"
fi

# 2. Alerta de Carga de CPU mayor a 5 revisandolo 3 veces
cpu_load=$(uptime | awk -F 'load average:' '{print $2}' | cut -d, -f1 | tr -d ' ')
cpu_high=$(awk -v val="$cpu_load" 'BEGIN {print (val > 5) ? 1 : 0}')
cpu_state_file="$STATE_DIR/cpu_streak"

if [ "$cpu_high" -eq 1 ]; then
    streak=0
    [ -f "$cpu_state_file" ] && streak=$(cat "$cpu_state_file")
    streak=$((streak + 1))
    echo "$streak" > "$cpu_state_file"

    if (( streak >= 3 )); then
        trigger_alert "CPU" "CRITICAL" "CPU load average > 5 for 3 consecutive checks (Current: $cpu_load)"
        echo "0" > "$cpu_state_file" # Resetear tras la alerta
    else
        log_info "CPU HIGH ($cpu_load) - Streak: $streak/3"
    fi
else
    echo "0" > "$cpu_state_file"
    log_info "CPU OK ($cpu_load)"
fi

# 3. Alerta de Disco mayor a 85% en la raiz
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if (( disk_usage > 85 )); then
    trigger_alert "DISK" "WARNING" "Root disk usage is at ${disk_usage}% (Threshold: 85%)"
else
    log_info "DISK OK (${disk_usage}%)"
fi

# 4. Alerta de Interfaz de Red Caída
down_interfaces=$(ip link | awk '/state DOWN/ {print $2}' | tr -d ':')
if [ -n "$down_interfaces" ]; then
    for iface in $down_interfaces; do
        trigger_alert "NET_${iface}" "CRITICAL" "Network interface $iface is DOWN"
    done
else
    log_info "NETWORK OK (No offline interfaces detected)"
fi