#!/bin/bash

# ==============================================================================
# 🎬 ANIMEAV1 DOWN 2.5 - Descargador de Animes (Local PC)
# ==============================================================================
# - Compatible con: animeav1.com
# - Extracción automática y limpia del Nombre del Anime y Total de Episodios
# - Extracción directa de HLS Player (player.zilla-networks.com)
# - Selector de Calidad: Máxima (1080p/720p), Estándar (720p/540p), Ligera (480p)
# - Selección flexible de episodios: Todos, Rangos, Episodio Único o Lista (1,3,7...)
# - Descarga paralela optimizada con control de memoria RAM (semáforo de procesos)
# - Guardado local en tu PC: [Anime]/[Anime] - Episodio [XX].mp4
# ==============================================================================

# Colores de Terminal
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${BOLD}🎬 DESCARGADOR DE ANIMES - ANIMEAV1.COM v2.5 (LOCAL PC)${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""

# ==============================================================================
# 0. DETECTAR yt-dlp (Cualquier nombre y ruta)
# ==============================================================================

detectar_ytdlp() {
    local NOMBRES=("yt-dlp" "yt-dlp_linux" "yt-dlp_linux_aarch64" "yt-dlp.exe")
    for nombre in "${NOMBRES[@]}"; do
        if command -v "$nombre" &> /dev/null; then
            echo "$nombre"
            return 0
        fi
    done
    for path in /usr/local/bin /usr/bin ~/.local/bin "$HOME/bin" "$USERPROFILE/bin"; do
        for nombre in "${NOMBRES[@]}"; do
            if [ -f "$path/$nombre" ] && [ -x "$path/$nombre" ]; then
                echo "$path/$nombre"
                return 0
            fi
        done
    done
    return 1
}

YTDLP_CMD=$(detectar_ytdlp)

if [ -z "$YTDLP_CMD" ]; then
    if command -v yt-dlp_linux &> /dev/null; then
        echo -e "${AMARILLO}⚠️ Detectado yt-dlp_linux, creando enlace simbólico...${NC}"
        sudo ln -sf $(which yt-dlp_linux) /usr/local/bin/yt-dlp 2>/dev/null
        if [ $? -eq 0 ]; then
            YTDLP_CMD="yt-dlp"
        else
            mkdir -p ~/.local/bin
            ln -sf $(which yt-dlp_linux) ~/.local/bin/yt-dlp 2>/dev/null
            export PATH="$HOME/.local/bin:$PATH"
            if command -v yt-dlp &> /dev/null; then
                YTDLP_CMD="yt-dlp"
            fi
        fi
    fi
fi

if [ -z "$YTDLP_CMD" ]; then
    echo -e "${AMARILLO}⚠️ yt-dlp no encontrado en PATH, intentando descargar versión oficial...${NC}"
    mkdir -p ~/.local/bin
    curl -sL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o ~/.local/bin/yt-dlp 2>/dev/null
    chmod a+rx ~/.local/bin/yt-dlp 2>/dev/null
    export PATH="$HOME/.local/bin:$PATH"
    YTDLP_CMD=$(detectar_ytdlp)
fi

if [ -z "$YTDLP_CMD" ]; then
    echo -e "${ROJO}❌ No se encontró yt-dlp instalado${NC}"
    echo ""
    echo "   📥 Instalación rápida en Linux / VPS:"
    echo "   sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp"
    echo "   sudo chmod a+rx /usr/local/bin/yt-dlp"
    echo ""
    read -p "Presiona Enter para salir..."
    exit 1
fi

echo -e "${VERDE}✅ yt-dlp detectado: $YTDLP_CMD${NC}"
echo ""

# ==============================================================================
# 1. SOLICITAR DATOS Y EXTRACCIÓN AUTOMÁTICA DE METADATOS
# ==============================================================================

read -p "📎 Pega la URL del anime (ej: https://animeav1.com/media/tengen-toppa-gurren-lagann): " RAW_URL
RAW_URL=$(echo "$RAW_URL" | xargs)

# Normalizar URL: quitar barras finales y números de episodio si pegaron un episodio puntual
BASE_URL=$(echo "$RAW_URL" | sed 's:/*$::')
BASE_URL=$(echo "$BASE_URL" | sed -E 's:/[0-9]+$::')

echo -e "${CYAN}🔍 Analizando página y extrayendo información del anime...${NC}"

# Detectar intérprete de Python para extracción rápida
PYTHON_CMD="python"
if python --version &> /dev/null; then
    PYTHON_CMD="python"
elif python3 --version &> /dev/null; then
    PYTHON_CMD="python3"
fi

METADATA_EXTRACTED=$($PYTHON_CMD -c "
import urllib.request, re, sys

url = sys.argv[1]
headers = {'User-Agent': '$UA'}
try:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=12) as resp:
        html = resp.read().decode('utf-8', errors='ignore')
    
    # 1. Extraer título
    h1_m = re.search(r'<h1[^>]*>(.*?)</h1>', html, re.DOTALL | re.I)
    title_m = re.search(r'<title>(.*?)</title>', html, re.I)
    
    clean_title = ''
    if h1_m:
        clean_title = re.sub(r'<[^>]+>', '', h1_m.group(1)).strip()
    elif title_m:
        raw_t = title_m.group(1)
        clean_title = raw_t.split('Online')[0].replace('Ver ', '').replace('Sub Español', '').strip()
    
    if not clean_title:
        slug = url.rstrip('/').split('/')[-1]
        clean_title = slug.replace('-', ' ').title()
    
    clean_title = re.sub(r'[\\\\/*?:\"<>|]', '', clean_title).strip()

    # 2. Extraer total de episodios
    ep_links = re.findall(r'href=[\"\'][^\"\']+/(\d+)[\"\']', html)
    total_eps = 0
    if ep_links:
        total_eps = max([int(x) for x in ep_links if x.isdigit()])
    
    print(f'{clean_title}|{total_eps}')
except Exception:
    print('|0')
" "$BASE_URL" 2>/dev/null)

SERIES_DETECTADA=$(echo "$METADATA_EXTRACTED" | cut -d'|' -f1)
TOTAL_DETECTADO=$(echo "$METADATA_EXTRACTED" | cut -d'|' -f2)

# Fallback si no hubo extracción automática
if [ -z "$SERIES_DETECTADA" ]; then
    SLUG=$(echo "$BASE_URL" | sed 's:/*$::' | awk -F'/' '{print $NF}')
    SERIES_DETECTADA=$(echo "$SLUG" | tr '-' ' ' | sed -e 's/\b\(.\)/\u\1/g')
fi

# Confirmar / Editar Nombre
echo ""
echo -e "📺 Anime detectado: ${AZUL}${BOLD}$SERIES_DETECTADA${NC}"
read -p "¿Es correcto? (Enter para aceptar, o escribe el nombre correcto): " SERIES_INPUT
if [ -n "$SERIES_INPUT" ]; then
    SERIES_NAME="$SERIES_INPUT"
else
    SERIES_NAME="$SERIES_DETECTADA"
fi

# Confirmar / Editar Total de Episodios
if [ -n "$TOTAL_DETECTADO" ] && [ "$TOTAL_DETECTADO" -gt 0 ]; then
    echo -e "📊 Episodios detectados: ${AZUL}${BOLD}$TOTAL_DETECTADO${NC}"
    read -p "¿Es correcto? (Enter para aceptar, o escribe el total): " TOTAL_INPUT
    if [ -n "$TOTAL_INPUT" ]; then
        TOTAL_EP="$TOTAL_INPUT"
    else
        TOTAL_EP="$TOTAL_DETECTADO"
    fi
else
    read -p "📊 Número total de episodios de este anime: " TOTAL_EP
fi

# ==============================================================================
# 2. SELECCIÓN DE CALIDAD DE VIDEO
# ==============================================================================

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${BOLD}🎥 SELECCIÓN DE CALIDAD DE VIDEO${NC}"
echo -e "${CYAN}==========================================${NC}"
echo "1) 🌟 Máxima Calidad Disponible (1080p / 720p HD) [Recomendado]"
echo "2) 📺 Calidad Estándar (720p / 540p)"
echo "3) 📱 Calidad Ligera (480p / 360p)"
echo ""
read -p "Selecciona calidad [1]: " OPCION_CALIDAD

case $OPCION_CALIDAD in
    2)
        YTDLP_FORMAT="bestvideo[height<=720]+bestaudio/best[height<=720]/best"
        CALIDAD_NOMBRE="Estándar (720p/540p)"
        ;;
    3)
        YTDLP_FORMAT="bestvideo[height<=480]+bestaudio/best[height<=480]/worst"
        CALIDAD_NOMBRE="Ligera (480p/360p)"
        ;;
    *)
        YTDLP_FORMAT="bestvideo+bestaudio/best"
        CALIDAD_NOMBRE="Máxima Calidad (1080p/720p HD)"
        ;;
