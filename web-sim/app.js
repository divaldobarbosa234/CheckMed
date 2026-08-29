(() => {
  const root = document.getElementById("app");
  const MOCK_DRAFT = {
    medicine: "Amoxicilina",
    dose: "500mg · 1 capsule",
    frequency: "3× daily",
    duration: "7 days",
  };

  const initialDoses = () => [
    { id: 1, time: "08:00", medicine: "Amoxicilina 500mg", detail: "1 capsule", status: "done" },
    { id: 2, time: "14:00", medicine: "Ibuprofeno 400mg", detail: "As needed", status: "current" },
    { id: 3, time: "20:00", medicine: "Amoxicilina 500mg", detail: "1 capsule", status: "locked" },
  ];

  const state = {
    locale: "en",
    screen: "splash",
    tab: "home",
    overlay: null,
    authMode: "signup",
    email: "",
    password: "",
    confirm: "",
    name: "",
    dob: "",
    pronouns: "",
    gender: "",
    howBeat: 0,
    addMethod: "photo",
    draft: { medicine: "", dose: "", frequency: "", duration: "" },
    medicines: [],
    doses: [],
    returning: false,
    paywallOpen: false,
    paywallOffered: false,
    toast: null,
    suggestOpen: false,
  };

  let timers = [];
  function later(ms, fn) {
    const id = setTimeout(fn, ms);
    timers.push(id);
    return id;
  }
  function clearTimers() {
    timers.forEach(clearTimeout);
    timers = [];
  }

  function t(key) {
    const pack = I18N[state.locale] || I18N.en;
    return pack[key] ?? I18N.en[key] ?? key;
  }
  function fmt(key, ...args) {
    let s = t(key);
    args.forEach((a) => {
      s = s.replace("%@", String(a));
    });
    return s;
  }

  function phil(size, smile, extraClass) {
    return `<div class="phil ${extraClass || ""}" style="--s:${size}px" aria-label="Phil">
      <div class="tuft"></div>
      <div class="body">
        <div class="belly"></div>
        <div class="eyes"><div class="eye"></div><div class="eye"></div></div>
        <div class="beak"></div>
        <div class="cheeks"><div class="cheek"></div><div class="cheek"></div></div>
        ${smile ? '<div class="smile"></div>' : ""}
      </div>
    </div>`;
  }

  function btn(title, kind, action, disabled) {
    return `<button type="button" class="btn ${kind}" data-act="${action}" ${disabled ? "disabled" : ""}>${esc(title)}</button>`;
  }
  function esc(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function greeting() {
    const h = new Date().getHours();
    if (h >= 5 && h < 12) return t("homeMorning");
    if (h < 18) return t("homeAfternoon");
    return t("homeEvening");
  }

  function matches(q) {
    const qn = q.trim().toLowerCase();
    if (qn.length < 1) return [];
    return CATALOG.filter((n) => n.toLowerCase().includes(qn)).slice(0, 8);
  }

  function isReturningEmail(email) {
    const e = email.trim().toLowerCase();
    return e.includes("existing") || e === "returning@checkmed.app";
  }

  function go(screen) {
    state.screen = screen;
    state.overlay = null;
    render();
  }

  function enterMain(opts) {
    state.returning = !!opts.returning;
    state.screen = "main";
    state.tab = opts.tab || (opts.returning ? "progress" : "home");
    if (opts.seed) {
      state.medicines = [
        { name: "Amoxicilina 500mg", meta: "1 capsule · 3× daily · 7 days" },
        { name: "Ibuprofeno 400mg", meta: "As needed · with meals if pain" },
      ];
      state.doses = initialDoses();
      state.name = state.name || "Alex";
    }
    state.paywallOffered = !!opts.returning;
    render();
    if (!opts.returning && !state.paywallOffered) {
      later(3500, () => {
        if (state.screen === "main" && !state.paywallOffered) {
          state.paywallOffered = true;
          state.paywallOpen = true;
          render();
        }
      });
    }
  }

  function confirmAuth(kind) {
    const email = state.email.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      state.toast = { text: t("philNeedsEmail"), err: true };
      render();
      return;
    }
    if (kind !== "reset") {
      if (!state.password) {
        state.toast = { text: t("enterPassword"), err: true };
        render();
        return;
      }
      if (state.password.length < 6) {
        state.toast = { text: t("passwordShort"), err: true };
        render();
        return;
      }
    }
    if (kind === "signup" && state.password !== state.confirm) {
      state.toast = { text: t("passwordsMatch"), err: true };
      render();
      return;
    }
    if (kind === "login" && isReturningEmail(email)) {
      enterMain({ returning: true, seed: true, tab: "progress" });
      return;
    }
    go("callYou");
  }

  function startAnalyse(method) {
    state.addMethod = method;
    if (method !== "manual") {
      state.draft = { ...MOCK_DRAFT };
    }
    go("analysing");
    later(method === "manual" ? 800 : 1600, () => go("confirm"));
  }

  function saveMedicine() {
    const d = state.draft;
    const name = `${d.medicine}${d.dose ? " " + d.dose.split("·")[0].trim() : ""}`.trim();
    state.medicines = [{ name: d.medicine, meta: `${d.dose} · ${d.frequency} · ${d.duration}` }];
    state.doses = [
      { id: 1, time: "08:00", medicine: name || d.medicine, detail: d.dose, status: "current" },
      { id: 2, time: "14:00", medicine: name || d.medicine, detail: d.dose, status: "locked" },
      { id: 3, time: "20:00", medicine: name || d.medicine, detail: d.dose, status: "locked" },
    ];
  }

  function takeSkip(id, status) {
    const i = state.doses.findIndex((d) => d.id === id);
    if (i < 0) return;
    state.doses[i].status = status;
    const next = state.doses.find((d) => d.status === "locked");
    if (next) next.status = "current";
    render();
  }

  function medicineField() {
    const hits = state.suggestOpen ? matches(state.draft.medicine) : [];
    return `<div class="field">
      <label>${esc(t("medicine"))}</label>
      <input id="med-name" value="${esc(state.draft.medicine)}" autocomplete="off" />
      <p class="muted" style="font-size:11px;margin-top:6px">${esc(t("suggestHint"))}</p>
      ${
        hits.length
          ? `<div class="suggest">${hits
              .map((n) => `<button type="button" data-pick="${esc(n)}">${esc(n)}</button>`)
              .join("")}</div>`
          : ""
      }
    </div>`;
  }

  function chrome() {
    return `<div class="chrome-label">${esc(t("previewChrome"))}</div>`;
  }

  function screenSplash() {
    return `<div class="screen"><div class="splash-glow"></div><div class="center-col">${phil(228, true)}</div></div>`;
  }

  function screenLanguage() {
    return `<div class="screen">
      ${chrome()}
      <div class="scroll" style="display:flex;flex-direction:column;align-items:center;gap:12px">
        ${phil(128, true)}
        <h2>${esc(t("languageHeadline"))}</h2>
        <p class="muted">${esc(t("languageSubhead"))}</p>
        <div class="lang-list">
          ${LOCALES.map(
            (l) =>
              `<button type="button" class="lang-opt ${state.locale === l.id ? "active" : ""}" data-lang="${l.id}">${esc(l.name)}</button>`
          ).join("")}
        </div>
      </div>
      <div class="footer">${btn(t("continue"), "primary", "how")}</div>
    </div>`;
  }

  function screenHow() {
    const feat = t("how")[state.howBeat] || I18N.en.how[0];
    return `<div class="screen">
      ${chrome()}
      <div class="scroll" style="text-align:center" data-act="how-next">
        ${phil(112, true)}
        <h2 style="margin:12px 0">${esc(t("howHeadline"))}</h2>
        <div class="icon-tile">${feat.icon}</div>
        <h2 style="margin-top:12px">${esc(feat.title)}</h2>
        <p class="muted">${esc(feat.short)}</p>
        <p style="font-weight:700;margin-top:8px">${esc(feat.body)}</p>
        <div class="dots" style="margin-top:16px">
          ${t("how").map((_, i) => `<div class="dot ${i === state.howBeat ? "on" : ""}"></div>`).join("")}
        </div>
      </div>
      <div class="footer">${btn(t("letsGetStarted"), "primary", "privacy")}</div>
    </div>`;
  }

  function screenPrivacy() {
    return `<div class="screen">
      ${chrome()}
      <div class="scroll" style="text-align:center">
        ${phil(80, true)}
        <h2>${esc(t("privacyHeadline"))}</h2>
        <p class="muted">${esc(t("privacySubhead"))}</p>
        <p style="font-weight:700;margin:10px 0">${esc(t("privacyBody"))}</p>
        ${infoCard("📋", t("privacyHowTitle"), t("privacyHowBody"))}
        ${infoCard("🎚️", t("privacyControlTitle"), t("privacyControlBody"))}
        ${infoCard("🔎", t("privacyTransparentTitle"), t("privacyTransparentBody"))}
      </div>
      <div class="footer">
        ${btn(t("privacyAccept"), "primary", "signIn")}
        ${btn(t("privacySettings"), "secondary", "privacySettings")}
        <p class="muted" style="font-size:12px;margin-top:8px">${esc(t("privacyFooter"))}</p>
      </div>
    </div>`;
  }

  function infoCard(icon, title, body) {
    return `<div class="card" style="display:flex;gap:12px;margin:8px 0">
      <div class="icon-tile" style="width:44px;height:44px;border-radius:18px;font-size:18px">${icon}</div>
      <div><b>${esc(title)}</b><p class="muted" style="font-size:12px">${esc(body)}</p></div>
    </div>`;
  }

  function screenPrivacySettings() {
    return `<div class="screen">
      ${chrome()}
      <div class="nav-title">${esc(t("privacySettings"))}</div>
      <div class="scroll">
        <div class="phil-row">${phil(72, true)}<p class="muted">${esc(t("privacySettingsIntro"))}</p></div>
        <div class="card" style="margin-top:12px"><span class="kicker">${esc(t("privacyAlwaysOn"))}</span><h2 style="font-size:18px">${esc(t("privacyRequired"))}</h2></div>
        <div class="card" style="margin-top:12px"><span class="kicker">${esc(t("privacyOptional"))}</span><h2 style="font-size:18px">${esc(t("privacyAnalytics"))}</h2></div>
        <div class="card" style="margin-top:12px"><span class="kicker">${esc(t("privacyOptional"))}</span><h2 style="font-size:18px">${esc(t("privacyMarketing"))}</h2></div>
      </div>
      <div class="footer">${btn(t("back"), "ghost", "privacy")}</div>
    </div>`;
  }

  function screenSignIn() {
    const signup = state.authMode === "signup";
    return `<div class="screen">
      ${chrome()}
      <div class="nav-title">${esc(t("logIn"))}</div>
      <div class="scroll">
        <div class="phil-row">${phil(100, true)}
          <div><div class="kicker" style="color:var(--primary-shadow)">CHECKMED</div>
          <div class="bubble">${esc(signup ? t("signInBubbleSignUp") : t("signInBubbleLogin"))}</div></div>
        </div>
        <h2 style="margin-top:16px">${esc(t("signInHeadline"))}</h2>
        <p class="muted">${esc(t("signInBody"))}</p>
        <div class="field"><label>${esc(t("email"))}</label><input id="email" type="email" value="${esc(state.email)}" /></div>
        <div class="field"><label>${esc(t("password"))}</label><input id="password" type="password" value="${esc(state.password)}" /></div>
        ${signup ? `<div class="field"><label>${esc(t("confirmPassword"))}</label><input id="confirm" type="password" value="${esc(state.confirm)}" /></div>` : ""}
        ${btn(signup ? t("createAccount") : t("logIn"), "primary", signup ? "submit-signup" : "submit-login")}
        <div style="display:flex;justify-content:space-between;margin:10px 0">
          <button type="button" class="btn ghost" style="width:auto;padding:0;text-transform:none;font-size:12px" data-act="toggle-auth">${esc(signup ? t("alreadyHave") : t("needAccount"))}</button>
        </div>
        ${btn(t("returningUser"), "ghost", "returning")}
        <p class="muted" style="text-align:center;margin:10px 0">${esc(t("orEmail"))}</p>
        ${btn(t("google"), "secondary", "oauth-google")}
        ${btn(t("facebook"), "secondary", "oauth-facebook")}
        ${btn(t("apple"), "secondary", "oauth-apple")}
        <p class="safety" style="margin-top:12px">${esc(t("safety"))}</p>
      </div>
    </div>`;
  }

  function screenCallYou() {
    const ok = state.name.trim() && state.dob;
    return `<div class="screen">
      ${chrome()}
      <div class="scroll" style="text-align:center">
        <h2>${esc(t("callYouTitle"))}</h2>
        ${phil(108, true)}
        <p style="font-weight:800">${esc(t("callYouIntro"))}</p>
        <div class="field"><label>${esc(t("preferredName"))}</label><input id="name" value="${esc(state.name)}" placeholder="Alex" /></div>
        <div class="field"><label>${esc(t("dob"))}</label><input id="dob" type="date" value="${esc(state.dob)}" /></div>
        <p class="muted" style="font-size:12px">${esc(t("dobHint"))}</p>
      </div>
      <div class="footer">${btn(t("continue"), "primary", "addressYou")}</div>
    </div>`;
  }

  function screenAddress() {
    return `<div class="screen">
      ${chrome()}
      <div class="scroll" style="text-align:center">
        <h2>${esc(t("addressYouTitle"))}</h2>
        ${phil(120, true)}
        <p style="font-weight:800">${esc(t("addressYouIntro"))}</p>
        <div class="field"><label>${esc(t("pronouns"))}</label>
          <select id="pronouns">
            <option value="">${esc(t("choose"))}</option>
            <option ${state.pronouns === "she" ? "selected" : ""} value="she">${esc(t("pronounShe"))}</option>
            <option ${state.pronouns === "he" ? "selected" : ""} value="he">${esc(t("pronounHe"))}</option>
            <option ${state.pronouns === "they" ? "selected" : ""} value="they">${esc(t("pronounThey"))}</option>
            <option ${state.pronouns === "na" ? "selected" : ""} value="na">${esc(t("pronounPreferNot"))}</option>
          </select>
        </div>
        <div class="field"><label>${esc(t("gender"))}</label>
          <select id="gender">
            <option value="">${esc(t("choose"))}</option>
            <option ${state.gender === "woman" ? "selected" : ""} value="woman">${esc(t("genderWoman"))}</option>
            <option ${state.gender === "man" ? "selected" : ""} value="man">${esc(t("genderMan"))}</option>
            <option ${state.gender === "nb" ? "selected" : ""} value="nb">${esc(t("genderNonBinary"))}</option>
            <option ${state.gender === "na" ? "selected" : ""} value="na">${esc(t("genderPreferNot"))}</option>
          </select>
        </div>
      </div>
      <div class="footer">
        ${btn(t("continue"), "primary", "addMed")}
        ${btn(t("back"), "ghost", "callYou")}
      </div>
    </div>`;
  }

  function screenAddMed() {
    return `<div class="screen">
      ${chrome()}
      <div class="scroll" style="text-align:center">
        <h2>${esc(t("scanAddTitle"))}</h2>
        ${phil(120, true)}
        <p class="muted">${esc(t("scanOrganizeHint"))}</p>
      </div>
      <div class="footer">
        ${btn(t("scanTakePhoto"), "primary", "camera")}
        ${btn(t("scanChoosePhotos"), "secondary", "mock-photo")}
        ${btn(t("scanUploadPDF"), "secondary", "mock-pdf")}
        ${btn(t("scanSetManually"), "secondary", "manual")}
        ${btn(t("back"), "ghost", "addressYou")}
        <p class="safety">${esc(t("safety"))}</p>
      </div>
    </div>`;
  }

  function screenCamera() {
    return `<div class="screen">
      ${chrome()}
      <div class="scroll" style="text-align:center">
        <h2>${esc(t("scanCameraTitle"))}</h2>
        ${phil(72, true)}
        <p class="muted">${esc(t("scanCameraBubble"))}</p>
        <h2>${esc(t("scanKeepFrame"))}</h2>
        <div class="camera-frame">${esc(t("scanCameraUnavailable"))}</div>
      </div>
      <div class="footer">
        ${btn(t("mockPickPhoto"), "primary", "mock-photo")}
        ${btn(t("mockPickLibrary"), "secondary", "mock-photo")}
        ${btn(t("back"), "ghost", "addMed")}
      </div>
    </div>`;
  }

  function screenManual() {
    return `<div class="screen">
      ${chrome()}
      <div class="scroll" style="text-align:center">
        <h2>${esc(t("scanSetManually"))}</h2>
        ${phil(88, true)}
        <p class="muted">${esc(t("scanOrganizeHint"))}</p>
        ${medicineField()}
        <div class="field"><label>${esc(t("dose"))}</label><input id="dose" value="${esc(state.draft.dose)}" /></div>
        <div class="field"><label>${esc(t("frequency"))}</label><input id="freq" value="${esc(state.draft.frequency)}" /></div>
        <div class="field"><label>${esc(t("duration"))}</label><input id="dur" value="${esc(state.draft.duration)}" /></div>
      </div>
      <div class="footer">
        ${btn(t("continue"), "primary", "analyse-manual", !state.draft.medicine || !state.draft.dose || !state.draft.frequency)}
        ${btn(t("back"), "ghost", "addMed")}
      </div>
    </div>`;
  }

  function screenAnalysing() {
    return `<div class="screen"><div class="center-col">
      ${phil(168, true, "pulse")}
      <h2>${esc(t("analysingTitle"))}</h2>
      <p class="muted">${esc(state.addMethod === "manual" ? t("analysingShort") : t("analysingBody"))}</p>
    </div></div>`;
  }

  function screenConfirm() {
    return `<div class="screen">
      ${chrome()}
      <div class="scroll" style="text-align:center">
        <h2>${esc(state.addMethod === "manual" ? t("confirmManual") : t("confirmEdit"))}</h2>
        ${phil(88, true)}
        ${medicineField()}
        <div class="field"><label>${esc(t("dose"))}</label><input id="dose" value="${esc(state.draft.dose)}" /></div>
        <div class="field"><label>${esc(t("frequency"))}</label><input id="freq" value="${esc(state.draft.frequency)}" /></div>
        <div class="field"><label>${esc(t("duration"))}</label><input id="dur" value="${esc(state.draft.duration)}" /></div>
      </div>
      <div class="footer">
        ${btn(t("looksGood"), "primary", "organize", !state.draft.medicine || !state.draft.dose || !state.draft.frequency)}
        ${btn(t("back"), "ghost", state.addMethod === "manual" ? "manual" : "addMed")}
        <p class="safety">${esc(t("safety"))}</p>
      </div>
    </div>`;
  }

  function screenOrganize() {
    return `<div class="screen">
      <div class="center-col">${phil(156, true)}<h2>${esc(t("organizeHeadline"))}</h2><div class="bubble">${esc(t("organizeBody"))}</div></div>
      <div class="footer">${btn(t("continue"), "primary", "notifs")}${btn(t("back"), "ghost", "confirm")}</div>
    </div>`;
  }

  function screenNotifs() {
    return `<div class="screen">
      ${chrome()}
      <div class="scroll" style="text-align:center">
        <h2>${esc(t("notifsTitle"))}</h2>
        ${phil(148, true)}
        <h2>${esc(t("notifsHeadline"))}</h2>
        <div style="text-align:left;font-weight:800;margin-top:16px">
          <p>${esc(t("notifsMeds"))}</p>
          <p>${esc(t("notifsTreatment"))}</p>
          <p>${esc(t("notifsImportant"))}</p>
        </div>
      </div>
      <div class="footer">
        ${btn(t("notifsEnable"), "primary", "ready")}
        ${btn(t("skip"), "secondary", "ready")}
        ${btn(t("back"), "ghost", "organize")}
      </div>
    </div>`;
  }

  function screenReady() {
    return `<div class="screen">
      <div class="center-col">${phil(176, true)}<h1>${esc(t("philReadyHeadline"))}</h1><p class="muted">${esc(t("philReadyBody"))}</p></div>
      <div class="footer">${btn(t("philReadyButton"), "primary", "home")}</div>
    </div>`;
  }

  function pathNodes() {
    if (!state.doses.length) return `<p class="muted">${esc(t("nothing"))}</p>`;
    return state.doses
      .map((n, i) => {
        const glyph = n.status === "done" ? "✓" : n.status === "skipped" ? "—" : n.status === "current" ? "✓" : "🔒";
        const actions =
          n.status === "current"
            ? `<div style="margin-top:8px;display:flex;gap:8px">
                <button type="button" class="pill" data-take="${n.id}">${esc(t("taken"))}</button>
                <button type="button" class="pill outline" data-skip="${n.id}">${esc(t("skip"))}</button>
              </div>`
            : `<p class="muted" style="font-size:12px">${esc(n.status === "done" ? t("logged") : n.status === "skipped" ? t("skipped") : "")}</p>`;
        return `<div class="node">
          <div><div class="ring ${n.status}">${glyph}</div>${i < state.doses.length - 1 ? '<div class="connector"></div>' : ""}</div>
          <div class="card" style="flex:1"><p class="muted" style="font-size:12px">${esc(n.time)}</p><h2 style="font-size:18px">${esc(n.medicine)}</h2>${actions}</div>
        </div>`;
      })
      .join("");
  }

  function tabHome() {
    const streak = state.doses.some((d) => d.status === "done") ? 1 : 0;
    return `<div class="scroll">
      <div style="display:flex;justify-content:space-between;align-items:flex-start">
        <div>
          <div class="kicker">${esc(t("homeDashboard"))}</div>
          <p class="muted">${esc(greeting())}</p>
          <h2>${esc(t("homeReady"))}</h2>
        </div>
        <button type="button" class="freeze" data-act="paywall">🔒 ${esc(t("homeFreeze"))}</button>
      </div>
      <div class="phil-row" style="margin:14px 0">
        ${phil(108, true)}
        <div class="card" style="border-color:#f3d7a0"><div style="font-size:28px">🔥 <b>${streak}</b></div><p class="muted">${esc(t("homeStreak"))}</p></div>
      </div>
      <div class="bubble">${esc(t("homePhil"))}</div>
      <p class="kicker" style="margin:14px 0 8px">${esc(t("homeToday"))}</p>
      ${pathNodes()}
      ${btn(t("homeScan"), "primary", "scan-home")}
      <div class="row-btns" style="margin-top:10px">
        ${btn(t("homeNextDose"), "ghost", "overlay-nextdose")}
        ${btn(t("homeAlarm"), "ghost", "overlay-alarm")}
      </div>
      <div class="row-btns" style="margin-top:10px">
        ${btn(t("homeTodaysTreatment"), "ghost", "overlay-today")}
        ${btn(t("homeUpcoming"), "ghost", "overlay-upcoming")}
      </div>
      ${btn(t("homeSummary"), "ghost", "overlay-summary")}
      <p class="safety" style="margin-top:12px">${esc(t("safety"))}</p>
    </div>`;
  }

  function tabTreatments() {
    const empty = !state.medicines.length;
    return `<div class="scroll">
      <div class="kicker">${esc(t("tabTreatments"))}</div>
      <div class="phil-row">${phil(96, true)}<div class="bubble">${esc(empty ? t("treatmentsEmpty") : t("treatmentsBubble"))}</div></div>
      ${
        empty
          ? `<p class="muted">${esc(t("nothing"))}</p>${btn(t("homeScan"), "primary", "scan-home")}`
          : state.medicines
              .map((m) => `<div class="card" style="margin:10px 0"><h2 style="font-size:18px">${esc(m.name)}</h2><p class="muted">${esc(m.meta)}</p></div>`)
              .join("") + btn(t("homeScan"), "secondary", "scan-home")
      }
    </div>`;
  }

  function tabProgress() {
    const taken = state.doses.filter((d) => d.status === "done").length;
    const planned = state.doses.length;
    const has = taken > 0 || state.returning;
    const pct = planned ? Math.round((taken / planned) * 100) : 0;
    return `<div class="scroll">
      <div class="phil-row">${phil(120, true)}<div class="bubble">${esc(has ? "Phil: Progress is a streak of small wins — not perfection." : t("progressEmptyBubble"))}</div></div>
      <h2>${esc(has ? t("progressOnARoll") : t("progressEmptyBody"))}</h2>
      <p style="color:var(--streak);font-weight:900;font-size:22px">🔥 ${has ? (state.returning ? 6 : taken) : 0}</p>
      ${
        has
          ? `<div class="stat-row">
              <div class="stat"><b>${pct}%</b><span class="muted">${esc(t("progressTaken"))}</span></div>
              <div class="stat"><b>${taken}/${planned || 3}</b><span class="muted">${esc(t("progressDoses"))}</span></div>
              <div class="stat"><b>${state.medicines.length || 2}</b><span class="muted">${esc(t("progressTreatments"))}</span></div>
            </div>`
          : `<p class="muted">${esc(t("nothing"))}</p>`
      }
      ${btn(t("backToDashboard"), "primary", "tab-home")}
      ${btn(t("progressCalendar"), "secondary", "noop")}
      ${btn(t("progressHistory"), "secondary", "noop")}
      <div class="card" style="margin-top:10px;display:flex;justify-content:space-between">
        <b>${esc(t("longerFilters"))}</b><span class="muted">${esc(t("paywallSuper"))}</span>
      </div>
    </div>`;
  }

  function tabProfile() {
    const name = state.name || "Alex";
    return `<div class="scroll">
      <h1>${esc(t("profileTitle"))}</h1>
      <div class="phil-row">${phil(96, true)}<div><h2>${esc(name)}</h2><p>${esc(LOCALES.find((l) => l.id === state.locale).name)}</p></div></div>
      <div class="bubble">${esc(fmt("profileSigned", name))}</div>
      <div class="card" style="margin:12px 0">
        <div class="kicker">${esc(t("profileAccount"))}</div>
        <h2 style="font-size:18px">${esc(state.email || "alex@checkmed.app")}</h2>
        ${btn(t("profileSignOut"), "secondary", "restart")}
      </div>
      <div class="card" style="margin:8px 0;display:flex;justify-content:space-between"><span>${esc(t("profileNotifs"))}</span><b>${esc(t("profileOn"))}</b></div>
      <div class="card" style="margin:8px 0">${esc(t("profileSettings"))}</div>
      <div class="card" style="margin:8px 0;display:flex;justify-content:space-between"><span>${esc(t("profileFamily"))}</span><span class="muted">1 of 1</span></div>
      <button type="button" class="card" style="width:100%;margin:8px 0;display:flex;justify-content:space-between" data-act="paywall">
        <span>${esc(t("profileSuper"))}</span><span class="muted">${esc(t("profileFree"))}</span>
      </button>
    </div>`;
  }

  function tabs() {
    const items = [
      ["home", "⌂", t("tabHome")],
      ["treatments", "💊", t("tabTreatments")],
      ["progress", "📈", t("tabProgress")],
      ["profile", "☺", t("tabProfile")],
    ];
    return `<nav class="tabs">${items
      .map(
        ([id, icon, label]) =>
          `<button type="button" class="tab ${state.tab === id ? "on" : ""}" data-tab="${id}"><span>${icon}</span>${esc(label)}</button>`
      )
      .join("")}</nav>`;
  }

  function overlayPanel() {
    if (!state.overlay) return "";
    const titles = {
      nextdose: t("nextDoseTitle"),
      alarm: t("alarmTitle"),
      today: t("homeTodaysTreatment"),
      upcoming: t("homeUpcoming"),
      summary: t("summaryTitle"),
      scan: t("scanAddTitle"),
    };
    let body = "";
    if (state.overlay === "scan") {
      body = `${phil(100, true)}<p class="muted">${esc(t("scanOrganizeHint"))}</p>
        ${btn(t("scanTakePhoto"), "primary", "camera-main")}
        ${btn(t("scanChoosePhotos"), "secondary", "mock-photo-main")}
        ${btn(t("scanUploadPDF"), "secondary", "mock-pdf-main")}
        ${btn(t("scanSetManually"), "secondary", "manual-main")}
        ${btn(t("back"), "ghost", "close-overlay")}`;
    } else if (state.overlay === "alarm") {
      body = `<div class="bubble">${esc(t("alarmThemeHint"))}</div>${btn(t("back"), "ghost", "close-overlay")}`;
    } else {
      const next = state.doses.find((d) => d.status === "current") || state.doses[0];
      body = `${phil(88, true)}<div class="bubble">${esc(next ? `${next.time} · ${next.medicine}` : t("nothing"))}</div>${btn(t("back"), "ghost", "close-overlay")}`;
    }
    return `<div class="overlay"><div class="nav-title">${esc(titles[state.overlay] || "")}</div><div class="scroll">${body}</div></div>`;
  }

  function paywallSheet() {
    if (!state.paywallOpen) return "";
    return `<div class="modal-scrim">
      <div class="sheet">
        <div class="phil-row">${phil(96, true)}<div class="bubble">${esc(t("paywallOffBubble"))}</div></div>
        <h1>${esc(t("paywallTitle"))}</h1>
        <p class="muted">${esc(t("paywallBody"))}</p>
        <div class="card plan free"><h3>${esc(t("paywallFree"))}</h3>${t("paywallFreeItems").map((i) => `<p>• ${esc(i)}</p>`).join("")}</div>
        <div class="card plan super"><h3>${esc(t("paywallSuper"))}</h3>${t("paywallSuperItems").map((i) => `<p>• ${esc(i)}</p>`).join("")}</div>
        <p class="safety">${esc(t("paywallMissing"))}</p>
        ${btn(t("paywallRestore"), "secondary", "close-paywall")}
        ${btn(t("paywallNotNow"), "ghost", "close-paywall")}
      </div>
    </div>`;
  }

  function appleAlert() {
    if (state.overlay !== "apple") return "";
    return `<div class="modal-scrim" style="align-items:center;padding:24px">
      <div class="card" style="width:100%">
        <h2>${esc(t("appleTitle"))}</h2>
        <p>${esc(t("appleComingSoon"))}</p>
        ${btn(t("ok"), "primary", "close-overlay")}
      </div>
    </div>`;
  }

  function screenMain() {
    const body =
      state.tab === "home"
        ? tabHome()
        : state.tab === "treatments"
          ? tabTreatments()
          : state.tab === "progress"
            ? tabProgress()
            : tabProfile();
    return `<div class="screen">
      ${chrome()}
      ${body}
      ${tabs()}
      ${overlayPanel()}
      ${paywallSheet()}
    </div>`;
  }

  function view() {
    switch (state.screen) {
      case "splash":
        return screenSplash();
      case "language":
        return screenLanguage();
      case "how":
        return screenHow();
      case "privacy":
        return screenPrivacy();
      case "privacySettings":
        return screenPrivacySettings();
      case "signIn":
        return screenSignIn();
      case "callYou":
        return screenCallYou();
      case "addressYou":
        return screenAddress();
      case "addMed":
        return screenAddMed();
      case "camera":
        return screenCamera();
      case "manual":
        return screenManual();
      case "analysing":
        return screenAnalysing();
      case "confirm":
        return screenConfirm();
      case "organize":
        return screenOrganize();
      case "notifs":
        return screenNotifs();
      case "ready":
        return screenReady();
      default:
        return screenMain();
    }
  }

  function render() {
    const toast = state.toast
      ? `<div class="toast ${state.toast.err ? "err" : "ok"}">${esc(state.toast.text)}</div>`
      : "";
    root.innerHTML = toast + view() + appleAlert() + (state.screen !== "main" ? paywallSheet() : "");
    bind();
  }

  function readFields() {
    const email = root.querySelector("#email");
    const password = root.querySelector("#password");
    const confirm = root.querySelector("#confirm");
    const name = root.querySelector("#name");
    const dob = root.querySelector("#dob");
    const pronouns = root.querySelector("#pronouns");
    const gender = root.querySelector("#gender");
    const med = root.querySelector("#med-name");
    const dose = root.querySelector("#dose");
    const freq = root.querySelector("#freq");
    const dur = root.querySelector("#dur");
    if (email) state.email = email.value;
    if (password) state.password = password.value;
    if (confirm) state.confirm = confirm.value;
    if (name) state.name = name.value;
    if (dob) state.dob = dob.value;
    if (pronouns) state.pronouns = pronouns.value;
    if (gender) state.gender = gender.value;
    if (med) state.draft.medicine = med.value;
    if (dose) state.draft.dose = dose.value;
    if (freq) state.draft.frequency = freq.value;
    if (dur) state.draft.duration = dur.value;
  }

  function bind() {
    root.querySelectorAll("[data-lang]").forEach((el) => {
      el.onclick = () => {
        state.locale = el.dataset.lang;
        render();
      };
    });
    root.querySelectorAll("[data-tab]").forEach((el) => {
      el.onclick = () => {
        state.tab = el.dataset.tab;
        state.overlay = null;
        render();
      };
    });
    root.querySelectorAll("[data-take]").forEach((el) => {
      el.onclick = () => takeSkip(Number(el.dataset.take), "done");
    });
    root.querySelectorAll("[data-skip]").forEach((el) => {
      el.onclick = () => takeSkip(Number(el.dataset.skip), "skipped");
    });
    root.querySelectorAll("[data-pick]").forEach((el) => {
      el.onclick = () => {
        state.draft.medicine = el.dataset.pick;
        state.suggestOpen = false;
        render();
      };
    });
    const med = root.querySelector("#med-name");
    if (med) {
      med.oninput = () => {
        state.draft.medicine = med.value;
        state.suggestOpen = true;
        const hits = matches(state.draft.medicine);
        const box = med.parentElement.querySelector(".suggest");
        if (hits.length) {
          if (box) {
            box.innerHTML = hits.map((n) => `<button type="button" data-pick="${esc(n)}">${esc(n)}</button>`).join("");
            box.querySelectorAll("[data-pick]").forEach((b) => {
              b.onclick = () => {
                state.draft.medicine = b.dataset.pick;
                state.suggestOpen = false;
                render();
              };
            });
          } else render();
        } else if (box) box.remove();
      };
    }
    ["#email", "#password", "#confirm", "#name", "#dob", "#dose", "#freq", "#dur", "#pronouns", "#gender"].forEach((sel) => {
      const el = root.querySelector(sel);
      if (!el) return;
      el.onchange = readFields;
      el.oninput = () => {
        readFields();
        if (sel === "#name" || sel === "#dob" || sel === "#pronouns" || sel === "#gender" || sel === "#dose" || sel === "#freq") {
          /* keep typing without full remount except selects */
        }
      };
    });
    root.querySelectorAll("[data-act]").forEach((el) => {
      el.onclick = () => act(el.dataset.act);
    });
  }

  function act(name) {
    readFields();
    state.toast = null;
    switch (name) {
      case "how":
        go("how");
        startHowTimer();
        break;
      case "how-next":
        state.howBeat = (state.howBeat + 1) % t("how").length;
        render();
        break;
      case "privacy":
        go("privacy");
        break;
      case "privacySettings":
        go("privacySettings");
        break;
      case "signIn":
        go("signIn");
        break;
      case "toggle-auth":
        state.authMode = state.authMode === "signup" ? "login" : "signup";
        render();
        break;
      case "submit-signup":
        confirmAuth("signup");
        break;
      case "submit-login":
        confirmAuth("login");
        break;
      case "returning":
        state.email = "existing@checkmed.app";
        state.name = "Alex";
        enterMain({ returning: true, seed: true, tab: "progress" });
        break;
      case "oauth-google":
      case "oauth-facebook":
        go("callYou");
        break;
      case "oauth-apple":
        state.overlay = "apple";
        render();
        break;
      case "callYou":
        go("callYou");
        break;
      case "addressYou":
        if (!state.name.trim() || !state.dob) return;
        go("addressYou");
        break;
      case "addMed":
        if (!state.pronouns || !state.gender) return;
        go("addMed");
        break;
      case "camera":
        go("camera");
        break;
      case "mock-photo":
      case "mock-pdf":
        startAnalyse(name === "mock-pdf" ? "pdf" : "photo");
        break;
      case "manual":
        state.addMethod = "manual";
        state.draft = { medicine: "", dose: "", frequency: "", duration: "" };
        go("manual");
        break;
      case "analyse-manual":
        startAnalyse("manual");
        break;
      case "organize":
        saveMedicine();
        go("organize");
        break;
      case "notifs":
        go("notifs");
        break;
      case "ready":
        go("ready");
        break;
      case "home":
        enterMain({ returning: false, seed: false, tab: "home" });
        break;
      case "tab-home":
        state.tab = "home";
        render();
        break;
      case "scan-home":
        state.overlay = "scan";
        render();
        break;
      case "camera-main":
        state.overlay = null;
        go("camera");
        break;
      case "mock-photo-main":
      case "mock-pdf-main":
        startAnalyse(name.includes("pdf") ? "pdf" : "photo");
        break;
      case "manual-main":
        state.overlay = null;
        state.addMethod = "manual";
        go("manual");
        break;
      case "overlay-nextdose":
        state.overlay = "nextdose";
        render();
        break;
      case "overlay-alarm":
        state.overlay = "alarm";
        render();
        break;
      case "overlay-today":
        state.overlay = "today";
        render();
        break;
      case "overlay-upcoming":
        state.overlay = "upcoming";
        render();
        break;
      case "overlay-summary":
        state.overlay = "summary";
        render();
        break;
      case "paywall":
        state.paywallOpen = true;
        render();
        break;
      case "close-paywall":
        state.paywallOpen = false;
        render();
        break;
      case "close-overlay":
        state.overlay = null;
        render();
        break;
      case "restart":
        restartFirst();
        break;
      default:
        break;
    }
  }

  let howTimer;
  function startHowTimer() {
    clearInterval(howTimer);
    howTimer = setInterval(() => {
      if (state.screen !== "how") {
        clearInterval(howTimer);
        return;
      }
      state.howBeat = (state.howBeat + 1) % 4;
      render();
    }, 2400);
  }

  function restartFirst() {
    clearTimers();
    clearInterval(howTimer);
    Object.assign(state, {
      screen: "splash",
      tab: "home",
      overlay: null,
      authMode: "signup",
      email: "",
      password: "",
      confirm: "",
      name: "",
      dob: "",
      pronouns: "",
      gender: "",
      howBeat: 0,
      draft: { medicine: "", dose: "", frequency: "", duration: "" },
      medicines: [],
      doses: [],
      returning: false,
      paywallOpen: false,
      paywallOffered: false,
      toast: null,
    });
    render();
    later(3000, () => {
      if (state.screen === "splash") go("language");
    });
  }

  document.getElementById("restart-first").onclick = restartFirst;
  document.getElementById("jump-returning").onclick = () => {
    clearTimers();
    state.locale = state.locale || "en";
    state.email = "existing@checkmed.app";
    state.name = "Alex";
    enterMain({ returning: true, seed: true, tab: "progress" });
  };

  restartFirst();
})();
