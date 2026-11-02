"""Link each deployed script and stylesheet to its content fingerprint."""
import hashlib
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "web"
index = root / "index.html"


def fingerprint(match):
    attribute, filename = match.groups()
    digest = hashlib.sha256((root / filename).read_bytes()).hexdigest()[:16]
    return f'{attribute}="{filename}?v={digest}"'


html = index.read_text(encoding="utf-8")
html = re.sub(r'(src|href)="([\w./-]+\.(?:js|css))(?:\?v=[\da-f]+)?"', fingerprint, html)
index.write_text(html, encoding="utf-8")
