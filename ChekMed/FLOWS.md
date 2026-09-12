# CheckMed — Locked Flows

**Date:** September 2026  
**Status:** Locked for reference. Do not regress without an explicit product decision.

---

## 1. Fresh install (no Keychain / no auth)

- [ ] Splash
- [ ] Language
- [ ] How it works
- [ ] Privacy
- [ ] **Sign-in** (Apple / Google / email / guest)
- [ ] Profile (name → birth → pronouns; **forward only**)
- [ ] Medication when appropriate

---

## 2. Delete app + reinstall **or** fresh install (always)

App delete wipes UserDefaults. Supabase/session Keychain can survive uninstall (`kSecAttrAccessibleAfterFirstUnlock` is not enough to drop it). **Session is still treated as gone:** do not restore Keychain auth; clear session tokens; user is **signed out** until they Sign-in or continue as guest.

- [ ] Splash
- [ ] Language
- [ ] How it works
- [ ] Privacy
- [ ] **Sign-in** (must actually sign in / guest — not a silent session restore)

**THEN branch** (after they authenticate):

- If **returning / already registered** (same Apple/Google account; ProfileSetupKeychain / profile says old user):
  - **Miss-you** (“been a while”)
    - **My progress** → Home
    - **Add other prescription** → scan (**user choice only**)
  - Do **not** auto Home
  - Do **not** skip Sign-in
- If **new**:
  - Preferred name → birth → pronouns (forward-only profile setup)

**Never:**
- Auto “Adicionar receita”
- Name / birth profile loop for returning users
- Auto-restore Keychain session after delete (`checkmed.hasLaunchedThisInstall` / `checkmed.installSessionToken` missing → discard session, skip restore)
- Treat leftover Keychain tokens as signed-in (`checkmed.signInScreenSeenThisInstall` is false until they finish this screen)

---

## 3. Scan / add prescription (after user taps Scan)

Linear post-journey queue — **do not skip**.

- [ ] Scan (photo / PDF / manual)
- [ ] Confirm recipe
- [ ] View journey
- [ ] Notifications
- [ ] Alarms
- [ ] Super 3-day trial
- [ ] Phil creating plan
- [ ] Home (Home blended with Progress)

---

## 4. Tabs

**Tab bar:** Home · Treatments · Refill · Profile

**Floating +** (bottom-right, above tab bar):

- Pharmacies
- Reports
- Scan
- Progress

---

## 5. Freemium curiosity

| Surface    | Free                         | Paywall trigger        |
|------------|------------------------------|------------------------|
| Pharmacies | Browse                       | Search → Super trial   |
| Reports    | See 4 themes                 | Download → Super trial |

---

## 6. Home rules

- [ ] No medicines until plan confirmed / user set plan
- [ ] One row per medicine (not all dose slots)
- [ ] Mood once per day
- [ ] After treatment finished → empty scan CTA
- [ ] Finish treatment → confirm + missing-meds warning; choices: **Scan new** | **See journey report**

---

## 7. Router note

`SessionStore.rootDestination` is the **single source of truth**.

After language / how-it-works / privacy: if `checkmed.signInScreenSeenThisInstall` is false → stay on first-time **Sign-in** even if `isSessionUnlocked`.

Do **not** reintroduce scattered `RootView` if/else that ranks `!onboardingComplete` or restored auth above Sign-in or Returning Welcome.
