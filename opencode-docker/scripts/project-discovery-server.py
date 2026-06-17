#!/usr/bin/env python3
import json
import os
import re
import sqlite3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


WORKSPACE = Path(os.environ.get("WORKSPACE_DIR", "/home/coder/workspace")).resolve()
DB_PATH = Path(os.environ.get("OPENCODE_DB_PATH", "/home/coder/.local/share/opencode/opencode.db"))
HOST = os.environ.get("OPENCODE_PROJECT_DISCOVERY_HOST", "0.0.0.0")
PORT = int(os.environ.get("OPENCODE_PROJECT_DISCOVERY_PORT", "4097"))
MAX_DEPTH = int(os.environ.get("OPENCODE_PROJECT_DISCOVERY_MAX_DEPTH", "3"))
IGNORED_NAMES = {
    ".cache",
    ".git",
    ".pio",
    ".venv",
    "build",
    "cache",
    "dist",
    "libdeps",
    "node_modules",
    "target",
    "vendor",
    "vendored",
}


def slug(value: str) -> str:
    value = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return value or "project"


def inside_workspace(path: Path) -> bool:
    try:
        path.resolve().relative_to(WORKSPACE)
        return True
    except ValueError:
        return False


def session_stats() -> dict[str, tuple[int, int]]:
    if not DB_PATH.exists():
        return {}
    con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    try:
        return {
            directory: (count, last)
            for directory, count, last in con.execute(
                "select directory, count(*), max(time_updated) from session where directory like ? and parent_id is null group by directory",
                (str(WORKSPACE) + "/%",),
            )
        }
    finally:
        con.close()


def git_projects() -> set[Path]:
    projects: set[Path] = set()
    if not WORKSPACE.is_dir():
        return projects
    for current, dirs, _files in os.walk(WORKSPACE):
        path = Path(current)
        rel = path.relative_to(WORKSPACE)
        depth = 0 if rel.parts == (".",) else len(rel.parts)
        dirs[:] = [name for name in dirs if name not in IGNORED_NAMES and not name.startswith(".")]
        if depth > MAX_DEPTH:
            dirs[:] = []
            continue
        if (path / ".git").exists() and path != WORKSPACE:
            projects.add(path)
            dirs[:] = []
    return projects


def discover() -> list[dict[str, object]]:
    stats = session_stats()
    projects = {str(path) for path in git_projects()}
    for directory in stats:
        path = Path(directory)
        if path.is_dir() and inside_workspace(path) and path != WORKSPACE:
            projects.add(str(path))

    base_aliases: dict[str, list[str]] = {}
    for directory in projects:
        base_aliases.setdefault(slug(Path(directory).name), []).append(directory)

    items = []
    for directory in sorted(projects):
        path = Path(directory)
        rel = path.relative_to(WORKSPACE)
        base = slug(path.name)
        alias = base if len(base_aliases[base]) == 1 else slug("-".join(rel.parts))
        count, last = stats.get(directory, (0, 0))
        items.append(
            {
                "alias": alias,
                "directory": directory,
                "sessionCount": count,
                "lastAccess": last,
                "git": (path / ".git").exists(),
            }
        )
    items.sort(key=lambda p: (p["sessionCount"] == 0, -(p["lastAccess"] or 0), str(p["alias"])))
    return items


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            self.send_json({"ok": True})
            return
        if path in {"/project/discover", "/projects"}:
            self.send_json(discover())
            return
        self.send_response(404)
        self.end_headers()

    def send_json(self, payload):
        body = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *_args):
        return


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
