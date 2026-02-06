<purpose>
Create all phases necessary to close gaps identified by `/gsd:audit-milestone`.

One command creates all fix phases — no manual `/gsd:add-phase` per gap.
</purpose>

<process>

## Step 1: Load Audit Results

```bash
ls -t .planning/v*-MILESTONE-AUDIT.md 2>/dev/null | head -1
```

Parse YAML frontmatter:
- `gaps.requirements` — unsatisfied requirements
- `gaps.integration` — missing cross-phase connections
- `gaps.flows` — broken E2E flows

Error if no audit file or no gaps:
```
No audit gaps found. Run /gsd:audit-milestone first.
```

## Step 2: Prioritize Gaps

Group by priority from REQUIREMENTS.md:

| Priority | Action |
|----------|--------|
| `must` | Create phase, blocks milestone |
| `should` | Create phase, recommended |
| `nice` | Ask user: include or defer? |

## Step 3: Group Gaps into Phases

Cluster related gaps:
- Same affected phase → combine
- Same subsystem (auth, API, UI) → combine
- Dependency order (fix stubs before wiring)
- Keep phases focused: 2-4 tasks each

## Step 4: Determine Phase Numbers

```bash
ls -d .planning/phases/*/ | sort -V | tail -1
```

New phases continue from highest existing.

## Step 5: Present Gap Closure Plan

```markdown
## Gap Closure Plan

**Milestone:** {version}
**Gaps to close:** {N} requirements, {M} integration, {K} flows

### Proposed Phases

**Phase {N}: {Name}**
Closes:
- {REQ-ID}: {description}
- Integration: {from} → {to}

{If nice-to-have gaps:}

### Deferred (nice-to-have)
These gaps are optional. Include them?

---

Create these {X} phases? (yes / adjust / defer optional)
```

## Step 6: Update ROADMAP.md

Add phases with gap closure context:

```markdown
### Phase {N}: {Name}
**Goal:** {derived from gaps}
**Requirements:** {REQ-IDs}
**Gap Closure:** Closes gaps from audit
```

## Step 7: Create Phase Directories

```bash
mkdir -p ".planning/phases/{NN}-{name}"
```

## Step 8: Commit

@./.claude/get-shit-done/references/git-planning-commit.md

## Step 9: Offer Next Steps

```
## ✓ Gap Closure Phases Created

**Phases added:** {N} - {M}
**Gaps addressed:** {count} requirements, {count} integration, {count} flows

---

## ▶ Next Up

**Plan first gap closure phase**

/gsd:plan-phase {N}

---

**After all gap phases complete:**
/gsd:audit-milestone — re-audit to verify gaps closed
```

</process>