esac
echo -e "${VERDE}✅ Calidad seleccionada: $CALIDAD_NOMBRE${NC}"

# ==============================================================================
# 3. SELECCIÓN DE EPISODIOS (TODOS, RANGO, ÚNICO O LISTA)
# ==============================================================================

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${BOLD}🎯 SELECCIÓN DE EPISODIOS${NC}"
echo -e "${CYAN}==========================================${NC}"
echo "1) 📚 Todos los episodios ($TOTAL_EP)"
echo "2) 🎯 Rango específico (ej: 5-10)"
echo "3) 📌 Desde un episodio hasta el final (ej: 12-${TOTAL_EP})"
echo "4) 🎬 Solo un episodio (ej: 1)"
echo "5) 📋 Episodios específicos (ej: 1,3,7,12,24)"
echo ""
read -p "Selecciona una opción [1]: " OPCION_RANGO

LISTA_CAPITULOS=()

case $OPCION_RANGO in
    2)
        read -p "Ingresa el rango (ej: 5-10): " RANGO
        INICIO_RANGO=$(echo "$RANGO" | cut -d'-' -f1)
        FIN_RANGO=$(echo "$RANGO" | cut -d'-' -f2)
        for (( i=INICIO_RANGO; i<=FIN_RANGO; i++ )); do
            LISTA_CAPITULOS+=($i)
        done
        ;;
    3)
        read -p "Ingresa el episodio de inicio (ej: 12): " INICIO_RANGO
        FIN_RANGO=$TOTAL_EP
        echo "📌 Rango: $INICIO_RANGO al $FIN_RANGO"
        for (( i=INICIO_RANGO; i<=FIN_RANGO; i++ )); do
            LISTA_CAPITULOS+=($i)
        done
        ;;
    4)
        read -p "Ingresa el número de episodio: " INICIO_RANGO
        FIN_RANGO=$INICIO_RANGO
        echo "📌 Episodio único: $INICIO_RANGO"
        LISTA_CAPITULOS=($INICIO_RANGO)
        ;;
    5)
        read -p "Ingresa los episodios separados por coma (ej: 1,3,7,12): " CAPS_INPUT
        IFS=',' read -ra LISTA_CAPITULOS <<< "$CAPS_INPUT"
        LISTA_CAPITULOS=($(echo "${LISTA_CAPITULOS[@]}" | tr ' ' '\n' | sort -n | uniq))
        INICIO_RANGO=${LISTA_CAPITULOS[0]}
        FIN_RANGO=${LISTA_CAPITULOS[-1]}
        echo "📋 Episodios seleccionados: ${LISTA_CAPITULOS[*]}"
        ;;
    *)
        INICIO_RANGO=1
        FIN_RANGO=$TOTAL_EP
        echo "📚 Descargando todos los episodios: 1 al $TOTAL_EP"
        for (( i=1; i<=TOTAL_EP; i++ )); do
            LISTA_CAPITULOS+=($i)
        done
        ;;
