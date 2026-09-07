#!/bin/bash
#
# generate_report.sh
# Practica 1A - Sistemas Operativos - UdeA
# Tarea 3: Report Generation
#
# Que hace este script:
#   Lee el historico de metricas que genera advanced_system_monitor.sh
#   (~/system_monitor_logs/metrics.csv) y con eso construye un reporte
#   diario en 2 formatos: texto plano y CSV.
#
#   El reporte incluye:
#     1. Uptime del sistema y load average actual.
#     2. Pico de uso de memoria del dia y el timestamp en que ocurrio.
#     3. Top 5 procesos por uso de CPU (instantaneo, ver nota abajo).
#     4. Resumen de trafico de red total (MB enviados/recibidos) del dia.
#
# Uso:
#   ./generate_report.sh                 Reporte del dia de hoy
#   ./generate_report.sh --date <YYYY-MM-DD>   Reporte de una fecha especifica


LOG_DIR="$HOME/system_monitor_logs"
LOG_FILE="$LOG_DIR/metrics.csv"
REPORTS_DIR="$LOG_DIR/reports"

mkdir -p "$REPORTS_DIR"


# Manejo de argumentos: por defecto el reporte es del dia de hoy, pero se
# puede pedir el de otra fecha con --date YYYY-MM-DD
REPORT_DATE=$(date +"%Y-%m-%d")

if [ "$1" = "--date" ]; then
    if [ -z "$2" ]; then
        echo "Uso: $0 --date <YYYY-MM-DD>"
        exit 1
    fi
    REPORT_DATE="$2"
fi

if [ ! -f "$LOG_FILE" ]; then
    echo "No existe $LOG_FILE todavia. Corre primero advanced_system_monitor.sh --daemon."
    exit 1
fi


# Filtra del CSV solo las filas cuyo timestamp empieza con la fecha pedida.
# El timestamp tiene formato "YYYY-MM-DD HH:MM:SS", asi que basta con
# comparar los primeros 10 caracteres del campo 1 contra REPORT_DATE.
# Se guarda en un archivo temporal para no repetir el filtro en cada
# funcion (evita leer y filtrar el CSV completo varias veces).
FILTERED_TMP=$(mktemp)
trap 'rm -f "$FILTERED_TMP"' EXIT   # borra el temporal aunque el script falle o termine

awk -F',' -v d="$REPORT_DATE" 'NR==1 || substr($1,1,10)==d' "$LOG_FILE" > "$FILTERED_TMP"

# Numero de filas de datos (sin contar el encabezado)
SAMPLE_COUNT=$(( $(wc -l < "$FILTERED_TMP") - 1 ))

if [ "$SAMPLE_COUNT" -le 0 ]; then
    echo "No hay muestras registradas para la fecha $REPORT_DATE en $LOG_FILE."
    exit 1
fi


# 1. Uptime del sistema y load average.
#    "uptime" muestra algo como:
#      18:50:12 up 3 days,  2:14,  2 users,  load average: 0.12, 0.09, 0.05
get_uptime_info() {
    uptime
}



# 2. Pico de memoria del dia + timestamp en que ocurrio.
#    awk recorre las filas filtradas (NR>1 salta el encabezado) y se queda
#    con la fila cuyo mem_percent ($5) es el mayor visto hasta el momento.
#    "max" arranca en -1 para que la primera fila siempre lo reemplace.
get_peak_memory() {
    awk -F',' '
        NR>1 {
            if ($5+0 > max) { max=$5+0; ts=$1 }
        }
        END { printf "%.1f%%,%s", max, ts }
    ' "$FILTERED_TMP"
}

# 3. Top 5 procesos por CPU.
get_top_processes() {
    ps aux --sort=-%cpu | head -n 6
}


