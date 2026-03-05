# Statusline Setup

Installs the statusline into `~/.claude/` and wires it into `~/.claude/settings.json`.

**What it shows (single line):**
- Model name · context-window progress bar · % used · `|` · working directory (neon cyan) · `|` · usage bar · % used · reset time (EST)
- Context section: neon cyan (`rgb(0,180,255)`)
- Usage section: neon pink (`rgb(255,120,240)`)
- Both bars: 9 characters wide
- Usage reset time requires a session key

---

## Instructions for Claude

Execute every step below in order. Use the actual home directory (resolve `~` via `echo ~` or `$HOME`).

### Step 1 — Write `~/.claude/statusline-command.sh`

Write the following content verbatim to the file `~/.claude/statusline-command.sh`:

```sh
#!/bin/sh
input=$(cat)

# ---------------------------------------------------------------------------
# Helper: build a 9-char progress bar string into variable $bar
# Usage: build_bar <integer_percentage>
# ---------------------------------------------------------------------------
build_bar() {
  _pct="$1"
  _filled=$(( (_pct * 9 + 50) / 100 ))
  _empty=$(( 9 - _filled ))
  bar=""
  _i=0
  while [ $_i -lt $_filled ]; do
    bar="${bar}█"
    _i=$(( _i + 1 ))
  done
  _i=0
  while [ $_i -lt $_empty ]; do
    bar="${bar}░"
    _i=$(( _i + 1 ))
  done
}

# ---------------------------------------------------------------------------
# Helper: pick ANSI color escape for a percentage
# Sets $bar_color
# ---------------------------------------------------------------------------
pick_color() {
  _pct="$1"
  if [ "$_pct" -ge 75 ]; then
    bar_color="\033[31m"
  elif [ "$_pct" -ge 50 ]; then
    bar_color="\033[33m"
  else
    bar_color="\033[32m"
  fi
}

# ---------------------------------------------------------------------------
# Context window data
# ---------------------------------------------------------------------------
if ! command -v jq > /dev/null 2>&1; then
  model="Unknown Model"
  used=""
else
  model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
  used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
fi

workdir=$(basename "${PWD:-$(pwd)}")
git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
git_changes=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

if [ -n "$git_branch" ]; then
  if [ -n "$git_changes" ] && [ "$git_changes" -gt 0 ] 2>/dev/null; then
    branch_label="⎇ ${git_branch} *${git_changes}"
  else
    branch_label="⎇ ${git_branch}"
  fi
  dir_section=$(printf "\033[22m\033[38;2;0;255;255m%s\033[0m \033[38;2;255;120;240m%s\033[0m" "$workdir" "$branch_label")
else
  dir_section=$(printf "\033[22m\033[38;2;0;255;255m%s\033[0m" "$workdir")
fi

if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  build_bar "$used_int"
  ctx_bar="$bar"
fi

# ---------------------------------------------------------------------------
# 5-hour account usage bar
# ---------------------------------------------------------------------------
CACHE_FILE="/tmp/claude_usage_cache"
FETCH_SCRIPT="$HOME/.claude/fetch-usage.sh"
STALE_SECONDS=30

needs_refresh=1
if [ -f "$CACHE_FILE" ]; then
  cache_age=$(( $(date +%s) - $(date -r "$CACHE_FILE" +%s 2>/dev/null || echo 0) ))
  if [ "$cache_age" -lt "$STALE_SECONDS" ]; then
    needs_refresh=0
  fi
fi

if [ "$needs_refresh" = "1" ] && [ -f "$FETCH_SCRIPT" ]; then
  sh "$FETCH_SCRIPT" > /dev/null 2>&1 &
fi

USAGE_PCT=""
RESET_TIME=""
if [ -f "$CACHE_FILE" ]; then
  USAGE_PCT=$(grep "^USAGE_PCT=" "$CACHE_FILE" | cut -d= -f2-)
  RESET_TIME=$(grep "^RESET_TIME=" "$CACHE_FILE" | cut -d= -f2-)
fi

if [ -n "$USAGE_PCT" ]; then
  build_bar "$USAGE_PCT"
  usage_bar="$bar"
  reset_label=""
  if [ -n "$RESET_TIME" ]; then
    reset_label="  resets $RESET_TIME"
  fi
fi

# ---------------------------------------------------------------------------
# Print single combined line:
#   model  [ctx_bar] X% | workdir  branch *N | [usage_bar] XX%  resets TIME
# ---------------------------------------------------------------------------
if [ -n "$used" ]; then
  if [ -n "$USAGE_PCT" ]; then
    printf "\033[38;2;0;180;255m%s\033[0m\033[2m  \033[38;2;0;180;255m%s\033[0m\033[2m \033[38;2;0;180;255m%d%%\033[0m\033[2m | %s\033[2m | \033[38;2;255;120;240m%s\033[0m\033[2m \033[38;2;255;120;240m%d%%\033[0m\033[38;2;255;120;240m%s\033[0m" \
      "$model" "$ctx_bar" "$used_int" "$dir_section" "$usage_bar" "$USAGE_PCT" "$reset_label"
  else
    printf "\033[38;2;0;180;255m%s\033[0m\033[2m  \033[38;2;0;180;255m%s\033[0m\033[2m \033[38;2;0;180;255m%d%%\033[0m\033[2m | %s\033[2m | \033[2m░░░░░░░░░ fetching…\033[0m" \
      "$model" "$ctx_bar" "$used_int" "$dir_section"
  fi
else
  if [ -n "$USAGE_PCT" ]; then
    printf "\033[38;2;0;180;255m%s\033[0m\033[2m  ░░░░░░░░░ -%%\033[0m\033[2m | %s\033[2m | \033[38;2;255;120;240m%s\033[0m\033[2m \033[38;2;255;120;240m%d%%\033[0m\033[38;2;255;120;240m%s\033[0m" \
      "$model" "$dir_section" "$usage_bar" "$USAGE_PCT" "$reset_label"
  else
    printf "\033[38;2;0;180;255m%s\033[0m\033[2m  ░░░░░░░░░ -%%\033[0m\033[2m | %s\033[2m | \033[2m░░░░░░░░░ fetching…\033[0m" \
      "$model" "$dir_section"
  fi
fi
```

