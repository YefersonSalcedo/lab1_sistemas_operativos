#!/bin/bash

# Directorios de los scripts
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
ADV_MONITOR="$DIR/advanced_system_monitor.sh"
ALERT_SYS="$DIR/alert_system.sh"
GEN_REPORT="$DIR/generate_report.sh"

# Funciones de línea de comandos
case "$1" in
    --daemon)
        nohup bash "$ADV_MONITOR" --daemon > /dev/null 2>&1 &
        echo "Monitoring daemon started in background. PID: $!"
        exit 0
        ;;
    --report)
        bash "$GEN_REPORT"
        exit 0
        ;;
    --alert)
        bash "$ALERT_SYS"
        cat "$HOME/system_monitor_logs/alerts.log" 2>/dev/null || echo "No alerts generated yet."
        exit 0
        ;;
    --config)
        nano "$DIR/alert_system.sh" # Edición rápida de umbrales
        exit 0
        ;;
    -h|--help)
        echo "Usage: ./main_monitor.sh [--daemon | --report | --alert | --config]"
        exit 0
        ;;
esac

# Menú Interactivo
show_menu() {
    clear
    echo "====================================="
    echo "  Comprehensive System Monitor Menu  "
    echo "====================================="
    echo "1. Start Monitoring Daemon"
    echo "2. Stop Monitoring Daemon"
    echo "3. View Real-time Stats (Top Procs)"
    echo "4. Generate Daily Report"
    echo "5. Check Alerts Immediately"
    echo "6. View Alert History"
    echo "7. Configure Alert Thresholds"
    echo "8. Exit"
    echo "====================================="
    read -p "Select an option [1-8]: " opt

    case $opt in
        1)
            nohup bash "$ADV_MONITOR" --daemon > /dev/null 2>&1 &
            echo "Daemon started."
            read -p "Press Enter to continue..."
            ;;
        2)
            pkill -f "advanced_system_monitor.sh --daemon"
            echo "Daemon stopped."
            read -p "Press Enter to continue..."
            ;;
        3)
            bash "$ADV_MONITOR" --top-procs
            read -p "Press Enter to continue..."
            ;;
        4)
            [ -f "$GEN_REPORT" ] && bash "$GEN_REPORT" || echo "generate_report.sh not found."
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
            nano "$ALERT_SYS"
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