esac

# Validación si array está vacío
if [ ${#LISTA_CAPITULOS[@]} -eq 0 ]; then
    INICIO_RANGO=1
    FIN_RANGO=$TOTAL_EP
    for (( i=1; i<=TOTAL_EP; i++ )); do
        LISTA_CAPITULOS+=($i)
    done
fi

CAPITULOS_A_DESCARGAR=${#LISTA_CAPITULOS[@]}
echo -e "${VERDE}✅ Se descargarán ${CAPITULOS_A_DESCARGAR} episodios: ${LISTA_CAPITULOS[*]}${NC}"

# ==============================================================================
# 4. MODO DE DESCARGA & CONTROL DE MEMORIA RAM (SEMÁFORO)
# ==============================================================================

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${BOLD}⚡ CONCURRENCIA & USO DE MEMORIA RAM${NC}"
echo -e "${CYAN}==========================================${NC}"
echo "1) 🐌 Secuencial (1 episodio a la vez - 0 consumo RAM)"
echo "2) ⚡ Equilibrado (3 episodios simultáneos - Recomendado)"
echo "3) 🚀 Rápido (5 episodios simultáneos - Mayor velocidad)"
echo "4) 🛠️  Personalizado"
echo ""
read -p "Selecciona modo [2]: " MODO_DESC

case $MODO_DESC in
    1)
        MAX_PARALELO=1
        MODO_NOMBRE="Secuencial (1 hilo)"
        ;;
    3)
        MAX_PARALELO=5
        MODO_NOMBRE="Rápido (5 hilos simultáneos)"
        ;;
    4)
        read -p "Ingresa número de descargas simultáneas (ej: 4): " MAX_PARALELO
        if [ -z "$MAX_PARALELO" ] || [ "$MAX_PARALELO" -lt 1 ]; then
            MAX_PARALELO=3
        fi
        MODO_NOMBRE="Personalizado ($MAX_PARALELO hilos simultáneos)"
        ;;
    *)
        MAX_PARALELO=3
        MODO_NOMBRE="Equilibrado (3 hilos simultáneos)"
        ;;
