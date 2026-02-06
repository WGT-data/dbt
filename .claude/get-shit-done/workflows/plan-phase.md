<purpose>
Orchestrate `/gsd:plan-phase` from validation through plan verification.

Design goals:
- Spawn research, planner, and checker agents with fresh context
- Build compact context files to avoid passing full source docs
- Handle revision loop for plan quality
</purpose>

<always_loaded>
- `./.claude/get-shit-done/references/ui-brand.md`
</always_loaded>

<process>

## Step 1: Validate Environment and Resolve Model Profile

```bash
ls .planning/ 2>/dev/null || { echo "ERROR: Run /gsd:new-project first"; exit 1; }
```

@./.claude/get-shit-done/references/model-profile-resolution.md

Resolve models for:
- `gsd-phase-researcher`
- `gsd-planner`
- `gsd-plan-checker`

## Step 2: Parse and Normalize Arguments

@./.claude/get-shit-done/references/phase-argument-parsing.md

Extract from $ARGUMENTS:
- Phase number (integer or decimal)
- `--research` — Force re-research
- `--skip-research` — Skip research
- `--gaps` — Gap closure mode (uses VERIFICATION.md)
- `--skip-verify` — Bypass verification loop

If no phase number: Detect next unplanned phase.

Check for existing research and plans:
```bash
ls "${PHASE_DIR}"/*-RESEARCH.md 2>/dev/null
ls "${PHASE_DIR}"/*-PLAN.md 2>/dev/null
```

## Step 3: Validate Phase

```bash
grep -A5 "Phase ${PHASE}:" .planning/ROADMAP.md 2>/dev/null || {
  echo "ERROR: Phase ${PHASE} not found"
  exit 1
}
```

Extract phase number, name, description.

## Step 4: Ensure Phase Directory and Load CONTEXT.md

```bash
PHASE_DIR=$(ls -d .planning/phases/${PHASE}-* 2>/dev/null | head -1)
if [ -z "$PHASE_DIR" ]; then
  PHASE_NAME=$(grep "Phase ${PHASE}:" .planning/ROADMAP.md | sed 's/.*Phase [0-9]*: //' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  mkdir -p ".planning/phases/${PHASE}-${PHASE_NAME}"
  PHASE_DIR=".planning/phases/${PHASE}-${PHASE_NAME}"
fi
CONTEXT_CONTENT=$(cat "${PHASE_DIR}"/*-CONTEXT.md 2>/dev/null)
```

**CRITICAL:** Store `CONTEXT_CONTENT` now. Pass to all downstream agents.

## Step 5: Handle Research

Skip if `--gaps` or `--skip-research`.

Check config: `workflow.research` setting.

If RESEARCH.md exists and `--research` not set: Use existing.

Otherwise spawn `gsd-phase-researcher`:

Display: `GSD ► RESEARCHING PHASE {X}`

Build research prompt with:
- Phase description from ROADMAP
- Requirements (if any)
- Prior decisions from STATE.md
- CONTEXT_CONTENT (locked decisions, Claude's discretion, deferred)

Handle returns:
- `## RESEARCH COMPLETE` → Continue
- `## RESEARCH BLOCKED` → Present blocker, offer options

## Step 6: Check Existing Plans

```bash
ls "${PHASE_DIR}"/*-PLAN.md 2>/dev/null
```

If exists: Offer continue/view/replan options.

## Step 7: Build Compact Context Files

```bash
mkdir -p "${PHASE_DIR}/_ctx"
```

Create:
- `planner-input.md` — phase goal, requirements, locked decisions, research findings, **full CONTEXT_CONTENT**
- `checker-input.md` — phase goal, must-haves, requirements, verification constraints, **full CONTEXT_CONTENT**
- `revision-input.md` — issues from checker, **full CONTEXT_CONTENT** (created during revision loop)

**CRITICAL:** All three context files MUST include the full CONTEXT_CONTENT (user decisions from /gsd:discuss-phase). This ensures:
- Planner honors locked decisions when creating tasks
- Checker can verify plans don't contradict user decisions
- Revision loop preserves user constraints

Do not inline full STATE.md / ROADMAP.md / RESEARCH.md.

## Step 8: Spawn gsd-planner

Display: `GSD ► PLANNING PHASE {X}`

```
Task(
  prompt="<planning_context>
**Phase:** {phase_number}
**Mode:** {standard | gap_closure}

{planner_input_content}

<user_decisions>
{CONTEXT_CONTENT}
</user_decisions>

Source files available (read on demand):
- .planning/STATE.md
- .planning/ROADMAP.md
- {phase_dir}/*-RESEARCH.md
</planning_context>

<constraints>
**CRITICAL:** The <user_decisions> section contains locked decisions from /gsd:discuss-phase.
- Plans MUST implement decisions from `## Decisions` exactly as specified
- Plans MUST NOT include anything from `## Deferred Ideas`
- Plans MAY exercise judgment on items in `## Claude's Discretion`
</constraints>

<output>
Plans executable by /gsd:execute-phase.
Frontmatter: wave, depends_on, files_modified, autonomous
Tasks in XML format with verification criteria
must_haves for goal-backward verification
</output>",
  subagent_type="gsd-planner",
  model="{planner_model}"
)
```

## Step 9: Handle Planner Return

- `## PLANNING COMPLETE` — Plans created, proceed to verification
- `## CHECKPOINT REACHED` — Present to user, spawn continuation
- `## PLANNING INCONCLUSIVE` — Show attempts, offer options

