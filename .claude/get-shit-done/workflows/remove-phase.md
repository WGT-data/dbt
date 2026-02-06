<purpose>
Remove an unstarted future phase from the roadmap and renumber all subsequent phases.

Purpose: Clean removal of work decided not to do, without polluting context with cancelled markers.
Output: Phase deleted, subsequent phases renumbered, git commit as historical record.
</purpose>

<process>

## Step 1: Parse Arguments

@./.claude/get-shit-done/references/phase-argument-parsing.md

Phase number required. Error if not provided:
```
ERROR: Phase number required
Usage: /gsd:remove-phase <phase-number>
```

## Step 2: Load State

```bash
cat .planning/STATE.md
cat .planning/ROADMAP.md
```

Parse current phase from STATE.md.

## Step 3: Validate Phase Exists

Search for `### Phase {target}:` heading.

If not found:
```
ERROR: Phase {target} not found in roadmap
Available phases: [list]
```

## Step 4: Validate Future Phase

Target must be > current phase number.

If target <= current:
```
ERROR: Cannot remove Phase {target}

Only future phases can be removed:
- Current phase: {current}
- Phase {target} is current or completed

To abandon current work, use /gsd:pause-work instead.
```

Check for SUMMARY.md files:
```bash
ls .planning/phases/{target}-*/*-SUMMARY.md 2>/dev/null
```

If any exist:
```
ERROR: Phase {target} has completed work
Cannot remove phases with completed work.
```

## Step 5: Gather Phase Info

Extract phase name from heading.
Find phase directory.
Find all subsequent phases needing renumbering.

**Subsequent phase detection:**
- For integer removal (17): Find phases > 17, decimals 17.x → 16.x
- For decimal removal (17.1): Find decimals > 17.1 within same integer

## Step 6: Confirm Removal

```
Removing Phase {target}: {Name}

This will:
- Delete: .planning/phases/{target}-{slug}/
- Renumber {N} subsequent phases:
  - Phase 18 → Phase 17
  - Phase 19 → Phase 18

Proceed? (y/n)
```

## Step 7: Delete Phase Directory

```bash
if [ -d ".planning/phases/{target}-{slug}" ]; then
  rm -rf ".planning/phases/{target}-{slug}"
fi
```

## Step 8: Renumber Directories

Process in descending order to avoid overwrites:
```bash
mv ".planning/phases/20-name" ".planning/phases/19-name"
mv ".planning/phases/19-name" ".planning/phases/18-name"
mv ".planning/phases/18-name" ".planning/phases/17-name"
```

Handle decimal directories:
- `17.1-fix-bug` → `16.1-fix-bug` (if removing integer 17)
- `17.2-hotfix` → `17.1-hotfix` (if removing decimal 17.1)

## Step 9: Rename Files in Directories

Inside each renumbered directory:
```bash
mv "18-01-PLAN.md" "17-01-PLAN.md"
mv "18-02-PLAN.md" "17-02-PLAN.md"
```

## Step 10: Update ROADMAP.md

1. Remove the phase section entirely
2. Remove from phase list
3. Remove from Progress table
4. Renumber all subsequent phases in headings, lists, tables
5. Update dependency references

## Step 11: Update STATE.md

Update total phase count and progress percentage.
Do NOT add "Roadmap Evolution" note — git commit is the record.

## Step 12: Update File Contents

Search for and update internal phase references:
```bash
grep -r "Phase 18" .planning/phases/17-*/
```

## Step 13: Commit

@./.claude/get-shit-done/references/git-planning-commit.md

If committing:
```bash
git add .planning/
git commit -m "chore: remove phase {target} ({original-name})"
```

## Step 14: Completion

```
Phase {target} ({name}) removed.

Changes:
- Deleted: .planning/phases/{target}-{slug}/
- Renumbered: Phases {X}-{Y} → {X-1}-{Y-1}
- Updated: ROADMAP.md, STATE.md
- Committed: chore: remove phase {target}

Current roadmap: {total} phases
Current position: Phase {current} of {new-total}

---

## What's Next

- /gsd:progress — see updated status
- Continue with current phase
```

</process>

<anti_patterns>
- Don't remove completed phases (have SUMMARY.md)
- Don't remove current or past phases
- Don't leave gaps in numbering
- Don't add "removed phase" notes to STATE.md
- Don't modify completed phase directories
</anti_patterns>