### Step 2 — Write `~/.claude/fetch-usage.sh`

Write the following content verbatim to `~/.claude/fetch-usage.sh`:

```sh
#!/bin/sh
# Fetches Claude.ai Pro 5-hour usage data directly via session key cookie.
# No browser automation or Chrome access required.
# Writes results to /tmp/claude_usage_cache

CACHE_FILE="/tmp/claude_usage_cache"
SESSION_FILE="$HOME/.claude/claude_session"

if [ ! -f "$SESSION_FILE" ]; then
  printf "USAGE_PCT=\nRESET_TIME=\nERROR=no_session_file\n" > "$CACHE_FILE"
  exit 0
fi

SESSION=$(cat "$SESSION_FILE" 2>/dev/null)
if [ -z "$SESSION" ]; then
  printf "USAGE_PCT=\nRESET_TIME=\nERROR=empty_session\n" > "$CACHE_FILE"
  exit 0
fi

python3 - "$SESSION" "$CACHE_FILE" << 'PYEOF'
import sys, json, http.client, ssl
from datetime import datetime
try:
    from zoneinfo import ZoneInfo
    EST = ZoneInfo('America/New_York')
except ImportError:
    from datetime import timezone, timedelta
    EST = timezone(timedelta(hours=-5))

session = sys.argv[1]
cache_file = sys.argv[2]

def write_cache(pct, reset_time, error=''):
    with open(cache_file, 'w') as f:
        f.write(f'USAGE_PCT={pct}\n')
        f.write(f'RESET_TIME={reset_time}\n')
        if error:
            f.write(f'ERROR={error}\n')

try:
    ctx = ssl.create_default_context()
    headers = {
        'Cookie': f'sessionKey={session}',
        'Accept': 'application/json',
        'User-Agent': 'claude-cli/2.1.63',
    }

    # Fetch account to get org UUID
    conn = http.client.HTTPSConnection('claude.ai', context=ctx, timeout=8)
    conn.request('GET', '/api/account', headers=headers)
    resp = conn.getresponse()
    if resp.status != 200:
        write_cache('', '', f'account_error_{resp.status}')
        sys.exit(0)
    account = json.loads(resp.read())
    conn.close()

    memberships = account.get('memberships', [])
    if not memberships:
        write_cache('', '', 'no_memberships')
        sys.exit(0)
    org_uuid = memberships[0]['organization']['uuid']

    # Fetch usage
    conn = http.client.HTTPSConnection('claude.ai', context=ctx, timeout=8)
    conn.request('GET', f'/api/organizations/{org_uuid}/usage', headers=headers)
    resp = conn.getresponse()
    if resp.status != 200:
        write_cache('', '', f'usage_error_{resp.status}')
        sys.exit(0)
    usage = json.loads(resp.read())
    conn.close()

    five_hour = usage.get('five_hour') or {}
    pct = five_hour.get('utilization')
    resets_at = five_hour.get('resets_at', '')

    if pct is None:
        write_cache('', '', 'no_utilization')
        sys.exit(0)

    pct_int = int(round(float(pct)))

    reset_str = ''
    if resets_at:
        try:
            reset_dt = datetime.fromisoformat(resets_at.replace('Z', '+00:00'))
            reset_est = reset_dt.astimezone(EST)
            reset_str = reset_est.strftime('%-I:%M %p EST')
        except Exception:
            reset_str = resets_at[:16] + ' UTC'

    write_cache(pct_int, reset_str)

except Exception as e:
    write_cache('', '', f'exception_{str(e)[:40]}')
PYEOF
```

### Step 3 — Make scripts executable

Run:
```sh
chmod +x ~/.claude/statusline-command.sh ~/.claude/fetch-usage.sh
```

### Step 4 — Configure `~/.claude/settings.json`

Use the `statusline-setup` agent to add the following `statusLine` block to `~/.claude/settings.json`, preserving all existing keys:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/statusline-command.sh"
}
```

The agent will resolve `~` to the real home path when writing the file.

### Step 5 — Session key setup (optional, for usage bar)

Ask the user:

> "Would you like to enable the usage bar? This requires your Claude.ai session key. It never leaves your machine — it's only used by `fetch-usage.sh` to call the claude.ai API locally."

If **yes**, guide them through these steps:
1. Open [https://claude.ai](https://claude.ai) in their browser and make sure they are logged in
2. Open DevTools (`F12` / `Cmd+Option+I`)
3. Go to **Application** → **Cookies** → `https://claude.ai`
4. Find the cookie named `sessionKey` and copy its value
5. Run: `echo 'PASTE_SESSION_KEY_HERE' > ~/.claude/claude_session && chmod 600 ~/.claude/claude_session`

If **no**, inform them: "The statusline will still show the context window bar. The usage section will show `fetching…` but won't update. You can add the session key later by creating `~/.claude/claude_session`."

### Step 6 — Verify

Tell the user: "Restart Claude Code (or open a new session) to see the statusline. It appears at the top of every prompt."

Also mention the dependency: `jq` must be installed for the context bar to work.
- macOS: `brew install jq`
- Ubuntu/Debian: `sudo apt install jq`
