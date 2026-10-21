# CHECKMED MASTER ROADMAP

> **Official product name: Conny Cooper.**
> Code, bundle identifiers, Keychain, UserDefaults, StoreKit product IDs, and some asset names still use CheckMed / ChekMed. Keep those identifiers where the existing code paths require them.
>
> **Single source of truth for Conny Cooper (CheckMed) development, verification, release readiness, and future phases.**
>
> This roadmap preserves completed work and its history. New work must be added here before implementation begins. Do not replace this file with a new roadmap.
>
> **Reconciled 8 October 2026** against iOS HEAD `2de9a94a19dbc4a4fa64b22d49e45e47c1779acc` and website HEAD `b42ade9fbb03b19b8fede538b0f75bea6eb614bc`.
>
> **Current product state:** Home / Progress remain DESIGN LOCKED. Treatments, Refill, and Profile presentation are integrated on `2de9a94`. Website Phase 3+4 showcase is live on `connycooper.com`. Onboarding is **architecture-audited only** — implementation is not approved.
>
> **Pre-Build 9 source freeze (22 Oct 2026):** iOS app Swift is checkpointed at `6943727fec1dd95cb938abe6f4c28715821ac2b9` on `cursor/dashboard-onboarding-and-super-trial`. Public product name is **Conny Cooper** (Dr. Cooper). Family in this binary is a **local extra profile**, not caregiver invitations. Confirm photo/PDF preview and tab-hosted Add Prescription layout are **user-confirmed**. Premium IAP, AlarmKit, voice runtime, report PDF export, and extra-profile cloud sync still require verification. **Build 9 is not authorized.** There is **no calendar launch deadline**.

---

# 0. ROADMAP RULES

## Single source of truth

`CHECKMED_MASTER_ROADMAP.md` is the authoritative ordered list for:

* bugs
* regressions
* root-cause investigations
* verification tasks
* architectural constraints
* completed phases
* deferred opportunities
* release blockers
* future product phases
* launch gates

Do not treat newly discovered issues as isolated tasks outside this roadmap.

Every new issue must be:

1. added to this roadmap;
2. classified by root cause and system impact;
3. placed in the correct priority/order;
4. assigned a status;
5. verified before being marked complete.

## Forest, not trees

Before changing or removing any presentation, navigation, or UI layer:

> **If I remove/move this presentation layer, what underlying functionality, route, calculation, or data consumer could be affected?**

Map dependencies first.

Make the minimum safe change.

Verify neighboring systems afterward.

Do not fix one surface by damaging another.

## Canonical medication truth

The canonical medication/event chain remains:

**Prescription → Medicine → Treatment → DoseSchedule → DoseLog → DoseLoop → adherence / challenge / Journey / reporting / gamification**

`DoseLog.scheduleId → DoseSchedule.medicineId → Medicine.treatmentId`

DoseLogs do not carry `treatmentId`.

Do not create a second medication-truth system.

Gamification, Journey, streaks, reports, notifications, and presentation layers must derive from canonical medication events/state rather than independently creating medication state.

## Freeze principle

When a system is marked **CLOSED / FROZEN**, later work must not casually reopen it.

A change to a frozen system requires:

* explicit roadmap entry;
* dependency audit;
* regression verification;
* release classification.

---

# 1. CURRENT RELEASE STATUS

## Overall status

**RELEASE-FINISH / VERIFICATION STAGE, plus an approved architecture-only onboarding plan**

The core medication architecture and planned Phase 6/7 retention work remain complete and frozen as originally recorded below.

Since that recording, Conny Cooper **presentation** work landed on iOS (`2de9a94`) and the public website showcase shipped (`b42ade9`). Those are closed presentation milestones, not a reopen of DoseLoop, Home medication truth, or gamification.

Remaining **launch** work is still (no calendar date; Build 9 is not authorized):

1. physical verification of the final release binary (Phase 5 A1–A4 / B1–B4 / AlarmKit);
2. Phase 8 release/legal/App Store readiness;
3. compact-device and live-dose verification that contracts cannot replace;
4. Super/premium verification (IAP, voice, alarm themes, report export) without repeating closed 12-medicine tests;
5. launch, only after explicit authorization.

**Personalisation & Onboarding** is now a **planned product phase**. Architecture audit is complete. **Do not implement it until explicitly approved.** Implementation must not redesign Home, mutate canonical medication state, or duplicate RewardEngine / PhilCoach.

---

# 2. COMPLETED CORE FOUNDATION

## STATUS: CLOSED

The stable CheckMed medication architecture is complete and remains frozen unless a verified release blocker requires intervention.

Completed and verified areas include:

* authentication;
* medication setup;
* prescription/manual flows;
* Medicine / Treatment / DoseSchedule structure;
* canonical DoseLog generation;
* DoseLoop action handling;
* normal doses;
* late doses;
* missed doses;
* recovery/back-on-track behavior;
* streak/adherence behavior;
* Journey;
* Treatment History;
* Medical Report;
* medication deletion/re-add behavior;
* Free/Super entitlement behavior;
* scan flow;
* prescription-date handling;
* future-dose creation;
* past treatment start without historical fake missed logs;
* Plan Resume / Confirm commit boundary;
* navigation/back continuity;
* prescription source archive identity;
* AlarmKit / notification architecture;
* notification crash-path fixes;
* Journey Tree / treatment UUID classification.

### Important architectural decisions that remain frozen

