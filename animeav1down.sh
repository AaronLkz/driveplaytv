#!/bin/bash

# ============================================
# SCRIPT PARA ANIMEAV1.COM - Descarga de animes
# Compatible con: animeav1.com
# Basado en ravedown2.sh
# ============================================

# Colores
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
NC='\033[0m'

echo ""
echo "=========================================="
echo "🎬 DESCARGADOR DE ANIMES (ANIMEAV1.COM)"
echo "=========================================="
echo ""

# ============================================
# 0. DETECTAR yt-dlp
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
# 1. SOLICITAR DATOS
# ============================================
read -p "📎 Pega la URL de la serie (ej: https://animeav1.com/media/tengen-toppa-gurren-lagann): " BASE_URL

# Extraer nombre base de la URL
SERIES_NAME_RAW=$(echo "$BASE_URL" | sed 's|https://animeav1.com/media/||' | sed 's|/||g' | tr '-' ' ')
echo "📺 Serie detectada: ${AZUL}$SERIES_NAME_RAW${NC}"
read -p "¿Es correcto? (Enter para aceptar, o escribe el nombre correcto): " SERIES_INPUT
if [ -n "$SERIES_INPUT" ]; then
    SERIES_NAME="$SERIES_INPUT"
else
    SERIES_NAME="$SERIES_NAME_RAW"
fi

read -p "🔢 Número total de episodios: " TOTAL_EP

# ============================================
# 1.5 SELECCIONAR RANGO (OPCIONAL)
# ============================================
echo ""
echo "=========================================="
echo "🎯 SELECCIÓN DE EPISODIOS"
echo "=========================================="
echo "1) 📚 Todos los episodios ($TOTAL_EP)"
echo "2) 🎯 Rango específico (ej: 5-10)"
echo "3) 📌 Desde un episodio hasta el final (ej: 30-${TOTAL_EP})"
echo "4) 🎬 Solo un episodio (ej: 15)"
echo ""
read -p "Selecciona una opción [1]: " OPCION_RANGO

case $OPCION_RANGO in
    2)
        read -p "Ingresa el rango (ej: 5-10): " RANGO
        INICIO_RANGO=$(echo "$RANGO" | cut -d'-' -f1)
        FIN_RANGO=$(echo "$RANGO" | cut -d'-' -f2)
        ;;
    3)
        read -p "Ingresa el episodio de inicio (ej: 30): " INICIO_RANGO
        FIN_RANGO=$TOTAL_EP
        ;;
    4)
        read -p "Ingresa el número de episodio: " INICIO_RANGO
        FIN_RANGO=$INICIO_RANGO
        ;;
    *)
        INICIO_RANGO=1
        FIN_RANGO=$TOTAL_EP
        ;;
esac

# Validación
if [ -z "$INICIO_RANGO" ] || [ -z "$FIN_RANGO" ] || [ "$INICIO_RANGO" -lt 1 ] || [ "$FIN_RANGO" -gt "$TOTAL_EP" ] || [ "$INICIO_RANGO" -gt "$FIN_RANGO" ]; then
    echo -e "${ROJO}❌ Rango inválido. Usando todos.${NC}"
    INICIO_RANGO=1
    FIN_RANGO=$TOTAL_EP
fi

CAPITULOS_A_DESCARGAR=$((FIN_RANGO - INICIO_RANGO + 1))
echo -e "${VERDE}✅ Se descargarán los episodios $INICIO_RANGO al $FIN_RANGO (Total: $CAPITULOS_A_DESCARGAR)${NC}"

# ============================================
# 2. EXTRAER IDs Y CONSTRUIR URLs (SIN .m3u8)
# ============================================
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
TEMP_FILE="/tmp/urls_temp_$$.txt"
ERROR_LOG="/tmp/errores_extraccion_$$.txt"

> "$TEMP_FILE"
> "$ERROR_LOG"

echo ""
echo "=========================================="
echo "🔍 EXTRAYENDO URLs DE EPISODIOS"
echo "=========================================="

