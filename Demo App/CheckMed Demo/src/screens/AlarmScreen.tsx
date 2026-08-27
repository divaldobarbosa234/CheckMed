import { useRef, useState } from "react";
import { Phil } from "../character/Phil";

type Props = { onSnooze: () => void; onStop: () => void };

export function AlarmScreen({ onSnooze, onStop }: Props) {
  return (
    <div className="alarm-kit">
      <div className="alarm-kit-top">
        <span className="alarm-kit-icon" aria-hidden>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
            <circle cx="12" cy="13" r="8" stroke="white" strokeWidth="2" />
            <path d="M12 9v4l2.5 1.5" stroke="white" strokeWidth="2" strokeLinecap="round" />
            <path d="M5 5l3 2M19 5l-3 2" stroke="white" strokeWidth="2" strokeLinecap="round" />
          </svg>
        </span>
        Alarm
      </div>
      <div className="alarm-kit-time">7:33</div>
      <div className="alarm-kit-med">Amoxicillin · 500 mg</div>
      <div className="alarm-kit-mood">
        <div className="alarm-kit-streak">🔥 4</div>
        <p>It’s getting late!</p>
      </div>
      <div className="alarm-kit-phil">
        <Phil mood="sad" size={210} />
      </div>
      <div className="alarm-kit-actions">
        <button className="alarm-snooze" onClick={onSnooze}>
          Snooze
        </button>
        <SlideToStop onStop={onStop} />
      </div>
    </div>
  );
}

function SlideToStop({ onStop }: { onStop: () => void }) {
  const track = useRef<HTMLDivElement>(null);
  const [x, setX] = useState(0);
  const xRef = useRef(0);
  const start = useRef(0);
  const origin = useRef(0);
  const dragging = useRef(false);

  function maxTravel() {
    const el = track.current;
    if (!el) return 220;
    return el.clientWidth - 56;
  }

  function onPointerDown(e: React.PointerEvent) {
    dragging.current = true;
    start.current = e.clientX;
    origin.current = xRef.current;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
  }

  function onPointerMove(e: React.PointerEvent) {
    if (!dragging.current) return;
    const next = Math.min(maxTravel(), Math.max(0, origin.current + e.clientX - start.current));
    xRef.current = next;
    setX(next);
  }

  function onPointerUp() {
    dragging.current = false;
    if (xRef.current > maxTravel() * 0.72) {
      xRef.current = maxTravel();
      setX(xRef.current);
      onStop();
    } else {
      xRef.current = 0;
      setX(0);
    }
  }

  return (
    <div className="slide-stop" ref={track} role="slider" aria-label="Slide to stop" aria-valuenow={x}>
      <span className="slide-hint">slide to stop</span>
      <button
        type="button"
        className="slide-knob"
        style={{ transform: `translateX(${x}px)` }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        aria-label="Drag to stop alarm"
      >
        <span />
      </button>
    </div>
  );
}
