#!/bin/bash
# PostToolUse hook: validates the Zabbix template YAML after Edit/Write.
# Checks: (1) valid YAML syntax, (2) all UUIDs are unique 32-char hex.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only validate if the template file was edited
if [ -z "$FILE_PATH" ] || ! echo "$FILE_PATH" | grep -q "Home Assistant - Zabbix.yaml"; then
  exit 0
fi

# Check that file exists
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Check 1: YAML syntax is valid
YAML_ERR=$(python3 -c "
import yaml, sys
try:
    with open('$FILE_PATH') as f:
        yaml.safe_load(f)
except yaml.YAMLError as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
" 2>&1)

if [ $? -ne 0 ]; then
  echo "Template YAML validation failed: $YAML_ERR" >&2
  exit 2
fi

# Check 2: All UUIDs are unique and properly formatted (32-char lowercase hex)
UUID_ERR=$(python3 -c "
import yaml, re, sys
from collections import Counter

with open('$FILE_PATH') as f:
    data = yaml.safe_load(f)

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

dupes = [u for u, c in Counter(uuids).items() if c > 1]
for d in dupes:
    errors.append(f'Duplicate UUID: {d}')

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
" 2>&1)

if [ $? -ne 0 ]; then
  echo "Template UUID validation failed:" >&2
  echo "$UUID_ERR" >&2
  exit 2
fi

exit 0