If `--skip-verify` or `workflow.plan_check = false`: Skip to Step 13.

## Step 10: Spawn gsd-plan-checker

Display: `GSD ► VERIFYING PLANS`

Read plans:
```bash
PLANS_CONTENT=$(cat "${PHASE_DIR}"/*-PLAN.md 2>/dev/null)
```

```
Task(
  prompt="<verification_context>
**Phase:** {phase_number}
**Phase Goal:** {goal}

**Plans:**
{plans_content}

{checker_input_content}

<user_decisions>
{CONTEXT_CONTENT}
</user_decisions>
</verification_context>

<verification_requirement>
**CRITICAL:** Verify Context Compliance dimension:
- Do plans implement all locked decisions from `## Decisions`?
- Do plans exclude everything from `## Deferred Ideas`?
- Flag any task that contradicts a user decision as a BLOCKER.
</verification_requirement>

Return: ## VERIFICATION PASSED or ## ISSUES FOUND",
  subagent_type="gsd-plan-checker",
  model="{checker_model}"
)
```

## Step 11: Handle Checker Return

- `## VERIFICATION PASSED` → Proceed to Step 13
- `## ISSUES FOUND` → Check iteration count, proceed to Step 12

## Step 12: Revision Loop (Max 3 Iterations)

Track `iteration_count`.

If iteration_count < 3:
- Display: `Sending back to planner for revision... (iteration {N}/3)`
- Write revision-input.md with:
  - Issues from checker
  - **Full CONTEXT_CONTENT** (user decisions - CRITICAL for maintaining fidelity)
- Spawn planner with revision context including `<user_decisions>{CONTEXT_CONTENT}</user_decisions>`
- After planner returns → spawn checker again (Step 10)
- Increment iteration_count

**CRITICAL:** Each revision iteration MUST re-inject CONTEXT_CONTENT. Without this, the planner loses user constraints during revision.

If iteration_count >= 3:
- Display remaining issues
- Offer: Force proceed / Provide guidance / Abandon

## Step 13: Index with Memory (Optional)

**If gsd_memory MCP tools are available:**

Check if `gsd_memory_index` tool exists. If available, trigger indexing:

```
gsd_memory_index({
  path: process.cwd()
})
```

This updates the project's searchable knowledge base with new plans and research.

**If tool not available:** Skip silently.

## Step 14: Present Final Status

@./.claude/get-shit-done/references/git-planning-commit.md

Route to completion banner.

</process>

<completion_banner>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GSD ► PHASE {X} PLANNED ✓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**Phase {X}: {Name}** — {N} plan(s) in {M} wave(s)

| Wave | Plans | What it builds |
|------|-------|----------------|
| 1 | 01, 02 | [objectives] |
| 2 | 03 | [objective] |

Research: {Completed | Used existing | Skipped}
Verification: {Passed | Passed with override | Skipped}

───────────────────────────────────────────────────────────────

## ▶ Next Up

**Execute Phase {X}** — run all {N} plans

/gsd:execute-phase {X}

<sub>/clear first → fresh context window</sub>

───────────────────────────────────────────────────────────────

**Also available:**
- cat .planning/phases/{phase-dir}/*-PLAN.md — review plans
- /gsd:plan-phase {X} --research — re-research first

───────────────────────────────────────────────────────────────
</completion_banner>
