import { Phil } from "../character/Phil";
import { LINES } from "../character/universe";

type Props = { onScan: () => void; onTake: () => void };

export function HomeScreen({ onScan, onTake }: Props) {
  return (
    <div className="screen">
      <span className="tiny">Today · Friday 28 Aug</span>
      <h2>Good evening</h2>
      <Phil mood="happy" size={200} showBubble line={LINES.happy} />
      <div className="card">
        <div className="row">
          <div>
            <div className="tiny">Next dose</div>
            <strong>Amoxicillin 500 mg</strong>
            <div className="muted">in 2 hours 14 min</div>
          </div>
          <button className="primary" onClick={onTake}>
            Taken
          </button>
        </div>
        <div className="progress" style={{ marginTop: 14 }}>
          <span style={{ width: "66%" }} />
        </div>
        <div className="muted" style={{ marginTop: 8, fontSize: "0.85rem" }}>
          2 of 3 doses today · 4-day streak
        </div>
      </div>
      <div className="actions">
        <button className="ghost" onClick={onScan}>
          Scan a prescription
        </button>
      </div>
    </div>
  );
}
