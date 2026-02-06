<purpose>
Execute small, ad-hoc tasks with GSD guarantees (atomic commits, STATE.md tracking) while skipping optional agents.

Quick mode is the same system with a shorter path:
- Spawns gsd-planner (quick mode) + gsd-executor(s)
- Skips research, plan-checker, verifier
- Quick tasks live in `.planning/quick/` separate from planned phases
- Updates STATE.md "Quick Tasks Completed" table
</purpose>

<process>

## Step 0: Resolve Model Profile

@./.claude/get-shit-done/references/model-profile-resolution.md

Resolve models for:
- `gsd-planner`
- `gsd-executor`

## Step 1: Pre-flight Validation

```bash
if [ ! -f .planning/ROADMAP.md ]; then
  echo "Quick mode requires an active project with ROADMAP.md."
  echo "Run /gsd:new-project first."
  exit 1
fi
```

## Step 2: Get Task Description

```
AskUserQuestion(
  header: "Quick Task",
  question: "What do you want to do?"
)
```

Store as `$DESCRIPTION`.

Generate slug:
```bash
slug=$(echo "$DESCRIPTION" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-40)
```

## Step 3: Calculate Next Number

```bash
mkdir -p .planning/quick
last=$(ls -1d .planning/quick/[0-9][0-9][0-9]-* 2>/dev/null | sort -r | head -1 | xargs -I{} basename {} | grep -oE '^[0-9]+')
if [ -z "$last" ]; then
  next_num="001"
else
  next_num=$(printf "%03d" $((10#$last + 1)))
fi
```

## Step 4: Create Directory

```bash
QUICK_DIR=".planning/quick/${next_num}-${slug}"
mkdir -p "$QUICK_DIR"
```

Report: `Creating quick task ${next_num}: ${DESCRIPTION}`

## Step 5: Spawn Planner

```
Task(
  prompt="<planning_context>
**Mode:** quick
**Directory:** ${QUICK_DIR}
**Description:** ${DESCRIPTION}

**Project State:** @.planning/STATE.md
</planning_context>

<constraints>
- Create a SINGLE plan with 1-3 focused tasks
- Quick tasks are atomic and self-contained
- Target ~30% context usage
</constraints>

<output>
Write plan to: ${QUICK_DIR}/${next_num}-PLAN.md
Return: ## PLANNING COMPLETE
</output>",
  subagent_type="gsd-planner",
  model="{planner_model}"
)
```

Verify plan exists.

## Step 6: Spawn Executor

```
Task(
  prompt="Execute quick task ${next_num}.

Plan: @${QUICK_DIR}/${next_num}-PLAN.md
Project state: @.planning/STATE.md

<constraints>
- Execute all tasks in the plan
- Commit each task atomically
- Create summary at: ${QUICK_DIR}/${next_num}-SUMMARY.md
- Do NOT update ROADMAP.md
</constraints>",
  subagent_type="gsd-executor",
  model="{executor_model}"
)
```

Verify summary exists.

## Step 7: Update STATE.md

**Check for "Quick Tasks Completed" section:**

If missing, insert after `### Blockers/Concerns`:

```markdown
### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
```

**Append row:**
```markdown
| ${next_num} | ${DESCRIPTION} | $(date +%Y-%m-%d) | ${commit_hash} | [${next_num}-${slug}](./quick/${next_num}-${slug}/) |
```

**Update "Last activity" line.**

## Step 8: Final Commit

@./.claude/get-shit-done/references/git-planning-commit.md

```bash
git add ${QUICK_DIR}/${next_num}-PLAN.md
git add ${QUICK_DIR}/${next_num}-SUMMARY.md
git add .planning/STATE.md
git commit -m "docs(quick-${next_num}): ${DESCRIPTION}"
```

Display completion:
```
GSD ► QUICK TASK COMPLETE

Quick Task ${next_num}: ${DESCRIPTION}
Summary: ${QUICK_DIR}/${next_num}-SUMMARY.md
Commit: ${commit_hash}

Ready for next: /gsd:quick
```

</process>
