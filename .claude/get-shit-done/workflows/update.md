<purpose>
Check for GSD updates, install if available, display changelog.

Provides better update experience than raw `npx get-shit-done-cc`.
</purpose>

<process>

## Step 1: Get Installed Version

```bash
# Check local install first
if [ -f ./.claude/get-shit-done/VERSION ]; then
  INSTALL_TYPE="local"
  VERSION_FILE="./.claude/get-shit-done/VERSION"
  INSTALL_FLAG="--local"
elif [ -f ./.claude/get-shit-done/VERSION ]; then
  INSTALL_TYPE="global"
  VERSION_FILE="$HOME/.claude/get-shit-done/VERSION"
  INSTALL_FLAG="--global"
else
  INSTALL_TYPE="unknown"
  INSTALL_FLAG="--global"
fi

[ -n "$VERSION_FILE" ] && cat "$VERSION_FILE"
```

If VERSION missing: Treat as 0.0.0, proceed to install.

## Step 2: Check Latest Version

```bash
npm view get-shit-done-cc version 2>/dev/null
```

If npm fails: Show offline message, stop.

## Step 3: Compare Versions

If installed == latest: "Already on latest version." Stop.
If installed > latest: "Ahead of release (dev version?)." Stop.

## Step 4: Show Changes and Confirm

Fetch changelog, extract entries between versions.

```
## GSD Update Available

**Installed:** 1.5.10
**Latest:** 1.5.15

### What's New
────────────────────────────────────────────

[changelog entries]

────────────────────────────────────────────

⚠️ Clean install warning:
- ./.claude/commands/gsd/ wiped and replaced
- ./.claude/get-shit-done/ wiped and replaced
- Custom files outside these preserved
```

Ask: "Proceed with update?" (Yes / No)

## Step 5: Run Update

```bash
npx get-shit-done-cc $INSTALL_FLAG
rm -f ./.claude/cache/gsd-update-check.json
```

## Step 6: Display Result

```
╔═══════════════════════════════════════════════════════════╗
║  GSD Updated: v1.5.10 → v1.5.15                           ║
╚═══════════════════════════════════════════════════════════╝

⚠️ Restart Claude Code to pick up new commands.
```

</process>
