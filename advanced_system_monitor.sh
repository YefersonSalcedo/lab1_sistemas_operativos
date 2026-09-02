#!/bin/bash
#
# advanced_system_monitor.sh
# Practica 1A - Sistemas Operativos - UdeA
# Tarea 1: Core Script Enhancement
#
# Que hace este script:
#   1. Recolecta metricas de CPU, memoria y red periodicamente y las guarda
#      en un archivo CSV (esto es lo que hace el modo "--daemon").
#   2. Ofrece funciones de analisis sobre esos datos historicos: promedio
#      de memoria, top de procesos, deteccion de posible fuga de memoria.
#   3. Ofrece funciones de monitoreo de red mas detallado: ancho de banda
#      por interfaz, conexiones activas y errores/paquetes perdidos.
#
# Uso:
#   ./advanced_system_monitor.sh --daemon              Inicia captura continua (cada 5 min)
#   ./advanced_system_monitor.sh --avg-mem <minutos>   Promedio de memoria en los ultimos N minutos
#   ./advanced_system_monitor.sh --top-procs           Top 5 procesos por CPU y por memoria
#   ./advanced_system_monitor.sh --check-leak          Compara memoria actual vs promedio de 1h
#   ./advanced_system_monitor.sh --bandwidth           Ancho de banda por interfaz (KB/s)
#   ./advanced_system_monitor.sh --connections         Conexiones de red activas (ESTABLISHED)
#   ./advanced_system_monitor.sh --net-errors          Revisa errores/paquetes perdidos por interfaz


# $HOME es una variable de entorno que apunta a la carpeta personal del usuario
# La usamos en vez de una ruta fija para que el script
# funcione igual sin importar que usuario lo ejecute.
LOG_DIR="$HOME/system_monitor_logs"

# Archivo donde se guarda el historial de metricas en formato CSV
# (una fila por cada vez que se mide CPU/memoria/red)
LOG_FILE="$LOG_DIR/metrics.csv"

# Cada cuantos segundos se toma una medicion en modo daemon.
INTERVAL=300 # 300 segundos = 5 minutos

# mkdir -p crea la carpeta si no existe, y NO da error si ya existe
mkdir -p "$LOG_DIR"


# Crea el archivo CSV con su encabezado (nombres de columna) SOLO si el
# archivo todavia no existe. Esto evita que cada vez que arranquemos el
# daemon se borre el historial que ya teniamos.
init_log_file() {
    # [ ! -f "$LOG_FILE" ] es verdadero si el archivo NO existe (-f prueba "es un archivo regular"; ! lo niega).
    if [ ! -f "$LOG_FILE" ]; then
        echo "timestamp,cpu_percent,mem_used_mb,mem_total_mb,mem_percent,net_rx_bytes,net_tx_bytes" > "$LOG_FILE"
    fi
}


# Devuelve el porcentaje de CPU usado por procesos de usuario en este instante.
# Como funciona el pipeline:
#   top -bn1          -> ejecuta "top" en modo batch (-b, sin interfaz grafica)
#                        y solo UNA vez (-n1), en vez de refrescar cada 3s.
#   grep "Cpu(s)"     -> de toda la salida de top, nos quedamos solo con la
#                        linea que resume el uso de CPU. Se ve asi:
#                        %Cpu(s):  0.0 us,  0.0 sy,  0.0 ni,100.0 id, ...
#   awk -F'[,:]' '{print $2}'
#                     -> separa esa linea usando "," O ":" como delimitador
#                        (el patron [,:] entre corchetes es una clase de
#                        caracteres: "cualquiera de estos dos simbolos").
#                        Eso deja el campo 2 como "  0.0 us" (el %us, uso
#                        de usuario).
#   awk '{print $1}'  -> de "  0.0 us" nos quedamos solo con el numero "0.0",
#                        descartando la etiqueta "us".
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk -F'[,:]' '{print $2}' | awk '{print $1}'
}


