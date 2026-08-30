#!/bin/bash

# ==============================================================================
# 🎬 RAVEDOWN 2.5 - Descargador de Temporadas Completas (Local PC)
# ==============================================================================
# - Extracción limpia y precisa de Nombres y Temporadas (sin IDs ni basura)
# - Selección de Calidad: 720p (HD/SD) / 540p (LD) / 360p (FD)
# - Descargas simultáneas con control de RAM (semáforo de procesos en paralelo)
# - Guardado local en tu PC: [Serie]/Season [XX]/[Serie] - S[XX]E[YY].mp4
# - Compatible con: cuevana4br, peliculaplay, flixlat, solo-latino, etc.
# ==============================================================================

# Colores de Terminal
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

UA="Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${BOLD}🎬 DESCARGADOR DE TEMPORADAS - RAVEDOWN 2.5 (LOCAL PC)${NC}"
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

# Si no encontró yt-dlp, intentar crear enlace o descargar
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
# 1. SOLICITAR DATOS Y EXTRACCIÓN LIMPIA DE METADATOS
# ==============================================================================

read -p "📎 Pega la URL completa de la temporada: " BASE_URL
BASE_URL=$(echo "$BASE_URL" | xargs)

# Detectar plataforma
if echo "$BASE_URL" | grep -q "cuevana4br.com"; then
    PLATAFORMA="Cuevana4BR"
    echo -e "${VERDE}✅ Plataforma detectada: Cuevana4BR${NC}"
elif echo "$BASE_URL" | grep -q "peliculaplay.com"; then
    PLATAFORMA="PeliculaPlay"
    echo -e "${VERDE}✅ Plataforma detectada: PeliculaPlay${NC}"
elif echo "$BASE_URL" | grep -q "flixlat.com"; then
    PLATAFORMA="FlixLat"
    echo -e "${VERDE}✅ Plataforma detectada: FlixLat${NC}"
elif echo "$BASE_URL" | grep -q "solo-latino.com"; then
    PLATAFORMA="Solo-Latino"
    echo -e "${VERDE}✅ Plataforma detectada: Solo-Latino${NC}"
else
    PLATAFORMA="Genérico"
    echo -e "${AMARILLO}⚠️ Plataforma no identificada, usando extractor universal${NC}"
fi

echo -e "${CYAN}🔍 Analizando página y extrayendo metadatos limpios...${NC}"

# Extracción limpia con Python integrado (o fallback regex)
PYTHON_CMD="python"
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
fi

METADATA_EXTRACTED=$($PYTHON_CMD -c "
import urllib.request, re, json, sys

url = sys.argv[1]
headers = {'User-Agent': '$UA'}
try:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=12) as resp:
        html = resp.read().decode('utf-8', errors='ignore')
    
    raw_name = ''
    season_num = None
    total_eps = 0

    m = re.search(r'<script id=\"__NEXT_DATA__\"[^>]*>(.*?)</script>', html, re.DOTALL)
    if m:
        data = json.loads(m.group(1))
        props = data.get('props', {}).get('pageProps', {})
        raw_name = props.get('name') or props.get('drama', {}).get('name', '')
        curr_season = props.get('currentSeason', {})
        eps = curr_season.get('episodes', [])
        if eps:
            total_eps = len(eps)

    # Detectar temporada
    if raw_name:
        m_s = re.search(r'(?:temporada|season)\s*(\d+)', raw_name, re.I) or re.search(r'(\d+)(?:st|nd|rd|th)?\s*season', raw_name, re.I)
        if m_s:
            season_num = int(m_s.group(1))
    
    if season_num is None:
        m_s2 = re.search(r'(\d+)(?:st|nd|rd|th)?[-_]season', url, re.I) or re.search(r'season[-_](\d+)', url, re.I) or re.search(r'temporada[-_](\d+)', url, re.I)
        if m_s2:
            season_num = int(m_s2.group(1))
    
    if season_num is None:
        season_num = 1

    # Limpiar nombre base
    clean_name = raw_name
    if not clean_name:
        slug = url.rstrip('/').split('/')[-1]
        slug = re.sub(r'^[a-zA-Z0-9]{10,40}-', '', slug)
        clean_name = slug.replace('-', ' ').title()

    clean_name = re.sub(r'[\s\-_]+(?:temporada|season)\s*\d+.*$', '', clean_name, flags=re.I)
    clean_name = re.sub(r'[\s\-_]+\d+(?:st|nd|rd|th)?\s*season.*$', '', clean_name, flags=re.I)
    clean_name = re.sub(r'[\\\\/*?:\"<>|]', '', clean_name).strip()

    if total_eps == 0:
        ep_links = re.findall(r'href=[\"\'][^\"\']+/(\d+)[\"\']', html)
        if ep_links:
            ep_ints = [int(x) for x in ep_links if x.isdigit()]
            if ep_ints:
                total_eps = max(ep_ints)

    print(f'{clean_name}|{season_num}|{total_eps}')
