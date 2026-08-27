import { PhilMark } from "../character/Phil";
import { WIDGET_TONES, type WidgetTone } from "../character/universe";

export function WidgetScreen() {
  return (
    <div className="screen widget-home">
      <div className="widget-clock">9:41</div>
      <div className="widget-grid">
        {WIDGET_TONES.map((tone) => (
          <MoodWidget key={tone.id} tone={tone} />
        ))}
      </div>
    </div>
  );
}

function MoodWidget({ tone }: { tone: WidgetTone }) {
  return (
    <article
      className={`mood-widget crop-${tone.crop}`}
      style={{ background: tone.bg, color: tone.ink }}
    >
      <header>
        <span className="mood-badge">{tone.badge}</span>
        <span className="mood-brand" style={{ color: tone.muted }}>
          checkmed
        </span>
      </header>
      <div className="mood-copy">
        <strong>{tone.title}</strong>
        <span style={{ color: tone.muted }}>{tone.line}</span>
      </div>
      <div className="mood-phil">
        <PhilMark mood={tone.mood} />
      </div>
    </article>
  );
}
