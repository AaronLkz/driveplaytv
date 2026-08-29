# 🎬 RAVEDOWN 3.0 - Descargador de Series & Sync con Google Drive (5TB)

Automatizador inteligente y escalable para descargar series completas en máxima calidad (720p HD / 1080p), organizar temporadas y sincronizar automáticamente con Google Drive a través de **Rclone** liberando espacio en disco local.

---

## ✨ Novedades y Mejoras en la Versión 3.0

1. **Extracción Limpia y Precisa de Metadatos**:
   - Resuelve el problema de nombres "infectados" con códigos o hashes alfanuméricos (`FHlVhWt6O4KFZJnoMQejq-...`).
   - Detecta automáticamente el nombre real de la serie (ej. `Rent-a-Girlfriend`), el número exacto de temporada (`Season 01`, `Season 02`, etc.) y la cantidad total de episodios desde la estructura interna del sitio web.

2. **Máxima Calidad Automática (720p SD / 1080p HD)**:
   - Ya no se limita a 540p (`ld.m3u8`).
   - Prioriza y extrae automáticamente los streams en **720p** (`-sd.m3u8` / `GROOT_SD`) o superiores, garantizando la mejor resolución disponible.

3. **Optimizado para Cuentas de 5TB con Rclone**:
   - **Estructura automática en Google Drive**:
     ```
     GoogleDrive:Series/
     └── Rent-a-Girlfriend/
         ├── Season 01/
         │   ├── Rent-a-Girlfriend - S01E01.mp4
         │   └── Rent-a-Girlfriend - S01E02.mp4
         └── Season 02/
             ├── Rent-a-Girlfriend - S02E01.mp4
             └── Rent-a-Girlfriend - S02E02.mp4
     ```
   - **Gestión de Espacio en Disco (`delete_after_upload`)**: Para llenar 5TB sin saturar el disco de tu PC o VPS, cada episodio se sube inmediatamente a Google Drive y se elimina la copia local tras verificar el éxito de la subida.

4. **Sistema de Cola en Vivo (`queue.txt` + Base de Datos SQLite)**:
   - Puedes pegar enlaces en `queue.txt` en tiempo real mientras el script está en ejecución.
   - Lleva un registro en base de datos (`ravedown.db`) para reanudar descargas interrumpidas sin repetir episodios ya completados.

5. **Doble Soporte Multiplataforma**:
   - **Python (`ravedown.py`)**: Para Windows, Linux y macOS, con monitor de cola en vivo y base de datos SQLite.
   - **Bash (`ravedown3.0.sh`)**: Script universal optimizado para servidores VPS / Linux.

---

## 🚀 Requisitos e Instalación

### 1. Requisitos del Sistema
- **Python 3.8+** (para `ravedown.py`)
- **yt-dlp**: Descargador de streams m3u8 / HLS.
- **rclone**: Para sincronizar con Google Drive.

### 2. Instalación de Dependencias

#### En Windows:
1. **yt-dlp**: Descarga `yt-dlp.exe` desde [Releases Oficiales](https://github.com/yt-dlp/yt-dlp/releases/latest) y colócalo en tu carpeta de usuario o en el PATH.
2. **rclone**: Descarga `rclone.exe` desde [rclone.org](https://rclone.org/downloads/) y colócalo en el PATH.

#### En Linux / VPS:
```bash
# Instalar yt-dlp
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp

# Instalar rclone
curl https://rclone.org/install.sh | sudo bash
```

---

## ☁️ Configuración de Google Drive con Rclone

Para conectar tu cuenta de Google Drive de 5TB con Rclone:

1. Ejecuta en tu terminal:
   ```bash
   rclone config
   ```
2. Selecciona `n` (Nuevo remote).
3. Nombre: `gdrive` (o el nombre que prefieras).
4. Tipo de almacenamiento: Busca el número correspondiente a **`Google Drive`** (usualmente `drive`).
5. Sigue las instrucciones para autenticar tu cuenta de Google en el navegador.
6. Verifica la conexión ejecutando:
   ```bash
   rclone lsd gdrive:
   ```

---

## ⚙️ Configuración (`config.json`)

Edita el archivo `config.json` para personalizar el comportamiento:

```json
{
  "rclone_remote": "gdrive:Series",
  "rclone_enabled": true,
  "delete_after_upload": true,
  "upload_per_episode": true,
  "preferred_quality": "720p",
  "concurrent_fragments": 5,
  "download_dir": "./downloads",
  "queue_file": "queue.txt",
  "ytdlp_path": "yt-dlp",
  "rclone_path": "rclone",
  "watch_interval_seconds": 5,
  "rclone_flags": [
    "--drive-chunk-size=64M",
    "--transfers=4",
    "--fast-list",
    "-P"
  ]
}
```

*Nota:* Si tu remote en Rclone tiene otro nombre (por ejemplo `midrive`), cambia `"gdrive:Series"` por `"midrive:Series"`.

---

## 📖 Modo de Uso

### Opción A: Modo Monitor de Cola (Recomendado para Descargas Masivas)

1. Abre el archivo `queue.txt` y agrega las URLs que deseas descargar (una por línea):
   ```text
   https://es.cuevana4br.com/es/detail/drama/FHlVhWt6O4KFZJnoMQejq-Rent-a-Girlfriend
   https://es.cuevana4br.com/es/detail/drama/9ByZz4ZV1iyQxBL8bVtjQ-Rent-a-Girlfriend-2nd-Season
   ```
2. Inicia el monitor:
   ```bash
   python ravedown.py
   ```
3. El programa detectará cada enlace, creará las carpetas correspondientes en Google Drive, descargará en 720p, subirá los episodios y liberará espacio en disco.
4. **Puedes seguir agregando enlaces a `queue.txt` en cualquier momento.**

---

### Opción B: Modo Interactivo

Si deseas descargar una serie puntual o seleccionar un rango de episodios (ej. capítulos 5 al 10):

```bash
python ravedown.py --interactive
```

---

### Opción C: Descarga Directa por Comando

```bash
python ravedown.py --url "https://es.cuevana4br.com/es/detail/drama/FHlVhWt6O4KFZJnoMQejq-Rent-a-Girlfriend"
```

---

### Opción D: Consultar Estado e Historial de Descargas

```bash
python ravedown.py --status
```

---

### Opción E: Probar Conexión con Google Drive

```bash
python ravedown.py --test-rclone
```

---

### Opción F: Uso con Script Bash (`ravedown3.0.sh` en Linux/VPS)

```bash
chmod +x ravedown3.0.sh
./ravedown3.0.sh
```

---

## 📁 Estructura del Proyecto

```
driveplaytv/
├── ravedown.py          # Programa principal con cola, rclone y base de datos
├── config.json          # Archivo de configuración personalizable
├── queue.txt            # Archivo de cola de enlaces en vivo
├── ravedown.db          # Base de datos SQLite (se genera automáticamente)
├── ravedown3.0.sh       # Script universal Bash para Linux/VPS
├── ravedown2.1.sh       # Script original (preservado como respaldo)
└── README.md            # Documentación completa
```
