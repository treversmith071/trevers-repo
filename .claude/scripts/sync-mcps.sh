#!/bin/bash
# Two-way MCP sync:
# 1. New MCPs in ~/.claude.json (project) → .claude/mcps/<name>.json
# 2. All .claude/mcps/*.json → .mcp.json (which Claude Code reads)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCPS_DIR="$PROJECT_ROOT/.claude/mcps"
OUTPUT="$PROJECT_ROOT/.mcp.json"
CLAUDE_JSON="$HOME/.claude.json"

python3 - <<EOF
import json, os, sys

project_root = "$PROJECT_ROOT"
mcps_dir = "$MCPS_DIR"
output_file = "$OUTPUT"
claude_json_path = "$CLAUDE_JSON"

# Step 1: Pull any new MCPs from ~/.claude.json into .claude/mcps/
try:
    with open(claude_json_path) as f:
        claude_config = json.load(f)

    project_mcps = (
        claude_config
        .get("projects", {})
        .get(project_root, {})
        .get("mcpServers", {})
    )

    for name, config in project_mcps.items():
        dest = os.path.join(mcps_dir, f"{name}.json")
        if not os.path.exists(dest):
            with open(dest, "w") as f:
                json.dump(config, f, indent=2)
                f.write("\n")
            print(f"sync-mcps: pulled '{name}' from ~/.claude.json → .claude/mcps/")

except Exception as e:
    print(f"sync-mcps: warning reading ~/.claude.json: {e}", file=sys.stderr)

# Step 2: Merge all .claude/mcps/*.json → .mcp.json
servers = {}
for fname in sorted(os.listdir(mcps_dir)):
    if fname.endswith(".json"):
        name = fname[:-5]
        path = os.path.join(mcps_dir, fname)
        with open(path) as f:
            try:
                servers[name] = json.load(f)
            except json.JSONDecodeError as e:
                print(f"sync-mcps: skipping {fname} (invalid JSON): {e}", file=sys.stderr)

with open(output_file, "w") as f:
    json.dump({"mcpServers": servers}, f, indent=2)
    f.write("\n")
EOF
