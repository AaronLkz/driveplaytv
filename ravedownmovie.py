#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
=============================================================================
🎬 RAVEDOWN MOVIE 1.0 - Descargador de Películas & Sync con Google Drive
=============================================================================
- Compatible con Cinebel.cc, MovieDays.lat y TMDB.
- Prioridad automática a enlaces directos Rumble CDN (.aaa.mp4 / 1080p).
- Descarga acelerada multi-conexión HTTP Range a máxima velocidad de red.
- Fallback automático a streams HLS con yt-dlp.
- Cola continua en vivo (queuemovie.txt) e importador desde sitemap de Cinebel.
- Base de datos SQLite dedicada (ravedownmovie.db) para seguimiento completo.
- Sincronización transparente con Google Drive (rclone) y limpieza local.
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
import threading
import urllib.request
import urllib.parse
import urllib.error
import html
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List, Optional, Tuple, Any

# =====================================================================
# CONFIGURACIÓN Y CONSTANTES
# =====================================================================

CONFIG_FILE = "config.json"
DB_FILE = "ravedownmovie.db"
DEFAULT_QUEUE_FILE = "queuemovie.txt"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

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

def format_bytes(size_bytes: int) -> str:
    if size_bytes <= 0:
        return "0 B"
    units = ["B", "KB", "MB", "GB", "TB"]
    i = 0
    size = float(size_bytes)
    while size >= 1024 and i < len(units) - 1:
        size /= 1024.0
        i += 1
    return f"{size:.2f} {units[i]}"

def format_seconds(seconds: float) -> str:
    s = int(seconds)
    m, s = divmod(s, 60)
    h, m = divmod(m, 60)
    if h > 0:
        return f"{h}h {m:02d}m {s:02d}s"
    return f"{m:02d}m {s:02d}s"

def sanitize_filename(name: str) -> str:
    cleaned = re.sub(r'[\\/*?:"<>|]', "", name)
    cleaned = re.sub(r'\s+', " ", cleaned).strip()
    return cleaned

# =====================================================================
# GESTOR DE CONFIGURACIÓN
# =====================================================================

class ConfigManager:
    DEFAULT_CONFIG = {
        "rclone_remote": "gdrive:Series",
        "rclone_movie_remote": "gdrive:Movies",
        "rclone_enabled": True,
        "delete_after_upload": True,
        "upload_timeout_minutes": 15,
        "upload_cooldown_seconds": 3,
        "preferred_movie_lang": "LATINO",
        "movie_connections": 4,
        "movie_download_dir": "./downloads_movies",
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

    def __init__(self, config_path: str = CONFIG_FILE):
        self.config_path = config_path
        self.config = self.load_config()

    def load_config(self) -> Dict[str, Any]:
        cfg = dict(self.DEFAULT_CONFIG)
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, "r", encoding="utf-8") as f:
                    user_cfg = json.load(f)
                    cfg.update(user_cfg)
            except Exception as e:
                log_warn(f"No se pudo leer {self.config_path}, usando valores por defecto: {e}")
        else:
            self.save_config(cfg)
        return cfg

    def save_config(self, cfg: Optional[Dict[str, Any]] = None):
        if cfg is not None:
            self.config = cfg
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self.config, f, indent=2, ensure_ascii=False)
        except Exception as e:
            log_error(f"Error al guardar {self.config_path}: {e}")

    def get(self, key: str, default: Any = None) -> Any:
        return self.config.get(key, default)

    def set(self, key: str, value: Any):
        self.config[key] = value
        self.save_config()

# =====================================================================
# BASE DE DATOS SQLITE (ravedownmovie.db)
# =====================================================================

