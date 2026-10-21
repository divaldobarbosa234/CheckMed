---
name: checkmed-change-protocol
description: >-
  Mandatory CheckMed implementation workflow from orientation through commit
  gate. Use before any CheckMed app change, bugfix, feature, or worktree work;
  when git status/HEAD/roadmap must be checked first; or when the user mentions
  change protocol, freeze lists, root cause, or commit approval.
---

# CheckMed change protocol

Read this skill before editing CheckMed application code. Follow phases in order. Do not skip to implementation.

Also apply: `.cursor/rules/checkmed-master-rule.mdc`, body-purity, SwiftData idempotent-writes, change-discipline, and `CHECKMED_MASTER_ROADMAP.md`.

## REGRESSION BUDGET = ZERO

A fix that introduces an unrelated regression is not progress.

Desired loop:

STABLE VERIFIED STATE → SMALL SAFE CHANGE → TARGET TEST → REGRESSION TEST → VERIFIED NEW STATE → FREEZE

Not:

CHANGE → DISCOVER REGRESSION → PATCH → DISCOVER REGRESSION → PATCH

---

## PHASE 0 — ORIENTATION

Before any CheckMed implementation:

* inspect git status
* inspect current HEAD
* identify current worktree
* identify all existing uncommitted changes
* read CHECKMED_MASTER_ROADMAP.md
* read applicable .cursor/rules
* identify whether the task belongs to main or an isolated worktree

Never assume the working tree is clean.

Never overwrite, reset, or commit another subsystem’s dirty files. Never move work between worktrees unless explicitly instructed.

---

## PHASE 1 — UNDERSTAND

Before editing, explicitly answer:

* What exactly is broken?
* What should happen?
* What happens now?
* Which code controls the behavior?
* What is canonical state?
* What existing behavior must remain unchanged?

Canonical chain: DoseLog → DoseSchedule → Medicine → Treatment. Presentation (navigation, highlight, sheets, previews) is not canonical.

---

## PHASE 2 — ROOT CAUSE

Trace the relevant end-to-end flow.

Do not edit merely because a symptom is visible.

Identify the most likely root cause and evidence supporting it.

If root cause is uncertain, STOP and report the uncertainty.

---

## PHASE 3 — IMPACT MAP

Before implementation, produce:

FILES TO MODIFY
FILES TO FREEZE
SYSTEMS AFFECTED
SYSTEMS NOT AFFECTED
REGRESSION RISKS

If additional files become necessary, STOP and explain why before expanding scope.

Do not combine unrelated problems (notification routing, 48-cap, prescription-source UI, Journey Tree, gamification, DoseLoop) even if they share a file.

---

## PHASE 4 — PLAN

Create the smallest safe implementation plan.

Do not combine unrelated problems.

Related cases may be grouped only when they share the same root cause or architecture.

No opportunistic refactoring.

---

## PHASE 5 — IMPLEMENT

Implement only the approved scope.

Never silently remove an existing feature.

Never replace working behavior with a simpler approximation.

Preserve existing UI capabilities unless the task explicitly changes them.

Example that must not vanish during unrelated work: Confirm Medicine photo/PDF source preview → tap → full-screen original → return to Confirm with source still available.

A presentation task must not mutate canonical medication state. Notification body/default taps must never mark a dose taken. Do not reintroduce `Task.detached` around AlarmKit.

---

## PHASE 6 — VALIDATE

Run appropriate validation:

* build
* debug contracts
* targeted test
* adjacent regression test
* persistence/relaunch test when relevant
* physical device test when required

Distinguish clearly between:
implemented,
built,
tested,
and verified.

Never call an untested physical flow verified. Then apply `.cursor/skills/checkmed-regression-gate/SKILL.md` before claiming complete.

---

## PHASE 7 — DIFF AUDIT

Before completion:

* inspect git diff
* inspect git diff --stat
* inspect git status
* verify changed files are expected
* verify no unrelated UI changed
* verify no canonical medication state changed unexpectedly
* verify no existing feature disappeared

---

## PHASE 8 — ROADMAP

Update CHECKMED_MASTER_ROADMAP.md only when the implementation status genuinely changed.

Record:

* status
* files
* tests
* remaining work
* verification level

Never invent verification.

---

## PHASE 9 — COMMIT GATE

Never commit automatically.

Before a commit, report:

FILES CHANGED
WHY
BUILD RESULT
CONTRACT RESULT
TARGET TEST RESULT
REGRESSION TEST RESULT
PHYSICAL DEVICE RESULT
GIT STATUS

Require explicit approval before committing.
