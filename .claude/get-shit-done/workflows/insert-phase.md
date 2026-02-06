<purpose>
Insert a decimal phase for urgent work between existing integer phases.

Uses decimal numbering (72.1, 72.2) to preserve logical sequence while accommodating urgent insertions.
</purpose>

<process>

## Step 1: Parse Arguments

First argument: integer phase to insert after
Remaining: phase description

Example: `/gsd:insert-phase 72 Fix critical auth bug`

Validate:
```bash
if [ $# -lt 2 ]; then
  echo "ERROR: Both phase number and description required"
  exit 1
fi
```

## Step 2: Load Roadmap

```bash
cat .planning/ROADMAP.md
```

Error if not found.

## Step 3: Verify Target Phase Exists

Search for `### Phase {after}:` heading.
If not found: Error with available phases.

## Step 4: Find Existing Decimals

@./.claude/get-shit-done/references/decimal-phase-calculation.md

## Step 5: Generate Slug

```bash
slug=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
```

## Step 6: Create Directory

```bash
phase_dir=".planning/phases/${decimal_phase}-${slug}"
mkdir -p "$phase_dir"
```

## Step 7: Update ROADMAP.md

Insert after target phase:

```markdown
### Phase {decimal}: {Description} (INSERTED)

**Goal:** [Urgent work - to be planned]
**Depends on:** Phase {after}
**Plans:** 0 plans
```

## Step 8: Update STATE.md

Add to "Roadmap Evolution":
```
- Phase {decimal} inserted after Phase {after}: {description} (URGENT)
```

## Step 9: Completion

```
Phase {decimal} inserted after Phase {after}:
- Directory: .planning/phases/{decimal}-{slug}/
- Status: Not planned yet
- Marker: (INSERTED)

---

## ▶ Next Up

/gsd:plan-phase {decimal}
```

</process>