# Devuelve "mem_usada_mb,mem_total_mb,porcentaje" en un solo string separado
# por comas, listo para pegarse directo en una fila del CSV.
#
# "free -m" muestra la memoria en megabytes, con una salida asi:
#                total        used        free      shared  buff/cache   available
#   Mem:          7844        1363        ...
#   Swap:            0           0           0
#
# awk '/Mem:/ {...}' busca la linea que EMPIEZA con "Mem:" (ignora la de Swap)
# y de esa linea usa:
#   $2 = total, $3 = used
# El porcentaje se calcula como (usado/total)*100, con %.1f para redondear
# a 1 decimal.
get_memory_usage() {
    free -m | awk '/Mem:/ {printf "%d,%d,%.1f", $3, $2, ($3/$2)*100}'
}


# Suma los bytes recibidos (RX) y enviados (TX) de TODAS las interfaces de
# red, EXCEPTO "lo" (loopback, la interfaz virtual 127.0.0.1 que no es
# trafico "real" hacia afuera de la maquina).
get_network_usage() {
    awk 'NR>2 && $1!~/lo:/ {rx+=$2; tx+=$10} END {print rx","tx}' /proc/net/dev
}


# Junta una medicion de CPU + memoria + red y la agrega como una nueva fila
# al final del CSV (>> agrega al final, a diferencia de > que sobreescribe
# todo el archivo).
log_metrics() {
    local ts cpu mem net
    ts=$(date +"%Y-%m-%d %H:%M:%S")   # timestamp legible, ej: 2026-09-01 18:48:44
    cpu=$(get_cpu_usage)
    mem=$(get_memory_usage)
    net=$(get_network_usage)
    echo "$ts,$cpu,$mem,$net" >> "$LOG_FILE"
}


# Modo "demonio": corre en primer plano en un bucle infinito, tomando una
# medicion y luego durmiendo $INTERVAL segundos, una y otra vez.
#
# (Un demonio "de verdad" corre en segundo plano incluso si cierras la
# terminal; aqui lo dejamos simple y en primer plano para la practica
run_daemon() {
    init_log_file
    echo "Monitor iniciado. Registrando en $LOG_FILE cada $((INTERVAL/60)) minutos."
    while true; do
        log_metrics
        sleep "$INTERVAL"
    done
}


# Calcula el promedio de la columna mem_percent del CSV, pero SOLO para las
# filas cuyo timestamp cae dentro de los ultimos N minutos.
#
# Como nuestro timestamp tiene el formato "YYYY-MM-DD HH:MM:SS",
# se puede COMPARAR COMO TEXTO (con >=) y el resultado es el mismo que
# compararlo cronologicamente. Esto funciona porque ese formato va de la
# unidad mas grande (año) a la mas chica (segundos), igual que el orden
# alfabetico de los caracteres.
#
# Pasos:
#   1. "date -d '-N minutes' ..." calcula que timestamp habia hace N minutos
#      (el "punto de corte" o cutoff).
#   2. awk recorre el CSV (NR>1 salta el encabezado) y para cada fila cuyo
#      timestamp ($1) sea mayor o igual al cutoff, suma su mem_percent ($5)
#      y cuenta cuantas filas entraron.
#   3. En el bloque END calculamos el promedio (sum/count).
avg_memory() {
    local minutes="$1" cutoff
    if [ -z "$minutes" ]; then
        echo "Uso: $0 --avg-mem <minutos>"
        exit 1
    fi
    if [ ! -f "$LOG_FILE" ]; then
        echo "No hay datos en $LOG_FILE todavia."
        exit 1
    fi

    cutoff=$(date -d "-${minutes} minutes" +"%Y-%m-%d %H:%M:%S")

    awk -F',' -v cutoff="$cutoff" -v mins="$minutes" '
        NR>1 && $1 >= cutoff { sum+=$5; count++ }
        END {
            if (count>0) printf "Promedio de memoria (ultimos %s min): %.2f%% (%d muestras)\n", mins, sum/count, count
            else print "No hay muestras en el rango solicitado."
        }
    ' "$LOG_FILE"
}


