---
name: checkmed-regression-gate
description: >-
  Pre-completion CheckMed regression gate. Use before calling a CheckMed change
  complete, done, fixed, or verified; after implementation or a diff audit; and
  when classifying NOT IMPLEMENTED / IMPLEMENTED — NOT TESTED / TESTED — NOT
  VERIFIED / VERIFIED / BLOCKED.
---

# CheckMed regression gate

Use this skill before calling a CheckMed change complete. Do not skip checks. Do not invent evidence.

Also apply: `.cursor/rules/checkmed-master-rule.mdc` and `.cursor/skills/checkmed-change-protocol/SKILL.md`.

## REGRESSION BUDGET = ZERO

A fix that introduces an unrelated regression is not considered progress.

The desired development loop is:

STABLE VERIFIED STATE
→ SMALL SAFE CHANGE
→ TARGET TEST
→ REGRESSION TEST
→ VERIFIED NEW STATE
→ FREEZE

NOT:

CHANGE
→ DISCOVER REGRESSION
→ PATCH
→ DISCOVER REGRESSION
→ PATCH

---

## Required checks

### 1. TARGET BEHAVIOR

Does the requested behavior now work?

### 2. ADJACENT BEHAVIOR

Does the surrounding flow still work?

### 3. EXISTING FEATURE PRESERVATION

Did anything that worked before disappear?

Inspect the screen/subsystem as it existed before the change (including preview, full-screen viewers, Back, confirm CTAs, notification actions). A feature is not optional because the current task omitted it.

### 4. CANONICAL STATE

Were DoseLogs, treatments, medicines, schedules, or other canonical data changed unexpectedly?

Presentation-only work must not write DoseLogs or bypass DoseLoop.

### 5. NAVIGATION

Did tabs, navigation paths, sheets, Back behavior, or deep linking change unexpectedly?

### 6. PERSISTENCE

Does the expected state survive relaunch?

### 7. DEVICE-SPECIFIC BEHAVIOR

If the feature involves:

* notifications
* AlarmKit
* camera
* PDF/document viewing
* authentication
* permissions
* background behavior

then physical-device verification is required before calling it VERIFIED.

Simulator/build/contracts are not a substitute for that VERIFIED label.

### 8. GIT SCOPE

Are only expected files changed?

Run `git status --short`, `git diff --stat`, and `git diff --name-only`. Unrelated dirty work (Journey Tree, other worktree) must remain untouched.

### 9. BUILD

Run the relevant build(s).

Record Generic iOS Debug and/or Simulator Debug as actually run. Build succeeded is not VERIFIED.

### 10. FINAL CLASSIFICATION

The Skill must use exactly one of:

NOT IMPLEMENTED
IMPLEMENTED — NOT TESTED
TESTED — NOT VERIFIED
VERIFIED
BLOCKED

Never say:
"looks good"
"should work"
"probably fixed"
"seems fine"

without the corresponding evidence.

---

## Classification meaning

| Label | Meaning |
| --- | --- |
| NOT IMPLEMENTED | Scope not done, or stopped before a complete change. |
| IMPLEMENTED — NOT TESTED | Code changed; required tests not run. |
| TESTED — NOT VERIFIED | Tests ran at a level below what the feature requires (e.g. notifications without physical device). |
| VERIFIED | Target, adjacent, and preservation checks passed at the required level, including physical device when section 7 applies. |
| BLOCKED | Cannot complete or cannot honestly classify (uncertain root cause, frozen files needed, dirty tree conflict, tests cannot establish outcome). |

State the evidence next to the label: builds, contracts, simulator vs physical, persistence, git scope.