* DoseLog remains the canonical medication event.
* DoseLoop remains the canonical action path.
* Phil is presentation-only.
* GamificationMemory is an idempotent presentation/retention overlay.
* Journey classification uses treatment identity and must not become a source of medication truth.
* Home must not independently manufacture medication state.
* Plan Resume **Continue** is the commit boundary.
* Back/navigation/time-picker interaction must not persist a plan prematurely.
* Confirm is not the medication persistence boundary.
* Past treatment start dates must not backfill historical fake missed DoseLogs.
* Future DoseLogs preserve the prescribed times.

---

# 3. FIX 2B — JOURNEY + TREATMENT HISTORY

## STATUS: CLOSED

FIX 2B is complete and frozen.

The Journey/Treatment History model is based on treatment identity.

### Canonical identity

`JourneyTreeBranch.id` = treatment UUID.

Medicines are grouped under their owning treatment.

`TreatmentJourneyClassification` derives classification from treatment state/date information rather than persisting a second classification system.

### Important freeze

Journey classification must not be reused as a substitute for medication-event truth.

Challenge/DoseLog logic must continue to use canonical medication state.

Do not reopen FIX 2B merely to solve an unrelated presentation issue.

---

# 4. MANUAL PRESCRIPTION / PLAN FLOW

## STATUS: CLOSED

The manual prescription flow is complete and verified.

Completed:

* manual prescription form;
* date selection;
* required-field validation;
* clearer validation state;
* frequency/times selection;
* dose/unit handling;
* prescription start-date handling;
* past start date support;
* no historical backfill of fake missed doses;
* correct creation of future DoseLogs;
* preservation of prescribed times;
* plan preview;
* Confirm behavior;
* Plan Resume;
* single commit boundary;
* navigation/back behavior.

### Commit boundary

**Confirm is not the persistence boundary.**

The plan is committed when the user proceeds through the designated Plan Resume **Continue** path.

Back/navigation/time-picker interaction must not independently persist the treatment.

---

# 5. PHASE 5 — NOTIFICATION / ALARMKIT CLOSURE

## IMPLEMENTATION STATUS: CLOSED

Phase 5 implementation is complete.

The notification closure includes:

* notification body-tap routing;
* Home focus/highlight behavior;
* delivered-notification cleanup;
* notification lifecycle handling;
* AlarmKit MainActor safety;
* notification icon handling;
* TestClock support associated with the implementation;
* preservation of existing Journey Tree functionality;
* preservation of canonical DoseLog/DoseLoop behavior.

Historical implementation references remain preserved, including:

* `d673153`
* `5a1ec64`
* related Phase 5 verification records.

`5eb9a9f` remains correctly classified as the Confirm-source-preview work and is not to be treated as part of the notification closure.

## PHASE 5 PHYSICAL VERIFICATION

### STATUS: OPEN — FINAL RELEASE VERIFICATION

The Phase 5 implementation itself is complete.

The remaining requirement is verification on the **final/main release binary**, not continued implementation.

### A1–A4

Physical verification required.

### B1–B4

Physical verification required.

### AlarmKit / notification two-tap crash path

Physical verification required on the final/main release binary.

### Rule

Do not reopen Phase 5 implementation unless final physical verification discovers an actual release blocker.

---

# 6. PHASE 6 — FULL GAMIFICATION / RETENTION SYSTEM

## STATUS: CLOSED

Phase 6 is complete.

Gamification is considered **core product/retention functionality**, not an optional post-launch extra.

Completed architecture includes:

* persistent XP;
* progression/levels;
* badges;
* achievements;
* reward presentation;
* idempotent persistence;
* streak/adherence integration;
* challenge progression;
* Phil reactions;
* missed-dose recovery presentation;
* day-complete behavior;
* persistent gamification memory;
* event-driven presentation.

### Canonical dependency rule

Gamification derives from canonical medication events.

It must not create or mutate medication truth.

### Phil

Phil remains presentation-only.

Phil must not become a second medication-state engine.

### Freeze

Do not redesign Phase 6 during release finish.

Do not introduce new Phil decision branches, new reward architecture, or new medication-event logic unless a release blocker is demonstrated.

---

# 7. PHASE 7 — PERSONALISATION (ORIGINAL SCOPE)

## STATUS: CLOSED FOR RELEASE (original 7A–7D scope)

The planned personalisation work **as originally defined in this section** (identity messaging, treatment-reason presentation, extra Phil copy, habit/subscription architecture notes) remains closed for release.

**This is not the same work as the 8 October 2026 Personalisation & Onboarding funnel** (Welcome → care context → profile → prescription → Super trial → Dashboard). That funnel is recorded in §20. Do not treat §20 as a reopen of 7B/7C code freezes.

---

## 7A — Identity & Messaging

### STATUS: CLOSED

Already solved.

Existing identity/messaging behavior is sufficient for release.

Do not reopen without a specific release blocker.

---

## 7B — Personalised Treatment Experience

### STATUS: CLOSED — NO RELEASE CODE REQUIRED

The treatment experience is already personalised through:

* user's medicines;
* prescribed times;
* treatment dates;
* Home path;
* Journey identity;
* treatment UUID classification;
* Confirm information;
* Plan Resume information;
* Medical Report information.

Existing `MedicineSummary.reason` can support optional future presentation, but this is not a release blocker.

### Explicit freeze

Do not add treatment reason to:

* Home/DoseNode;
* Challenge;
* DoseLoop;
* Plan Resume commit;
* Journey classification;
* Phil;
* rewards;
* notifications;
* entitlements.