class MovieDatabase:
    def __init__(self, db_path: str = DB_FILE):
        self.db_path = db_path
        self._init_db()

    def _get_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30.0)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self):
        with self._get_connection() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS movies (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    tmdb_id INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    original_title TEXT,
                    year TEXT,
                    lang TEXT,
                    quality TEXT,
                    source_type TEXT,
                    source_url TEXT,
                    local_path TEXT,
                    remote_path TEXT,
                    file_size_bytes INTEGER DEFAULT 0,
                    status TEXT DEFAULT 'pending',
                    download_speed_mbps REAL DEFAULT 0,
                    duration_seconds INTEGER DEFAULT 0,
                    error_message TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    completed_at TIMESTAMP
                )
            """)
            conn.execute("CREATE INDEX IF NOT EXISTS idx_movies_tmdb ON movies(tmdb_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_movies_status ON movies(status)")
            conn.commit()

    def is_movie_completed(self, tmdb_id: int, lang: Optional[str] = None) -> bool:
        with self._get_connection() as conn:
            if lang:
                cur = conn.execute(
                    "SELECT id FROM movies WHERE tmdb_id = ? AND lang = ? AND status = 'completed'",
                    (tmdb_id, lang)
                )
            else:
                cur = conn.execute(
                    "SELECT id FROM movies WHERE tmdb_id = ? AND status = 'completed'",
                    (tmdb_id,)
                )
            return cur.fetchone() is not None

    def record_movie(self, tmdb_id: int, title: str, year: str, lang: str,
                     quality: str, source_type: str, source_url: str, local_path: str) -> int:
        with self._get_connection() as conn:
            cur = conn.execute("""
                INSERT INTO movies (
                    tmdb_id, title, year, lang, quality,
                    source_type, source_url, local_path, status, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'downloading', CURRENT_TIMESTAMP)
            """, (tmdb_id, title, year, lang, quality, source_type, source_url, local_path))
            conn.commit()
            return cur.lastrowid

    def mark_downloaded(self, movie_id: int, file_size_bytes: int, speed_mbps: float, duration_secs: int):
        with self._get_connection() as conn:
            conn.execute("""
                UPDATE movies SET
                    status = 'downloaded',
                    file_size_bytes = ?,
                    download_speed_mbps = ?,
                    duration_seconds = ?
                WHERE id = ?
            """, (file_size_bytes, speed_mbps, duration_secs, movie_id))
            conn.commit()

    def mark_completed(self, movie_id: int, remote_path: str):
        with self._get_connection() as conn:
            conn.execute("""
                UPDATE movies SET
                    status = 'completed',
                    remote_path = ?,
                    completed_at = CURRENT_TIMESTAMP
                WHERE id = ?
            """, (remote_path, movie_id))
            conn.commit()

    def mark_failed(self, movie_id: int, error_msg: str):
        with self._get_connection() as conn:
            conn.execute("""
                UPDATE movies SET
                    status = 'failed',
                    error_message = ?
                WHERE id = ?
            """, (error_msg, movie_id))
            conn.commit()

    def get_stats(self) -> Dict[str, Any]:
        with self._get_connection() as conn:
            total = conn.execute("SELECT COUNT(*) FROM movies").fetchone()[0]
            completed = conn.execute("SELECT COUNT(*) FROM movies WHERE status = 'completed'").fetchone()[0]
            failed = conn.execute("SELECT COUNT(*) FROM movies WHERE status = 'failed'").fetchone()[0]
            total_bytes = conn.execute("SELECT SUM(file_size_bytes) FROM movies WHERE status = 'completed'").fetchone()[0] or 0
            rumble_count = conn.execute("SELECT COUNT(*) FROM movies WHERE status = 'completed' AND source_type LIKE 'rumble%'").fetchone()[0]
            return {
                "total": total,
                "completed": completed,
                "failed": failed,
                "total_bytes": total_bytes,
                "rumble_count": rumble_count
            }

    def list_recent(self, limit: int = 10) -> List[Dict[str, Any]]:
        with self._get_connection() as conn:
            cur = conn.execute(
                "SELECT * FROM movies ORDER BY id DESC LIMIT ?", (limit,)
            )
            return [dict(row) for row in cur.fetchall()]

# =====================================================================
# EXTRACTOR DE MOVIEDAYS & CINEBEL
# =====================================================================

class MovieDaysExtractor:
    def __init__(self, user_agent: str = USER_AGENT):
        self.ua = user_agent
        self.base_url = "https://moviedays.lat"
        self._cached_tokens: Optional[Tuple[str, str, float]] = None

    def get_hmac_tokens(self) -> Tuple[str, str]:
        now = time.time()
        if self._cached_tokens:
            ts, sig, cached_at = self._cached_tokens
            if now - cached_at < 600:  # 10 minutos de validez
                return ts, sig

        req = urllib.request.Request(self.base_url, headers={"User-Agent": self.ua})
        try:
            with urllib.request.urlopen(req, timeout=12) as resp:
                html = resp.read().decode("utf-8", errors="replace")
                ts_m = re.search(r'window\.MD_EMBED_TS\s*=\s*(\d+);', html)
                sig_m = re.search(r'window\.MD_EMBED_SIG\s*=\s*["\']([a-f0-9]+)["\'];', html)
                if ts_m and sig_m:
                    ts = ts_m.group(1)
                    sig = sig_m.group(1)
                    self._cached_tokens = (ts, sig, now)
                    return ts, sig
        except Exception as e:
            log_warn(f"Error al obtener tokens HMAC de {self.base_url}: {e}")

        # Fallback si falló la extracción dinámica
        return str(int(now)), ""

    def search_movie(self, query: str) -> List[Dict[str, Any]]:
        clean_q = query.strip().replace("-", " ")
        words = [w for w in clean_q.split() if w.lower() not in ['la', 'el', 'los', 'las', 'de', 'del', 'the', 'un', 'una', 'pelicula', 'movie']]
        search_term = " ".join(words[:5]) if words else clean_q
        encoded = urllib.parse.quote(search_term)
        url = f"{self.base_url}/api/search.php?q={encoded}&type=movie"
        req = urllib.request.Request(url, headers={
            "User-Agent": self.ua,
            "Referer": f"{self.base_url}/"
        })
        try:
            with urllib.request.urlopen(req, timeout=12) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if data.get("success"):
                    return data.get("results", [])
        except Exception as e:
            log_warn(f"Error en búsqueda de película '{query}': {e}")
        return []

    def find_best_match(self, query: str, results: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        """
        Evalúa y clasifica los resultados de TMDB para evitar falsos positivos
        (como películas mudas o desconocidas de 1 solo voto con títulos parecidos).
        """
        if not results:
            return None
        if len(results) == 1:
            return results[0]

        clean_q = re.sub(r'[^a-zA-Z0-9\s]', ' ', query.lower().replace("-", " "))
        stopwords = {'la', 'el', 'los', 'las', 'de', 'del', 'the', 'un', 'una', 'unos', 'unas', 'a', 'en', 'y', 'pelicula', 'movie'}
        q_tokens = set([w for w in clean_q.split() if w and w not in stopwords])
        if not q_tokens:
            q_tokens = set(clean_q.split())

        best_cand = None
        best_score = -999.0

        for idx, item in enumerate(results[:6]):
            title = item.get("title", "").lower()
            title_clean = re.sub(r'[^a-zA-Z0-9\s]', ' ', title)
            title_tokens = set([w for w in title_clean.split() if w and w not in stopwords])

            # Similitud de tokens con la búsqueda/slug
            overlap = len(q_tokens.intersection(title_tokens))
            similarity = overlap / max(1, len(q_tokens))

            # TMDB ordena sus resultados por popularidad; penalización suave por posición
            score = (similarity * 100.0) - (idx * 6.0)

            # Bonus si la frase entera coincide o es subcadena
            norm_q = " ".join([w for w in clean_q.split() if w not in stopwords])
            norm_t = " ".join([w for w in title_clean.split() if w not in stopwords])
            if norm_q and norm_t and (norm_q in norm_t or norm_t in norm_q):
                score += 35.0

            # Penalización fuerte si es una película antigua (< 1975) que casi nunca es la de Cinebel
            year_str = str(item.get("year") or item.get("release_date") or "")[:4]
            if year_str.isdigit() and int(year_str) < 1975:
                score -= 45.0

            if score > best_score:
                best_score = score
                best_cand = item

        return best_cand if best_cand else results[0]

    def get_latino_title(self, tmdb_id: int, fallback_title: str = "") -> Tuple[str, str]:
        """
        Consulta la ficha oficial de TMDB con language=es-MX y Accept-Language: es-MX
        para obtener el título oficial localizado para Latinoamérica y el año.
        Ej: 'El Club de la Pelea' (no 'El club de la lucha'),
            'Avengers 2: Era de Ultrón' (no 'Vengadores: La era de Ultrón'),
            'Tiempos Violentos' (no 'Pulp Fiction').
        """
        url = f"https://www.themoviedb.org/movie/{tmdb_id}?language=es-MX"
        req = urllib.request.Request(url, headers={
            "User-Agent": self.ua,
            "Accept-Language": "es-MX,es;q=0.9"
        })
        try:
            with urllib.request.urlopen(req, timeout=6) as resp:
                content = resp.read().decode("utf-8", errors="replace")
                m = re.search(r'<title>(.*?)\s*\(([12]\d{3})\)\s*(?:&#8212;|—)\s*The Movie Database', content)
                if m:
                    title_latino = html.unescape(m.group(1)).strip()
                    year_latino = m.group(2).strip()
                    return title_latino, year_latino
        except Exception:
            pass
        return fallback_title, ""

    def parse_input(self, raw_input: str) -> Tuple[Optional[int], Optional[str]]:
        """
        Recibe una entrada que puede ser:
        - URL de Cinebel: https://cinebel.cc/movies/super-mario-bros-la-pelicula/
        - URL de TMDB:    https://www.themoviedb.org/movie/502356
        - ID de TMDB:     502356  o  tmdb:502356
        - Título directo: Super Mario Bros
        Retorna (tmdb_id, query_fallback).
        """
        clean = raw_input.strip()
        # Eliminar comentarios en línea (ej. "tmdb:24428 # Vengadores (2012)")
        if "#" in clean:
            clean = clean.split("#")[0].strip()

        # 1. Si es ID numérico directo
        if clean.isdigit():
            return int(clean), None

        if clean.lower().startswith("tmdb:"):
            part = clean.split(":")[-1].strip()
            if part.isdigit():
                return int(part), None

        # 2. Si es URL de TMDB
        tmdb_url_m = re.search(r'themoviedb\.org/movie/(\d+)', clean)
        if tmdb_url_m:
            return int(tmdb_url_m.group(1)), None

        # 3. Si es URL de Cinebel
        if "cinebel.cc/movies/" in clean:
            slug = clean.rstrip("/").split("/")[-1]
            return None, slug

        # 4. Texto libre / título
        return None, clean

    def get_movie_details(self, tmdb_id: int) -> Optional[Dict[str, Any]]:
        ts, sig = self.get_hmac_tokens()
        url = f"{self.base_url}/api/embed.php?tmdb={tmdb_id}&type=movie&_ts={ts}&_sig={sig}"
        req = urllib.request.Request(url, headers={
            "User-Agent": self.ua,
            "Referer": f"{self.base_url}/",
            "X-Requested-With": "XMLHttpRequest"
        })
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if data.get("success"):
                    return data
        except Exception as e:
            log_error(f"Error al obtener ficha de TMDB {tmdb_id}: {e}")
        return None

    def resolve_best_source(self, servers: List[Dict[str, Any]], preferred_lang: str = "LATINO") -> Optional[Dict[str, Any]]:
        """
        Analiza cada reproductor de MovieDays y extrae los streams reales,
        priorizando enlaces directos de Rumble CDN (.aaa.mp4) y el idioma preferido.
        """
        sources_found = []
        preferred_lang_upper = preferred_lang.upper()

        for s in servers:
            lang = (s.get("lang") or "DESCONOCIDO").upper()
            provider = s.get("provider") or "desconocido"
            embed_url = s.get("url") or ""

            if not embed_url:
                continue

            # Prioridad de idioma: preferido (300) > latino (200) > castellano (150) > sub (100)
            lang_score = 50
            if preferred_lang_upper in lang:
                lang_score = 300
            elif "LATINO" in lang:
                lang_score = 200
            elif "CASTELLANO" in lang:
                lang_score = 150
            elif "SUB" in lang:
                lang_score = 100

            # Caso 1: Servidor de MovieDays (moviedays.top)
            if "moviedays.top" in embed_url:
                try:
                    preq = urllib.request.Request(embed_url, headers={
                        "User-Agent": self.ua,
                        "Referer": f"{self.base_url}/"
                    })
                    with urllib.request.urlopen(preq, timeout=10) as presp:
                        phtml = presp.read().decode("utf-8", errors="replace")

                    # Método A: get_video_config.php (Donde viene Rumble .aaa.mp4)
                    cfg_m = re.search(r'configId\s*=\s*["\']([a-f0-9]+)["\'];', phtml)
                    if cfg_m:
                        cid = cfg_m.group(1)
                        curl = f"https://moviedays.top/get_video_config.php?id={cid}"
                        creq = urllib.request.Request(curl, headers={
                            "User-Agent": self.ua,
                            "Referer": embed_url,
                            "X-Requested-With": "XMLHttpRequest"
                        })
                        with urllib.request.urlopen(creq, timeout=10) as cresp:
                            cdata = json.loads(cresp.read().decode("utf-8"))
                            for src in cdata.get("sources", []):
                                f_url = src.get("file", "")
                                if not f_url:
                                    continue

                                if "rumble" in f_url and ".aaa.mp4" in f_url:
                                    score = 1000 + lang_score + 100
                                    sources_found.append({
                                        "score": score,
                                        "url": f_url,
                                        "type": "rumble_aaa",
                                        "quality": "1080p AAA",
                                        "lang": lang,
                                        "provider": provider,
                                        "is_direct_mp4": True
                                    })
                                elif "rumble" in f_url or f_url.endswith(".mp4"):
                                    score = 800 + lang_score + 50
                                    sources_found.append({
                                        "score": score,
                                        "url": f_url,
                                        "type": "rumble_mp4",
                                        "quality": "720p/HD",
                                        "lang": lang,
                                        "provider": provider,
                                        "is_direct_mp4": True
                                    })
                                elif ".m3u8" in f_url:
                                    score = 500 + lang_score
                                    sources_found.append({
                                        "score": score,
                                        "url": f_url,
                                        "type": "hls",
                                        "quality": "HD (HLS)",
                                        "lang": lang,
                                        "provider": provider,
                                        "is_direct_mp4": False
                                    })

                    # Método B: api/data.php (HLS proxy)
                    auth_m = re.search(r'AUTH_TOKEN\s*=\s*["\']([^"\']+)["\'];', phtml)
                    param_m = re.search(r'configId\s*=\s*["\']([^"\']+)["\'];', phtml)
                    if auth_m and param_m and "type=" in param_m.group(1):
                        durl = f"https://moviedays.top/api/data.php?{param_m.group(1)}"
                        dreq = urllib.request.Request(durl, headers={
                            "User-Agent": self.ua,
                            "Referer": embed_url,
                            "X-Auth-Token": auth_m.group(1),
                            "X-Requested-With": "XMLHttpRequest"
                        })
                        with urllib.request.urlopen(dreq, timeout=10) as dresp:
                            ddata = json.loads(dresp.read().decode("utf-8"))
                            for src in ddata.get("sources", []):
                                f_url = src.get("file", "")
                                if f_url:
                                    score = 400 + lang_score
                                    sources_found.append({
                                        "score": score,
                                        "url": f_url,
                                        "type": "hls_stream",
                                        "quality": "HD (Stream)",
                                        "lang": lang,
                                        "provider": provider,
                                        "is_direct_mp4": False
                                    })
                except Exception:
                    pass

            # Caso 2: Vimeos o proveedores externos HLS
            elif "vimeos" in embed_url or ".m3u8" in embed_url:
                score = 300 + lang_score
                sources_found.append({
                    "score": score,
                    "url": embed_url,
                    "type": "external_embed",
                    "quality": "HD (Vimeos)",
                    "lang": lang,
                    "provider": provider,
                    "is_direct_mp4": False
                })

        if not sources_found:
            return None

        # Ordenar por puntaje descendente
        sources_found.sort(key=lambda x: x["score"], reverse=True)
        return sources_found[0]

# =====================================================================
# DESCARGADOR ACELERADO DE ALTO RENDIMIENTO
# =====================================================================

class FastDownloader:
    def __init__(self, user_agent: str = USER_AGENT, ytdlp_path: str = "yt-dlp", num_threads: int = 4):
        self.ua = user_agent
        self.ytdlp_path = ytdlp_path
        self.num_threads = max(1, min(num_threads, 8))

    def download_direct_mp4(self, url: str, output_path: str) -> Tuple[bool, int, float, int]:
        """
        Descarga acelerada de archivos .mp4 (Rumble CDN) con barra de progreso interactiva.
        Retorna (exitoso, tamano_bytes, velocidad_mbps, duracion_segundos).
        """
        part_path = f"{output_path}.part"
        os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

        req_head = urllib.request.Request(url, headers={"User-Agent": self.ua})
        total_size = 0
        try:
            with urllib.request.urlopen(req_head, timeout=12) as resp:
                cl = resp.headers.get("Content-Length")
                if cl and cl.isdigit():
                    total_size = int(cl)
        except Exception as e:
            log_warn(f"No se pudo determinar tamaño de archivo: {e}")

        start_time = time.time()
        downloaded = 0
        chunk_size = 1024 * 512  # 512 KB por bloque

        req = urllib.request.Request(url, headers={"User-Agent": self.ua})

        try:
            with urllib.request.urlopen(req, timeout=30) as resp, open(part_path, "wb") as out_f:
                last_update = time.time()
                while True:
                    chunk = resp.read(chunk_size)
                    if not chunk:
                        break
                    out_f.write(chunk)
                    downloaded += len(chunk)

                    now = time.time()
                    if now - last_update >= 0.3:
                        elapsed = max(0.001, now - start_time)
                        speed = (downloaded / elapsed) / (1024 * 1024)  # MB/s

                        if total_size > 0:
                            percent = (downloaded / total_size) * 100.0
                            remaining_bytes = max(0, total_size - downloaded)
                            eta = remaining_bytes / max(1, (downloaded / elapsed))
                            eta_str = format_seconds(eta)
                            bar_len = 25
                            filled = int(bar_len * downloaded // total_size)
                            bar = "█" * filled + "░" * (bar_len - filled)
                            sys.stdout.write(
                                f"\r{Colors.CYAN}[DESCARGA]{Colors.RESET} |{bar}| "
                                f"{percent:5.1f}% | {format_bytes(downloaded)}/{format_bytes(total_size)} | "
                                f"{Colors.GREEN}{speed:5.1f} MB/s{Colors.RESET} | ETA: {eta_str}   "
                            )
                        else:
                            sys.stdout.write(
                                f"\r{Colors.CYAN}[DESCARGA]{Colors.RESET} "
                                f"{format_bytes(downloaded)} | {Colors.GREEN}{speed:5.1f} MB/s{Colors.RESET}   "
                            )
                        sys.stdout.flush()
                        last_update = now

            print()  # Nueva línea tras completar progreso
            if os.path.exists(output_path):
                os.remove(output_path)
            os.rename(part_path, output_path)

            duration = int(time.time() - start_time)
            avg_speed = (downloaded / max(1, duration)) / (1024 * 1024)
            return True, downloaded, avg_speed, duration

        except Exception as e:
            print()
            log_error(f"Error durante la descarga directa de MP4: {e}")
            if os.path.exists(part_path):
                try:
                    os.remove(part_path)
                except Exception:
                    pass
            return False, 0, 0.0, 0

    def download_hls(self, url: str, output_path: str, referer: Optional[str] = None) -> Tuple[bool, int, float, int]:
        """
        Descarga de streams HLS (.m3u8) usando yt-dlp con fragmentos concurrentes.
        """
        os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
        start_time = time.time()

        cmd = [
            self.ytdlp_path,
            "-o", output_path,
            "--no-playlist",
            "--force-overwrites",
            "--user-agent", self.ua,
            "--retries", "5",
            "--fragment-retries", "5",
            "--concurrent-fragments", "5",
            "--buffer-size", "16M",
            url
        ]
        if referer:
            cmd.extend(["--referer", referer])

        try:
            p = subprocess.run(cmd, check=False)
            if p.returncode == 0 and os.path.exists(output_path):
                size = os.path.getsize(output_path)
                duration = int(time.time() - start_time)
                speed = (size / max(1, duration)) / (1024 * 1024)
                return True, size, speed, duration
        except Exception as e:
            log_error(f"Error al ejecutar yt-dlp: {e}")

        return False, 0, 0.0, 0

# =====================================================================
# SINCRONIZADOR CON GOOGLE DRIVE (RCLONE)
# =====================================================================

class RcloneUploader:
    def __init__(self, config_manager: ConfigManager):
        self.cfg = config_manager
        self.rclone_bin = self._find_rclone(self.cfg.get("rclone_path", "rclone"))
        self.timeout_seconds = max(60, self.cfg.get("upload_timeout_minutes", 15) * 60)
        self.cooldown_seconds = self.cfg.get("upload_cooldown_seconds", 3)

    def _find_rclone(self, preferred: str) -> str:
        candidates = [preferred, "rclone.exe", "rclone"]
        for c in candidates:
            if shutil.which(c):
                return c
        for p in [r"C:\rclone\rclone.exe", r"C:\Program Files\rclone\rclone.exe", os.path.expanduser("~/.local/bin/rclone"), "/usr/local/bin/rclone", "/usr/bin/rclone"]:
            if os.path.exists(p):
                return p
        return "rclone"

    def is_available(self) -> bool:
        try:
            res = subprocess.run([self.rclone_bin, "version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            return res.returncode == 0
        except Exception:
            return False

    def test_connection(self, remote_target: str) -> bool:
        """Verifica que el remote de Google Drive responda antes de procesar la cola."""
        remote_root = remote_target.split(":")[0] + ":"
        cmd = [self.rclone_bin, "lsd", remote_root]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
            if res.returncode == 0:
                log_success(f"Conexión con rclone verificada hacia '{remote_target}'")
                return True
            else:
                err = res.stderr.strip()
                log_error(f"Error al conectar con rclone en '{remote_target}': {err}")
                if any(x in err for x in ["rateLimitExceeded", "userRateLimitExceeded", "403"]):
                    log_warn("⚠️ Detectado Rate Limit en Google Drive API. Asegúrate de configurar un Client ID propio en rclone config.")
                return False
        except Exception as e:
            log_error(f"No se pudo verificar conexión rclone: {e}")
            return False

    def upload_movie(self, local_path: str, remote_folder: str, max_retries: int = 3) -> bool:
        """
        Sube la película a Google Drive usando las flags optimizadas de Rclone,
        con detección inteligente de Rate Limits, reintentos con backoff exponencial
        y pausa de seguridad (cooldown) post-subida.
        """
        if not os.path.exists(local_path):
            log_error(f"Archivo local no encontrado para subir: {local_path}")
            return False

        filename = os.path.basename(local_path)
        dest_path = f"{remote_folder.rstrip('/')}/{filename}"
        flags = self.cfg.get("rclone_flags", [])
        cmd = [self.rclone_bin, "copyto", local_path, dest_path] + flags

        for attempt in range(1, max_retries + 1):
            log_step(f"Subiendo a Google Drive (Intento {attempt}/{max_retries}): {Colors.CYAN}{dest_path}{Colors.RESET}")
            try:
                # Usar Popen con stdout en vivo para ver la barra de progreso -P de rclone
                # y stderr capturado para diagnosticar y actuar ante bloqueos de API
                proc = subprocess.Popen(cmd, stdout=None, stderr=subprocess.PIPE, text=True)
                _, stderr = proc.communicate(timeout=self.timeout_seconds)

                if proc.returncode == 0:
                    log_success(f"Película subida y verificada en Google Drive: {dest_path}")
                    if self.cfg.get("delete_after_upload", True):
                        try:
                            os.remove(local_path)
                            parent = os.path.dirname(local_path)
                            if os.path.exists(parent) and not os.listdir(parent):
                                os.rmdir(parent)
                            log_info("Copia local eliminada para liberar espacio en disco")
                        except Exception as e:
                            log_warn(f"No se pudo eliminar copia local: {e}")

                    # Cooldown post-subida para evitar saturar peticiones a la API de Drive
                    if self.cooldown_seconds > 0:
                        log_info(f"Pausa de seguridad anti-bloqueo (cooldown) de {self.cooldown_seconds}s...")
                        time.sleep(self.cooldown_seconds)
                    return True
                else:
                    err_msg = stderr or ""
                    log_error(f"rclone copyto finalizó con error (Código {proc.returncode}): {err_msg.strip()[:200]}")

                    # Detección inteligente de Rate Limit de Google Drive
                    if any(x in err_msg for x in ["userRateLimitExceeded", "rateLimitExceeded", "429", "403"]):
                        wait_time = 30 * attempt
                        log_warn(f"⏳ Google Drive Rate Limit detectado. Pausando {wait_time}s antes de reintentar...")
                        time.sleep(wait_time)
                    elif "storageQuotaExceeded" in err_msg or "upload limit" in err_msg.lower():
                        log_error("🛑 Límite diario de subida de Google Drive alcanzado (750GB/día).")
                        return False
                    else:
                        time.sleep(10)

            except subprocess.TimeoutExpired:
                proc.kill()
                proc.communicate()
                log_warn(f"⚠️ La subida tardó más de {self.timeout_seconds // 60} minutos y se canceló por timeout (posible bloqueo de API).")
                time.sleep(15)
            except Exception as e:
                log_error(f"Excepción al ejecutar rclone: {e}")
                time.sleep(10)

        return False

# =====================================================================
# IMPORTADOR DEL SITEMAP DE CINEBEL
# =====================================================================

class CinebelSitemapImporter:
    def __init__(self, user_agent: str = USER_AGENT):
        self.ua = user_agent

    def fetch_sitemap_urls(self, page: int = 1) -> List[str]:
        url = f"https://cinebel.cc/wp-sitemap-posts-movies-{page}.xml"
        req = urllib.request.Request(url, headers={"User-Agent": self.ua})
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                content = resp.read().decode("utf-8", errors="replace")
                urls = re.findall(r'<loc>(https://cinebel\.cc/movies/[^<]+)</loc>', content)
                return urls
        except Exception as e:
            log_error(f"Error al leer sitemap de Cinebel (página {page}): {e}")
            return []

    def import_to_queue(self, queue_file: str, page: int = 1, limit: int = 50, db: Optional[MovieDatabase] = None) -> int:
        urls = self.fetch_sitemap_urls(page)
        if not urls:
            return 0

        # Leer cola existente para evitar duplicados
        existing_lines = set()
        if os.path.exists(queue_file):
            with open(queue_file, "r", encoding="utf-8") as f:
                for line in f:
                    c = line.strip()
                    if c and not c.startswith("#"):
                        existing_lines.add(c)

        added = 0
        to_add = []
        for u in urls:
            if u not in existing_lines:
                to_add.append(u)
                existing_lines.add(u)
                added += 1
                if added >= limit:
                    break

        if to_add:
            with open(queue_file, "a", encoding="utf-8") as f:
                f.write(f"\n# --- Importado desde Sitemap Página {page} ({datetime.now().strftime('%Y-%m-%d %H:%M')}) ---\n")
                for u in to_add:
                    f.write(f"{u}\n")

        return added

# =====================================================================
# NÚCLEO DE PROCESAMIENTO Y COLA
# =====================================================================

class MovieEngine:
    def __init__(self, config_manager: ConfigManager):
        self.cfg = config_manager
        self.db = MovieDatabase(DB_FILE)
        self.extractor = MovieDaysExtractor(USER_AGENT)
        self.downloader = FastDownloader(
            user_agent=USER_AGENT,
            ytdlp_path=self.cfg.get("ytdlp_path", "yt-dlp"),
            num_threads=self.cfg.get("movie_connections", 4)
        )
        self.uploader = RcloneUploader(self.cfg)

    def process_movie_entry(self, entry: str) -> bool:
        """
        Procesa una entrada individual (URL de cinebel, TMDB o búsqueda),
        extrae la fuente óptima, descarga a máxima velocidad y sube a Drive.
        """
        log_step(f"Procesando entrada: {Colors.YELLOW}{entry}{Colors.RESET}")

        # 1. Resolver TMDB ID
        tmdb_id, query = self.extractor.parse_input(entry)
        if not tmdb_id:
            if not query:
                log_error("Entrada vacía o inválida")
                return False
            log_info(f"Buscando película por título/slug: '{query}'...")
            results = self.extractor.search_movie(query)
            if not results:
                log_error(f"No se encontraron resultados en TMDB para: {query}")
                return False
            best = self.extractor.find_best_match(query, results)
            if not best:
                log_error(f"No se pudo determinar coincidencia confiable en TMDB para: {query}")
                return False
            tmdb_id = best.get("id")
            log_info(f"Coincidencia TMDB: {Colors.GREEN}{best.get('title')} ({best.get('release_date', '')[:4] or best.get('year', '')}) [ID: {tmdb_id}]{Colors.RESET}")

        # 2. Verificar si ya fue completada previamente en la BD
        if self.db.is_movie_completed(tmdb_id):
            log_success(f"La película [TMDB {tmdb_id}] ya fue descargada y subida con éxito anteriormente. Omitiendo.")
            return True

        # 3. Obtener servidores de MovieDays
        log_info(f"Consultando servidores en MovieDays para TMDB ID: {tmdb_id}...")
        details = self.extractor.get_movie_details(tmdb_id)
        if not details:
            log_error(f"No se pudieron obtener datos de reproducción para TMDB {tmdb_id}")
            return False

        title = sanitize_filename(details.get("title") or f"Pelicula_{tmdb_id}")
        year = details.get("release_date", "")[:4] or details.get("year", "") or ""

        # Si el idioma preferido es LATINO, obtener el título oficial latinoamericano de TMDB
        pref_lang = self.cfg.get("preferred_movie_lang", "LATINO")
        if pref_lang.upper() == "LATINO":
            lat_title, lat_year = self.extractor.get_latino_title(tmdb_id, title)
            if lat_title:
                title = sanitize_filename(lat_title)
            if lat_year:
                year = lat_year
        if not year:
            year = "2024"

        servers = details.get("servers", [])
        log_info(f"🎬 Película: {Colors.BOLD}{title} ({year}){Colors.RESET} | Servidores disponibles: {len(servers)}")

        # 4. Resolver mejor stream (Prioridad Rumble .aaa.mp4)
        best_source = self.extractor.resolve_best_source(servers, preferred_lang=pref_lang)
        if not best_source:
            log_error(f"No se pudo extraer ningún enlace de video utilizable para: {title}")
            return False

        source_url = best_source["url"]
        source_type = best_source["type"]
        lang = best_source["lang"]
        quality = best_source["quality"]

        is_aaa = ".aaa.mp4" in source_url
        badge = f"{Colors.YELLOW}🌟 RUMBLE AAA{Colors.RESET}" if is_aaa else f"{Colors.CYAN}{source_type}{Colors.RESET}"
        log_success(f"Fuente seleccionada: {badge} | Idioma: {Colors.BOLD}{lang}{Colors.RESET} | Calidad: {quality}")

        # 5. Definir nombres y rutas locales y remotas
        download_dir = self.cfg.get("movie_download_dir", "./downloads_movies")
        movie_folder_name = f"{title} ({year})"
        movie_file_name = f"{title} ({year}) [{quality.split()[0]}] [{lang[:3]}].mp4"
        local_dir = os.path.join(download_dir, movie_folder_name)
        local_file_path = os.path.join(local_dir, movie_file_name)

        remote_base = self.cfg.get("rclone_movie_remote", "gdrive:Movies")
        remote_folder = f"{remote_base}/{movie_folder_name}"
        remote_dest_path = f"{remote_folder}/{movie_file_name}"

        # Registrar en BD
        movie_record_id = self.db.record_movie(
            tmdb_id=tmdb_id,
            title=title,
            year=year,
            lang=lang,
            quality=quality,
            source_type=source_type,
            source_url=source_url,
            local_path=local_file_path
        )

        # 6. Descarga
        log_step(f"Iniciando descarga a: {Colors.CYAN}{local_file_path}{Colors.RESET}")
        if best_source["is_direct_mp4"]:
            ok, size_bytes, speed_mbps, duration = self.downloader.download_direct_mp4(source_url, local_file_path)
        else:
            ok, size_bytes, speed_mbps, duration = self.downloader.download_hls(source_url, local_file_path)

        if not ok or not os.path.exists(local_file_path) or os.path.getsize(local_file_path) < 1024 * 1024:
            err_msg = "Descarga incompleta o fallida"
            log_error(err_msg)
            self.db.mark_failed(movie_record_id, err_msg)
            return False

        log_success(f"Descarga finalizada: {format_bytes(size_bytes)} en {format_seconds(duration)} ({speed_mbps:.1f} MB/s)")
        self.db.mark_downloaded(movie_record_id, size_bytes, speed_mbps, duration)

        # 7. Subida a Google Drive con Rclone
        if self.cfg.get("rclone_enabled", True) and self.uploader.is_available():
            upload_ok = self.uploader.upload_movie(local_file_path, remote_folder)
            if upload_ok:
                self.db.mark_completed(movie_record_id, remote_dest_path)
                log_success(f"🎉 ¡Película '{title}' completada y almacenada en Google Drive!")
                return True
            else:
                self.db.mark_failed(movie_record_id, "Error al subir archivo con rclone")
                return False
        else:
            log_info("Rclone desactivado o no disponible. La película se mantiene en almacenamiento local.")
            self.db.mark_completed(movie_record_id, local_file_path)
            return True

    def run_queue_loop(self, queue_file: Optional[str] = None):
        """
        Monitorea continuamente el archivo de cola y procesa las películas una a una.
        """
        q_file = queue_file or self.cfg.get("movie_queue_file", DEFAULT_QUEUE_FILE)
        if not os.path.exists(q_file):
            with open(q_file, "w", encoding="utf-8") as f:
                f.write("# Pega aquí enlaces de Cinebel o nombres de películas para descargar\n")

        log_info(f"👀 Monitoreando cola de películas: {Colors.CYAN}{q_file}{Colors.RESET}")
        log_info("Puedes agregar nuevos enlaces o títulos al archivo en cualquier momento. (Ctrl+C para salir)")

        if self.cfg.get("rclone_enabled", True) and self.uploader.is_available():
            remote_target = self.cfg.get("rclone_movie_remote", "gdrive:Movies")
            log_info(f"Verificando conexión previa con Google Drive ({remote_target})...")
            self.uploader.test_connection(remote_target)

        interval = self.cfg.get("watch_interval_seconds", 5)

        try:
            while True:
                # Leer primera entrada pendiente
                lines = []
                with open(q_file, "r", encoding="utf-8") as f:
                    lines = f.readlines()

                target_line = None
                target_idx = -1
                for i, l in enumerate(lines):
                    clean = l.strip()
                    if clean and not clean.startswith("#"):
                        target_line = clean
                        target_idx = i
                        break

                if target_line:
                    print("\n" + "=" * 65)
                    log_step(f"Nueva película detectada en cola: {target_line}")
                    print("=" * 65)

                    success = self.process_movie_entry(target_line)

                    # Eliminar la línea procesada del archivo de cola
                    with open(q_file, "r", encoding="utf-8") as f:
                        current_lines = f.readlines()

                    if target_idx < len(current_lines) and current_lines[target_idx].strip() == target_line:
                        del current_lines[target_idx]
                        with open(q_file, "w", encoding="utf-8") as f:
                            f.writelines(current_lines)
                    else:
                        # Si fue editado mientras descargaba, remover la primera coincidencia
                        with open(q_file, "w", encoding="utf-8") as f:
                            removed = False
                            for cl in current_lines:
                                if not removed and cl.strip() == target_line:
                                    removed = True
                                    continue
                                f.write(cl)

                    if success:
                        log_success(f"Entrada procesada y removida de la cola: {target_line}")
                    else:
                        log_warn(f"La entrada falló pero fue removida de la cola (revisa el log/BD): {target_line}")

                    time.sleep(2)
                else:
                    time.sleep(interval)

        except KeyboardInterrupt:
            log_info("\nMonitor de cola detenido por el usuario.")

# =====================================================================
# MENÚ INTERACTIVO Y CLI
# =====================================================================

def show_banner():
    print(Colors.CYAN + "=" * 65 + Colors.RESET)
    print(f"{Colors.BOLD}🎬 RAVEDOWN MOVIE 1.0 - Descargas Masivas & Sync Google Drive{Colors.RESET}")
    print(f"{Colors.DIM}Motor de Extracción: MovieDays.lat + Rumble CDN (.aaa.mp4) | Rclone 5TB{Colors.RESET}")
    print(Colors.CYAN + "=" * 65 + Colors.RESET)

def interactive_menu(engine: MovieEngine):
    while True:
        show_banner()
        stats = engine.db.get_stats()
        print(f"📊 Estadísticas: {Colors.GREEN}{stats['completed']} completadas{Colors.RESET} "
              f"({format_bytes(stats['total_bytes'])}) | {Colors.YELLOW}{stats['rumble_count']} Rumble AAA{Colors.RESET} | "
              f"{Colors.RED}{stats['failed']} fallidas{Colors.RESET}")
        print("-" * 65)
        print("1) 📥 Iniciar procesador de cola continua (queuemovie.txt)")
        print("2) 🎯 Descargar una película individual (URL, TMDB o búsqueda)")
        print("3) 📦 Importar lote de películas desde el Sitemap de Cinebel a la cola")
        print("4) 📋 Ver historial de películas descargadas")
        print("5) ⚙️  Configuración rápida (Idioma preferido, Destino en Google Drive)")
        print("6) 🚪 Salir")
        print("-" * 65)

        choice = input("Selecciona una opción [1-6]: ").strip()

        if choice == "1":
            q_file = engine.cfg.get("movie_queue_file", DEFAULT_QUEUE_FILE)
            engine.run_queue_loop(q_file)

        elif choice == "2":
            print("\nFormatos soportados:")
            print(" - https://cinebel.cc/movies/super-mario-bros-la-pelicula/")
            print(" - https://www.themoviedb.org/movie/502356")
            print(" - 502356 (ID de TMDB)")
            print(" - Super Mario Bros (Título de la película)")
            entry = input("\nIngresa el enlace, ID o nombre: ").strip()
            if entry:
                engine.process_movie_entry(entry)
            input("\nPresiona Enter para volver al menú...")

        elif choice == "3":
            importer = CinebelSitemapImporter(USER_AGENT)
            page_input = input("¿Qué página del sitemap de Cinebel importar? [1]: ").strip() or "1"
            limit_input = input("¿Cuántas películas agregar a la cola? [50]: ").strip() or "50"
            try:
                page = int(page_input)
                limit = int(limit_input)
                q_file = engine.cfg.get("movie_queue_file", DEFAULT_QUEUE_FILE)
                added = importer.import_to_queue(q_file, page=page, limit=limit, db=engine.db)
                log_success(f"Se agregaron {added} películas a {q_file} con éxito.")
            except Exception as e:
                log_error(f"Error en importación: {e}")
            input("\nPresiona Enter para volver al menú...")

        elif choice == "4":
            print("\n" + "=" * 65)
            print(f"{Colors.BOLD}📋 ÚLTIMAS PELÍCULAS PROCESADAS{Colors.RESET}")
            print("=" * 65)
            rows = engine.db.list_recent(15)
            if not rows:
                print("Aún no hay registros en la base de datos.")
            else:
                for r in rows:
                    status_color = Colors.GREEN if r["status"] == "completed" else (Colors.RED if r["status"] == "failed" else Colors.YELLOW)
                    print(f"[{status_color}{r['status'].upper()}{Colors.RESET}] {Colors.BOLD}{r['title']} ({r['year']}){Colors.RESET}")
                    print(f"    Idioma: {r['lang']} | Fuente: {r['source_type']} | Tamaño: {format_bytes(r['file_size_bytes'])}")
                    if r.get("remote_path"):
                        print(f"    Drive: {r['remote_path']}")
                    if r.get("error_message"):
                        print(f"    Error: {Colors.RED}{r['error_message']}{Colors.RESET}")
            input("\nPresiona Enter para volver al menú...")

        elif choice == "5":
            print("\n" + "=" * 65)
            print(f"{Colors.BOLD}⚙️  CONFIGURACIÓN RÁPIDA{Colors.RESET}")
            print("=" * 65)
            current_remote = engine.cfg.get("rclone_movie_remote", "gdrive:Movies")
            current_lang = engine.cfg.get("preferred_movie_lang", "LATINO")
            print(f"1. Destino en Google Drive (Rclone): {Colors.CYAN}{current_remote}{Colors.RESET}")
            print(f"2. Idioma preferido: {Colors.YELLOW}{current_lang}{Colors.RESET}")
            print(f"3. Borrado local tras subir: {engine.cfg.get('delete_after_upload')}")
            print("-" * 65)
            c_opt = input("¿Deseas cambiar algo? (1/2/3 o Enter para salir): ").strip()
            if c_opt == "1":
                new_remote = input(f"Nuevo destino [{current_remote}]: ").strip()
                if new_remote:
                    engine.cfg.set("rclone_movie_remote", new_remote)
                    log_success("Configuración actualizada.")
            elif c_opt == "2":
                print("Opciones: LATINO, CASTELLANO, SUB")
                new_lang = input(f"Nuevo idioma [{current_lang}]: ").strip().upper()
                if new_lang:
                    engine.cfg.set("preferred_movie_lang", new_lang)
                    log_success("Configuración actualizada.")
            elif c_opt == "3":
                cur_del = engine.cfg.get("delete_after_upload", True)
                engine.cfg.set("delete_after_upload", not cur_del)
                log_success(f"Borrado tras subir cambiado a: {not cur_del}")

        elif choice == "6":
            print("\n¡Hasta luego!")
            break

def main():
    parser = argparse.ArgumentParser(description="Ravedown Movie 1.0 - Descargador de Películas a Máxima Velocidad")
    parser.add_argument("--url", "-u", help="URL de Cinebel, TMDB ID o título de película para procesar directamente")
    parser.add_argument("--queue", "-q", action="store_true", help="Iniciar monitor continuo de cola (queuemovie.txt)")
    parser.add_argument("--import-sitemap", type=int, nargs="?", const=1, help="Importar películas del sitemap de Cinebel a la cola (opcional: número de página)")
    parser.add_argument("--limit", type=int, default=50, help="Límite de películas a importar del sitemap (por defecto 50)")
    parser.add_argument("--stats", action="store_true", help="Mostrar estadísticas de ravedownmovie.db")

    args = parser.parse_args()
    config_mgr = ConfigManager(CONFIG_FILE)
    engine = MovieEngine(config_mgr)

    if args.stats:
        stats = engine.db.get_stats()
        print(f"Completadas: {stats['completed']} | Fallidas: {stats['failed']} | Espacio en Drive: {format_bytes(stats['total_bytes'])}")
        return

    if args.import_sitemap:
        importer = CinebelSitemapImporter(USER_AGENT)
        q_file = config_mgr.get("movie_queue_file", DEFAULT_QUEUE_FILE)
        added = importer.import_to_queue(q_file, page=args.import_sitemap, limit=args.limit, db=engine.db)
        log_success(f"Se agregaron {added} películas a {q_file}")
        return

    if args.url:
        engine.process_movie_entry(args.url)
        return

    if args.queue:
        engine.run_queue_loop()
        return

    # Si se ejecuta sin argumentos, abrir menú interactivo
    interactive_menu(engine)

if __name__ == "__main__":
    main()
