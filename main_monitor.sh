#!/bin/bash
#
# Autores: Yeferson Alexis Salcedo Preciado
#          Jhoan Esteban Echeverri Villa
#
# Tarea 4: Script Integration and Menu System
#
# Que hace este script:
#   Integra los otros 3 scripts (advanced_system_monitor.sh, alert_system.sh
#   y generate_report.sh) en un solo punto de entrada, con dos formas de uso:
#     1. Argumentos de linea de comandos: --daemon, --report, --alert, --config.
#     2. Menu interactivo: iniciar/detener el daemon, ver estadisticas en
#        tiempo real, generar reportes (hoy / fecha especifica / semanal),
#        revisar y filtrar el historial de alertas, y configurar los
#        umbrales de alert_system.sh.
#
# Uso:
#   ./main_monitor.sh                                Abre el menu interactivo
#   ./main_monitor.sh --daemon                        Inicia el daemon en segundo plano
#   ./main_monitor.sh --report [--date YYYY-MM-DD]     Genera un reporte
#   ./main_monitor.sh --alert                          Revisa alertas de inmediato
#   ./main_monitor.sh --config                         Edita los umbrales de alerta

# Directorios de los scripts
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
ADV_MONITOR="$DIR/advanced_system_monitor.sh"
ALERT_SYS="$DIR/alert_system.sh"
GEN_REPORT="$DIR/generate_report.sh"

LOG_DIR="$HOME/system_monitor_logs"
DAEMON_PID_FILE="$LOG_DIR/daemon.pid"

mkdir -p "$LOG_DIR"


# Utilidades de manejo del daemon


# Guardamos el PID exacto del daemon en un archivo y lo usamos
# para iniciar/detener/consultar su estado de forma precisa.
daemon_is_running() {
    # Devuelve 0 (verdadero) si el PID guardado existe y sigue vivo.
    [ -f "$DAEMON_PID_FILE" ] || return 1
    local pid
    pid=$(cat "$DAEMON_PID_FILE")
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

start_daemon() {
    if daemon_is_running; then
        echo "El daemon ya esta corriendo (PID $(cat "$DAEMON_PID_FILE"))."
        return
    fi
    nohup bash "$ADV_MONITOR" --daemon > /dev/null 2>&1 &
    echo "$!" > "$DAEMON_PID_FILE"
    echo "Monitoring daemon started in background. PID: $!"
}

stop_daemon() {
    if ! daemon_is_running; then
        echo "El daemon no esta corriendo (o no fue iniciado desde este menu)."
        rm -f "$DAEMON_PID_FILE"
        return
    fi
    local pid
    pid=$(cat "$DAEMON_PID_FILE")
    kill "$pid" 2>/dev/null
    rm -f "$DAEMON_PID_FILE"
    echo "Daemon detenido (PID $pid)."
}

daemon_status() {
    if daemon_is_running; then
        echo "Daemon: EN EJECUCION (PID $(cat "$DAEMON_PID_FILE"))."
    else
        echo "Daemon: DETENIDO."
    fi
}


# Reportes: hoy / fecha especifica / semanal
is_valid_date() {
    # Valida formato YYYY-MM-DD y que sea una fecha real (usa `date -d`).
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && date -d "$1" >/dev/null 2>&1
}

report_today() {
    bash "$GEN_REPORT"
}

report_for_date() {
    local d="$1"
    if ! is_valid_date "$d"; then
        echo "Fecha invalida: '$d'. Formato esperado: YYYY-MM-DD."
        return 1
    fi
    bash "$GEN_REPORT" --date "$d"
}

report_weekly() {
    echo "Generando reportes de los ultimos 7 dias..."
    local i d
    for i in 6 5 4 3 2 1 0; do
        d=$(date -d "-${i} days" +"%Y-%m-%d")
        echo "--- $d ---"
        bash "$GEN_REPORT" --date "$d"
    done
    echo "Reportes semanales generados en $LOG_DIR/reports/"
}


# Configuracion de umbrales
edit_config() {
    local backup="${ALERT_SYS}.bak.$(date +%s)"
    cp "$ALERT_SYS" "$backup"

    nano "$ALERT_SYS"

    if ! bash -n "$ALERT_SYS" 2>/tmp/alert_syntax_err; then
        echo "El archivo quedo con errores de sintaxis:"
        cat /tmp/alert_syntax_err
        read -p "Restaurar la version anterior? [s/N]: " resp
        if [[ "$resp" =~ ^[sS]$ ]]; then
            cp "$backup" "$ALERT_SYS"
            echo "Restaurado desde $backup."
        else
            echo "Se mantiene el archivo editado (con errores). Respaldo disponible en $backup."
        fi
    else
        rm -f "$backup"
    fi
}

# Funciones de línea de comandos
case "$1" in
    --daemon)
        start_daemon
        exit 0
        ;;
    --report)
        shift
        bash "$GEN_REPORT" "$@"
        exit 0
        ;;
    --alert)
        bash "$ALERT_SYS"
        cat "$HOME/system_monitor_logs/alerts.log" 2>/dev/null || echo "No alerts generated yet."
        exit 0
        ;;
    --config)
        edit_config
        exit 0
        ;;
    -h|--help)
        echo "Usage: ./main_monitor.sh [--daemon | --report [--date YYYY-MM-DD] | --alert | --config]"
        exit 0
        ;;
esac

# Submenu de reportes
report_menu() {
    echo "----- Generar Reporte -----"
    echo "1. Reporte de hoy"
    echo "2. Reporte de una fecha especifica"
    echo "3. Reporte semanal (ultimos 7 dias)"
    echo "4. Volver"
    read -p "Selecciona una opcion [1-4]: " ropt
    case $ropt in
        1) report_today ;;
        2)
            read -p "Fecha (YYYY-MM-DD): " fecha
            report_for_date "$fecha"
            ;;
        3) report_weekly ;;
        4) return ;;
        *) echo "Opcion invalida." ;;
    esac
}

# Menú Interactivo
show_menu() {
    clear
    echo "====================================="
    echo "  Comprehensive System Monitor Menu  "
    echo "====================================="
    daemon_status
    echo "-------------------------------------"
    echo "1. Start Monitoring Daemon"
    echo "2. Stop Monitoring Daemon"
    echo "3. View Real-time Stats (Top Procs)"
    echo "4. Generate Report (daily/date/weekly)"
    echo "5. Check Alerts Immediately"
    echo "6. View Alert History"
    echo "7. Configure Alert Thresholds"
    echo "8. Exit"
    echo "====================================="
    read -p "Select an option [1-8]: " opt

    case $opt in
        1)
            start_daemon
            read -p "Press Enter to continue..."
            ;;
        2)
            stop_daemon
            read -p "Press Enter to continue..."
            ;;
        3)
            bash "$ADV_MONITOR" --top-procs
            read -p "Press Enter to continue..."
            ;;
        4)
            [ -f "$GEN_REPORT" ] && report_menu || echo "generate_report.sh not found."
            read -p "Press Enter to continue..."
            ;;
        5)
            bash "$ALERT_SYS"
            echo "Alert check completed."
            read -p "Press Enter to continue..."
            ;;
        6)
            cat "$HOME/system_monitor_logs/alerts.log" 2>/dev/null || echo "Log empty."
            read -p "Press Enter to continue..."
            ;;
        7)
            edit_config
            read -p "Press Enter to continue..."
            ;;
        8)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option."
            read -p "Press Enter to continue..."
            ;;
    esac
}

while true; do
    show_menu
done