Optional medication-detail/overview presentation remains safely deferrable.

---

## 7C — Personalised Phil / Habit Messaging

### STATUS: CLOSED — NO RELEASE CODE REQUIRED

Phil is already context-sensitive to relevant medication/habit events.

Existing behavior includes contextual reactions for:

* dose completion;
* recovery;
* day completion;
* streak progression;
* other established gamification events.

### Deferred opportunities

Optional future copy improvements such as using the existing `philNiceTook` medicine-specific message in additional presentation surfaces remain post-release opportunities.

### Explicit freeze

Do not:

* rebuild PhilCoach;
* introduce new late-dose coaching architecture;
* introduce new XP coaching;
* change GamificationMemory;
* change Reward persistence;
* alter DoseLoop;
* alter notification logic for personalisation.

---

## 7D — Personalisation / Habit / Subscription Architecture

### STATUS: CLOSED FOR RELEASE

The broader personalisation direction has been architecturally defined and does not require additional release-blocking implementation.

The product direction remains:

**Personalisation → Habit → Subscription**

Future personalisation must build on the stable canonical medication and gamification foundation rather than creating parallel state.

---

## 7E — Additional Personalisation

### STATUS: PARKED

No implementation.

No release dependency.

Do not begin 7E before launch unless a specific release requirement changes the roadmap.

---

# 8. RELEASE-FINISH ORDER

This is the current mandatory execution order.

## 8.1 FINAL PHYSICAL VERIFICATION

### STATUS: OPEN

Complete physical verification of the final/main release binary.

### Required Phase 5 verification

* A1
* A2
* A3
* A4
* B1
* B2
* B3
* B4
* AlarmKit / notification crash path

### Important

Verification must be performed against the final binary that is intended to proceed toward release.

A previous Phase 5 test-binary PASS does not replace final-main-binary verification.

---

# 9. PHASE 8 — RELEASE HARDENING / LEGAL / APP STORE

## STATUS: OPEN

Phase 8 begins after the final physical verification gate is satisfied, while release-readiness work can be audited in parallel where it does not modify frozen product behavior.

### 8A — Production configuration

Verify:

* Release configuration;
* production Supabase configuration;
* production authentication;
* Google Sign-In production configuration;
* Apple Sign-In production configuration;
* email authentication;
* no guest/anonymous authentication path;
* production entitlement configuration.

### 8B — StoreKit / subscription

Verify:

* production subscription products;
* Super entitlement;
* Free-plan limits;
* 3-day trial configuration;
* paywall behavior;
* report-download entitlement;
* production StoreKit configuration;
* no test-only purchase assumptions.

### 8C — Privacy / legal

Verify:

* privacy manifest;
* required privacy declarations;
* data collection disclosures;
* account/data deletion requirements;
* privacy policy;
* terms where required;
* App Store privacy information;
* subscription disclosures;
* trial/renewal disclosures;
* required medical/health disclaimers.

### 8D — App Store metadata

Verify:

* app name;
* subtitle;
* description;
* keywords;
* screenshots;
* app icon;
* age rating;
* category;
* support URL;
* privacy policy URL;
* marketing information;
* localization;
* subscription metadata.

### 8E — Release build

Verify:

* Release build succeeds;
* no DEBUG-only behavior;
* no TestClock/test bridge in production behavior;
* no development credentials;
* no temporary UI;
* no guest flow;
* no debug controls;
* no test data;
* no stale feature flags;
* no accidental recording/debug assets;
* no development-only assumptions.

### 8E verification (20 Oct 2026) — SOURCE + generic iOS Release compile

**STATUS: COMPILE PASSED — not a TestFlight archive, not physical-device VERIFIED.**

Generic iOS Release (`-destination generic/platform=iOS`, derivedData `.derivedData-8e-release`, `CODE_SIGNING_ALLOWED=NO`): **BUILD SUCCEEDED**, `XCODEBUILD_EXIT=0`. No simulator boot. No physical iPhone.

| Check | Result | Evidence |
| --- | --- | --- |
| `CHECKMED_DEBUG_CONTRACTS`, `CHECKMED_SEED_DURABLE_CONTRACT`, `CHECKMED_CAPACITY_CONTRACTS`, `CHECKMED_INTAKE_VERIFY`, `CHECKMED_TH1_VERIFY`, `CHECKMED_LIFECYCLE_CONTRACTS`, `CHECKMED_UI_*` | Cannot activate in Release | Types/call sites `#if DEBUG`. Release binary `strings` has none of these keys. |
| TestClock / Darwin clock bridge | Unreachable in Release | `CheckMedClock.now` is `Date()`; freeze/bridge compiled out. `installCommandBridge` only in `#if DEBUG` `bindStores`. No `checkmed-clock-command` / `com.checkmed.debug.clock` in Release `strings`. |
| Guest / debug routes | Cannot bypass auth | `allowsGuest` forces `.signIn`. Legal copy: no guest. WindowGroup Release is `standardRoot` only. |
| DEBUG test hosts vs production onboarding | Isolated | TH-1 / Intake / Capacity / Seed hosts are `#if DEBUG` and not in Release `strings`. Release `makeAppStore()` is disk `CheckMedStore()`. |
| Local Supabase isolation | Cannot enable test endpoint | Isolation URL/key helpers `#if DEBUG`. Isolation **intent** in Release returns `nil` client (fail-closed), not `127.0.0.1:54321`. Info.plist `SUPABASE_URL` is hosted `https://`. Release `strings`: `CHECKMED_LOCAL_ISOLATION` remains (enum is not `#if DEBUG`); no `54321` / `supabase-demo`. Residual: if that env were set on a Release process, Auth would have **no** client rather than localhost. |
| Canonical medication this batch | Unchanged | `persistDrafts` / schema / DoseLoop not in the CheckMedStore diff. Only DEBUG `init(contractStoreURL:configurationName:)`. |