except Exception:
    print('||0')
" "$BASE_URL" 2>/dev/null)

SERIES_DETECTADA=$(echo "$METADATA_EXTRACTED" | cut -d'|' -f1)
SEASON_DETECTADA=$(echo "$METADATA_EXTRACTED" | cut -d'|' -f2)
TOTAL_DETECTADO=$(echo "$METADATA_EXTRACTED" | cut -d'|' -f3)

# Fallback si Python no estuvo disponible
if [ -z "$SERIES_DETECTADA" ]; then
    SLUG=$(echo "$BASE_URL" | sed 's:/*$::' | awk -F'/' '{print $NF}')
    SLUG_LIMPIO=$(echo "$SLUG" | sed -E 's/^[a-zA-Z0-9]{10,40}-//' | sed 's/-/ /g')
    SERIES_DETECTADA="$SLUG_LIMPIO"
fi
if [ -z "$SEASON_DETECTADA" ] || [ "$SEASON_DETECTADA" = "0" ]; then
    SEASON_DETECTADA=$(echo "$BASE_URL" | grep -oP 'Season-(\d+)' | grep -oP '\d+')
    if [ -z "$SEASON_DETECTADA" ]; then
        SEASON_DETECTADA=1
    fi
fi
if [ -z "$TOTAL_DETECTADO" ] || [ "$TOTAL_DETECTADO" = "0" ]; then
    TOTAL_DETECTADO=""
fi

# Confirmar / Editar Nombre
echo ""
echo -e "📺 Serie detectada: ${AZUL}${BOLD}$SERIES_DETECTADA${NC}"
read -p "¿Es correcto? (Enter para aceptar, o escribe el nombre correcto): " SERIES_INPUT
if [ -n "$SERIES_INPUT" ]; then
    SERIES_NAME="$SERIES_INPUT"
else
    SERIES_NAME="$SERIES_DETECTADA"
fi

# Confirmar / Editar Temporada
echo -e "🔢 Temporada detectada: ${AZUL}${BOLD}$SEASON_DETECTADA${NC}"
read -p "¿Es correcto? (Enter para aceptar, o escribe el número correcto): " SEASON_INPUT
if [ -n "$SEASON_INPUT" ]; then
    SEASON_NUM="$SEASON_INPUT"
else
    SEASON_NUM="$SEASON_DETECTADA"
fi

# Confirmar Total de Capítulos
if [ -n "$TOTAL_DETECTADO" ] && [ "$TOTAL_DETECTADO" -gt 0 ]; then
    echo -e "📊 Capítulos detectados: ${AZUL}${BOLD}$TOTAL_DETECTADO${NC}"
    read -p "¿Es correcto? (Enter para aceptar, o escribe el total): " TOTAL_INPUT
    if [ -n "$TOTAL_INPUT" ]; then
        TOTAL_EP="$TOTAL_INPUT"
    else
        TOTAL_EP="$TOTAL_DETECTADO"
    fi
else
    read -p "📊 Número total de capítulos de esta temporada: " TOTAL_EP
fi

# ==============================================================================
# 2. SELECCIONAR CALIDAD DE VIDEO
# ==============================================================================

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${BOLD}🎥 SELECCIÓN DE CALIDAD DE VIDEO${NC}"
echo -e "${CYAN}==========================================${NC}"
echo "1) 🌟 Máxima Calidad (720p HD / SD) [Recomendado]"
echo "2) 📺 Calidad Estándar (540p LD)"
echo "3) 📱 Calidad Ligera (360p FD)"
echo ""
read -p "Selecciona calidad [1]: " OPCION_CALIDAD