esac

# Resumen de configuración
echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${BOLD}📋 RESUMEN DE CONFIGURACIÓN${NC}"
echo -e "${CYAN}==========================================${NC}"
echo -e "📺 Anime:        ${VERDE}$SERIES_NAME${NC}"
echo -e "📊 Episodios:    ${VERDE}$CAPITULOS_A_DESCARGAR de $TOTAL_EP (${LISTA_CAPITULOS[*]})${NC}"
echo -e "🎥 Calidad:      ${VERDE}$CALIDAD_NOMBRE${NC}"
echo -e "⚡ Modo:         ${VERDE}$MODO_NOMBRE${NC}"
echo -e "🌐 Fuente:       ${VERDE}AnimeAV1 (HLS Zilla-Networks)${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

read -p "¿Iniciar descarga? (s/N): " CONFIRMAR
if [[ ! "$CONFIRMAR" =~ ^[sS]$ ]]; then
    echo "❌ Cancelado por el usuario"
    exit 0
fi

# ==============================================================================
# 5. EXTRAER ENLACES HLS DE CADA EPISODIO
# ==============================================================================

TEMP_FILE="/tmp/urls_animeav1_$$.txt"
ERROR_LOG="/tmp/errores_animeav1_$$.txt"

# Fallback si /tmp no existe en Windows Git Bash / entorno local
if [ ! -d "/tmp" ]; then
    TEMP_FILE="./.urls_animeav1_$$.txt"
    ERROR_LOG="./.errores_animeav1_$$.txt"
fi

> "$TEMP_FILE"
> "$ERROR_LOG"

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${BOLD}🔍 EXTRAYENDO ENLACES HLS DE EPISODIOS${NC}"
echo -e "${CYAN}==========================================${NC}"