Notification category ids (`CHECKMED_TAKEN`, etc.) are production UN identifiers, not launch flags.

### 8F — Final regression

Verify the complete critical product path:

**Sign in → setup → medication → schedule → DoseLog → reminder → dose action → adherence → Challenge → Journey → Report → subscription/entitlement**

Also verify:

* scan;
* manual setup;
* past start date;
* future logs;
* late dose;
* missed dose;
* recovery;
* delete/re-add;
* notification;
* AlarmKit;
* Free/Super;
* report download;
* force quit/relaunch;
* persistence.

---

# 10. RELEASE BLOCKER POLICY

During release finish, classify discoveries as:

### RELEASE BLOCKER

Must be fixed before submission/launch.

Examples:

* medication truth corruption;
* incorrect DoseLog creation;
* incorrect DoseLoop action;
* incorrect entitlement;
* authentication failure;
* data loss;
* crash;
* broken notification/AlarmKit critical path;
* privacy/legal requirement failure;
* App Store submission blocker.

### IMPORTANT BUT SAFELY DEFERRABLE

Does not block release.

Examples:

* optional presentation improvements;
* additional personalisation copy;
* non-critical visual refinement;
* optional medication reason presentation;
* additional Phil copy.

### POST-LAUNCH / FUTURE

Do not implement during release finish unless promoted through the roadmap.

Examples:

* Phase 7E;
* richer Journey personalisation;
* expanded Phil personality;
* additional habit/subscription experiments.

---

# 11. FROZEN SYSTEMS DURING RELEASE FINISH

Unless a verified release blocker requires intervention, freeze:

* DoseLog creation semantics;
* DoseLoop;
* Treatment identity;
* Journey classification;
* Journey Tree;
* Treatment History;
* Home medication-path architecture;
* Plan Resume commit boundary;
* prescription scheduling;
* gamification persistence;
* PhilCoach;
* GamificationMemory;
* rewards;
* Challenge calculations;
* entitlement semantics;
* notification action semantics;
* AlarmKit architecture.

### Rule

**No “small cleanup” is automatically safe.**

Any change touching a frozen system requires a dependency/forest audit first.

---

# 12. LAUNCH

## STATUS: PENDING

Launch is blocked only by the remaining release gates.

Required order:

**1. Final physical verification**

↓

**2. Phase 8 release/legal/App Store readiness**

↓

**3. Final Release build**

↓

**4. App Store submission/review requirements**

↓

**5. Launch**

No new product phase should be inserted between these gates unless a real release blocker is discovered.

---

# 13. POST-LAUNCH / FUTURE ROADMAP

These remain future work and are intentionally not part of release finish.

Potential future work includes:

* Phase 7E additional personalisation;
* richer habit formation;
* deeper subscription personalisation;
* additional Phil presentation improvements;
* optional medication-reason presentation;
* richer Journey personalisation;
* additional retention experiments;
* future UX refinements.

These must not be allowed to destabilise the canonical medication architecture.

---

# 14. CURRENT MASTER STATUS TABLE

| Area                                          | Status                 | Release relevance |
| --------------------------------------------- | ---------------------- | ----------------- |
| Stable Core                                   | **CLOSED**             | Complete          |
| FIX 2B Journey + Treatment History            | **CLOSED**             | Frozen            |
| Manual Prescription / Plan Flow               | **CLOSED**             | Frozen            |
| Phase 5 Implementation                        | **CLOSED**             | Complete          |
| Phase 5 A1–A4 Physical Verification           | **OPEN**               | Required          |
| Phase 5 B1–B4 Physical Verification           | **OPEN**               | Required          |
| Phase 5 AlarmKit Final-Binary Verification    | **OPEN**               | Required          |
| Phase 6 Full Gamification / Retention         | **CLOSED**             | Frozen            |
| Phase 7A                                      | **CLOSED**             | Frozen            |
| Phase 7B                                      | **CLOSED / NO CODE**   | Deferrable        |
| Phase 7C                                      | **CLOSED / NO CODE**   | Deferrable        |
| Phase 7D                                      | **CLOSED FOR RELEASE** | Frozen            |
| Phase 7E                                      | **PARKED**             | Post-launch       |
| Phase 8 Release Hardening / Legal / App Store | **OPEN**               | Required          |
| Phase 8E generic iOS Release compile (20 Oct) | **PASSED (source)**    | Not TestFlight / not physical |
| Final Release Build                           | **PENDING**            | Required          |
| App Store Submission                          | **PENDING**            | Required          |
| Launch                                        | **PENDING**            | Final gate        |
| iOS four-tab presentation (`2de9a94`)         | **COMPLETED**          | Simulator + DEBUG contracts; not physical-device VERIFIED |
| Website Phase 3+4 showcase (`b42ade9`)        | **COMPLETED**          | Live on connycooper.com |
| Website footer Support tap (automation)       | **FOLLOW-UP**          | Non-blocking |
| Personalisation & Onboarding funnel (§20)     | **PLANNED**            | Architecture audit only — no implementation |
| Compact-device UI (iPhone 17e logged-in)      | **VERIFICATION REQUIRED** | Launch-relevant |
| Live missed-dose acknowledgement              | **VERIFICATION REQUIRED** | Launch-relevant; contracts ≠ live |
| Avatar / photo persistence                    | **POST-LAUNCH**        | Profile already discloses default avatar |
| Genuine Dark / System appearance              | **POST-LAUNCH**        | Light is locked (`RootView` + SessionStore) |
| Outstanding Dr. Cooper artwork                | **POST-LAUNCH / PARTIAL** | Onboarding still uses phil_* assets; website uses Cooper art |

