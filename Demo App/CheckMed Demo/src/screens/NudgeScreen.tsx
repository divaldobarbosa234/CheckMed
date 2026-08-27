import { Phil } from "../character/Phil";
import { LINES } from "../character/universe";

type Props = { onTake: () => void; onSkip: () => void };

export function NudgeScreen({ onTake, onSkip }: Props) {
  return (
    <div className="screen">
      <span className="tiny">Gentle reminder</span>
      <h2>Still here when you’re ready</h2>
      <Phil mood="wink" size={210} showBubble line={LINES.wink} />
      <div className="actions">
        <button className="primary" onClick={onTake}>
          Take it now
        </button>
        <button className="ghost" onClick={onSkip}>
          Skip this dose
        </button>
      </div>
    </div>
  );
}
