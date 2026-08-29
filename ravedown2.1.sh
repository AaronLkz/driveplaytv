#!/bin/bash

# ============================================
# SCRIPT UNIVERSAL - Descarga de temporadas
# Compatible con: peliculaplay.com, flixlat.com, solo-latino.com
# ============================================

# Colores
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
NC='\033[0m'

echo ""
echo "=========================================="
echo "🎬 DESCARGADOR DE TEMPORADAS COMPLETAS"
echo "=========================================="
echo ""

# ============================================
# 0. DETECTAR yt-dlp (cualquier nombre)
# ============================================

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

# Si no encontró yt-dlp, intentar crear enlace simbólico
if [ -z "$YTDLP_CMD" ]; then
    if command -v yt-dlp_linux &> /dev/null; then
        echo -e "${AMARILLO}⚠️ Detectado yt-dlp_linux, creando enlace simbólico...${NC}"
        sudo ln -sf $(which yt-dlp_linux) /usr/local/bin/yt-dlp 2>/dev/null
        if [ $? -eq 0 ]; then
            YTDLP_CMD="yt-dlp"
            echo -e "${VERDE}✅ Enlace creado: yt-dlp → yt-dlp_linux${NC}"
        else
            mkdir -p ~/.local/bin
            ln -sf $(which yt-dlp_linux) ~/.local/bin/yt-dlp 2>/dev/null
            export PATH="$HOME/.local/bin:$PATH"
            if command -v yt-dlp &> /dev/null; then
                YTDLP_CMD="yt-dlp"
                echo -e "${VERDE}✅ Enlace creado en ~/.local/bin/yt-dlp${NC}"
            fi
        fi
    fi
fi

if [ -z "$YTDLP_CMD" ]; then
    YTDLP_CMD=$(detectar_ytdlp)
fi

if [ -z "$YTDLP_CMD" ]; then
    echo -e "${ROJO}❌ No se encontró yt-dlp instalado${NC}"
    echo ""
    echo "   📥 Instalación rápida:"
    echo "   sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux -o /usr/local/bin/yt-dlp"
    echo "   sudo chmod a+rx /usr/local/bin/yt-dlp"
    echo ""
    read -p "Presiona Enter para salir..."
    exit 1
fi

echo -e "${VERDE}✅ yt-dlp detectado: $YTDLP_CMD${NC}"
echo ""

# ============================================
# 1. SOLICITAR DATOS AL USUARIO
# ============================================

read -p "📎 Pega la URL completa de la temporada: " BASE_URL

# Detectar plataforma
if echo "$BASE_URL" | grep -q "peliculaplay.com"; then
    PLATAFORMA="peliculaplay"
    echo -e "${VERDE}✅ Plataforma detectada: PeliculaPlay${NC}"
elif echo "$BASE_URL" | grep -q "flixlat.com"; then
    PLATAFORMA="flixlat"
    echo -e "${VERDE}✅ Plataforma detectada: FlixLat${NC}"
elif echo "$BASE_URL" | grep -q "solo-latino.com"; then
    PLATAFORMA="sololatino"
    echo -e "${VERDE}✅ Plataforma detectada: Solo-Latino${NC}"
else
    echo -e "${AMARILLO}⚠️ Plataforma no reconocida, usando método genérico${NC}"
    PLATAFORMA="generico"
fi

# Extraer el nombre de la serie y temporada de la URL
SERIES_RAW=$(echo "$BASE_URL" | grep -oP '[^-]+(?=-Season-\d+$)' | sed 's/-/ /g')
SEASON_NUM=$(echo "$BASE_URL" | grep -oP 'Season-(\d+)$' | grep -oP '\d+')

# Si no se pudo extraer automáticamente, preguntar
if [ -z "$SERIES_RAW" ]; then
    read -p "📺 Nombre de la serie (ej. The Walking Dead): " SERIES_NAME
else
    echo "📺 Serie detectada: ${AZUL}$SERIES_RAW${NC}"
    read -p "¿Es correcto? (Enter para aceptar, o escribe el nombre correcto): " SERIES_INPUT
    if [ -n "$SERIES_INPUT" ]; then
        SERIES_NAME="$SERIES_INPUT"
    else
        SERIES_NAME="$SERIES_RAW"
    fi