---

# 15. THE CURRENT NEXT ACTION

## DO NOT IMPLEMENT ONBOARDING. DO NOT START UNRELATED FEATURES.

Authorized now:

1. Keep Home / Progress / Treatments / Refill / Profile frozen as shipped on `2de9a94`.
2. Wait for explicit approval of the §20 onboarding implementation phases.
3. Continue launch verification (Phase 5 physical, remaining Phase 8A–8D/8F) in parallel where it does not modify frozen product behavior.
4. Do **not** switch accounts on the iPhone 11 Build 5 install. Do **not** implement the account-isolation register until explicitly approved.

The previous next action remains valid for **shipping**:

> **Complete/update the final physical verification of Phase 5 A1–A4, B1–B4, and the AlarmKit/notification crash path on the final/main release binary, then Phase 8.**

Onboarding implementation is **not** inserted as a silent replacement for those gates. If onboarding is approved, it must be a separate changeset that does not reopen DoseLoop, Home body, RewardEngine, or AlarmKit.

---

# 16. RELEASE-FINISH PRINCIPLE

At this point CheckMed is not in a feature-building phase.

The objective is:

> **Protect what is already working, verify the final binary, satisfy release requirements, and ship without introducing unnecessary change.**

**Stable Core → Phase 5 Final Verification → Phase 6 Frozen → Phase 7 Frozen/Parked → Phase 8 Release Readiness → Launch**

That remains the **shipping** execution order. Onboarding (§20) is a gated product phase beside it, not a substitute for it.

---

# 17. iOS PRESENTATION MILESTONE — FOUR-TAB EXPERIENCE

## STATUS: COMPLETED (Simulator + DEBUG contracts)

## COMMIT: `2de9a94a19dbc4a4fa64b22d49e45e47c1779acc`

## BRANCH: `cursor/dashboard-onboarding-and-super-trial` (not pushed as of this reconciliation)

Classification of the recorded presentation work:

| Item | Classification | Evidence |
| ---- | -------------- | -------- |
| Four-tab navigation (Home, Treatments, Refill, Profile) | **COMPLETED** | `MainTabs.swift`; Progress is not a root tab |
| Home and Progress preservation | **COMPLETED** | `HomeView.swift` / Progress DESIGN LOCKED at parent `4e7da3d`; `2de9a94` did not restyle Home |
| Treatments experience | **COMPLETED** | `TreatmentsExperience.swift` |
| Treatment renaming (existing `TreatmentRecord.title`, no extra schema) | **COMPLETED** | `CheckMedStore.setTreatmentTitle`; saveDraft does not overwrite non-empty title |
| Completed-treatment performance | **COMPLETED** | `journeyReport(treatmentId:)` + `@State` cache after first appear; UUID a11y identifiers |
| Refill experience | **COMPLETED** | `RefillExperience.swift`; Color.clear Super CTA clearance |
| Profile experience | **COMPLETED** | `ProfileExperience.swift`; full-width cards |
| Profile FAB removal (Alternative A) | **COMPLETED** | FAB overlay only on Treatments and Refill |
| Shared safe-area corrections | **COMPLETED** | `Theme.checkMedStatusBarSafeContent`; window inset |
| Missed-dose acknowledgement presentation | **COMPLETED** (presentation) / **VERIFICATION REQUIRED** (live device) | UserDefaults ack + list filter; DoseLoop unchanged; live Não tomei on device not VERIFIED |
| Localization skipped-count (`%d puladas` / singular) | **COMPLETED** | `L10n.journeySkipped` / `journeySkippedOne`; DEBUG CompletedSkippedLabel contracts |
| Passing Debug contracts | **COMPLETED** | DEBUG launch contracts; **not** physical-device verification |

**Explicitly not claimed VERIFIED:** physical iPhone, AlarmKit, live missed-dose action, compact iPhone 17e logged-in, StoreKit production, family scoping on device.

**Frozen during this milestone (unchanged):** DoseLoop, Home medication path, AchievementBadgeViews / RewardEngine / XP, AlarmKit isolation, 48-notification cap.

---

# 18. WEBSITE — PHASE 3 + 4 SHOWCASE

## STATUS: COMPLETED

Do not modify the website repository from the iOS worktree.

| Item | Classification |
| ---- | -------------- |
| Phase 3 + 4 authentic app showcase | **COMPLETED** |
| Commit | `b42ade9fbb03b19b8fede538b0f75bea6eb614bc` — `Add authentic app showcase and Cooper website artwork` |
| GitHub Pages | **COMPLETED** — `pages-build-deployment` run 37830757217 success |
| Production | https://connycooper.com/ |
| Support, Privacy, Terms, Legal Notice | **COMPLETED** — HTTP 200; files not in `b42ade9` |
| Coming soon | Informational artwork, not an App Store download link |
| Footer Support navigation (automation click) | **FOLLOW-UP** — non-blocking; direct `/support/` works |
| Domain / CNAME | Unchanged (`connycooper.com`) |

