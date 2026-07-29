#!/usr/bin/env bash
#
# Raw bombardier runs against a server that is already listening on :3000.
# For the full automated benchmark use "bun benchmark" instead.
#
set -euo pipefail

BOMBARDIER="${BOMBARDIER_BIN:-bombardier}"
if ! command -v "$BOMBARDIER" >/dev/null 2>&1; then
	echo "bombardier not found in \$PATH. Run ./install.sh to install it." >&2
	exit 1
fi

BASE_URL="${BASE_URL:-http://localhost:3000}"

"$BOMBARDIER" --fasthttp -c 500 -d 10s "$BASE_URL/"
"$BOMBARDIER" --fasthttp -c 500 -d 10s "$BASE_URL/id/1?name=bun"
"$BOMBARDIER" --fasthttp -c 500 -d 10s -m POST -H 'Content-Type: application/json' -f ./scripts/body.json "$BASE_URL/json"
