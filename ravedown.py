#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
=============================================================================
🎬 RAVEDOWN 3.0 - Automatizador de Descargas de Series & Sync con Google Drive
=============================================================================
- Extracción automática y limpia de nombres, temporadas y episodios.
- Selección automática de máxima calidad disponible (720p SD / 1080p HD).
- Cola en vivo a través de queue.txt o base de datos SQLite.
- Integración nativa con rclone para subir a Google Drive (5TB).
- Limpieza automática de archivos locales tras subir para ahorrar espacio.
=============================================================================
"""

import os
import sys
import re
import json
import time
import shutil
import sqlite3
import argparse
import subprocess
import urllib.request
import urllib.error
from datetime import datetime
from typing import Dict, List, Optional, Tuple, Any

# =====================================================================
# CONFIGURACIÓN Y CONSTANTES
# =====================================================================

CONFIG_FILE = "config.json"
DB_FILE = "ravedown.db"
DEFAULT_QUEUE_FILE = "queue.txt"
USER_AGENT = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Definición de prioridades de calidad
QUALITY_PRIORITIES = {
    "GROOT_FHD": 1080,
    "GROOT_HD": 1080,
    "GROOT_SD": 720,
    "GROOT_LD": 540,
    "GROOT_FD": 360,
}

# Códigos de color ANSI para consola
class Colors:
    HEADER = "\033[95m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RESET = "\033[0m"

    @classmethod
    def disable(cls):
        cls.HEADER = ""
        cls.BLUE = ""
        cls.CYAN = ""
        cls.GREEN = ""
        cls.YELLOW = ""
        cls.RED = ""
        cls.BOLD = ""
        cls.DIM = ""
        cls.RESET = ""

if sys.platform == "win32":
    # Habilitar UTF-8 y ANSI en terminales Windows
    try:
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        if hasattr(sys.stderr, "reconfigure"):
            sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    os.system("")

def log_info(msg: str):
    print(f"{Colors.BLUE}[INFO]{Colors.RESET} {msg}")

def log_success(msg: str):
    print(f"{Colors.GREEN}[OK]{Colors.RESET} {msg}")

def log_warn(msg: str):
    print(f"{Colors.YELLOW}[AVISO]{Colors.RESET} {msg}")

def log_error(msg: str):
    print(f"{Colors.RED}[ERROR]{Colors.RESET} {msg}")

def log_step(msg: str):
    print(f"{Colors.CYAN}▶{Colors.RESET} {Colors.BOLD}{msg}{Colors.RESET}")


# =====================================================================
# GESTOR DE CONFIGURACIÓN
# =====================================================================

def load_config() -> Dict[str, Any]:
    default_config = {
        "rclone_remote": "gdrive:Series",
        "rclone_enabled": True,
        "delete_after_upload": True,
        "upload_per_episode": True,
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
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                loaded = json.load(f)
                default_config.update(loaded)
        except Exception as e:
            log_warn(f"No se pudo leer {CONFIG_FILE}, usando valores por defecto. Error: {e}")
    else:
        try:
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(default_config, f, indent=2, ensure_ascii=False)
        except Exception:
            pass
    return default_config


# =====================================================================
# GESTOR DE BASE DE DATOS (HISTORIAL & COLA)
# =====================================================================

class Database:
    def __init__(self, db_path: str = DB_FILE):
        self.db_path = db_path
        self.init_db()

    def get_connection(self):
        return sqlite3.connect(self.db_path)

    def init_db(self):
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS series (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    url TEXT UNIQUE,
                    name TEXT,
                    season_num INTEGER,
                    total_episodes INTEGER,
                    status TEXT, -- QUEUED, IN_PROGRESS, COMPLETED, FAILED
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    error_message TEXT
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS episodes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    series_id INTEGER,
                    episode_num INTEGER,
                    quality TEXT,
                    m3u8_url TEXT,
                    local_path TEXT,
                    status TEXT, -- QUEUED, DOWNLOADING, DOWNLOADED, UPLOADING, UPLOADED, FAILED
                    file_size INTEGER DEFAULT 0,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (series_id) REFERENCES series (id),
                    UNIQUE (series_id, episode_num)
                )
            """)
            conn.commit()

    def add_or_get_series(self, url: str) -> Tuple[int, str]:
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT id, status FROM series WHERE url = ?", (url,))
            row = cursor.fetchone()
            if row:
                return row[0], row[1]
            cursor.execute("INSERT INTO series (url, status) VALUES (?, 'QUEUED')", (url,))
            conn.commit()
            return cursor.lastrowid, "QUEUED"

    def update_series_info(self, series_id: int, name: str, season_num: int, total_episodes: int):
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE series 
                SET name = ?, season_num = ?, total_episodes = ?, status = 'IN_PROGRESS', updated_at = CURRENT_TIMESTAMP 
                WHERE id = ?
            """, (name, season_num, total_episodes, series_id))
            conn.commit()

    def mark_series_status(self, series_id: int, status: str, error_message: Optional[str] = None):
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE series 
                SET status = ?, error_message = ?, updated_at = CURRENT_TIMESTAMP 
                WHERE id = ?
            """, (status, error_message, series_id))
            conn.commit()

    def add_or_update_episode(self, series_id: int, ep_num: int, quality: str, m3u8_url: str, local_path: str, status: str):
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO episodes (series_id, episode_num, quality, m3u8_url, local_path, status, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(series_id, episode_num) DO UPDATE SET
                    quality = excluded.quality,
                    m3u8_url = excluded.m3u8_url,
                    local_path = excluded.local_path,
                    status = excluded.status,
                    updated_at = CURRENT_TIMESTAMP
            """, (series_id, ep_num, quality, m3u8_url, local_path, status))
            conn.commit()

    def update_episode_status(self, series_id: int, ep_num: int, status: str, file_size: int = 0):
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE episodes 
                SET status = ?, file_size = COALESCE(NULLIF(?, 0), file_size), updated_at = CURRENT_TIMESTAMP
                WHERE series_id = ? AND episode_num = ?
            """, (status, file_size, series_id, ep_num))
            conn.commit()

    def is_episode_completed(self, series_id: int, ep_num: int) -> bool:
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT status FROM episodes WHERE series_id = ? AND episode_num = ?", (series_id, ep_num))
            row = cursor.fetchone()
            if row and row[0] in ("UPLOADED", "DOWNLOADED"):
                return True
            return False

    def get_summary(self) -> List[Dict[str, Any]]:
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT s.id, s.name, s.season_num, s.total_episodes, s.status, s.url,
                       COUNT(CASE WHEN e.status IN ('UPLOADED', 'DOWNLOADED') THEN 1 END) as completed_eps
                FROM series s
                LEFT JOIN episodes e ON s.id = e.series_id
                GROUP BY s.id
                ORDER BY s.id DESC
            """)
            rows = cursor.fetchall()
            return [
                {
                    "id": r[0],
                    "name": r[1] or "Desconocido",
                    "season": r[2] or 1,
                    "total_episodes": r[3] or 0,
                    "status": r[4],
                    "url": r[5],
                    "completed_eps": r[6] or 0
                }
                for r in rows
            ]


# =====================================================================
# EXTRACTOR DE METADATOS Y STREAM (CUEVANA / COMPATIBLES)
# =====================================================================

class CuevanaScraper:
    def __init__(self, user_agent: str = USER_AGENT):
        self.user_agent = user_agent
        self.headers = {
            "User-Agent": self.user_agent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
        }

    def fetch_html(self, url: str) -> str:
        req = urllib.request.Request(url, headers=self.headers)
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.read().decode("utf-8", errors="ignore")

    def clean_name(self, name: str) -> str:
        """Limpia caracteres no válidos para nombres de carpeta en Windows/Linux."""
        return re.sub(r'[\\/*?:"<>|]', "", name).strip()

    def parse_series_metadata(self, url: str) -> Dict[str, Any]:
        """Obtiene el nombre limpio de la serie, temporada y cantidad de episodios."""
        html = self.fetch_html(url)
        
        raw_name = ""
        season_num = 1
        total_episodes = 0
        episodes_list = []

        # Intentar extraer objeto __NEXT_DATA__
        next_data_match = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.DOTALL)
        if next_data_match:
            try:
                data = json.loads(next_data_match.group(1))
                page_props = data.get("props", {}).get("pageProps", {})
                
                raw_name = page_props.get("name") or page_props.get("drama", {}).get("name", "")
                current_season_obj = page_props.get("currentSeason", {})
                season_text = page_props.get("seasonText") or current_season_obj.get("name", "")
                
                episodes = current_season_obj.get("episodes", [])
                if episodes:
                    total_episodes = len(episodes)
                    episodes_list = list(range(1, total_episodes + 1))
            except Exception as e:
                log_warn(f"Error parseando JSON __NEXT_DATA__: {e}")

        # Fallback si no hay nombre en NEXT_DATA
        if not raw_name:
            og_match = re.search(r'<meta\s+property=["\']og:title["\']\s+content=["\']([^"\']+)["\']', html, re.I)
            if og_match:
                raw_name = og_match.group(1).split("-")[0].strip()

        # Detección limpia de Temporada
        detected_season = None
        # 1. Por el raw_name
        if raw_name:
            m = re.search(r'(?:temporada|season)\s*(\d+)', raw_name, re.I)
            if m:
                detected_season = int(m.group(1))
            else:
                m = re.search(r'(\d+)(?:st|nd|rd|th)?\s*season', raw_name, re.I)
                if m:
                    detected_season = int(m.group(1))

        # 2. Por el slug de la URL
        if detected_season is None:
            m = re.search(r'(\d+)(?:st|nd|rd|th)?[-_]season', url, re.I)
            if m:
                detected_season = int(m.group(1))
            else:
                m = re.search(r'season[-_](\d+)', url, re.I)
                if m:
                    detected_season = int(m.group(1))
                else:
                    m = re.search(r'temporada[-_](\d+)', url, re.I)
                    if m:
                        detected_season = int(m.group(1))

        season_num = detected_season if detected_season is not None else 1

        # Limpiar nombre base de la serie (remover 'Temporada X' o '2nd Season' del nombre base)
        clean_series = raw_name
        if not clean_series:
            # Extraer del slug
            slug = url.rstrip("/").split("/")[-1]
            slug = re.sub(r'^[a-zA-Z0-9]{10,40}-', '', slug)
            clean_series = slug.replace("-", " ").title()

        clean_series = re.sub(r'[\s\-_]+(?:temporada|season)\s*\d+.*$', '', clean_series, flags=re.I)
        clean_series = re.sub(r'[\s\-_]+\d+(?:st|nd|rd|th)?\s*season.*$', '', clean_series, flags=re.I)
        clean_series = self.clean_name(clean_series.strip())

        # Si aún no tenemos total de episodios, buscar enlaces href
        if total_episodes == 0:
            ep_links = re.findall(r'href=["\'][^"\']+/(\d+)["\']', html)
            if ep_links:
                ep_ints = [int(x) for x in ep_links if x.isdigit()]
                if ep_ints:
                    total_episodes = max(ep_ints)
                    episodes_list = list(range(1, total_episodes + 1))

        if total_episodes == 0:
            total_episodes = 12
            episodes_list = list(range(1, 13))

        return {
            "series_name": clean_series,
            "season_num": season_num,
            "total_episodes": total_episodes,
            "episodes_list": episodes_list,
            "base_url": url.rstrip("/")
        }

    def get_episode_stream(self, base_url: str, episode_num: int) -> Optional[Tuple[str, str]]:
        """
        Extrae el enlace m3u8 con la mejor calidad disponible para un episodio específico.
        Retorna (quality_name, m3u8_url) o None.
        """
        ep_url = f"{base_url.rstrip('/')}/{episode_num}"
        try:
            html = self.fetch_html(ep_url)
        except Exception as e:
            log_warn(f"Error descargando HTML de episodio {episode_num}: {e}")
            return None

        # 1. Buscar en __NEXT_DATA__
        next_data_match = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.DOTALL)
        if next_data_match:
            try:
                data = json.loads(next_data_match.group(1))
                media_list = data.get("props", {}).get("pageProps", {}).get("mediaInfoList", [])
                
                if media_list:
                    # Ordenar por prioridad de calidad
                    sorted_media = sorted(
                        media_list,
                        key=lambda x: QUALITY_PRIORITIES.get(x.get("currentDefinition", ""), 0),
                        reverse=True
                    )
                    best = sorted_media[0]
                    def_name = best.get("currentDefinition", "UNKNOWN")
                    m3u8_url = best.get("mediaUrl", "").replace("\\u0026", "&")
                    
                    if m3u8_url:
                        quality_label = f"{QUALITY_PRIORITIES.get(def_name, 720)}p ({def_name})"
                        return quality_label, m3u8_url
            except Exception as e:
                log_warn(f"Error parseando mediaInfoList en episodio {episode_num}: {e}")

        # 2. Fallback: Extraer cualquier .m3u8 y forzar -sd.m3u8 (720p) si tiene -ld.m3u8 (540p)
        direct_m3u8 = re.search(r'https?://[^\s"\'<>]+?\.m3u8[^\s"\'<>]*', html)
        if direct_m3u8:
            url_found = direct_m3u8.group(0).replace("\\u0026", "&")
            if "-ld.m3u8" in url_found:
                # Intentar mejorar a 720p
                sd_candidate = url_found.replace("-ld.m3u8", "-sd.m3u8")
                return "720p (SD auto)", sd_candidate
            return "Auto M3U8", url_found

        return None


# =====================================================================
# DESCARGADOR CON YT-DLP
# =====================================================================

class Downloader:
    def __init__(self, ytdlp_path: str = "yt-dlp", fragments: int = 5):
        self.ytdlp_cmd = self.detect_ytdlp(ytdlp_path)
        self.fragments = fragments

    def detect_ytdlp(self, custom_path: str) -> str:
        candidates = [
            custom_path,
            "yt-dlp",
            "yt-dlp.exe",
            "yt-dlp_linux",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
            os.path.expanduser("~/.local/bin/yt-dlp")
        ]
        for c in candidates:
            if shutil.which(c) or (os.path.isfile(c) and os.access(c, os.X_OK)):
                return c
        return "yt-dlp"

    def download_m3u8(self, m3u8_url: str, output_path: str) -> bool:
        """Descarga el stream m3u8 a un archivo local mp4."""
        os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
        
        cmd = [
            self.ytdlp_cmd,
            "-o", output_path,
            "--no-playlist",
            "--force-overwrites",
            "--user-agent", USER_AGENT,
            "--retries", "5",
            "--fragment-retries", "5",
            "--concurrent-fragments", str(self.fragments),
            "--buffer-size", "16M",
            "--no-warnings",
            m3u8_url
        ]

        try:
            res = subprocess.run(cmd, capture_output=False, text=True)
            if res.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 100000:
                return True
        except FileNotFoundError:
            log_error(f"No se encontró el ejecutable '{self.ytdlp_cmd}'. Instala yt-dlp.")
            return False
        except Exception as e:
            log_error(f"Error ejecutando yt-dlp: {e}")
            return False

        return False


# =====================================================================
# INTEGRACIÓN CON RCLONE (GOOGLE DRIVE)
# =====================================================================

class RcloneUploader:
    def __init__(self, remote: str, rclone_path: str = "rclone", flags: Optional[List[str]] = None):
        self.remote = remote.rstrip("/")
        self.rclone_cmd = self.detect_rclone(rclone_path)
        self.flags = flags or ["--drive-chunk-size=64M", "--transfers=4", "--fast-list", "-P"]

    def detect_rclone(self, custom_path: str) -> str:
        candidates = [
            custom_path,
            "rclone",
            "rclone.exe",
            "/usr/local/bin/rclone",
            "/usr/bin/rclone"
        ]
        for c in candidates:
            if shutil.which(c) or (os.path.isfile(c) and os.access(c, os.X_OK)):
                return c
        return "rclone"

    def test_connection(self) -> bool:
        """Verifica que el remote de Google Drive responda."""
        remote_root = self.remote.split(":")[0] + ":"
        cmd = [self.rclone_cmd, "lsd", remote_root]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            if res.returncode == 0:
                log_success(f"Conexión con rclone exitosa hacia '{self.remote}'")
                return True
            else:
                log_error(f"Error al conectar con rclone: {res.stderr.strip()}")
                return False
        except Exception as e:
            log_error(f"No se pudo ejecutar rclone: {e}")
            return False

    def upload_file(self, local_file: str, remote_dest_path: str) -> bool:
        """
        Sube un archivo individual a Google Drive manteniendo la jerarquía.
        remote_dest_path: ej. 'Rent-a-Girlfriend/Season 01/Rent-a-Girlfriend - S01E01.mp4'
        """
        if not os.path.exists(local_file):
            log_error(f"El archivo local '{local_file}' no existe.")
            return False

        # Construir destino completo con remote
        full_dest = f"{self.remote}/{remote_dest_path}"
        cmd = [self.rclone_cmd, "copyto", local_file, full_dest] + self.flags

        log_step(f"Subiendo a Google Drive: {Colors.CYAN}{remote_dest_path}{Colors.RESET}")
        try:
            res = subprocess.run(cmd, text=True)
            if res.returncode == 0:
                log_success(f"Subida completada en Drive: {remote_dest_path}")
                return True
            else:
                log_error(f"Falló la subida de rclone (Código {res.returncode})")
                return False
        except Exception as e:
            log_error(f"Excepción en subida rclone: {e}")
            return False

    def upload_directory(self, local_dir: str, remote_dir: str) -> bool:
        """Sube una carpeta completa a Google Drive."""
        if not os.path.exists(local_dir):
            return False

        full_dest = f"{self.remote}/{remote_dir}"
        cmd = [self.rclone_cmd, "copy", local_dir, full_dest] + self.flags

        log_step(f"Subiendo carpeta a Google Drive: {Colors.CYAN}{remote_dir}{Colors.RESET}")
        try:
            res = subprocess.run(cmd, text=True)
            return res.returncode == 0
        except Exception as e:
            log_error(f"Excepción en subida rclone: {e}")
            return False


# =====================================================================
# MOTOR PRINCIPAL DE DESCARGA Y COLA
# =====================================================================

class RavedownEngine:
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.db = Database()
        self.scraper = CuevanaScraper()
        self.downloader = Downloader(
            ytdlp_path=config.get("ytdlp_path", "yt-dlp"),
            fragments=config.get("concurrent_fragments", 5)
        )
        self.uploader = RcloneUploader(
            remote=config.get("rclone_remote", "gdrive:Series"),
            rclone_path=config.get("rclone_path", "rclone"),
            flags=config.get("rclone_flags")
        )

    def process_url(self, url: str, episode_filter: Optional[List[int]] = None) -> bool:
        """Procesa una serie completa o rango de episodios."""
        print("")
        print("=" * 60)
        log_step(f"Procesando URL: {Colors.BLUE}{url}{Colors.RESET}")
        print("=" * 60)

        series_id, initial_status = self.db.add_or_get_series(url)
        
        # 1. Extraer metadatos
        log_info("Extrayendo información de la serie y episodios...")
        try:
            meta = self.scraper.parse_series_metadata(url)
        except Exception as e:
            log_error(f"No se pudieron obtener los metadatos de la URL: {e}")
            self.db.mark_series_status(series_id, "FAILED", str(e))
            return False

        series_name = meta["series_name"]
        season_num = meta["season_num"]
        total_episodes = meta["total_episodes"]
        season_pad = f"{season_num:02d}"

        self.db.update_series_info(series_id, series_name, season_num, total_episodes)

        print("")
        print(f"  📺 {Colors.BOLD}Serie:{Colors.RESET}        {Colors.GREEN}{series_name}{Colors.RESET}")
        print(f"  🔢 {Colors.BOLD}Temporada:{Colors.RESET}    {Colors.GREEN}Season {season_pad}{Colors.RESET}")
        print(f"  📊 {Colors.BOLD}Total Caps:{Colors.RESET}   {Colors.GREEN}{total_episodes}{Colors.RESET}")
        print(f"  ☁️  {Colors.BOLD}Google Drive:{Colors.RESET} {Colors.CYAN}{self.config.get('rclone_remote')}/{series_name}/Season {season_pad}/{Colors.RESET}")
        print("=" * 60)
        print("")

        target_episodes = episode_filter if episode_filter else meta["episodes_list"]
        
        # 2. Descargar y subir cada episodio
        download_dir = self.config.get("download_dir", "./downloads")
        local_season_dir = os.path.join(download_dir, series_name, f"Season {season_pad}")
        os.makedirs(local_season_dir, exist_ok=True)

        failed_episodes = []
        completed_episodes = 0

        for ep_num in target_episodes:
            ep_pad = f"{ep_num:02d}"
            filename = f"{series_name} - S{season_pad}E{ep_pad}.mp4"
            local_file_path = os.path.join(local_season_dir, filename)
            remote_relative_path = f"{series_name}/Season {season_pad}/{filename}"

            # Verificar si ya está completado en base de datos
            if self.db.is_episode_completed(series_id, ep_num):
                log_info(f"Capítulo {ep_num}/{total_episodes} ya procesado anteriormente. Omitiendo.")
                completed_episodes += 1
                continue

            log_step(f"Obteniendo enlace para Episodio {ep_num}/{total_episodes}...")
            stream_info = self.scraper.get_episode_stream(url, ep_num)
            
            if not stream_info:
                log_error(f"No se encontró URL m3u8 para el capítulo {ep_num}")
                failed_episodes.append(ep_num)
                continue

            quality_label, m3u8_url = stream_info
            log_info(f"Calidad seleccionada: {Colors.GREEN}{quality_label}{Colors.RESET}")

            self.db.add_or_update_episode(
                series_id, ep_num, quality_label, m3u8_url, local_file_path, "DOWNLOADING"
            )

            # Descargar archivo
            log_info(f"Descargando {filename}...")
            success_dl = self.downloader.download_m3u8(m3u8_url, local_file_path)

            if not success_dl:
                log_error(f"Falló la descarga del episodio {ep_num}")
                self.db.update_episode_status(series_id, ep_num, "FAILED")
                failed_episodes.append(ep_num)
                continue

            file_size = os.path.getsize(local_file_path) if os.path.exists(local_file_path) else 0
            size_mb = file_size / (1024 * 1024)
            log_success(f"Episodio {ep_num} descargado ({size_mb:.1f} MB)")
            self.db.update_episode_status(series_id, ep_num, "DOWNLOADED", file_size)

            # Subir con Rclone
            if self.config.get("rclone_enabled", True) and self.config.get("upload_per_episode", True):
                self.db.update_episode_status(series_id, ep_num, "UPLOADING")
                uploaded = self.uploader.upload_file(local_file_path, remote_relative_path)
                
                if uploaded:
                    self.db.update_episode_status(series_id, ep_num, "UPLOADED")
                    completed_episodes += 1
                    
                    # Eliminar archivo local para preservar espacio en disco
                    if self.config.get("delete_after_upload", True):
                        try:
                            os.remove(local_file_path)
                            log_info(f"🗑️ Archivo local eliminado ({filename}) para liberar espacio.")
                        except Exception as e:
                            log_warn(f"No se pudo borrar archivo local: {e}")
                else:
                    log_error(f"No se pudo subir el episodio {ep_num} a Google Drive.")
                    failed_episodes.append(ep_num)
            else:
                completed_episodes += 1

            time.sleep(1)

        # Si se optó por subir toda la temporada junta
        if self.config.get("rclone_enabled", True) and not self.config.get("upload_per_episode", True):
            remote_season_dir = f"{series_name}/Season {season_pad}"
            uploaded = self.uploader.upload_directory(local_season_dir, remote_season_dir)
            if uploaded and self.config.get("delete_after_upload", True):
                shutil.rmtree(local_season_dir, ignore_errors=True)
                log_info(f"🗑️ Carpeta local eliminada ({local_season_dir}).")

        # Actualizar estado final de la serie
        if not failed_episodes:
            self.db.mark_series_status(series_id, "COMPLETED")
            log_success(f"🎉 Temporada completa finalizada con éxito: {series_name} - Season {season_pad}")
            return True
        else:
            self.db.mark_series_status(series_id, "PARTIAL", f"Fallaron episodios: {failed_episodes}")
            log_warn(f"Temporada terminada con {len(failed_episodes)} episodios fallidos: {failed_episodes}")
            return False

    def watch_queue(self):
        """Monitorea el archivo queue.txt en tiempo real y procesa nuevos enlaces."""
        queue_file = self.config.get("queue_file", DEFAULT_QUEUE_FILE)
        interval = self.config.get("watch_interval_seconds", 5)

        print("")
        print("=" * 65)
        print(f"👀 {Colors.BOLD}MODO MONITOR DE COLA ACTIVADO{Colors.RESET}")
        print(f"📄 Archivo de cola:  {Colors.CYAN}{queue_file}{Colors.RESET}")
        print(f"☁️  Google Drive:    {Colors.GREEN}{self.config.get('rclone_remote')}{Colors.RESET}")
        print(f"⏱️  Intervalo check: {interval}s")
        print("💡 Agrega URLs en queue.txt en cualquier momento para procesarlas.")
        print("=" * 65)
        print("")

        # Probar conexión rclone antes de empezar
        if self.config.get("rclone_enabled", True):
            self.uploader.test_connection()

        processed_urls = set()

        while True:
            try:
                if not os.path.exists(queue_file):
                    with open(queue_file, "w", encoding="utf-8") as f:
                        f.write("# Agrega tus enlaces aquí (uno por línea)\n")

                with open(queue_file, "r", encoding="utf-8") as f:
                    lines = [line.strip() for line in f.readlines()]

                urls_to_process = []
                for line in lines:
                    if line and not line.startswith("#") and line.startswith("http"):
                        urls_to_process.append(line)

                for url in urls_to_process:
                    if url not in processed_urls:
                        # Verificar si ya está completada en DB
                        series_id, status = self.db.add_or_get_series(url)
                        if status == "COMPLETED":
                            processed_urls.add(url)
                            continue

                        log_info(f"Tomando nuevo enlace de la cola: {url}")
                        success = self.process_url(url)
                        processed_urls.add(url)

                time.sleep(interval)
            except KeyboardInterrupt:
                print("\n🛑 Monitor de cola detenido por el usuario.")
                break
            except Exception as e:
                log_error(f"Error en el ciclo del monitor: {e}")
                time.sleep(interval)


# =====================================================================
# MODO INTERACTIVO
# =====================================================================

def interactive_mode(engine: RavedownEngine):
    print("")
    print("=" * 60)
    print("🎬 RAVEDOWN 3.0 - MODO INTERACTIVO")
    print("=" * 60)
    
    url = input("📎 Pega la URL de la serie / temporada: ").strip()
    if not url:
        print("❌ URL no válida.")
        return

    log_info("Consultando metadatos...")
    try:
        meta = engine.scraper.parse_series_metadata(url)
    except Exception as e:
        log_error(f"Error obteniendo metadatos: {e}")
        return

    series_name = meta["series_name"]
    season_num = meta["season_num"]
    total_episodes = meta["total_episodes"]

    print(f"\n📺 Serie detectada:      {Colors.GREEN}{series_name}{Colors.RESET}")
    name_input = input("¿Nombre correcto? (Enter para aceptar o escribe el nuevo): ").strip()
    if name_input:
        series_name = name_input

    print(f"🔢 Temporada detectada:  {Colors.GREEN}{season_num}{Colors.RESET}")
    season_input = input("¿Temporada correcta? (Enter para aceptar o escribe el número): ").strip()
    if season_input and season_input.isdigit():
        season_num = int(season_input)

    print(f"📊 Capítulos detectados: {Colors.GREEN}{total_episodes}{Colors.RESET}")
    total_input = input("¿Total correcto? (Enter para aceptar o escribe el total): ").strip()
    if total_input and total_input.isdigit():
        total_episodes = int(total_input)

    print("\n🎯 SELECCIÓN DE CAPÍTULOS:")
    print(f"1) 📚 Todos los capítulos (1 al {total_episodes})")
    print("2) 🎯 Rango específico (ej: 5-10)")
    print("3) 🎬 Solo un capítulo (ej: 1)")
    print("4) 📋 Capítulos específicos (ej: 1,3,7,12)")
    
    opt = input("\nSelecciona opción [1]: ").strip()
    ep_filter = None
    if opt == "2":
        r = input("Ingresa rango (ej: 5-10): ").strip()
        start, end = map(int, r.split("-"))
        ep_filter = list(range(start, end + 1))
    elif opt == "3":
        c = int(input("Ingresa número de capítulo: ").strip())
        ep_filter = [c]
    elif opt == "4":
        c_list = input("Ingresa números separados por coma: ").strip()
        ep_filter = [int(x.strip()) for x in c_list.split(",") if x.strip().isdigit()]

    engine.process_url(url, episode_filter=ep_filter)


# =====================================================================
# PUNTO DE ENTRADA (CLI)
# =====================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Ravedown 3.0 - Descargador de Series y Sincronizador con Google Drive (Rclone)"
    )
    parser.add_argument("--url", "-u", help="Descargar directamente una URL específica")
    parser.add_argument("--interactive", "-i", action="store_true", help="Ejecutar en modo interactivo")
    parser.add_argument("--queue", "-q", action="store_true", help="Monitorear archivo queue.txt en tiempo real")
    parser.add_argument("--status", "-s", action="store_true", help="Mostrar resumen de descargas e historial")
    parser.add_argument("--test-rclone", action="store_true", help="Probar conexión con Google Drive vía Rclone")
    parser.add_argument("--remote", help="Sobrescribir el remote de Rclone (ej: gdrive:Series)")

    args = parser.parse_args()
    config = load_config()

    if args.remote:
        config["rclone_remote"] = args.remote

    engine = RavedownEngine(config)

    if args.test_rclone:
        engine.uploader.test_connection()
    elif args.status:
        summary = engine.db.get_summary()
        print("\n" + "=" * 70)
        print("📊 HISTORIAL Y ESTADO DE DESCARGAS")
        print("=" * 70)
        if not summary:
            print("No hay descargas registradas en la base de datos.")
        else:
            for s in summary:
                print(f"ID #{s['id']:02d} | {Colors.BOLD}{s['name']}{Colors.RESET} - Season {s['season']:02d}")
                print(f"       Progreso: {s['completed_eps']}/{s['total_episodes']} caps | Estado: {s['status']}")
                print(f"       URL: {s['url']}")
                print("-" * 70)
    elif args.url:
        engine.process_url(args.url)
    elif args.interactive:
        interactive_mode(engine)
    else:
        # Por defecto si no se pasan argumentos: modo monitor de cola
        engine.watch_queue()

if __name__ == "__main__":
    main()