for EP in "${LISTA_CAPITULOS[@]}"; do
    echo -n "Episodio $EP: "
    EP_URL="${BASE_URL}/${EP}"
    HTML=$(curl -s -L -A "$UA" "$EP_URL" 2>/dev/null)
    
    # 1. Buscar ID del reproductor en zilla-networks
    PLAYER_ID=$(echo "$HTML" | grep -oP 'player\.zilla-networks\.com/play/\K[a-f0-9]+' | head -1)
    if [ -z "$PLAYER_ID" ]; then
        PLAYER_ID=$(echo "$HTML" | grep -oP 'zilla-networks\.com/(?:play|m3u8)/\K[a-f0-9]+' | head -1)
    fi
    
    if [ -n "$PLAYER_ID" ]; then
        # URL HLS directa del reproductor
        M3U8_URL="https://player.zilla-networks.com/m3u8/${PLAYER_ID}"
        echo -e " ${VERDE}✅ Encontrado (ID: ${PLAYER_ID:0:12}...)${NC}"
        echo "$EP|$M3U8_URL" >> "$TEMP_FILE"
    else
        # Fallback si hay enlace m3u8 directo en la página
        DIRECT_M3U8=$(echo "$HTML" | grep -oP 'https?://[^\s"'\''<>]+\.m3u8[^\s"'\''<>]*' | head -1)
        if [ -n "$DIRECT_M3U8" ]; then
            DIRECT_M3U8=$(echo "$DIRECT_M3U8" | sed 's/\\u0026/\&/g')
            echo -e " ${VERDE}✅ Enlace M3U8 alternativo encontrado${NC}"
            echo "$EP|$DIRECT_M3U8" >> "$TEMP_FILE"
        else
            echo -e " ${ROJO}❌ NO ENCONTRADO${NC}"
            echo "Episodio $EP: No se encontró reproductor HLS" >> "$ERROR_LOG"
        fi
    fi
    
    sleep 0.2
done

ENCONTRADOS=$(grep -c '|https' "$TEMP_FILE" 2>/dev/null || echo 0)
FALLIDOS=$((CAPITULOS_A_DESCARGAR - ENCONTRADOS))

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${BOLD}📊 RESULTADO DE EXTRACCIÓN${NC}"
echo -e "${CYAN}==========================================${NC}"
echo -e "${VERDE}✅ Encontrados: $ENCONTRADOS/$CAPITULOS_A_DESCARGAR${NC}"
if [ $FALLIDOS -gt 0 ]; then
    echo -e "${ROJO}❌ Fallidos: $FALLIDOS${NC}"
    cat "$ERROR_LOG"
fi
echo -e "${CYAN}==========================================${NC}"

if [ "$ENCONTRADOS" -eq 0 ]; then
    echo ""
    echo -e "${ROJO}❌ No se encontraron enlaces HLS disponibles. Abortando.${NC}"
    rm -f "$TEMP_FILE" "$ERROR_LOG"
    exit 1
fi

# ==============================================================================
# 6. DESCARGAR EPISODIOS CON CONTROL DE RAM (SEMÁFORO)
# ==============================================================================

OUTPUT_DIR="./$SERIES_NAME"
if [ "$OPCION_RANGO" = "5" ]; then
    NOMBRE_CAPS=$(echo "${LISTA_CAPITULOS[@]}" | tr ' ' '-')
    OUTPUT_DIR="${OUTPUT_DIR}_eps-${NOMBRE_CAPS}"
elif [ "$INICIO_RANGO" != "1" ] || [ "$FIN_RANGO" != "$TOTAL_EP" ]; then
    OUTPUT_DIR="${OUTPUT_DIR}_ep${INICIO_RANGO}-${FIN_RANGO}"
fi
mkdir -p "$OUTPUT_DIR"

echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "🚀 ${BOLD}INICIANDO DESCARGAS${NC}"
echo -e "📁 Carpeta destino: ${VERDE}$OUTPUT_DIR${NC}"
echo -e "⚡ Modo:            ${VERDE}$MODO_NOMBRE${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FALLIDOS_FILE="fallidos_${TIMESTAMP}.txt"
> "$FALLIDOS_FILE"

INICIO=$(date +%s)

# Función de descarga individual
descargar_episodio() {
    local ep=$1
    local url=$2
    local ep_pad=$(printf "%02d" $ep)
    local archivo_salida="$OUTPUT_DIR/${SERIES_NAME} - Episodio ${ep_pad}.mp4"

    echo -e "📥 [Episodio $ep] Descargando..."

    $YTDLP_CMD \
        -o "$archivo_salida" \
        --no-playlist \
        --force-overwrites \
        --no-warnings \
        --user-agent "$UA" \
        --referer "https://player.zilla-networks.com/" \
        --add-header "Origin: https://player.zilla-networks.com" \
        -f "$YTDLP_FORMAT" \
        --retries 5 \
        --fragment-retries 5 \
        --concurrent-fragments 4 \
        --buffer-size 16M \
        "$url" > /dev/null 2>&1

    if [ $? -eq 0 ] && [ -f "$archivo_salida" ]; then
        echo -e " ${VERDE}✅ [Episodio $ep] Completado${NC}"
    else
        echo -e " ${ROJO}❌ [Episodio $ep] Falló la descarga${NC}"
        echo "$ep|$url" >> "$FALLIDOS_FILE"
    fi
}

export -f descargar_episodio 2>/dev/null
export OUTPUT_DIR SERIES_NAME UA YTDLP_FORMAT FALLIDOS_FILE YTDLP_CMD

if [ "$MAX_PARALELO" -eq 1 ]; then
    # Modo Secuencial
    while IFS='|' read -r EP_NUM M3U8_URL; do
        EP_PAD=$(printf "%02d" $EP_NUM)
        echo ""
        echo -e "📥 ${BOLD}Descargando Episodio $EP_NUM...${NC}"
        
        $YTDLP_CMD \
            -o "$OUTPUT_DIR/${SERIES_NAME} - Episodio ${EP_PAD}.mp4" \
            --no-playlist \
            --force-overwrites \
            --progress \
            --user-agent "$UA" \
            --referer "https://player.zilla-networks.com/" \
            --add-header "Origin: https://player.zilla-networks.com" \
            -f "$YTDLP_FORMAT" \
            --retries 5 \
            --fragment-retries 5 \
            --concurrent-fragments 4 \
            --buffer-size 16M \
            "$M3U8_URL"
        
        if [ $? -eq 0 ]; then
            echo -e "${VERDE}✅ Episodio $EP_NUM completado${NC}"
        else
            echo -e "${ROJO}❌ Falló episodio $EP_NUM${NC}"
            echo "$EP_NUM|$M3U8_URL" >> "$FALLIDOS_FILE"
        fi
    done < "$TEMP_FILE"
else
    # Modo Paralelo Controlado (Semáforo de RAM)
    echo -e "⚡ Descargando $ENCONTRADOS episodios (Máximo $MAX_PARALELO simultáneos para cuidar la RAM)..."
    echo ""
    
    while IFS='|' read -r EP_NUM M3U8_URL; do
        while [ $(jobs -r -p 2>/dev/null | wc -l) -ge $MAX_PARALELO ]; do
            sleep 0.5
        done
        
        descargar_episodio "$EP_NUM" "$M3U8_URL" &
    done < "$TEMP_FILE"
    
    # Esperar a que todos los hilos terminen
    wait
fi

FIN=$(date +%s)
TIEMPO=$((FIN - INICIO))
MINUTOS=$((TIEMPO / 60))
SEGUNDOS=$((TIEMPO % 60))

FALLIDOS_DESC=0
if [ -f "$FALLIDOS_FILE" ]; then
    FALLIDOS_DESC=$(wc -l < "$FALLIDOS_FILE" 2>/dev/null || echo 0)
    if [ "$FALLIDOS_DESC" -eq 0 ]; then
        rm -f "$FALLIDOS_FILE"
    fi
fi

# Limpieza de temporales
rm -f "$TEMP_FILE" "$ERROR_LOG"

# ==============================================================================
# 7. RESUMEN FINAL
# ==============================================================================

echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "🎉 ${BOLD}DESCARGA FINALIZADA${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "${VERDE}✅ Descargados exitosamente: $((ENCONTRADOS - FALLIDOS_DESC))/$ENCONTRADOS${NC}"
if [ "$FALLIDOS_DESC" -gt 0 ]; then
    echo -e "${ROJO}❌ Fallidos: $FALLIDOS_DESC${NC}"
    echo -e "📁 Revisa la lista de reintentos en: ${AMARILLO}$FALLIDOS_FILE${NC}"
fi
echo -e "📁 Ubicación en tu PC: ${VERDE}$OUTPUT_DIR${NC}"
echo -e "⏱️  Tiempo total:      ${VERDE}${MINUTOS}m ${SEGUNDOS}s${NC}"

if [ -d "$OUTPUT_DIR" ]; then
    TAMANO=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
    if [ -n "$TAMANO" ]; then
        echo -e "💾 Espacio en disco:   ${AZUL}$TAMANO${NC}"
    fi
fi
echo -e "${CYAN}================================================================${NC}"
echo ""
read -p "Presiona Enter para salir..."