case $OPCION_CALIDAD in
    2)
        PREF_CALIDAD="ld"
        CALIDAD_NOMBRE="540p (LD)"
        ;;
    3)
        PREF_CALIDAD="fd"
        CALIDAD_NOMBRE="360p (FD)"
        ;;
    *)
        PREF_CALIDAD="sd"
        CALIDAD_NOMBRE="720p (HD/SD)"
        ;;
esac
echo -e "${VERDE}✅ Calidad seleccionada: $CALIDAD_NOMBRE${NC}"

# ==============================================================================
# 3. SELECCIÓN DE CAPÍTULOS (RANGO O LISTA)
# ==============================================================================

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${BOLD}🎯 SELECCIÓN DE CAPÍTULOS${NC}"
echo -e "${CYAN}==========================================${NC}"
echo "1) 📚 Todos los capítulos ($TOTAL_EP)"
echo "2) 🎯 Rango específico (ej: 5-10)"
echo "3) 📌 Desde un capítulo hasta el final (ej: 30-${TOTAL_EP})"
echo "4) 🎬 Solo un capítulo (ej: 15)"
echo "5) 📋 Capítulos específicos (ej: 5,6,20,26)"
echo ""
read -p "Selecciona una opción [1]: " OPCION_RANGO

case $OPCION_RANGO in
    2)
        read -p "Ingresa el rango (ej: 5-10): " RANGO
        INICIO_RANGO=$(echo "$RANGO" | cut -d'-' -f1)
        FIN_RANGO=$(echo "$RANGO" | cut -d'-' -f2)
        LISTA_CAPITULOS=()
        for (( i=INICIO_RANGO; i<=FIN_RANGO; i++ )); do
            LISTA_CAPITULOS+=($i)
        done
        ;;
    3)
        read -p "Ingresa el capítulo de inicio (ej: 30): " INICIO_RANGO
        FIN_RANGO=$TOTAL_EP
        echo "📌 Rango: $INICIO_RANGO al $FIN_RANGO"
        LISTA_CAPITULOS=()
        for (( i=INICIO_RANGO; i<=FIN_RANGO; i++ )); do
            LISTA_CAPITULOS+=($i)
        done
        ;;
    4)
        read -p "Ingresa el número de capítulo: " INICIO_RANGO
        FIN_RANGO=$INICIO_RANGO
        echo "📌 Capítulo único: $INICIO_RANGO"
        LISTA_CAPITULOS=($INICIO_RANGO)
        ;;
    5)
        read -p "Ingresa los capítulos separados por coma (ej: 5,6,20,26): " CAPS_INPUT
        IFS=',' read -ra LISTA_CAPITULOS <<< "$CAPS_INPUT"
        LISTA_CAPITULOS=($(echo "${LISTA_CAPITULOS[@]}" | tr ' ' '\n' | sort -n | uniq))
        INICIO_RANGO=${LISTA_CAPITULOS[0]}
        FIN_RANGO=${LISTA_CAPITULOS[-1]}
        echo "📋 Capítulos seleccionados: ${LISTA_CAPITULOS[*]}"
        ;;
    *)
        INICIO_RANGO=1
        FIN_RANGO=$TOTAL_EP
        echo "📚 Descargando todos los capítulos: 1 al $TOTAL_EP"
        LISTA_CAPITULOS=()
        for (( i=1; i<=TOTAL_EP; i++ )); do
            LISTA_CAPITULOS+=($i)
        done
        ;;
esac