---

# 19. REMAINING RELEASE VERIFICATION

Distinguish launch blockers from post-launch.

### Launch-relevant — VERIFICATION REQUIRED or OPEN

* Phase 5 A1–A4 / B1–B4 physical verification on the **final/main release binary**
* AlarmKit / notification two-tap crash path on that binary
* Live missed-dose acknowledgement interaction (Não tomei) on device
* Authentication (Apple / Google / email) production configuration
* Family scoping on device
* StoreKit subscriptions, trial eligibility, restore purchases (production products)
* Legal / App Store readiness (Phase 8)
* Compact-device UI (logged-in compact iPhone not exercised in the `2de9a94` gate)
* Release build: no DEBUG-only harness, TestClock, or guest path — **8E generic iOS Release compile 20 Oct 2026 PASSED** (source + `strings`; not TestFlight)
* **Seed-from-drafts durable persistence (20 Oct 2026)** — runner implemented and Debug-compiled; **runtime not executed**. Do not mark PASS.

### Seed-from-drafts durable contract (DEBUG runner)

**Implementation (present, uncommitted):** `CHECKMED_SEED_DURABLE_CONTRACT=1` → `SeedDurableContractLaunch` → `SeedFromDraftsDurableContractChecks.failures()` only. Disposable temp SQLite; first store released before same-process file-URL reopen; unique ModelConfiguration name. Production `persistDrafts` / schema unchanged. A PASS would mean same-process reopen only, not process-restart durability or full onboarding.

**Execution (20 Oct 2026) — BLOCKED, not FAIL:**

* CareContext-Route-Test `95EB7ECE-5C71-43D7-83BB-1BD13A7BC9F2` left Booted; `default.store` sha16 `abadd64c725998a1` / WAL sha16 `02632b22838baec3` unchanged (filesystem).
* Idle iPhone 17 Pro `561F1190-EF7D-4477-A8A5-20793F6CF561` shut down (authorized).
* Disposable `ConnyCooper-NewUser-E2E` `A3E3A439-85E2-467A-BA9E-97B936921E97` booted (exit 0, 4.7s).
* **Blocker:** `simctl install` of `.derivedData-seed-durable` Debug bundle timed out at 40s; follow-up `get_app_container` also timed out at 20s. Launch never run. `checkmed-seed-durable-contract.txt` never produced.
* No CoreSimulatorService restart; no install/launch retry; no further `simctl` in the close-out batch.

**Do not claim** durable persistence or full isolated onboarding E2E as verified.

### Account isolation — RISK REGISTER (20 Oct 2026)

Source-confirmed. **Do not switch accounts on the physical iPhone 11 Build 5 install.** Not implemented this batch.

| Sev | Risk | Mechanism | Customer impact |
| --- | --- | --- | --- |
| **P0** | Shared SwiftData file | One `default.store` for all `ownerId`s. Home filters bound owner; other owners remain on disk. | Account switch does not isolate/delete the original plan. Disposable seed writes into the same file. |
| **P0** | Keychain identity collision | `ProfileSetupKeychain` is **one slot**. `markComplete` / `markOnboardingComplete` overwrite user id. `associateUserIfNeeded` can bind unscoped flags to the next sign-in. | Original profile/onboarding Keychain can be claimed by another account. |
| **P0** | Reminder replacement | Sign-out does **not** `cancelAllManagedReminders`. `reschedule` no-ops when onboarding is cleared, so original AlarmKit/UN can keep firing. Completing a second account’s plan `rebuild()` **wipes all** `checkmed.*` pending and resyncs AlarmKit to the bound store. | Original user’s reminders cancelled or replaced. |
| **P1** | Install-wide UserDefaults funnel | `resetFirstTimePathAfterLogout` clears language/privacy/how-it-works and **global** onboarding/plan flags. Per-user keys remain. | Next user on this install replays legal/sign-in; routing can still mis-fire from leftover per-user/Keychain flags. |
| **P1** | Local-owner adoption | `adoptOwner(localPlanOwnerId → auth.userId)` on bind. Rows already on the original auth UUID should stay; leftover `checkmed.localOwnerId` rows are rewritten onto the new account. | Possible claim of pre-auth leftovers; not a proven wipe of the original Google owner. |
| **P1** | Replica merge | `applyRemoteReplica` / `mergeTreatments` insert/update by UUID; empty replica does not delete other owners. Same-UUID collision would overwrite. | Disposable cloud rows added beside original local rows. |
| **P1** | Returning-user misclassification | `hasMedicalData`, replica treatments, `isOnboardingComplete(for: nil)`, `load().isComplete` during restore. | Disposable account on this device may skip genuine first-time onboarding. |

**Dependencies:** `SessionStore.signOut` → UserDefaults + Auth; `ChekMedApp.bindStores` → `adoptOwner` + `bindIdentity`; `ReminderScheduler.rebuild`; `ProfileSetupKeychain`; `SyncEngine.restoreUserData` → owner-scoped pull, shared SQLite apply; RootView `hasCompletedOnboarding`.

**Proposed remediation sequence (not started):**

