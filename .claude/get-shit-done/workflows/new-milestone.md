<purpose>
Orchestrate `/gsd:new-milestone` from context loading through roadmap approval.

Design goals:
- Keep base context small
- Load heavy assets only when needed
- Leverage existing validated requirements
</purpose>

<always_loaded>
Load these first:

- `./.claude/get-shit-done/references/questioning.md`
- `./.claude/get-shit-done/references/ui-brand.md`
- `./.claude/get-shit-done/templates/project.md`
- `./.claude/get-shit-done/templates/requirements.md`
</always_loaded>

<process>

## Phase 1: Load Context

Load project context:

```bash
cat .planning/PROJECT.md
cat .planning/STATE.md
cat .planning/MILESTONES.md 2>/dev/null
cat .planning/config.json 2>/dev/null
cat .planning/MILESTONE-CONTEXT.md 2>/dev/null
```

Error if PROJECT.md missing:
```
ERROR: No project found. Run /gsd:new-project first.
```

## Phase 2: Gather Milestone Goals

**If MILESTONE-CONTEXT.md exists:**
- Use features and scope from discuss-milestone
- Present summary for confirmation

**If no context file:**
- Present what shipped in last milestone
- Start with: "What do you want to build next?"
- Use AskUserQuestion to explore features, priorities, constraints

## Phase 3: Determine Milestone Version

Parse last version from MILESTONES.md.
Suggest next version (v1.0 → v1.1, or v2.0 for major).

AskUserQuestion:
- header: "Version"
- question: "What version for this milestone?"
- options:
  - "v[X.Y] — [suggested description]"
  - "v[X+1].0 — Major version bump"
  - "Custom version"

## Phase 4: Update PROJECT.md

Add/update Current Milestone section:

```markdown
## Current Milestone: v[X.Y] [Name]

**Goal:** [One sentence describing milestone focus]

**Target features:**
- [Feature 1]
- [Feature 2]
- [Feature 3]
```

Update Active requirements section with new goals.
Update footer timestamp.

## Phase 5: Update STATE.md

```markdown
## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: [today] — Milestone v[X.Y] started
```

Keep Accumulated Context (decisions, blockers) from previous milestone.

## Phase 6: Cleanup and Commit

Delete MILESTONE-CONTEXT.md if exists (consumed).

@./.claude/get-shit-done/references/git-planning-commit.md

If committing:
```bash
git add .planning/PROJECT.md .planning/STATE.md
git commit -m "docs: start milestone v[X.Y] [Name]"
```

## Phase 6.5: Resolve Model Profile

@./.claude/get-shit-done/references/model-profile-resolution.md

Resolve models for:
- `gsd-project-researcher`
- `gsd-research-synthesizer`
- `gsd-roadmapper`

## Phase 7: Research Decision

AskUserQuestion:
- header: "Research"
- question: "Research the domain ecosystem for new features before defining requirements?"
- options:
  - "Research first (Recommended)" — Discover patterns, expected features, architecture for NEW capabilities
  - "Skip research" — Go straight to requirements

**If skip:** Continue to Phase 8.

**If research:**

Display `GSD ► RESEARCHING` banner.

```bash
mkdir -p .planning/research
```

Create milestone-aware research brief:
- Note this is SUBSEQUENT MILESTONE
- List validated/existing capabilities (DO NOT re-research)
- Focus on NEW features only

Load research prompt templates and spawn 4 parallel researchers:
- Stack (additions for new features)
- Features (expected behavior)
- Architecture (integration)
- Pitfalls (mistakes when adding to existing system)

Spawn synthesizer for SUMMARY.md.

Display `GSD ► RESEARCH COMPLETE ✓` banner with key findings.

If committing, commit research artifacts.

## Phase 8: Define Requirements

Display `GSD ► DEFINING REQUIREMENTS` banner.

Load context:
- `.planning/PROJECT.md` (Validated requirements = existing)
- `.planning/research/FEATURES.md` (if exists)

**If research exists:**
- Present features by category
- Scope each category with AskUserQuestion (multi-select)

**If no research:**
- Gather requirements through AskUserQuestion conversation

Track:
- Selected features → this milestone's requirements
- Unselected table stakes → future milestone
- Unselected differentiators → out of scope

Additions pass:
- header: "Additions"
- question: "Any requirements research missed?"
- options: "No" / "Yes, let me add some"

Generate REQUIREMENTS.md:
- v1 Requirements for THIS milestone (checkboxes, REQ-IDs)
- Future Requirements (deferred)
- Out of Scope (explicit exclusions)
- Traceability section (filled by roadmap)

REQ-ID format: `[CATEGORY]-[NUMBER]` (continue numbering from existing).

Present full requirements list for confirmation.

If committing, commit requirements.

## Phase 9: Create Roadmap

Display `GSD ► CREATING ROADMAP` banner.

**Determine starting phase number:**
- Read MILESTONES.md for last phase number
- New phases continue from there

Create compact context files in `.planning/_ctx/`.

Spawn gsd-roadmapper with milestone context:
- Start phase numbering from [N]
- Derive phases from THIS MILESTONE's requirements
- Map every requirement to exactly one phase
- Derive 2-5 success criteria per phase
- Validate 100% coverage

Handle returns:
- `## ROADMAP BLOCKED`: Surface blockers, resolve, respawn
- `## ROADMAP CREATED`: Present structured summary

Approval gate:
- header: "Roadmap"
- question: "Does this roadmap structure work for you?"
- options: "Approve" / "Adjust phases" / "Review full file"

If adjust: Collect feedback, respawn roadmapper, loop until approved.

After approval, if committing:
```bash
git add .planning/ROADMAP.md .planning/STATE.md .planning/REQUIREMENTS.md
git commit -m "docs: create milestone v[X.Y] roadmap ([N] phases)"
```

## Phase 10: Done

Display `GSD ► MILESTONE INITIALIZED ✓` banner.

Show artifact table:
| Artifact | Location |
|----------|----------|
| Project | `.planning/PROJECT.md` |
| Research | `.planning/research/` |
| Requirements | `.planning/REQUIREMENTS.md` |
| Roadmap | `.planning/ROADMAP.md` |

Show Next Up block:
- `/gsd:discuss-phase [N]` — gather context and clarify approach
- optional `/gsd:plan-phase [N]`

</process>
