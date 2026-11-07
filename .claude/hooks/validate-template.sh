#!/bin/bash
# PostToolUse hook: validates the Zabbix template YAML after Edit/Write.
# Checks: (1) valid YAML syntax, (2) all UUIDs are unique 32-char hex.
#
# The edited path comes from tool input, so it is treated as untrusted data:
# it is matched exactly against the one template file in this repo, and it is
# handed to Python as an argument, never pasted into Python source.

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Resolve the repo root from this script's location (.claude/hooks/ -> repo root).
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd -P) || exit 0
TEMPLATE="$REPO_ROOT/7.0/Home Assistant - Zabbix.yaml"

# Only validate if the edited file IS the template (exact match after resolving symlinks / ..).
[ -f "$FILE_PATH" ] || exit 0
RESOLVED="$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && pwd -P)/$(basename "$FILE_PATH")" || exit 0
[ "$RESOLVED" = "$TEMPLATE" ] || exit 0

ERRORS=$(python3 -I - "$TEMPLATE" <<'PY' 2>&1
import re, sys
from collections import Counter
import yaml

path = sys.argv[1]

# Check 1: YAML syntax is valid
try:
    with open(path) as f:
        data = yaml.safe_load(f)
except yaml.YAMLError as e:
    print(f"Template YAML validation failed: {e}", file=sys.stderr)
    sys.exit(1)

# Check 2: All UUIDs are unique and properly formatted (32-char lowercase hex)
uuids = []
def collect(obj):
    if isinstance(obj, dict):
        if 'uuid' in obj:
            uuids.append(obj['uuid'])
        for v in obj.values():
            collect(v)
    elif isinstance(obj, list):
        for i in obj:
            collect(i)

collect(data)

errors = []
for u in uuids:
    if not re.match(r'^[0-9a-f]{32}$', str(u)):
        errors.append(f'Invalid UUID format: {u} (must be 32-char lowercase hex, no dashes)')
for d in [u for u, c in Counter(uuids).items() if c > 1]:
    errors.append(f'Duplicate UUID: {d}')

if errors:
    print("Template UUID validation failed:", file=sys.stderr)
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
PY
)

if [ $? -ne 0 ]; then
  echo "$ERRORS" >&2
  exit 2
fi

exit 0