CAPITULOS_A_DESCARGAR=${#LISTA_CAPITULOS[@]}
echo -e "${VERDE}✅ Se descargarán ${CAPITULOS_A_DESCARGAR} capítulos: ${LISTA_CAPITULOS[*]}${NC}"

# ==============================================================================
# 4. MODO DE DESCARGA & CONTROL DE MEMORIA RAM (PARALELO CONTROLADO)
# ==============================================================================

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${BOLD}⚡ CONCURRENCIA & USO DE MEMORIA RAM${NC}"
echo -e "${CYAN}==========================================${NC}"
echo "1) 🐌 Secuencial (1 capítulo a la vez - 0 consumo RAM)"
echo "2) ⚡ Equilibrado (3 capítulos simultáneos - Recomendado)"
echo "3) 🚀 Rápido (5 capítulos simultáneos - Mayor velocidad)"
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
echo -e "📺 Serie:        ${VERDE}$SERIES_NAME${NC}"
echo -e "🔢 Temporada:    ${VERDE}Season $(printf "%02d" $SEASON_NUM)${NC}"
echo -e "📊 Capítulos:    ${VERDE}$CAPITULOS_A_DESCARGAR de $TOTAL_EP${NC}"
echo -e "🎥 Calidad:      ${VERDE}$CALIDAD_NOMBRE${NC}"
echo -e "⚡ Modo:         ${VERDE}$MODO_NOMBRE${NC}"
echo -e "🌐 Plataforma:   ${VERDE}$PLATAFORMA${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

read -p "¿Iniciar proceso? (s/N): " CONFIRMAR
if [[ ! "$CONFIRMAR" =~ ^[sS]$ ]]; then
    echo "❌ Cancelado por el usuario"
    exit 0
fi

# ==============================================================================
# 5. EXTRAER URLs DE LOS CAPÍTULOS
# ==============================================================================

TEMP_FILE="/tmp/urls_temp_$$.txt"
ERROR_LOG="/tmp/errores_extraccion_$$.txt"

# Fallback si /tmp no existe (entornos locales Windows)
if [ ! -d "/tmp" ]; then
    TEMP_FILE="./.urls_temp_$$.txt"
    ERROR_LOG="./.errores_extraccion_$$.txt"
fi

> "$TEMP_FILE"
> "$ERROR_LOG"

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${BOLD}🔍 EXTRAYENDO ENLACES DE CAPÍTULOS${NC}"
echo -e "${CYAN}==========================================${NC}"

for EP in "${LISTA_CAPITULOS[@]}"; do
    echo -n "Episodio $EP: "
    EP_URL="${BASE_URL}/${EP}"
    HTML_CONTENT=$(curl -s -L -A "$UA" "$EP_URL" 2>/dev/null)
    
    M3U8=""

    # 1. Extracción avanzada desde __NEXT_DATA__
    if [ -z "$M3U8" ]; then
        M3U8=$($PYTHON_CMD -c "
import sys, re, json
html = sys.argv[1]
pref = '$PREF_CALIDAD'
m = re.search(r'<script id=\"__NEXT_DATA__\"[^>]*>(.*?)</script>', html, re.DOTALL)
if m:
    data = json.loads(m.group(1))
    media_list = data.get('props', {}).get('pageProps', {}).get('mediaInfoList', [])
    if media_list:
        if pref == 'sd':
            order = ['GROOT_SD', 'GROOT_HD', 'GROOT_FHD', 'GROOT_LD', 'GROOT_FD']
        elif pref == 'ld':
            order = ['GROOT_LD', 'GROOT_FD', 'GROOT_SD']
        else:
            order = ['GROOT_FD', 'GROOT_LD', 'GROOT_SD']
        
        for q in order:
            for item in media_list:
                if item.get('currentDefinition') == q and item.get('mediaUrl'):
                    print(item['mediaUrl'].replace('\\u0026', '&'))
                    sys.exit(0)
        print(media_list[0].get('mediaUrl', '').replace('\\u0026', '&'))
" "$HTML_CONTENT" 2>/dev/null)
    fi

    # 2. Búsqueda por regex de calidad específica
    if [ -z "$M3U8" ]; then
        if [ "$PREF_CALIDAD" = "sd" ]; then
            M3U8=$(echo "$HTML_CONTENT" | grep -oP 'https?://[^"'\''<>\s]+?sd\.m3u8[^"'\''<>\s]*' | head -1)
            if [ -z "$M3U8" ]; then
                M3U8=$(echo "$HTML_CONTENT" | grep -oP 'https?://[^"'\''<>\s]+?hd\.m3u8[^"'\''<>\s]*' | head -1)
            fi
            if [ -z "$M3U8" ]; then
                M3U8=$(echo "$HTML_CONTENT" | grep -oP 'https?://[^"'\''<>\s]+?ld\.m3u8[^"'\''<>\s]*' | head -1)
                if [ -n "$M3U8" ]; then
                    M3U8=$(echo "$M3U8" | sed 's/-ld\.m3u8/-sd\.m3u8/g')
                fi
            fi
        elif [ "$PREF_CALIDAD" = "ld" ]; then
            M3U8=$(echo "$HTML_CONTENT" | grep -oP 'https?://[^"'\''<>\s]+?ld\.m3u8[^"'\''<>\s]*' | head -1)
        fi
    fi

    # 3. Fallbacks genéricos
    if [ -z "$M3U8" ]; then
        M3U8=$(echo "$HTML_CONTENT" | grep -oP '"mediaUrl":"\K[^"]+?\.m3u8[^"]*' | head -1)
    fi
    if [ -z "$M3U8" ]; then
        M3U8=$(echo "$HTML_CONTENT" | grep -oP 'data-url="\K[^"]+?\.m3u8[^"]*' | head -1)
    fi
    if [ -z "$M3U8" ]; then
        M3U8=$(echo "$HTML_CONTENT" | grep -oP 'https?://[^"'\''<>\s]+?\.m3u8[^"'\''<>\s]*' | head -1)
    fi

    M3U8=$(echo "$M3U8" | sed 's/\\u0026/\&/g')

    if [ -n "$M3U8" ]; then
        echo -e " ${VERDE}✅ Encontrado${NC}"
        echo "$EP|$M3U8" >> "$TEMP_FILE"
    else
        echo -e " ${ROJO}❌ NO ENCONTRADO${NC}"
        echo "Episodio $EP: No se encontró URL" >> "$ERROR_LOG"
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
    echo -e "${ROJO}❌ No se encontraron URLs disponibles para descargar. Abortando.${NC}"
    rm -f "$TEMP_FILE" "$ERROR_LOG"
    exit 1
fi

# ==============================================================================
# 6. DESCARGAR CAPÍTULOS CON GESTIÓN DE RAM
# ==============================================================================

SEASON_PAD=$(printf "%02d" $SEASON_NUM)
OUTPUT_DIR="./$SERIES_NAME/Season $SEASON_PAD"

if [ "$OPCION_RANGO" = "5" ]; then
    NOMBRE_CAPS=$(echo "${LISTA_CAPITULOS[@]}" | tr ' ' '-')
    OUTPUT_DIR="${OUTPUT_DIR}_caps-${NOMBRE_CAPS}"
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
    local archivo_salida="$OUTPUT_DIR/${SERIES_NAME} - S${SEASON_PAD}E${ep_pad}.mp4"

    echo -e "📥 [Episodio $ep] Descargando..."

    $YTDLP_CMD \
        -o "$archivo_salida" \
        --no-playlist \
        --force-overwrites \
        --no-warnings \
        --user-agent "$UA" \
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
export OUTPUT_DIR SERIES_NAME SEASON_PAD UA FALLIDOS_FILE YTDLP_CMD

# Control de concurrencia optimizado (Semáforo de RAM)
if [ "$MAX_PARALELO" -eq 1 ]; then
    # Modo Secuencial
    while IFS='|' read -r EP_NUM M3U8_URL; do
        EP_PAD=$(printf "%02d" $EP_NUM)
        echo ""
        echo -e "📥 ${BOLD}Descargando Episodio $EP_NUM...${NC}"
        
        $YTDLP_CMD \
            -o "$OUTPUT_DIR/${SERIES_NAME} - S${SEASON_PAD}E${EP_PAD}.mp4" \
            --no-playlist \
            --force-overwrites \
            --progress \
            --user-agent "$UA" \
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
    # Modo Paralelo Controlado (Semáforo: Máximo $MAX_PARALELO procesos a la vez)
    echo -e "⚡ Descargando $ENCONTRADOS episodios (Máximo $MAX_PARALELO simultáneos para cuidar la RAM)..."
    echo ""
    
    while IFS='|' read -r EP_NUM M3U8_URL; do
        # Esperar si ya alcanzamos el límite de procesos en paralelo
        while [ $(jobs -r -p 2>/dev/null | wc -l) -ge $MAX_PARALELO ]; do
            sleep 0.5
        done
        
        descargar_episodio "$EP_NUM" "$M3U8_URL" &
    done < "$TEMP_FILE"
    
    # Esperar a que terminen los procesos restantes
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