# Muestra el top 5 de procesos por uso de CPU y el top 5 por uso de memoria,
# en el instante actual (esto NO usa el historico del CSV, es una foto del
# momento).
#
# "ps aux" lista todos los procesos del sistema con detalle.
# "--sort=-%cpu" los ordena de mayor a menor %CPU (el signo "-" antes del
# nombre de columna significa orden descendente; sin el "-" seria ascendente).
# "head -n 6" se queda con las primeras 6 lineas: la de encabezado (USER PID
# %CPU ...) mas los 5 procesos con mayor uso.
top_procs() {
    echo "== Top 5 procesos por CPU =="
    ps aux --sort=-%cpu | head -n 6
    echo
    echo "== Top 5 procesos por Memoria =="
    ps aux --sort=-%mem | head -n 6
}


# Detecta una posible "fuga de memoria" comparando el uso de memoria ACTUAL
# contra el promedio de la ULTIMA HORA en el historico.
#
# Logica: si el uso actual esta muy por encima (mas de $threshold puntos
# porcentuales) del promedio reciente, es una señal de que algo esta
# consumiendo memoria de mas y no la esta liberando -> posible fuga.
#
# threshold=15 es un valor arbitrario para esta practica; en un sistema real
# se ajustaria segun el comportamiento normal de la aplicacion que se este
# monitoreando.
check_leak() {
    local current_mem cutoff avg_mem threshold diff is_leak
    if [ ! -f "$LOG_FILE" ]; then
        echo "No hay datos en $LOG_FILE todavia."
        exit 1
    fi

    # get_memory_usage devuelve "usado,total,porcentaje" -> nos quedamos
    # solo con el 3er campo (porcentaje) usando "cut -d',' -f3"
    current_mem=$(get_memory_usage | cut -d',' -f3)

    cutoff=$(date -d "-60 minutes" +"%Y-%m-%d %H:%M:%S")
    avg_mem=$(awk -F',' -v cutoff="$cutoff" '
        NR>1 && $1 >= cutoff { sum+=$5; count++ }
        END { if (count>0) printf "%.2f", sum/count; else print "0" }
    ' "$LOG_FILE")

    threshold=15  # puntos porcentuales de diferencia para considerar fuga

    echo "Memoria actual: ${current_mem}% | Promedio ultima hora: ${avg_mem}%"

    # Bash no sabe hacer aritmetica con decimales (0.0, 17.11, etc.), por eso
    # usamos "awk BEGIN{...}" como una mini-calculadora para restar y comparar
    # numeros con decimales.
    diff=$(awk -v a="$current_mem" -v b="$avg_mem" 'BEGIN{printf "%.2f", a-b}')
    is_leak=$(awk -v d="$diff" -v t="$threshold" 'BEGIN{print (d>t)?"1":"0"}')

    if [ "$is_leak" = "1" ]; then
        echo "ALERTA: posible fuga de memoria (uso actual ${diff} puntos por encima del promedio de 1h)"
    else
        echo "Uso de memoria dentro de rango normal."
    fi
}


# Calcula cuantos KB/s se estan recibiendo (RX) y enviando (TX) en CADA
# interfaz de red por separado (a diferencia de get_network_usage, que suma
# todo en un solo numero).
#
# La unica forma de medir una "velocidad" (KB por SEGUNDO) es comparar dos
# mediciones de bytes TOTALES separadas en el tiempo y dividir la diferencia
# entre el tiempo transcurrido. Por eso el script:
#   1. Toma una foto de los contadores de bytes de cada interfaz (rx1/tx1).
#   2. Espera exactamente 1 segundo (sleep 1).
#   3. Toma una segunda foto (rx2/tx2).
#   4. La diferencia (bytes2 - bytes1) dividida por 1 segundo = bytes/seg,
#      y dividiendo entre 1024 lo pasamos a KB/s.
bandwidth_per_interface() {
    declare -A rx1 tx1

    while read -r line; do
        local iface
    
        iface=$(echo "$line" | awk -F: '{print $1}' | tr -d ' ')
        [ -z "$iface" ] && continue      # linea vacia -> saltar
        [ "$iface" = "lo" ] && continue  # loopback -> saltar

        rx1[$iface]=$(echo "$line" | awk -F: '{print $2}' | awk '{print $1}')
        tx1[$iface]=$(echo "$line" | awk -F: '{print $2}' | awk '{print $9}')
    done < <(tail -n +3 /proc/net/dev)

    sleep 1

    printf "%-14s %-12s %-12s\n" "Interfaz" "RX (KB/s)" "TX (KB/s)"
    while read -r line; do
        local iface rx2 tx2 rx_rate tx_rate
        iface=$(echo "$line" | awk -F: '{print $1}' | tr -d ' ')
        [ -z "$iface" ] && continue
        [ "$iface" = "lo" ] && continue

        rx2=$(echo "$line" | awk -F: '{print $2}' | awk '{print $1}')
        tx2=$(echo "$line" | awk -F: '{print $2}' | awk '{print $9}')

        rx_rate=$(( (rx2 - ${rx1[$iface]:-0}) / 1024 ))
        tx_rate=$(( (tx2 - ${tx1[$iface]:-0}) / 1024 ))

        printf "%-14s %-12s %-12s\n" "$iface" "$rx_rate" "$tx_rate"
    done < <(tail -n +3 /proc/net/dev)
}


# Muestra las conexiones de red que estan en estado ESTABLISHED (una
# conexion TCP ya negociada y activa, no simplemente "escuchando").
active_connections() {
    echo "== Conexiones ESTABLISHED =="
    ss -tan state established | tail -n +2
    echo
    echo "Total ESTABLISHED: $(ss -tan state established | tail -n +2 | wc -l)"
}


# Revisa, para cada interfaz (menos "lo"), si /proc/net/dev reporta algun
# error o paquete perdido, y si encuentra algo lo agrega a un log aparte.
#
# Columnas relevantes de /proc/net/dev (recordando el mapa de mas arriba):
#   $4  = rx_err  (paquetes recibidos con error)
#   $5  = rx_drop (paquetes recibidos y descartados, ej: buffer lleno)
#   $12 = tx_err  (paquetes enviados con error)
#   $13 = tx_drop (paquetes enviados y descartados)
NET_ERR_LOG="$LOG_DIR/network_errors.log"
check_network_errors() {
    local ts found
    ts=$(date +"%Y-%m-%d %H:%M:%S")

    found=$(awk -v ts="$ts" 'NR>2 && $1!~/lo:/ {
        gsub(":", "", $1)
        rx_err=$4; rx_drop=$5; tx_err=$12; tx_drop=$13
        if (rx_err+rx_drop+tx_err+tx_drop > 0) {
            printf "%s,%s,rx_err=%s,rx_drop=%s,tx_err=%s,tx_drop=%s\n", ts, $1, rx_err, rx_drop, tx_err, tx_drop
        }
    }' /proc/net/dev)

    # -n "$found" es verdadero si la variable NO esta vacia, es decir, si
    # awk SI encontro errores/paquetes perdidos en alguna interfaz.
    if [ -n "$found" ]; then
        echo "$found" | tee -a "$NET_ERR_LOG"
    else
        echo "Sin errores ni paquetes perdidos detectados ($ts)."
    fi
}


# PUNTO DE ENTRADA DEL SCRIPT
# "$1" es el primer argumento con el que se llamo al script
# (ej: en "./advanced_system_monitor.sh --daemon", $1 vale "--daemon").
# El "case" funciona como un switch: compara "$1" contra cada patron y
# ejecuta la funcion correspondiente a la opcion que el usuario pidio.
# "*)" es el caso por defecto, cuando no coincide con ninguna opcion valida.
case "$1" in
    --daemon)
        run_daemon
        ;;
    --avg-mem)
        avg_memory "$2"
        ;;
    --top-procs)
        top_procs
        ;;
    --check-leak)
        check_leak
        ;;
    --bandwidth)
        bandwidth_per_interface
        ;;
    --connections)
        active_connections
        ;;
    --net-errors)
        check_network_errors
        ;;
    *)
        echo "Uso: $0 --daemon | --avg-mem <minutos> | --top-procs | --check-leak | --bandwidth | --connections | --net-errors"
        exit 1
        ;;
esac