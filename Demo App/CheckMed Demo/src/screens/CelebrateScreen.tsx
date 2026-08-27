import { Phil } from "../character/Phil";
import { LINES } from "../character/universe";

type Props = { onHome: () => void };

export function CelebrateScreen({ onHome }: Props) {
  return (
    <div className="screen">
      <Phil mood="excited" size={230} showBubble line={LINES.excited} />
      <div className="card" style={{ textAlign: "center" }}>
        <div className="tiny">Streak</div>
        <div style={{ fontSize: "2.6rem", fontWeight: 800 }}>4 days</div>
        <div className="muted">Amoxicillin logged · 16:00 still open</div>
      </div>
      <div className="actions">
        <button className="primary" onClick={onHome}>
          Back to today
        </button>
      </div>
    </div>
  );
}