1. **Reminders:** on sign-out, cancel managed UN/AlarmKit **without** DoseLoop taken. On sign-in, reschedule only the bound owner. Freeze DoseLoop / 48-cap / body-tap.
2. **Keychain:** namespace profile/onboarding/plan flags by `userId`; never `associateUserIfNeeded` across users. Freeze SwiftData schema.
3. **Funnel flags:** do not clear another user’s per-user keys; keep language/privacy install-scoped by design.
4. **Adoption:** `adoptOwner` only from leftover local owner, never from a previous auth owner. Contract: two auth owners in one store remain distinct.
5. **Store isolation (later):** per-owner store or explicit purge-other-owners only after remote delete. Highest regression risk — last.
6. **Routing:** first-time vs returning must use **this** auth user id only; ignore unscoped Keychain and other owners’ local treatments.

**Regression boundaries:** Home Dashboard of the original returning user; Confirm source preview; Plan Resume Continue commit; DoseLoop; AlarmKit MainActor; notification default tap not taken; SwiftData idempotent writes; no second medication truth.

**Physical E2E:** Build 5 is **insufficient** for current uncommitted onboarding. Account-switch E2E on the iPhone 11 with real meds is **UNSAFE**. Needs a clean install/device **and** a TestFlight that contains the intended onboarding changeset.

### POST-LAUNCH / DEFERRED (not launch blockers unless promoted)

* Genuine Dark / System themes (`RootView.preferredColorScheme(.light)`; Appearance screen is informational)
* Avatar / illustrated photo persistence (Profile already shows default-avatar hint)
* Outstanding Dr. Cooper artwork replacement for remaining `phil_*` onboarding assets
* Optional medication-reason presentation (7B freeze)
* Extra Phil copy (7C freeze)
* Website footer Support-tap follow-up

---

# 20. PERSONALISATION & ONBOARDING — ARCHITECTURE AUDIT

## STATUS: PLANNED — AUDIT COMPLETE — IMPLEMENTATION NOT APPROVED

**Intended product journey (approved for planning):**

**Welcome animation → Care context → Personal profile → Prescription scheduling → Super trial → Dashboard**

Do not create new models or storage until implementation is approved.

### 20.1 Existing first-launch routing (canonical)

Single root switch: `SessionStore.rootDestination` → `RootView`.

Priority already encoded (do not add a second independent Home vs new-user decision):

1. launch restoring
2. pre-auth funnel (UserDefaults: language → How it works → privacy → **sign-in this install**)
3. post-auth resolving / data not settled (empty/loading is **not** new user)
4. resume / unfinished plan (`PostJourneyStep`, `ResumePlanSetupFlow`)
5. returning welcome
6. identity profile if incomplete (`AccountProfileSetupView`)
7. user-initiated add prescription
8. first-time meds host if `!hasCompletedOnboarding`
9. **Home** (`MainTabView`)

Pre-auth flags are UserDefaults and **must** replay after app delete. Identity/onboarding-complete/plan-confirmed can live in Keychain (`ProfileSetupKeychain`) so the same Apple/Google account does not replay name/DOB/pronouns.

### 20.2 Existing first-time host (`FirstTimeOnboardingView`)

Current in-host sequence:

Splash → Language → How it works → Privacy → Sign-in → Profile (name + DOB + pronouns + gender) → Add medication (photo / library / PDF / manual) → Confirm → Plan Resume **Continue** (commit boundary) → Alarms → Notifications → Super trial → Phil ready → Home.

Post-journey chain (`SessionStore.PostJourneyStep`): **alarms → notifications → trial (skipped if already Super) → philReady → done**.

### 20.3 Mapping intended journey onto existing capabilities

| Intended step | Existing capability | Gap |
| ------------- | ------------------- | --- |
| Welcome (skippable Dr. Cooper intro: organize + progress) | `HowItWorksView` + `phil_onboarding_01…05` stills + optional bundled `phil_onboarding_flow.mp4`; skip is “Let’s get started”, not a dedicated Skip on beat 1 | **PARTIALLY COMPLETED** — exists as How it works after language, before legal/sign-in; copy/assets still Phil-named; not the post-auth welcome the product now describes |
| Care context (ongoing / supplements / short-term; no diagnosis) | None | **MISSING** — no model, no UI, no persistence. Must not infer medicines or write DoseLogs |
| Personal profile | `AccountProfileSetupView` + `AddressYouSetupView`; Keychain+UserDefaults; Profile tab later | **PARTIALLY COMPLETED** — name+DOB+pronouns+gender currently all required to continue |
| Prescription scheduling | `OnboardingMedicationFlow` / `PrescriptionIntakeHost`; photo, PDF, manual; Confirm source preview; Plan Resume Continue commit | **COMPLETED** as architecture — **reuse**, do not fork |
| Super trial | `OnboardingSuperTrialView`, `EntitlementStore`, `PaywallView`, StoreKit monthly/yearly `com.checkmed.super.*`; skip if `isSuper`; Home `.task` can re-present if `shouldOfferOnboardingPaywall` | **PARTIALLY COMPLETED** — trial **eligibility** (`isEligibleForFreeTrial`) exists but onboarding CTA currently always uses Start Trial copy; Home delay-offer can double-present |
| Dashboard | Existing approved Home | **COMPLETED** — do not redesign |

Legal/auth steps (language, privacy, Apple/Google/email sign-in) are **not** in the six-step marketing journey and **must remain** as gates. Do not drop them to shorten the storyboard.

Alarms + notification permission currently sit **between** scheduling and trial. The intended six-step list does not mention them. **Do not delete them.** Treat as required system steps adjacent to Super trial.

### 20.4 Celebration & encouragement (reuse, do not duplicate)

Existing, frozen:

