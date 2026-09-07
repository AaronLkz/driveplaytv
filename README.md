# 🎬 RAVEDOWN 3.0 & RAVEDOWN MOVIE 1.0
### Automatizador Masivo de Series & Películas con Sync a Google Drive (5TB)

Suite completa de herramientas para descargar series y películas en máxima calidad (1080p / 720p), organizar temporadas y metadatos, y sincronizar automáticamente con Google Drive a través de **Rclone**, liberando espacio en disco local.

---

## 📑 Tabla de Contenidos

- [🍿 Novedades: Ravedown Movie 1.0 (Películas)](#-novedades-ravedown-movie-10-películas)
- [📺 Novedades: Ravedown 3.0 (Series)](#-novedades-ravedown-30-series)
- [☁️ Cómo Conectar la Carpeta Movies en Rclone](#️-cómo-conectar-la-carpeta-movies-en-rclone)
- [⚙️ Configuración (`config.json`)](#️-configuración-configjson)
- [🚀 Modo de Uso: Películas (`ravedownmovie.py`)](#-modo-de-uso-películas-ravedownmoviepy)
- [📖 Modo de Uso: Series (`ravedown.py` y `ravedown3.0.sh`)](#-modo-de-uso-series-ravedownpy-y-ravedown30sh)
- [💻 Scripts de Descarga Local en PC (Sin Rclone)](#-scripts-de-descarga-local-en-pc-sin-rclone)
- [⚡ Solución al Problema de Rate Limits en Google Drive](#-solución-al-problema-de-rate-limits-en-google-drive)
- [📁 Estructura del Proyecto](#-estructura-del-proyecto)

---

## 🍿 Novedades: Ravedown Movie 1.0 (Películas)

Diseñado para aprovechar al máximo tu conexión y almacenamiento en la nube para descargar películas masivamente:

1. **Bypass de Cloudflare de Cinebel.cc**:
   - `cinebel.cc` cuenta con protección Cloudflare Turnstile en sus páginas. `ravedownmovie.py` utiliza la API pública de `moviedays.lat` con resolución automática de firmas HMAC (`_ts` y `_sig`), permitiendo consultar fichas técnicas y servidores sin bloqueos.
2. **Prioridad Absoluta a Enlaces Rumble CDN (`.aaa.mp4`)**:
   - El 90% de las películas están alojadas en el CDN de Rumble Cloud.
   - El script analiza los reproductores internos y extrae automáticamente los archivos `.aaa.mp4` (máxima calidad y bitrate 1080p).
3. **Descarga Acelerada Directa**:
   - Descarga directa de archivos `.mp4` a máxima velocidad de tu conexión con soporte HTTP Range y barra de progreso interactiva (`MB/s`, `%`, `ETA`).
   - Fallback automático a streams HLS con `yt-dlp` en caso de que una película no esté en Rumble.
4. **Base de Datos y Cola Dedicadas**:
   - Base de datos SQLite separada: `ravedownmovie.db` (no interfiere con tus temporadas de series en `ravedown.db`).
   - Cola de descargas en vivo: `queuemovie.txt`.
5. **Importador Masivo desde Cinebel**:
   - Lee automáticamente el sitemap público de Cinebel (`/wp-sitemap-posts-movies-1.xml`) para agregar lotes de 50, 100 o más películas a la cola con un solo comando.
6. **Nomenclatura Limpia y Organizada**:
   - Guarda y sube con la estructura estándar:
     ```
     GoogleDrive:Movies/
     └── Super Mario Bros (2023)/
         └── Super Mario Bros (2023) [1080p] [LAT].mp4
     ```

---

## 📺 Novedades: Ravedown 3.0 (Series)

1. **Extracción Limpia de Metadatos**:
   - Extrae el nombre real de la serie (ej. `Rent-a-Girlfriend`), la temporada exacta (`Season 01`) y la cantidad de episodios sin hashes ni caracteres extraños.
2. **Máxima Calidad Automática (720p HD / 1080p)**:
   - Prioriza y extrae streams `-sd.m3u8` (`GROOT_SD` / 720p) en lugar de limitarse a 540p.
3. **Sincronización Inteligente (`delete_after_upload`)**:
   - Cada episodio se descarga, se sube de inmediato a Google Drive y se borra la copia local para no agotar el disco de tu PC.
4. **Base de Datos y Cola en Vivo**:
   - Cola `queue.txt` y registro en `ravedown.db` para evitar descargas duplicadas.

---

## ☁️ Cómo Conectar la Carpeta Movies en Rclone

Actualmente tienes configurada tu carpeta de **Series** en Rclone. Dependiendo de cómo hayas creado tu remote `gdrive`, sigue el caso correspondiente:

### Caso 1: Tu remote `gdrive:` apunta a la raíz de tu Drive o Unidad Compartida (Más Común)

Si al configurar Rclone **no especificaste** ningún `root_folder_id` (o tu remote `gdrive:` ve todas tus carpetas), simplemente puedes crear la carpeta `Movies` como hermana de `Series`:

1. **Crear la carpeta en Google Drive desde la terminal:**
   ```bash
   rclone mkdir gdrive:Movies
   ```

2. **Verificar que ambas carpetas existen:**
   ```bash
   rclone lsd gdrive:
   ```
   Deberías ver listadas:
   ```text
             -1 2026-09-07 12:00:00        -1 Series
             -1 2026-09-07 17:00:00        -1 Movies
   ```

3. **Verificar `config.json`:**
   El archivo `config.json` ya viene preconfigurado con:
   ```json
   "rclone_remote": "gdrive:Series",
   "rclone_movie_remote": "gdrive:Movies"
   ```
   ¡Listo! `ravedown.py` subirá a `Series` y `ravedownmovie.py` subirá a `Movies`.

---

### Caso 2: Tu remote `gdrive:` apunta directamente dentro de la carpeta Series (`root_folder_id`)

Si durante el asistente `rclone config` pegaste el ID de la carpeta `Series` en el campo `root_folder_id`, para Rclone la "raíz" es esa carpeta y todo lo que subas a `gdrive:` irá dentro de Series.

Para crear una conexión dedicada a **Movies**:

1. **Crear la carpeta Movies en tu Google Drive**:
   - Entra a [drive.google.com](https://drive.google.com).
   - Crea una carpeta llamada `Movies`.
   - Entra en esa carpeta y copia el **ID de la carpeta** desde la barra de direcciones del navegador:
     ```text
     https://drive.google.com/drive/folders/1a2B3c4D5e6F7g8H9i0J_kLmNoP
                                             └── ESTE ES EL ID ──┘
     ```

2. **Crear un nuevo remote en Rclone**:
   ```bash
   rclone config
   ```
   - Escribe `n` (Nuevo remote).
   - Nombre: `gdrive_movies`
   - Tipo: Busca el número de `Google Drive` (o escribe `drive`).
   - `client_id` y `client_secret`: Pega los mismos que usaste para Series (o déjalo en blanco si usas el predeterminado).
   - `scope`: `1` (Full access).
   - `root_folder_id`: **Pega el ID de tu carpeta Movies** copiado en el paso 1.
   - Sigue los pasos de autenticación en el navegador y guarda con `y`.

3. **Verificar la conexión**:
   ```bash
   rclone lsf gdrive_movies:
   ```

4. **Actualizar `config.json`**:
   Cambia la clave `rclone_movie_remote`:
   ```json
   "rclone_remote": "gdrive:Series",
   "rclone_movie_remote": "gdrive_movies:"
   ```

---

## ⚙️ Configuración (`config.json`)

Personaliza las opciones generales, de series y de películas:

```json
{
  "rclone_remote": "gdrive:Series",
  "rclone_movie_remote": "gdrive:Movies",
  "rclone_enabled": true,
  "delete_after_upload": true,
  "upload_per_episode": true,
  "upload_cooldown_seconds": 3,
  "upload_timeout_minutes": 15,
  "preferred_quality": "720p",
  "preferred_movie_lang": "LATINO",
  "concurrent_fragments": 5,
  "movie_connections": 4,
  "download_dir": "./downloads",
  "movie_download_dir": "./downloads_movies",
  "queue_file": "queue.txt",
  "movie_queue_file": "queuemovie.txt",
  "ytdlp_path": "yt-dlp",
  "rclone_path": "rclone",
  "watch_interval_seconds": 5,
  "rclone_flags": [
    "--drive-chunk-size=128M",
    "--drive-upload-cutoff=1000M",
    "--drive-pacer-min-sleep=200ms",
    "--drive-pacer-burst=5",
    "--tpslimit=8",
    "--no-traverse",
    "--timeout=8m",
    "--contimeout=30s",
    "--retries=3",
    "--low-level-retries=10",
    "--transfers=2",
    "--fast-list",
    "-P"
  ]
}
```

---

## 🚀 Modo de Uso: Películas (`ravedownmovie.py`)

### 1. Menú Interactivo Completo (Recomendado)
Ejecuta el script sin parámetros para abrir el panel interactivo:
```bash
python ravedownmovie.py
```
Opciones disponibles:
- **1) Iniciar monitor de cola continua (`queuemovie.txt`)**: Se queda esperando nuevas películas en el archivo de texto y las procesa automáticamente.
- **2) Descargar película individual**: Pega cualquier enlace de Cinebel, TMDB o busca por título.
- **3) Importar lote desde Sitemap de Cinebel**: Agrega de 50 a 500 películas automáticamente a la cola.
- **4) Ver historial y estadísticas**: Consulta cuántas películas llevas descargadas y el espacio ocupado en Drive.
- **5) Configuración rápida**: Cambia el idioma preferido (`LATINO`, `CASTELLANO`, `SUB`) o el remote de Drive.

---

### 2. Modo Cola Continua en Segundo Plano
Edita `queuemovie.txt` agregando una película por línea:
```text
https://cinebel.cc/movies/super-mario-bros-la-pelicula/
https://cinebel.cc/movies/el-hombre-de-acero/
https://cinebel.cc/movies/ted-2/
502356
Super Mario Bros
```
Luego inicia el procesador:
```bash
python ravedownmovie.py --queue
```

---

### 3. Descarga Directa por Comando
```bash
# Con enlace de Cinebel:
python ravedownmovie.py --url "https://cinebel.cc/movies/super-mario-bros-la-pelicula/"

# Con ID de TMDB:
python ravedownmovie.py --url "502356"

# Con título directo:
python ravedownmovie.py --url "El Hombre de Acero"
```

---

### 4. Importar Lotes de Películas desde el Sitemap de Cinebel
```bash
# Agrega las primeras 100 películas de la página 1 del sitemap a queuemovie.txt:
python ravedownmovie.py --import-sitemap 1 --limit 100

# Para la siguiente tanda de películas (página 2):
python ravedownmovie.py --import-sitemap 2 --limit 100
```

---

### 5. Consultar Estadísticas
```bash
python ravedownmovie.py --stats
```

---

## 📖 Modo de Uso: Series (`ravedown.py` y `ravedown3.0.sh`)

### Opción A: Monitor de Cola para Series
Agrega enlaces de series en `queue.txt` e inicia:
```bash
python ravedown.py
```

### Opción B: Descarga Directa de Serie
```bash
python ravedown.py --url "https://es.cuevana4br.com/es/detail/drama/FHlVhWt6O4KFZJnoMQejq-Rent-a-Girlfriend"
```

### Opción C: Modo Interactivo (Rango de capítulos)
```bash
python ravedown.py --interactive
```

### Opción D: Script Universal en Bash para VPS / Linux
```bash
chmod +x ravedown3.0.sh
./ravedown3.0.sh
```

---

## 💻 Scripts de Descarga Local en PC (Sin Rclone)

Si deseas descargar directamente al disco de tu ordenador sin subir a Google Drive:

### 1. Series Locales: `ravedown2.5.sh`
Descarga series completas con menú de calidad y control de memoria RAM (semáforo de procesos para no congelar la máquina):
```bash
chmod +x ravedown2.5.sh
./ravedown2.5.sh
```

### 2. Animes Locales: `animeav1down2.5.sh`
Descargador especializado para **AnimeAV1.com** con bypass de cabeceras Cloudflare (`Sec-Fetch-*` y `Referer` dinámico para fragmentos HLS en Zilla-Networks):
```bash
chmod +x animeav1down2.5.sh
./animeav1down2.5.sh
```

---

## ⚡ Solución al Problema de Rate Limits en Google Drive

### ¿Por qué se queda colgado en `200MB / 200MB (100%)` tras muchos videos?
1. **Client ID Compartido**: Por defecto, Rclone usa un ID público compartido por miles de usuarios. Tras 100-150 videos consecutivos, Google activa el límite de peticiones (`403 User Rate Limit Exceeded`).
2. **Commit Final y Checksum**: Al llegar al 100%, Google Drive calcula el hash MD5 y crea las carpetas remotas.
3. **Traversals Innecesarios**: Sin `--no-traverse`, Rclone consulta toda la carpeta remota antes de cada archivo.

### Soluciones ya integradas en Ravedown:
- **`--drive-chunk-size=128M`**: Sube archivos en solo 1 o 2 bloques en lugar de 4+, reduciendo las llamadas HTTP a la mitad.
- **`--no-traverse`**: Sube directo sin escanear carpetas remotas antes.
- **`--tpslimit=8` y `--drive-pacer-min-sleep=200ms`**: Regula la tasa de peticiones a la API para prevenir bloqueos.
- **Timeouts automáticos**: Si una subida se atasca, la cancela limpiamente y reintenta con backoff.

### 🔑 Recomendación: Crear tu propio Google Client ID (2 minutos)
1. Entra a [Google Cloud Console](https://console.cloud.google.com/).
2. Crea un proyecto nuevo (ej. `MiDriveRclone`).
3. En **APIs & Services** > **Library**, activa **Google Drive API**.
4. En **APIs & Services** > **Credentials** > **Create Credentials**, elige **OAuth client ID** (tipo **Desktop App**).
5. Copia tu `Client ID` y `Client Secret`.
6. Ejecuta `rclone config`, edita tu remote y pega tus credenciales propias.

---

## 📁 Estructura del Proyecto

```text
driveplaytv/
├── ravedownmovie.py     # 🍿 Descargador masivo de películas (Rumble CDN .aaa.mp4 + Rclone)
├── queuemovie.txt       # 📋 Cola de películas en vivo
├── ravedownmovie.db     # 🗄️ Base de datos SQLite de películas (auto-generada)
│
├── ravedown.py          # 📺 Descargador masivo de series (HLS 720p + Rclone)
├── queue.txt            # 📋 Cola de series en vivo
├── ravedown.db          # 🗄️ Base de datos SQLite de series (auto-generada)
├── ravedown3.0.sh       # 🐧 Script Bash universal para series con Rclone (VPS/Linux)
│
├── ravedown2.5.sh       # 💻 Script Bash para series locales en PC (control RAM)
├── animeav1down2.5.sh   # 🎬 Script Bash para animes locales en PC (AnimeAV1 HLS)
├── ravedown2.1.sh       # 📦 Script original de series (respaldo histórico)
├── animeav1down.sh      # 📦 Script original de anime (respaldo histórico)
│
├── config.json          # ⚙️ Configuración global (remotes de Drive, calidades, hilos)
└── README.md            # 📖 Guía completa y documentación del sistema
```
