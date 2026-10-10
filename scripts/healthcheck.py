"""Container health probe: GET /health on the local laya-serve."""

import os
import sys
import urllib.request

url = f"http://127.0.0.1:{os.environ.get('LAYA_PORT', '8000')}/health"
try:
    with urllib.request.urlopen(url, timeout=4) as resp:
        sys.exit(0 if resp.status == 200 else 1)
except OSError:  # URLError, HTTPError, timeouts
    sys.exit(1)