# 4. Trafico de red total del dia (MB enviados/recibidos).
#    net_rx_bytes y net_tx_bytes en el CSV son CONTADORES ACUMULADOS desde
#    que arranco la maquina (asi los reporta /proc/net/dev), no bytes "de
#    ese momento". Por eso el trafico del dia NO se suma fila por fila:
#    se calcula como la diferencia entre la ULTIMA y la PRIMERA muestra del
#    dia (bytes_final - bytes_inicial), y luego se convierte a MB
#    (1 MB = 1048576 bytes).
#
#    "head -2 | tail -1" toma la primera fila de datos (salta encabezado).
#    "tail -1" toma la ultima fila de datos.
get_network_summary() {
    local first_line last_line rx1 tx1 rx2 tx2 rx_mb tx_mb

    first_line=$(head -n 2 "$FILTERED_TMP" | tail -n 1)
    last_line=$(tail -n 1 "$FILTERED_TMP")

    rx1=$(echo "$first_line" | awk -F',' '{print $6}')
    tx1=$(echo "$first_line" | awk -F',' '{print $7}')
    rx2=$(echo "$last_line"  | awk -F',' '{print $6}')
    tx2=$(echo "$last_line"  | awk -F',' '{print $7}')

    rx_mb=$(awk -v a="$rx1" -v b="$rx2" 'BEGIN{d=b-a; if(d<0) d=0; printf "%.2f", d/1048576}')
    tx_mb=$(awk -v a="$tx1" -v b="$tx2" 'BEGIN{d=b-a; if(d<0) d=0; printf "%.2f", d/1048576}')

    printf "%s,%s" "$rx_mb" "$tx_mb"
}



# Se calculan una sola vez los valores que se van a
# reutilizar 
UPTIME_INFO=$(get_uptime_info)
PEAK_MEM_PCT=$(get_peak_memory | cut -d',' -f1)
PEAK_MEM_TS=$(get_peak_memory | cut -d',' -f2)
TOP_PROCS=$(get_top_processes)
NET_RX_MB=$(get_network_summary | cut -d',' -f1)
NET_TX_MB=$(get_network_summary | cut -d',' -f2)
GENERATED_AT=$(date +"%Y-%m-%d %H:%M:%S")


# Reporte en TEXTO PLANO
generate_text_report() {
    local out="$REPORTS_DIR/report_${REPORT_DATE}.txt"
    {
        echo "=================================================="
        echo " Reporte diario de recursos del sistema"
        echo " Fecha del reporte: $REPORT_DATE"
        echo " Generado el:       $GENERATED_AT"
        echo " Muestras analizadas: $SAMPLE_COUNT"
        echo "=================================================="
        echo
        echo "--- Uptime y load average (valor actual del sistema) ---"
        echo "$UPTIME_INFO"
        echo
        echo "--- Pico de memoria del dia ---"
        echo "Uso maximo de memoria: $PEAK_MEM_PCT"
        echo "Ocurrio a las:         $PEAK_MEM_TS"
        echo
        echo "--- Top 5 procesos por CPU (snapshot al generar el reporte) ---"
        echo "$TOP_PROCS"
        echo
        echo "--- Trafico de red total del dia ---"
        echo "Recibido (RX): ${NET_RX_MB} MB"
        echo "Enviado  (TX): ${NET_TX_MB} MB"
    } > "$out"
    echo "$out"
}

# Reporte en CSV
generate_csv_report() {
    local out="$REPORTS_DIR/report_${REPORT_DATE}.csv"
    {
        echo "campo,valor"
        echo "fecha_reporte,$REPORT_DATE"
        echo "generado_el,$GENERATED_AT"
        echo "muestras_analizadas,$SAMPLE_COUNT"
        echo "pico_memoria_pct,$PEAK_MEM_PCT"
        echo "pico_memoria_timestamp,$PEAK_MEM_TS"
        echo "red_rx_mb,$NET_RX_MB"
        echo "red_tx_mb,$NET_TX_MB"
    } > "$out"
    echo "$out"
}


# Punto de entrada: genera los 2 formatos y avisa donde quedaron.
txt_path=$(generate_text_report)
csv_path=$(generate_csv_report)

echo "Reporte generado para $REPORT_DATE ($SAMPLE_COUNT muestras):"
echo "  Texto: $txt_path"
echo "  CSV:   $csv_path"