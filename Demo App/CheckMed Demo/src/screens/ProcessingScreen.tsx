import { useEffect, useState } from "react";
import { Phil } from "../character/Phil";

type Props = { onDone: () => void };

const STEPS = [
  { mood: "listen" as const, line: "Looking at the photo…" },
  { mood: "thinking" as const, line: "Finding medicine names…" },
  { mood: "doctor" as const, line: "You’ll review every line." },
];

export function ProcessingScreen({ onDone }: Props) {
  const [i, setI] = useState(0);
  const [pct, setPct] = useState(16);

  useEffect(() => {
    const t = window.setInterval(() => {
      setI((n) => (n + 1) % STEPS.length);
      setPct((p) => (p >= 90 ? 20 : p + 18));
    }, 1200);
    return () => window.clearInterval(t);
  }, []);

  const step = STEPS[i];

  return (
    <div className="screen">
      <span className="tiny">Import</span>
      <h2>Reading prescription</h2>
      <p className="muted" style={{ marginTop: 0 }}>
        This is a reading aid. You confirm what goes into the plan.
      </p>
      <Phil mood={step.mood} size={210} showBubble line={step.line} />
      <div className="progress">
        <span style={{ width: `${pct}%` }} />
      </div>
      <div className="actions">
        <button className="primary" onClick={onDone}>
          Continue to review
        </button>
      </div>
    </div>
  );
}