for (( EP=$INICIO_RANGO; EP<=$FIN_RANGO; EP++ )); do
    echo -n "Episodio $EP: "
    
    EP_URL="${BASE_URL}/${EP}"
    HTML=$(curl -s -L -A "$UA" "$EP_URL" 2>/dev/null)
    
    # Buscar el ID del reproductor (patrón: player.zilla-networks.com/play/ID)
    PLAYER_ID=$(echo "$HTML" | grep -oP 'player\.zilla-networks\.com/play/\K[a-f0-9]+' | head -1)
    
    if [ -n "$PLAYER_ID" ]; then
        # URL CORRECTA: SIN extensión .m3u8
        M3U8_URL="https://player.zilla-networks.com/m3u8/${PLAYER_ID}"
        echo -e " ${VERDE}✅ Encontrado (ID: ${PLAYER_ID})${NC}"
        echo "$EP|$M3U8_URL" >> "$TEMP_FILE"
    else
        echo -e " ${ROJO}❌ NO ENCONTRADO${NC}"
        echo "Episodio $EP: No se encontró ID del reproductor" >> "$ERROR_LOG"
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
    echo -e "${ROJO}❌ No se encontraron IDs. Abortando.${NC}"
    rm -f "$TEMP_FILE" "$ERROR_LOG"
    exit 1
fi

# Mostrar ejemplo de URL generada
PRIMER_ID=$(head -1 "$TEMP_FILE" | cut -d'|' -f2)
echo -e "${AMARILLO}📝 Ejemplo de URL generada:${NC}"
echo "   $PRIMER_ID"
echo ""

# ============================================
# 3. MODO DE DESCARGA
# ============================================
echo "=========================================="
echo "⚡ MODO DE DESCARGA"
echo "=========================================="
echo "1) 🐌 Secuencial (1 episodio a la vez)"
echo "2) ⚡ Paralelo (4 episodios a la vez - más rápido)"
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
# 4. DESCARGAR
# ============================================
OUTPUT_DIR="$SERIES_NAME"
mkdir -p "$OUTPUT_DIR"

# Si es un rango parcial, añadir al nombre de la carpeta
if [ "$INICIO_RANGO" != "1" ] || [ "$FIN_RANGO" != "$TOTAL_EP" ]; then
    OUTPUT_DIR="${OUTPUT_DIR}_ep${INICIO_RANGO}-${FIN_RANGO}"
    mkdir -p "$OUTPUT_DIR"
fi

echo ""
echo "=========================================="
echo "🚀 INICIANDO DESCARGA ($MODO_NOMBRE)"
echo "=========================================="
echo -e "📁 Carpeta destino: ${VERDE}$OUTPUT_DIR${NC}"
echo -e "${AMARILLO}📝 Usando URLs sin extensión .m3u8 (formato correcto)${NC}"
echo "=========================================="

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FALLIDOS_FILE="fallidos_${TIMESTAMP}.txt"
> "$FALLIDOS_FILE"
INICIO=$(date +%s)

if [ "$PARALELO" = "1" ]; then
    # SECUENCIAL
    while IFS='|' read -r EP_NUM M3U8_URL; do
        echo ""
        echo "📥 Descargando Episodio $EP_NUM..."
        echo "   URL: $M3U8_URL"
        
        $YTDLP_CMD \
            -o "$OUTPUT_DIR/${SERIES_NAME} - Episodio $(printf "%02d" $EP_NUM).%(ext)s" \
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
    # PARALELO
    descargar_ep() {
        local ep=$1
        local url=$2
        $YTDLP_CMD \
            -o "$OUTPUT_DIR/${SERIES_NAME} - Episodio $(printf "%02d" $ep).%(ext)s" \
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
    export OUTPUT_DIR SERIES_NAME UA FALLIDOS_FILE YTDLP_CMD
    
    echo "⚡ Descargando $ENCONTRADOS episodios en paralelo..."
    echo ""
    
    while IFS='|' read -r EP_NUM M3U8_URL; do
        descargar_ep "$EP_NUM" "$M3U8_URL" &
    done < "$TEMP_FILE"
    
    wait
fi

FIN=$(date +%s)
TIEMPO=$((FIN - INICIO))
MINUTOS=$((TIEMPO / 60))
SEGUNDOS=$((TIEMPO % 60))

# ============================================
# 5. LIMPIEZA Y RESUMEN
# ============================================
rm -f "$TEMP_FILE" "$ERROR_LOG"

FALLIDOS_DESC=0
if [ -f "$FALLIDOS_FILE" ]; then
    FALLIDOS_DESC=$(wc -l < "$FALLIDOS_FILE")
fi

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
