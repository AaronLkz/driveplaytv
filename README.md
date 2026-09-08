# 🎬 RAVEDOWN 3.0 & RAVEDOWN MOVIE 1.0
### Automatizador Masivo de Series & Películas con Sync a Google Drive (5TB)

Suite completa de herramientas para descargar series y películas en máxima calidad (1080p / 720p), organizar temporadas y metadatos, y sincronizar automáticamente con Google Drive a través de **Rclone**, liberando espacio en disco local.

---

## 📑 Tabla de Contenidos

- [🍿 Novedades: Ravedown Movie 1.0 (Películas)](#-novedades-ravedown-movie-10-películas)
- [📺 Novedades: Ravedown 3.0 (Series)](#-novedades-ravedown-30-series)
- [🐧 Instalación en VPS Ubuntu ARM (ARM64)](#-instalación-en-vps-ubuntu-arm-arm64)
- [📟 Guía Completa de Tmux: Ejecución en Segundo Plano 24/7](#-guía-completa-de-tmux-ejecución-en-segundo-plano-247)
- [☁️ Cómo Conectar la Carpeta Movies en Rclone](#️-cómo-conectar-la-carpeta-movies-en-rclone)
- [⚙️ Configuración (`config.json`)](#️-configuración-configjson)
- [🚀 Modo de Uso: Películas (`ravedownmovie.py`)](#-modo-de-uso-películas-ravedownmoviepy)
- [📖 Modo de Uso: Series (`ravedown.py` y `ravedown3.0.sh`)](#-modo-de-uso-series-ravedownpy-y-ravedown30sh)
- [💻 Scripts de Descarga Local en PC (Sin Rclone)](#-scripts-de-descarga-local-en-pc-sin-rclone)
- [⚡ Solución al Problema de Rate Limits & Client ID Propio](#-solución-al-problema-de-rate-limits--client-id-propio)
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

## 🐧 Instalación en VPS Ubuntu ARM (ARM64)

Si utilizas un VPS con procesador ARM (como **Oracle Cloud Always Free Ampere A1**, **AWS Graviton**, **Hetzner ARM64** o cualquier servidor Ubuntu aarch64), sigue estos pasos para dejar tu entorno 100% optimizado y listo para correr:

### 1. Actualizar el sistema e instalar dependencias base
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 python3-pip python3-venv ffmpeg tmux wget curl git
```
> [!IMPORTANT]
> **FFmpeg** es fundamental: `yt-dlp` lo utiliza obligatoriamente para fusionar video y audio en streams HLS y validar los contenedores MP4.

### 2. Instalación de `yt-dlp` en ARM64 (¡Evitar `apt install yt-dlp`!)
> [!WARNING]
> **No instales `yt-dlp` con `apt`**: Los repositorios de Ubuntu traen versiones muy desactualizadas que fallan con los extractores y reproductores modernos.

Descarga directamente el **binario compilado oficial para arquitectura ARM64 (`aarch64`)**:
```bash
# 1. Descargar el binario oficial ARM64
sudo wget https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_aarch64 -O /usr/local/bin/yt-dlp

# 2. Dar permisos de ejecución
sudo chmod a+rx /usr/local/bin/yt-dlp

# 3. Verificar que quedó instalado y funcional
yt-dlp --version
```
*(Para actualizarlo en el futuro en cualquier momento a la última versión, basta con ejecutar `sudo yt-dlp -U`).*

### 3. Instalación de Rclone en Ubuntu ARM
El instalador oficial de Rclone detecta automáticamente la arquitectura ARM64 e instala la versión más reciente:
```bash
sudo -v ; curl https://rclone.org/install.sh | sudo bash

# Verificar versión instalada
rclone version
```

### 4. Clonar el repositorio en tu VPS
```bash
git clone https://github.com/AaronLkz/driveplaytv.git
cd driveplaytv
```

---

## 📟 Guía Completa de Tmux: Ejecución en Segundo Plano 24/7

### ¿Qué es Tmux y por qué es indispensable en tu VPS?
Cuando te conectas a tu VPS mediante SSH (con PuTTY, PowerShell o la terminal de Linux/Mac), cualquier programa que ejecutes **se cancelará inmediatamente si cierras la ventana, se desconecta el WiFi o apagas tu ordenador**.

**`tmux`** (Terminal Multiplexer) crea sesiones de terminal virtuales y persistentes dentro del servidor. Esto te permite:
1. Dejar descargando y subiendo cientos de películas o series **de manera continua e ininterrumpida las 24 horas del día**.
2. Desconectarte de tu VPS con total tranquilidad.
3. Volver a conectarte horas o días después desde cualquier equipo y ver exactamente por dónde va la descarga.

---

### 1. Instalación de Tmux en Ubuntu / Debian
```bash
sudo apt update && sudo apt install -y tmux
```

Verificar que quedó instalado:
```bash
tmux -V
```

---

### 2. Flujo Completo de Trabajo: Dejarlo Corriendo y Desconectarse

#### Paso 1: Iniciar una sesión virtual con nombre
Crea una sesión con un nombre identificativo:
```bash
# Para descargar películas:
tmux new -s movies

# O para descargar series:
tmux new -s series
```
*(Se abrirá una nueva terminal limpia con una barra de estado verde en la parte inferior).*

#### Paso 2: Ejecutar el descargador
Dentro de esa sesión de tmux, entra a la carpeta y lanza el monitor de cola:
```bash
cd driveplaytv
python3 ravedownmovie.py --queue
```
Verás el progreso de descarga y la subida en tiempo real a Google Drive.

#### Paso 3: Desconectarte de la sesión (Detach) sin detener el programa
Para salir de tmux y dejar el script corriendo en el fondo del VPS:
1. Presiona en tu teclado la combinación: **`Ctrl + B`**
2. Suelta ambas teclas.
3. Presiona la tecla: **`D`** *(de Detach / Desconectar)*.

Verás un mensaje en la consola como:
```text
[detached (from session movies)]
```
¡Listo! El descargador ya está corriendo de forma 100% autónoma en el servidor. Ya puedes cerrar la terminal, apagar tu PC o desconectarte.

---

### 3. Cómo Volver a Conectarte para Ver el Progreso (Attach)

Cuando quieras revisar el estado de las descargas:
1. Conéctate a tu VPS por SSH.
2. Reconéctate a la sesión con:
   ```bash
   tmux attach -t movies
   ```
   *(Si es de series: `tmux attach -t series`)*.

Volverás a ver la pantalla exactamente como la dejaste, con el progreso activo de las descargas.

---

### 4. Atajos y Comandos Esenciales de Tmux

| Acción | Comando / Atajo de Teclado |
| :--- | :--- |
| **Crear nueva sesión** | `tmux new -s [nombre]` |
| **Desconectarse (dejar en fondo)** | Presionar `Ctrl + B`, soltar y luego presionar `D` |
| **Reconectar a una sesión** | `tmux attach -t [nombre]` |
| **Listar sesiones activas** | `tmux ls` |
| **Subir/Bajar en el historial (Scroll)** | `Ctrl + B`, luego `[` (usa las flechas o `RePág`/`AvPág`). Presiona `q` para salir del modo scroll. |
| **Cerrar/Eliminar una sesión** | Escribir `exit` dentro de la sesión o ejecutar: `tmux kill-session -t [nombre]` |

---

### 💡 Consejo Pro: Descargar Películas y Series en Paralelo
Puedes tener dos sesiones independientes corriendo simultáneamente en el mismo VPS sin que interfieran entre sí:
```bash
# Sesión 1: Series
tmux new -s series
python3 ravedown.py --queue
# Presiona: Ctrl+B, luego D

# Sesión 2: Películas
tmux new -s movies
python3 ravedownmovie.py --queue
# Presiona: Ctrl+B, luego D
```
Para verificar que ambas siguen vivas y trabajando en segundo plano:
```bash
tmux ls
```

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

## ⚡ Solución al Problema de Rate Limits & Client ID Propio

### ¿Por qué se queda colgado en `200MB / 200MB (100%)` o tarda mucho tras subir varios videos?
1. **Client ID Público Compartido**: Por defecto, si no configuras tus propias credenciales, Rclone utiliza el Client ID público de Rclone. Como millones de personas lo usan a nivel mundial, Google activa frecuentemente el límite por IP y por API (`403 User Rate Limit Exceeded`).
2. **Commit Final y Checksums de Drive**: Al llegar al 100%, Google Drive procesa el hash MD5 y el registro en el índice de archivos. Si la API está saturada, este paso puede tardar minutos o fallar.
3. **Traversals Innecesarios**: Sin la opción `--no-traverse`, Rclone lista recursivamente la carpeta remota antes de cada archivo que sube, agotando rápidamente la cuota de peticiones por minuto.

---

### 🛡️ Optimizaciones ya integradas en `ravedownmovie.py` y `ravedown.py`:
- **`--drive-chunk-size=128M`**: Sube archivos grandes en bloques de 128 MB en vez de 8 MB, reduciendo la cantidad de llamadas HTTP a la API en más de un 90%.
- **`--no-traverse`**: Sube el archivo directamente a la ruta de destino sin escanear el contenido previo de Google Drive.
- **`--tpslimit=8` y `--drive-pacer-min-sleep=200ms`**: Regula la tasa máxima de transacciones por segundo para evitar picos que alerten a Google.
- **Cooldown post-subida (`upload_cooldown_seconds: 3`)**: Pausa de seguridad de 3 segundos entre películas consecutivas para dejar respirar a la API.
- **Reintentos con Backoff Exponencial**: Si Google devuelve un código 429 o `userRateLimitExceeded`, el script no se rompe: detecta el error automáticamente, pausa `30s * intento` y reanuda la subida.

---

### 🔑 Paso a Paso: Crear tu Propio Google Client ID (Recomendado para Máxima Estabilidad)

Tener tu propio Client ID te otorga **1,000,000 de consultas al día exclusivas para tu cuenta**, garantizando velocidad máxima y cero bloqueos.

#### Paso 1: Crear el proyecto en Google Cloud
1. Entra a [Google Cloud Console](https://console.cloud.google.com/) e inicia sesión con tu cuenta de Google.
2. En la barra superior, haz clic en el selector de proyectos y elige **"New Project"** (o **"Nuevo Proyecto"**).
3. Nómbralo como quieras (ej. `MiDriveRclone`) y pulsa **Create**.

#### Paso 2: Habilitar la API de Google Drive
1. En el menú lateral izquierdo (☰), ve a **APIs & Services** > **Library** (o **Biblioteca**).
2. Busca `Google Drive API`, selecciónala y haz clic en **Enable** (Habilitar).

#### Paso 3: Configurar la Pantalla de Consentimiento (OAuth Consent Screen)
1. En el menú lateral, ve a **APIs & Services** > **OAuth consent screen**.
2. Selecciona **External** (Externo) y haz clic en **Create**.
3. Rellena los datos básicos:
   - **App name**: `Rclone Drive`
   - **User support email**: Tu correo de Gmail.
   - **Developer contact information**: Tu correo de Gmail.
4. Pulsa **Save and Continue** en todas las secciones hasta llegar a **Test users** (Usuarios de prueba).
5. En **Test users**, haz clic en **+ ADD USERS** y escribe tu mismo correo de Gmail. *(Paso crucial para que Google te permita acceder sin verificar la aplicación).*
6. Pulsa **Save and Continue**.

#### Paso 4: Generar las Credenciales
1. En el menú lateral, ve a **APIs & Services** > **Credentials**.
2. Haz clic arriba en **+ CREATE CREDENTIALS** > **OAuth client ID**.
3. En **Application type**, selecciona **Desktop app** (Aplicación de escritorio).
4. En **Name**, escribe `Rclone` y pulsa **Create**.
5. Se abrirá una ventana con tu **Client ID** y tu **Client Secret**. Cópialos y guárdalos.

---

### 💻 Cómo Vincular tus Credenciales en Rclone en un VPS sin Navegador (Headless)

Como un VPS por lo general no tiene interfaz gráfica ni navegador web, Rclone utiliza un mecanismo muy simple:

1. **En la terminal de tu VPS:**
   ```bash
   rclone config
   ```
2. Elige `e` (Editar remote existente) y selecciona tu remote (ej. `gdrive`).
3. Cuando te pida `client_id`, pega tu Client ID propio.
4. Cuando te pida `client_secret`, pega tu Client Secret propio.
5. En `scope`, elige `1` (Full access all files).
6. En `root_folder_id`, presiona `Enter` (dejar vacío si quieres ver la raíz).
7. Cuando pregunte:
   ```text
   Use web browser to automatically authenticate?
   y) Yes
   n) No
   ```
   **Responde `n` (No)**.
8. Rclone te mostrará en la terminal un comando como este:
   ```bash
   rclone authorize "drive" "TU_CLIENT_ID" "TU_CLIENT_SECRET"
   ```
9. **En tu PC local** (en tu Windows en PowerShell o Mac/Linux donde tengas `rclone` instalado y navegador web):
   - Abre tu terminal local y pega ese comando exacto.
   - Se abrirá tu navegador web, selecciona tu cuenta de Google, haz clic en **"Continuar"** (si sale advertencia de seguridad, dale a Avanzado -> Continuar) y acepta los permisos.
   - En tu terminal local aparecerá un bloque JSON largo parecido a:
     ```json
     {"access_token":"ya29.a0...","token_type":"Bearer","refresh_token":"1//04...","expiry":"..."}
     ```
10. **Copia todo ese bloque JSON** y pégalo en la terminal de tu VPS cuando te pida:
    ```text
    Paste config token here:
    ```
11. Confirma con `y` y guarda.

¡Listo! A partir de ese momento, tanto `ravedownmovie.py` como `ravedown.py` utilizarán tu cuota privada con máxima estabilidad y sin bloqueos de peticiones.

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
