import { useEffect, useState } from "react";
import { STAGES, type StageId } from "./character/universe";
import { SplashScreen } from "./screens/SplashScreen";
import { HomeScreen } from "./screens/HomeScreen";
import { AlarmScreen } from "./screens/AlarmScreen";
import { WidgetScreen } from "./screens/WidgetScreen";
import { ProcessingScreen } from "./screens/ProcessingScreen";
import { CelebrateScreen } from "./screens/CelebrateScreen";
import { NudgeScreen } from "./screens/NudgeScreen";

function TabBar() {
  return (
    <nav className="tabbar" aria-label="App tabs">
      <div className="on">Home</div>
      <div>Plan</div>
      <div>History</div>
      <div>You</div>
    </nav>
  );
}

export function App() {
  const [stage, setStage] = useState<StageId>("splash");

  useEffect(() => {
    const t = window.setTimeout(() => {
      setStage((current) => (current === "splash" ? "home" : current));
    }, 2400);
    return () => window.clearTimeout(t);
  }, []);

  const chrome = stage !== "alarm" && stage !== "widget" && stage !== "splash";

  return (
    <div className="app-shell">
      <aside className="stage-nav">
        <div>
          <h1>Phil · CheckMed companion</h1>
          <p>
            A round yellow chick from our character bible. Same universe on the
            splash, alarm, widget, and processing screens — mood always matches
            the moment.
          </p>
        </div>
        <div className="stage-list">
          {STAGES.map((s) => (
            <button
              key={s.id}
              aria-current={stage === s.id ? "page" : undefined}
              onClick={() => setStage(s.id)}
            >
              {s.label}
              <small>{s.hint}</small>
            </button>
          ))}
        </div>
      </aside>
      <main className="preview">
        <div
          className={`phone${stage === "splash" ? " is-splash" : ""}${stage === "alarm" ? " is-alarm" : ""}`}
        >
          {chrome && (
            <div className="phone-status">
              <span>9:41</span>
              <span>CheckMed</span>
            </div>
          )}
          {stage === "splash" && <SplashScreen />}
          {stage === "home" && (
            <HomeScreen
              onScan={() => setStage("processing")}
              onTake={() => setStage("celebrate")}
            />
          )}
          {stage === "alarm" && (
            <AlarmScreen
              onSnooze={() => setStage("nudge")}
              onStop={() => setStage("celebrate")}
            />
          )}
          {stage === "widget" && <WidgetScreen />}
          {stage === "processing" && (
            <ProcessingScreen onDone={() => setStage("home")} />
          )}
          {stage === "nudge" && (
            <NudgeScreen
              onTake={() => setStage("celebrate")}
              onSkip={() => setStage("home")}
            />
          )}
          {stage === "celebrate" && (
            <CelebrateScreen onHome={() => setStage("home")} />
          )}
          {chrome && <TabBar />}
        </div>
      </main>
    </div>
  );
}