* `RewardEngine` / `RewardCatalog` / `GamificationMemory` (idempotent overlay)
* `PhilCoach` (presentation-only; event-driven)
* Badges / XP / streaks / day-complete / recovery
* Home celebrate banner

Onboarding should **introduce** these surfaces (Progress exists; first-dose / first-day badges already catalogued) without awarding XP or inventing DoseLogs during Welcome/care-context/profile.

Future copy may encourage partial progress; that is **presentation**, not a second reward ledger.

### 20.5 Persistence and navigation risks (must stay true in any implementation)

* One launch path: restore auth → restore data → mark ready → **one** navigation decision.
* Empty/loading ≠ new user.
* Multiple writers of `onboardingComplete` / `postJourneyStep` / `rootDestination` can loop or skip Home.
* Body/computed UI must not mutate SwiftData.
* Plan Resume **Continue** remains the medication commit boundary — Welcome/care-context must not persist treatments.
* Notification body tap must never mark taken.
* Care context must not become a second medication truth or a diagnosis.
* Keychain vs UserDefaults: do not move language/privacy/how-it-works into Keychain.
* Home `.task` paywall vs in-flow trial: one offer path, idempotent `markOnboardingPaywallOffered`.
* Never promise a 3-day trial unless `EntitlementStore.isEligibleForFreeTrial` (or equivalent StoreKit intro offer) is true.
* Do not add `@State` that frequently invalidates Home.

### 20.6 Proposed screen sequence (planning only)

Keep existing legal/auth **before** the product story:

1. Splash (existing)
2. Language (existing)
3. Privacy / terms accept (existing)
4. Sign-in (existing; no guest)
5. **Welcome** — short skippable Cooper intro (reuse How it works media or successor assets; do not rebuild routing)
6. **Care context** — optional/explicit choice; store as profile/presentation preference only
7. **Personal profile** — supported fields; avoid extra mandatory questions (pronouns/gender already exist — changing mandatoriness is a product decision, not a schema rewrite)
8. **Prescription** — existing photo / PDF / manual → Confirm → Plan Resume Continue
9. Alarms permission (existing)
10. Notifications permission (existing)
11. **Super trial** — existing StoreKit; skip if Super; Not now allowed; eligibility-checked copy
12. Phil ready (existing, optional shorten)
13. **Home** — approved Dashboard

Returning users: keep `ReturningWelcomeFlow`; do not replay Welcome/care-context when Keychain says identity+onboarding complete.

### 20.7 Recommended implementation phases (after approval)

**O0 — Freeze & contracts.** Document current `rootDestination` matrix. Add DEBUG contracts for “loading ≠ firstTime” and “trial copy requires eligibility”. No UI redesign.

**O1 — Welcome only.** Presentation on existing How it works slot (or immediately post-sign-in if approved). Skip control. No new persistence keys unless required for “seen”.

**O2 — Profile field policy.** Only if approved: reduce mandatory questions using existing SessionStore fields. No new models.

**O3 — Care context.** Small presentation preference (UserDefaults/profile field). No DoseLog, no treatment inference, no extra SwiftData `@Model` unless proven necessary.

**O4 — Trial offer hygiene.** Single present path; eligibility-gated CTA; do not double-fire Home `.task` after in-flow trial.

**O5 — Copied celebration intro.** Optional Progress/badge preview copy in Welcome only. No RewardEngine changes.

Each phase: one changeset, regression on Home tabs, relaunch, login/logout, unfinished plan.

### 20.8 Verification strategy (when implemented)

Not this planning pass.

* Source inspection of `SessionStore.computeRootDestination`
* DEBUG contracts already used for treatment title / missed presentation / skipped L10n
* Simulator first-install, reinstall+same Apple ID, returning user, unfinished plan, Super already entitled
* Physical: notification permission, AlarmKit, StoreKit sandbox trial eligibility
* Regression: Home interactive, Progress locked, Treatments/Refill/Profile, Confirm source preview, no Home rebuild loop

Never call untested physical notification/dose flow VERIFIED.

---

# 21. ROADMAP FILE CHANGE LOG (8 OCTOBER 2026)

Made in this untracked file only. **Do not commit or push the roadmap until asked.**

* Added Conny Cooper as official product name; kept CheckMed/ChekMed for code paths.
* Recorded iOS `2de9a94` four-tab presentation as COMPLETED (not physical VERIFIED).
* Recorded website `b42ade9` Phase 3+4 as COMPLETED; footer Support follow-up.
* Clarified Phase 7 CLOSED applies to original 7A–7D, not the new onboarding funnel.
* Added §17–§20. Did not delete historical CLOSED/FROZEN sections.
* Next action: wait for onboarding implementation approval; continue launch verification.
* 20 Oct 2026: recorded SeedDurableContractLaunch implementation vs runtime BLOCKED (`simctl install` timeout on disposable after 17 Pro shutdown). CareContext store/WAL hashes unchanged. Simulator loop closed; no further simctl. Parallel non-simulator next: Phase 8E source/generic Release compile gate (DEBUG flags, TestClock, guest path) — not a substitute for Phase 5 physical verification.
* 20 Oct 2026: Phase 8E generic iOS Release **BUILD SUCCEEDED**. DEBUG launch flags / TestClock / test hosts absent from Release `strings`. Isolation env fail-closes (no localhost). Recorded account-isolation risk register (shared SwiftData, Keychain slot, reminder wipe, adoption/replica, returning misclassification). Isolation remediation **not implemented**. No production source edits this batch.
