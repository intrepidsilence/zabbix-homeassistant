# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Zabbix 7.0 template** for agentless monitoring of Home Assistant via its REST API. The entire template lives in a single file: `7.0/Home Assistant - Zabbix.yaml`. There is no build system, no tests, and no code to compile — the deliverable is the YAML file itself, which is imported directly into Zabbix.

## Architecture

### Data Flow

1. **Single HTTP master item** (`HA-raw`, key `ha.raw`) polls `{$HA.URL}/api/states` with a bearer token, fetching the full JSON array of all HA entity states.
2. **~50 LLD (Low-Level Discovery) rules** are all `type: DEPENDENT` on `ha.raw`. Each rule uses JSONPath preprocessing to filter the master JSON for its entity type (e.g., `$.body[?(@.attributes.device_class=="battery")]`).
3. **Item prototypes** within each LLD rule extract individual entity values using JSONPath with LLD macros: `$.body[?(@.entity_id == "{#ENTITY_ID}")].state.first()`.
4. **Trigger prototypes** define alerting conditions using Zabbix expression syntax with per-entity macro overrides (e.g., `{$BATTERY.MINIMUM:"{#ENTITY_ID}"}`).

### Key LLD Macros

- `{#ENTITY_ID}` — HA entity identifier (extracted from `$.entity_id`)
- `{#FRIENDLY_NAME}` — human-readable name (from `$.attributes.friendly_name`)
- `{#DEVICE_CLASS}` — entity device class (from `$.attributes.device_class`)
- `{#UNITS}` — unit of measurement (from `$.attributes.unit_of_measurement`)

### Preprocessing Pipeline

Most items follow a common preprocessing pattern:
1. JSONPath extraction from the master item's JSON body
2. `STR_REPLACE` steps to convert string states (`on`/`off`/`unavailable`) to numeric values
3. Value maps translate the numeric values back to human-readable labels in the Zabbix UI

### Trigger Enable/Disable Pattern

Triggers use `{$SWITCH.TRIGGER.*}` macros (default `1` or `0`) to enable/disable individual trigger categories. These can be overridden per-entity using Zabbix's macro context syntax: `{$SWITCH.TRIGGER.BATTERY:"{#ENTITY_ID}"}`.

### Apps (Add-ons) Monitoring

HA Apps (formerly "Add-ons") are monitored through entities exposed by the Supervisor integration in `/api/states` — no separate API calls needed. Four discovery rules handle different aspects:

| Rule | Key | Entity Pattern | Notes |
|------|-----|----------------|-------|
| `HA-addon-update` | `ha.addon.update` | `update.*` with `entity_picture` containing `hassio/addons` | Always enabled in HA. Tracks update state, installed/latest version, auto-update. |
| `HA-addon-running` | `ha.addon.running` | `binary_sensor.*_running` | **Disabled by default in HA** — user must enable. |
| `HA-addon-cpu` | `ha.addon.cpu` | `sensor.*_cpu_percent` | **Disabled by default in HA** — user must enable. |
| `HA-addon-memory` | `ha.addon.memory` | `sensor.*_memory_percent` | **Disabled by default in HA** — user must enable. |

The `HA-addon-update` rule uses `{#ENTITY_PICTURE}` (from `$.attributes.entity_picture`) to distinguish add-on update entities from device firmware or HACS updates. This attribute contains `/api/hassio/addons/{slug}/icon` for add-on entities.

The Supervisor REST API (`/addons/{slug}/info`, `/addons/{slug}/stats`) is NOT externally accessible — it only works within HA's Docker network. All add-on monitoring must go through `/api/states` entities.

## Working with the Template

### Editing the YAML

The file is a Zabbix 7.0 native export format. Key structural rules:
- Discovery rules go under `discovery_rules:`, not `items:`
- Item prototypes use `{#MACRO}` syntax in their `key` field for uniqueness (e.g., `ent.bat[{#ENTITY_ID}]`)
- `master_item.key: ha.raw` links dependent items/rules back to the HTTP master item
- LLD filter `conditions` use regex patterns against extracted macros

### Adding a New Entity Type

Follow this pattern (modeled on existing rules like `HA-batterie` or `HA-temperature`):
1. Add a new discovery rule under `discovery_rules:` with a unique uuid
2. Set `type: DEPENDENT`, `master_item.key: ha.raw`
3. Define `filter.conditions` with a regex matching the entity (by `{#ENTITY_ID}` pattern or `{#DEVICE_CLASS}`)
4. Add `lld_macro_paths` to extract `{#ENTITY_ID}`, `{#FRIENDLY_NAME}`, and relevant attributes
5. Add JSONPath `preprocessing` to filter the master JSON (e.g., `$.body[?(@.attributes.device_class=="temperature")]`)
6. Create `item_prototypes` with dependent items that extract per-entity state via JSONPath
7. Add `trigger_prototypes` if alerting is needed, with `{$SWITCH.TRIGGER.*}` macro gating
8. Add a `valuemap` entry under the top-level `valuemaps:` section if needed

### Validating Changes

- Check that LLD rules discover entities from a live HA instance
- Verify trigger expressions reference valid item keys and macros

### Common Pitfalls

- JSONPath `$.body[*]` vs `$.body[?(@.filter)]` — use the filter form for LLD preprocessing to scope entity discovery
- The `.first()` JSONPath function is used in item prototypes to extract a single value from the filtered array
- State string normalization is case-sensitive (`unavailable` vs `Unavailable` — both may appear; handle both)
- Trigger expressions must reference the full template name: `last(/Home Assistant - Zabbix/item.key[{#ENTITY_ID}])`
- `{$MACRO:"{#CONTEXT}"}` enables per-entity threshold overrides — always include the context variant in trigger expressions where appropriate
- Boolean attributes (`auto_update`, etc.) may come through as `true`/`True`/`false`/`False` — handle both cases in `STR_REPLACE` steps
- LLD filters can match on custom-extracted macros (e.g., `{#ENTITY_PICTURE}`) — useful for distinguishing entity subtypes that share the same `entity_id` prefix
