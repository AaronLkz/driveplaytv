#!/bin/bash

# ==============================================================================
# 🎬 RAVEDOWN 3.0 - Script Universal de Descarga y Sincronización con Google Drive
# ==============================================================================
# - Extracción limpia y precisa de Nombres y Temporadas (sin IDs ni basura)
# - Selección de Máxima Calidad automática (720p SD / 1080p HD)
# - Subida automática a Google Drive mediante Rclone
# - Borrado automático de archivos locales para no saturar disco (ideal 5TB)
# - Soporte para descarga individual, cola por archivo (queue.txt) o interactiva
# ==============================================================================

# Colores de Terminal
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuración por defecto
RCLONE_REMOTE="gdrive:Series"
ENABLE_RCLONE=true
DELETE_LOCAL=true
QUEUE_FILE="queue.txt"
UA="Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${BOLD}🎬 RAVEDOWN 3.0 - Descargador de Series & Sync con Google Drive${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""

# ==============================================================================
# 0. DETECCIÓN DE DEPENDENCIAS (yt-dlp, rclone, python3/curl)
# ==============================================================================

detectar_ytdlp() {
    local NOMBRES=("yt-dlp" "yt-dlp_linux" "yt-dlp_linux_aarch64" "yt-dlp.exe")
    for nombre in "${NOMBRES[@]}"; do
        if command -v "$nombre" &> /dev/null; then
            echo "$nombre"
            return 0
        fi
    done
    for path in /usr/local/bin /usr/bin ~/.local/bin; do
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
    echo -e "${AMARILLO}⚠️ yt-dlp no encontrado en PATH, intentando descargar versión oficial...${NC}"
    mkdir -p ~/.local/bin
    curl -sL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o ~/.local/bin/yt-dlp
    chmod a+rx ~/.local/bin/yt-dlp
    export PATH="$HOME/.local/bin:$PATH"
    YTDLP_CMD=$(detectar_ytdlp)
fi

if [ -z "$YTDLP_CMD" ]; then
    echo -e "${ROJO}❌ No se pudo encontrar ni instalar yt-dlp.${NC}"
    exit 1
fi
echo -e "${VERDE}✅ yt-dlp detectado: $YTDLP_CMD${NC}"

# Detección de rclone
if command -v rclone &> /dev/null; then
    echo -e "${VERDE}✅ Rclone detectado${NC}"
else
    echo -e "${AMARILLO}⚠️ Rclone no encontrado. Las subidas a Google Drive estarán desactivadas.${NC}"
    ENABLE_RCLONE=false
fi

# ==============================================================================
# 1. FUNCIÓN PARA PROCESAR UNA SERIE / TEMPORADA
# ==============================================================================

procesar_serie() {
    local BASE_URL="$1"
    local RANGO_OPC="$2"
    local RANGO_CUSTOM="$3"

    echo ""
    echo -e "${CYAN}----------------------------------------------------------------${NC}"
    echo -e "🔍 ${BOLD}Consultando metadatos para:${NC} $BASE_URL"
    echo -e "${CYAN}----------------------------------------------------------------${NC}"

    # Extraer metadatos limpios usando Python (o regex si falla)
    METADATA_JSON=$(python3 -c "
import urllib.request, re, json, sys

url = sys.argv[1]
headers = {'User-Agent': '$UA'}
try:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode('utf-8', errors='ignore')
    
    name = ''
    season_num = 1
    total_eps = 0

    m = re.search(r'<script id=\"__NEXT_DATA__\"[^>]*>(.*?)</script>', html, re.DOTALL)
    if m:
        data = json.loads(m.group(1))
        props = data.get('props', {}).get('pageProps', {})
        name = props.get('name') or props.get('drama', {}).get('name', '')
        curr_season = props.get('currentSeason', {})
        eps = curr_season.get('episodes', [])
        if eps:
            total_eps = len(eps)

    # Detectar temporada
    detected_season = None
    if name:
        m_s = re.search(r'(?:temporada|season)\s*(\d+)', name, re.I) or re.search(r'(\d+)(?:st|nd|rd|th)?\s*season', name, re.I)
        if m_s:
            detected_season = int(m_s.group(1))
    
    if detected_season is None:
        m_s2 = re.search(r'(\d+)(?:st|nd|rd|th)?[-_]season', url, re.I) or re.search(r'season[-_](\d+)', url, re.I) or re.search(r'temporada[-_](\d+)', url, re.I)
        if m_s2:
            detected_season = int(m_s2.group(1))
    
    season_num = detected_season if detected_season else 1

    # Limpiar nombre
    clean_name = name
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
            total_eps = max([int(x) for x in ep_links if x.isdigit()])
    
    if total_eps == 0:
        total_eps = 12

    print(json.dumps({'name': clean_name, 'season': season_num, 'total_eps': total_eps}))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" "$BASE_URL" 2>/dev/null)

    # Parsear JSON obtenido
    SERIES_NAME=$(echo "$METADATA_JSON" | grep -oP '"name":\s*"\K[^"]+')
    SEASON_NUM=$(echo "$METADATA_JSON" | grep -oP '"season":\s*\K\d+')
    TOTAL_EP=$(echo "$METADATA_JSON" | grep -oP '"total_eps":\s*\K\d+')

    if [ -z "$SERIES_NAME" ]; then
        SERIES_NAME="Serie"
    fi
    if [ -z "$SEASON_NUM" ]; then
        SEASON_NUM=1
    fi
    if [ -z "$TOTAL_EP" ]; then
        TOTAL_EP=12
    fi

    SEASON_PAD=$(printf "%02d" $SEASON_NUM)

    echo -e "📺 ${BOLD}Serie:${NC}        ${VERDE}$SERIES_NAME${NC}"
    echo -e "🔢 ${BOLD}Temporada:${NC}    ${VERDE}Season $SEASON_PAD${NC}"
    echo -e "📊 ${BOLD}Total Caps:${NC}   ${VERDE}$TOTAL_EP${NC}"
    if [ "$ENABLE_RCLONE" = true ]; then
        echo -e "☁️  ${BOLD}Google Drive:${NC} ${CYAN}$RCLONE_REMOTE/$SERIES_NAME/Season $SEASON_PAD/${NC}"
    fi

    # Generar lista de episodios a descargar
    LISTA_CAPS=()
    if [ "$RANGO_OPC" = "2" ] && [ -n "$RANGO_CUSTOM" ]; then
        INI=$(echo "$RANGO_CUSTOM" | cut -d'-' -f1)
        FIN=$(echo "$RANGO_CUSTOM" | cut -d'-' -f2)
        for (( i=INI; i<=FIN; i++ )); do LISTA_CAPS+=($i); done
    elif [ "$RANGO_OPC" = "3" ] && [ -n "$RANGO_CUSTOM" ]; then
        LISTA_CAPS=($RANGO_CUSTOM)
    else
        for (( i=1; i<=TOTAL_EP; i++ )); do LISTA_CAPS+=($i); done
    fi

    TOTAL_A_DESC=${#LISTA_CAPS[@]}
    echo -e "🎯 ${BOLD}Capítulos a procesar (${TOTAL_A_DESC}):${NC} ${LISTA_CAPS[*]}"
    echo ""

    LOCAL_SEASON_DIR="./downloads/$SERIES_NAME/Season $SEASON_PAD"
    mkdir -p "$LOCAL_SEASON_DIR"

    # Procesar episodio por episodio
    for EP in "${LISTA_CAPS[@]}"; do
        EP_PAD=$(printf "%02d" $EP)
        FILENAME="${SERIES_NAME} - S${SEASON_PAD}E${EP_PAD}.mp4"
        LOCAL_FILE="$LOCAL_SEASON_DIR/$FILENAME"
        REMOTE_PATH="$SERIES_NAME/Season $SEASON_PAD/$FILENAME"

        echo -e "▶ ${BOLD}Extrayendo URL Episodio $EP/$TOTAL_EP (Máxima Calidad)...${NC}"
        
        # Extraer URL en 720p / mejor calidad
        EP_URL="${BASE_URL}/${EP}"
        HTML_EP=$(curl -s -L -A "$UA" "$EP_URL")

        # Buscar mejor calidad (sd.m3u8 > hd.m3u8 > ld.m3u8)
        M3U8_URL=$(echo "$HTML_EP" | grep -oP 'https?://[^"'\''<>\s]+?sd\.m3u8[^"'\''<>\s]*' | head -1)
        if [ -z "$M3U8_URL" ]; then
            M3U8_URL=$(echo "$HTML_EP" | grep -oP 'https?://[^"'\''<>\s]+?hd\.m3u8[^"'\''<>\s]*' | head -1)
        fi
        if [ -z "$M3U8_URL" ]; then
            M3U8_URL=$(echo "$HTML_EP" | grep -oP 'https?://[^"'\''<>\s]+?ld\.m3u8[^"'\''<>\s]*' | head -1)
            # Reemplazar ld por sd si es posible
            if [ -n "$M3U8_URL" ]; then
                M3U8_SD=$(echo "$M3U8_URL" | sed 's/-ld\.m3u8/-sd\.m3u8/g')
                M3U8_URL="$M3U8_SD"
            fi
        fi
        if [ -z "$M3U8_URL" ]; then
            M3U8_URL=$(echo "$HTML_EP" | grep -oP 'https?://[^"'\''<>\s]+?\.m3u8[^"'\''<>\s]*' | head -1)
        fi

        # Limpiar escape unicode
        M3U8_URL=$(echo "$M3U8_URL" | sed 's/\\u0026/\&/g')

        if [ -z "$M3U8_URL" ]; then
            echo -e "  ${ROJO}❌ No se encontró enlace M3U8 para el capítulo $EP${NC}"
            continue
        fi

        echo -e "  ${VERDE}✅ Enlace 720p encontrado${NC}"
        echo -e "  📥 ${BOLD}Descargando $FILENAME...${NC}"

        $YTDLP_CMD \
            -o "$LOCAL_FILE" \
            --no-playlist \
            --force-overwrites \
            --user-agent "$UA" \
            --retries 5 \
            --fragment-retries 5 \
            --concurrent-fragments 5 \
            --buffer-size 16M \
            --no-warnings \
            "$M3U8_URL"

        if [ $? -eq 0 ] && [ -f "$LOCAL_FILE" ]; then
            echo -e "  ${VERDE}✅ Descarga completada ($FILENAME)${NC}"
            
            # Subir a Google Drive con Rclone (Parámetros Anti-Rate Limit)
            if [ "$ENABLE_RCLONE" = true ]; then
                echo -e "  ☁️  ${CYAN}Subiendo a Google Drive ($REMOTE_PATH)...${NC}"
                rclone copyto "$LOCAL_FILE" "$RCLONE_REMOTE/$REMOTE_PATH" \
                    --drive-chunk-size=128M \
                    --drive-upload-cutoff=1000M \
                    --drive-pacer-min-sleep=200ms \
                    --drive-pacer-burst=5 \
                    --tpslimit=8 \
                    --no-traverse \
                    --timeout=8m \
                    --contimeout=30s \
                    --retries=3 \
                    --low-level-retries=10 \
                    --transfers=2 \
                    --fast-list \
                    -P
                
                if [ $? -eq 0 ]; then
                    echo -e "  ${VERDE}✅ Subida a Drive exitosa!${NC}"
                    if [ "$DELETE_LOCAL" = true ]; then
                        rm -f "$LOCAL_FILE"
                        echo -e "  🗑️  ${AMARILLO}Archivo local eliminado para ahorrar espacio.${NC}"
                    fi
                    # Pausa de enfriamiento para no saturar la API de Google Drive
                    sleep 3
                else
                    echo -e "  ${ROJO}❌ Error al subir a Google Drive con rclone.${NC}"
                    sleep 10
                fi
            fi
        else
            echo -e "  ${ROJO}❌ Falló la descarga del episodio $EP${NC}"
        fi

        sleep 1
    done

    echo ""
    echo -e "${VERDE}🎉 Procesamiento completado para: $SERIES_NAME - Season $SEASON_PAD${NC}"
}

# ==============================================================================
# 2. MENÚ PRINCIPAL / SELECCIÓN DE MODO
# ==============================================================================

echo "Selecciona el modo de operación:"
echo "1) 📄 Procesar cola de enlaces en vivo (desde $QUEUE_FILE)"
echo "2) 🎬 Descargar un enlace de temporada individual"
echo "3) ☁️  Probar conexión con Rclone / Google Drive"
echo ""
read -p "Opción [1]: " MODO_OPC

case $MODO_OPC in
    2)
        echo ""
        read -p "📎 Pega la URL de la serie / temporada: " INPUT_URL
        if [ -n "$INPUT_URL" ]; then
            echo ""
            echo "Selección de capítulos:"
            echo "1) Todos los capítulos"
            echo "2) Rango específico (ej: 1-5)"
            echo "3) Solo un capítulo (ej: 1)"
            read -p "Opción [1]: " R_OPC
            R_CUST=""
            if [ "$R_OPC" = "2" ]; then
                read -p "Ingresa rango (ej: 1-5): " R_CUST
            elif [ "$R_OPC" = "3" ]; then
                read -p "Ingresa capítulo: " R_CUST
            fi
            procesar_serie "$INPUT_URL" "$R_OPC" "$R_CUST"
        fi
        ;;
    3)
        echo ""
        echo "Verificando remote: $RCLONE_REMOTE..."
        rclone lsd "$RCLONE_REMOTE"
        ;;
    *)
        echo ""
        echo -e "${CYAN}================================================================${NC}"
        echo -e "👀 ${BOLD}MONITOR DE COLA ACTIVADO ($QUEUE_FILE)${NC}"
        echo -e "💡 Agrega URLs en $QUEUE_FILE en cualquier momento."
        echo -e "${CYAN}================================================================${NC}"
        
        if [ ! -f "$QUEUE_FILE" ]; then
            echo "# Agrega enlaces aquí" > "$QUEUE_FILE"
        fi

        while true; do
            while IFS= read -r linea || [ -n "$linea" ]; do
                linea=$(echo "$linea" | xargs)
                if [[ -n "$linea" && ! "$linea" =~ ^# && "$linea" =~ ^http ]]; then
                    procesar_serie "$linea" "1" ""
                    # Marcar URL procesada con '#' para no repetirla
                    sed -i "s|^$linea|# [COMPLETADO] $linea|" "$QUEUE_FILE" 2>/dev/null
                fi
            done < "$QUEUE_FILE"
            sleep 5
        done
        ;;
esac