fi

if [ -z "$SEASON_NUM" ]; then
    read -p "🔢 Número de temporada: " SEASON_NUM
else
    echo "🔢 Temporada detectada: ${AZUL}$SEASON_NUM${NC}"
    read -p "¿Es correcto? (Enter para aceptar, o escribe el número correcto): " SEASON_INPUT
    if [ -n "$SEASON_INPUT" ]; then
        SEASON_NUM="$SEASON_INPUT"
    fi
fi

read -p "📊 Número total de capítulos de esta temporada: " TOTAL_EP

# ============================================
# 1.5 SELECCIONAR CAPÍTULOS (RANGO O LISTA)
# ============================================
echo ""
echo "=========================================="
echo "🎯 SELECCIÓN DE CAPÍTULOS"
echo "=========================================="
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
        # Generar lista de capítulos en el rango
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
        # Convertir "5,6,20,26" en array
        IFS=',' read -ra LISTA_CAPITULOS <<< "$CAPS_INPUT"
        # Ordenar numéricamente y eliminar duplicados
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

# Si no se generó LISTA_CAPITULOS (por si acaso)
if [ ${#LISTA_CAPITULOS[@]} -eq 0 ]; then
    for (( i=$INICIO_RANGO; i<=$FIN_RANGO; i++ )); do
        LISTA_CAPITULOS+=($i)
    done
fi

CAPITULOS_A_DESCARGAR=${#LISTA_CAPITULOS[@]}
echo -e "${VERDE}✅ Se descargarán ${CAPITULOS_A_DESCARGAR} capítulos: ${LISTA_CAPITULOS[*]}${NC}"

# Mostrar resumen
echo ""
echo "=========================================="
echo "📋 RESUMEN DE CONFIGURACIÓN"
echo "=========================================="
echo -e "📺 Serie:        ${VERDE}$SERIES_NAME${NC}"
echo -e "🔢 Temporada:    ${VERDE}$SEASON_NUM${NC}"
echo -e "📊 Capítulos:    ${VERDE}$TOTAL_EP${NC}"
echo -e "🎯 Selección:    ${VERDE}${CAPITULOS_A_DESCARGAR} capítulos específicos${NC}"
echo -e "🌐 Plataforma:   ${VERDE}$PLATAFORMA${NC}"
echo -e "🔗 URL base:     ${AZUL}${BASE_URL:0:80}...${NC}"
echo "=========================================="
echo ""

read -p "¿Los datos son correctos? (s/N): " CONFIRMAR
if [[ ! "$CONFIRMAR" =~ ^[sS]$ ]]; then
    echo "❌ Cancelado por el usuario"
    exit 0
fi

# ============================================
# 2. EXTRAER URLs DE LOS CAPÍTULOS (SOLO DE LA LISTA)
# ============================================

UA="Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36"
TEMP_FILE="/tmp/urls_temp_$$.txt"
ERROR_LOG="/tmp/errores_extraccion_$$.txt"

> "$TEMP_FILE"
> "$ERROR_LOG"

echo ""
echo "=========================================="
echo "🔍 EXTRAYENDO URLs DE CAPÍTULOS"
echo "=========================================="
echo -e "${AMARILLO}📋 Capítulos a extraer: ${LISTA_CAPITULOS[*]}${NC}"
echo ""

for EP in "${LISTA_CAPITULOS[@]}"; do
    echo -n "Episodio $EP: "
    
    EP_URL="${BASE_URL}/${EP}"
    HTML_CONTENT=$(curl -s -L -A "$UA" "$EP_URL" 2>/dev/null)
    
    M3U8=""
    
    # Patrón 1: mediaUrl en JSON (peliculaplay)
    if [ -z "$M3U8" ]; then
        M3U8=$(echo "$HTML_CONTENT" | grep -oP '"mediaUrl":"\K[^"]+?ld\.m3u8[^"]*' | head -1)
    fi
    
    # Patrón 2: URL directa .m3u8 (flixlat)
    if [ -z "$M3U8" ]; then
        M3U8=$(echo "$HTML_CONTENT" | grep -oP 'https?://[^"]+?ld\.m3u8[^"]*' | head -1)
    fi
    
    # Patrón 3: data-url en botones (solo-latino.com)
    if [ -z "$M3U8" ]; then
        M3U8=$(echo "$HTML_CONTENT" | grep -oP 'data-url="\K[^"]+?\.m3u8[^"]*' | head -1)
    fi
    
    # Limpiar caracteres escapados
    M3U8=$(echo "$M3U8" | sed 's/\\u0026/\&/g')
    
    if [ -n "$M3U8" ]; then
        echo -e " ${VERDE}✅ Encontrado${NC}"
        echo "$EP|$M3U8" >> "$TEMP_FILE"
    else
        echo -e " ${ROJO}❌ NO ENCONTRADO${NC}"
        echo "Episodio $EP: No se encontró URL" >> "$ERROR_LOG"
    fi
    
    sleep 0.3
done

ENCONTRADOS=$(grep -c '|https' "$TEMP_FILE")
FALLIDOS=$((CAPITULOS_A_DESCARGAR - ENCONTRADOS))

echo ""
echo "=========================================="
echo -e "📊 RESULTADO DE EXTRACCIÓN"
echo "=========================================="
echo -e "${VERDE}✅ Encontrados: $ENCONTRADOS/$CAPITULOS_A_DESCARGAR${NC}"
if [ $FALLIDOS -gt 0 ]; then
    echo -e "${ROJO}❌ Fallidos: $FALLIDOS${NC}"
    cat "$ERROR_LOG"
fi
echo "=========================================="

if [ $ENCONTRADOS -eq 0 ]; then
    echo ""
    echo -e "${ROJO}❌ No se encontraron URLs. Abortando.${NC}"
    rm -f "$TEMP_FILE" "$ERROR_LOG"
    exit 1
fi

# Preguntar modo de descarga
echo ""
echo "=========================================="
echo "⚡ MODO DE DESCARGA"
echo "=========================================="
echo "1) 🐌 Secuencial (1 capítulo a la vez)"
echo "2) ⚡ Paralelo (más rápido)"
echo ""
read -p "Selecciona modo [2]: " MODO_DESC

if [ "$MODO_DESC" = "1" ]; then
    PARALELO=1
    MODO_NOMBRE="Secuencial"
else
    PARALELO=4
    MODO_NOMBRE="Paralelo"
fi

echo ""
read -p "¿Descargar los $ENCONTRADOS episodios? (s/N): " CONFIRMAR_DESCARGAR
if [[ ! "$CONFIRMAR_DESCARGAR" =~ ^[sS]$ ]]; then
    echo "❌ Descarga cancelada"
    rm -f "$TEMP_FILE" "$ERROR_LOG"
    exit 0
fi

# ============================================
# 3. DESCARGAR CAPÍTULOS
# ============================================

OUTPUT_DIR="$SERIES_NAME/Season $(printf "%02d" $SEASON_NUM)"
mkdir -p "$OUTPUT_DIR"

# Si es una selección personalizada, crear carpeta con los capítulos
if [ "$OPCION_RANGO" = "5" ]; then
    # Crear nombre de carpeta con los capítulos (ej: _caps-5-6-20-26)
    NOMBRE_CAPS=$(echo "${LISTA_CAPITULOS[@]}" | tr ' ' '-')
    OUTPUT_DIR="${OUTPUT_DIR}_caps-${NOMBRE_CAPS}"
elif [ "$INICIO_RANGO" != "1" ] || [ "$FIN_RANGO" != "$TOTAL_EP" ]; then
    OUTPUT_DIR="${OUTPUT_DIR}_ep${INICIO_RANGO}-${FIN_RANGO}"
fi
mkdir -p "$OUTPUT_DIR"

echo ""
echo "=========================================="
echo "🚀 INICIANDO DESCARGA ($MODO_NOMBRE)"
echo "=========================================="
echo -e "📁 Carpeta destino: ${VERDE}$OUTPUT_DIR${NC}"
if [ "$OPCION_RANGO" = "5" ]; then
    echo -e "🎯 Capítulos: ${VERDE}${LISTA_CAPITULOS[*]}${NC}"
elif [ "$INICIO_RANGO" != "1" ] || [ "$FIN_RANGO" != "$TOTAL_EP" ]; then
    echo -e "🎯 Rango: ${VERDE}$INICIO_RANGO al $FIN_RANGO${NC}"
fi
echo "=========================================="

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FALLIDOS_FILE="fallidos_${TIMESTAMP}.txt"
> "$FALLIDOS_FILE"

INICIO=$(date +%s)

if [ "$PARALELO" = "1" ]; then
    # Modo secuencial
    while IFS='|' read -r EP_NUM M3U8_URL; do
        echo ""
        echo "📥 Descargando Episodio $EP_NUM..."
        
        $YTDLP_CMD \
            -o "$OUTPUT_DIR/${SERIES_NAME} - S${SEASON_NUM}E${EP_NUM} - %(title)s.%(ext)s" \
            --no-playlist \
            --force-overwrites \
            --progress \
            --user-agent "$UA" \
            --retries 3 \
            "$M3U8_URL"
        
        if [ $? -eq 0 ]; then
            echo "✅ Episodio $EP_NUM completado"
        else
            echo "❌ Falló episodio $EP_NUM"
            echo "$EP_NUM|$M3U8_URL" >> "$FALLIDOS_FILE"
        fi
    done < "$TEMP_FILE"
else
    # Modo paralelo con background jobs
    descargar_ep() {
        local ep=$1
        local url=$2
        
        $YTDLP_CMD \
            -o "$OUTPUT_DIR/${SERIES_NAME} - S${SEASON_NUM}E${ep} - %(title)s.%(ext)s" \
            --no-playlist \
            --force-overwrites \
            --no-progress \
            --user-agent "$UA" \
            --retries 3 \
            --buffer-size 16M \
            --limit-rate 50M \
            "$url" > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo "✅ Episodio $ep completado"
        else
            echo "❌ Falló episodio $ep"
            echo "$ep|$url" >> "$FALLIDOS_FILE"
        fi
    }
    
    export -f descargar_ep
    export OUTPUT_DIR SERIES_NAME SEASON_NUM UA FALLIDOS_FILE YTDLP_CMD
    
    echo "⚡ Descargando $ENCONTRADOS episodios en paralelo..."
    echo ""
    
    # Lanzar todas las descargas en background
    while IFS='|' read -r EP_NUM M3U8_URL; do
        descargar_ep "$EP_NUM" "$M3U8_URL" &
    done < "$TEMP_FILE"
    
    wait
fi

FIN=$(date +%s)
TIEMPO=$((FIN - INICIO))
MINUTOS=$((TIEMPO / 60))
SEGUNDOS=$((TIEMPO % 60))

# Contar fallidos
FALLIDOS_DESC=0
if [ -f "$FALLIDOS_FILE" ]; then
    FALLIDOS_DESC=$(wc -l < "$FALLIDOS_FILE")
fi

# ============================================
# 4. LIMPIEZA Y RESUMEN FINAL
# ============================================

rm -f "$TEMP_FILE" "$ERROR_LOG"

echo ""
echo "=========================================="
echo "🎉 DESCARGA FINALIZADA"
echo "=========================================="
echo -e "${VERDE}✅ Descargados: $((ENCONTRADOS - FALLIDOS_DESC))/$ENCONTRADOS${NC}"
if [ $FALLIDOS_DESC -gt 0 ]; then
    echo -e "${ROJO}❌ Fallidos: $FALLIDOS_DESC${NC}"
    echo -e "📁 Revisa: ${AMARILLO}$FALLIDOS_FILE${NC}"
fi
echo -e "📁 Ubicación: ${VERDE}$OUTPUT_DIR${NC}"
echo -e "⏱️  Tiempo total: ${VERDE}${MINUTOS}m ${SEGUNDOS}s${NC}"
echo "=========================================="

if [ -d "$OUTPUT_DIR" ]; then
    TAMANO=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
    if [ -n "$TAMANO" ]; then
        echo -e "💾 Tamaño total: ${AZUL}$TAMANO${NC}"
    fi
fi
echo "=========================================="

echo ""
read -p "Presiona Enter para salir..."
