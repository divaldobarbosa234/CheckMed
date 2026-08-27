export type PhilMood =
  | "happy"
  | "excited"
  | "thinking"
  | "wink"
  | "sad"
  | "sick"
  | "love"
  | "sleepy"
  | "doctor"
  | "listen"
  | "cheer"
  | "worry";

type PhilProps = {
  mood?: PhilMood;
  size?: number;
  showBubble?: boolean;
  line?: string;
};

export function Phil({ mood = "happy", size = 220, showBubble = false, line }: PhilProps) {
  return (
    <div className="phil-block">
      {showBubble && line && <p className="speech">{line}</p>}
      <div className={`phil-stage mood-${mood}`} style={{ width: size }}>
        <PhilMark mood={mood} />
      </div>
    </div>
  );
}

export function PhilMark({ mood }: { mood: PhilMood }) {
  const eyes = eyeKind(mood);
  return (
    <svg viewBox="0 0 200 230" className="phil-mark" aria-hidden>
      <ellipse cx="100" cy="214" rx="42" ry="8" fill="rgba(40,30,10,0.12)" />
      {mood === "doctor" && (
        <path d="M48 118 h104 v70 a20 20 0 0 1 -20 20 H68 a20 20 0 0 1 -20 -20 z" fill="#F4F7FB" />
      )}
      <ellipse cx="100" cy="128" rx="72" ry="70" fill="#FFD400" />
      <ellipse cx="100" cy="148" rx="40" ry="28" fill="#FFE56A" />
      <path d="M100 42 C108 42 114 52 114 62 C100 56 86 56 86 62 C86 52 92 42 100 42Z" fill="#F0B400" />
      <ellipse cx="42" cy="138" rx="18" ry="12" fill="#FFD400" transform="rotate(-32 42 138)" />
      <ellipse cx="158" cy="138" rx="18" ry="12" fill="#FFD400" transform="rotate(32 158 138)" />
      {mood === "thinking" && (
        <ellipse cx="48" cy="118" rx="16" ry="11" fill="#FFD400" transform="rotate(-10 48 118)" />
      )}
      <Eyes kind={eyes} />
      {mood === "doctor" && <Glasses />}
      {mood === "listen" && <Headphones />}
      {mood === "sleepy" && <Nightcap />}
      {mood === "sick" && <IcePack />}
      {mood === "sad" && <circle cx="138" cy="150" r="7" fill="#7EC8FF" />}
      {mood === "love" && <Heart x={148} y={70} />}
      {mood === "thinking" && (
        <text x="150" y="78" fontSize="36" fill="#5B9FFF" fontFamily="Nunito, sans-serif" fontWeight="800">
          ?
        </text>
      )}
      {mood === "worry" && (
        <text x="150" y="78" fontSize="36" fill="#FF4B4B">
          !
        </text>
      )}
      {mood === "excited" && (
        <g stroke="#FF8C32" strokeWidth="4" strokeLinecap="round">
          <path d="M28 88 l-12 -10" />
          <path d="M172 88 l12 -10" />
          <path d="M24 110 h-14" />
          <path d="M176 110 h14" />
        </g>
      )}
      {mood === "sleepy" && (
        <g fill="#5B9FFF" fontSize="18" fontFamily="Nunito, sans-serif" fontWeight="800">
          <text x="150" y="80">z</text>
          <text x="164" y="64">z</text>
        </g>
      )}
      <ellipse cx="100" cy="156" rx="12" ry="8" fill="#FF8C32" />
      {mood === "wink" || mood === "happy" ? (
        <path d="M88 164 Q100 172 112 164" fill="none" stroke="#FF8C32" strokeWidth="3" />
      ) : null}
      {mood !== "sleepy" && (
        <g fill="#FF8C32">
          <ellipse cx="78" cy="200" rx="10" ry="7" />
          <ellipse cx="122" cy="200" rx="10" ry="7" />
        </g>
      )}
      {mood === "doctor" && <Stethoscope />}
    </svg>
  );
}

function eyeKind(mood: PhilMood): "open" | "happy" | "sleepy" | "sad" | "wink" | "wide" {
  if (mood === "happy" || mood === "love" || mood === "cheer") return "happy";
  if (mood === "sleepy") return "sleepy";
  if (mood === "sad" || mood === "sick") return "sad";
  if (mood === "wink") return "wink";
  if (mood === "excited" || mood === "worry") return "wide";
  return "open";
}

function Eyes({ kind }: { kind: ReturnType<typeof eyeKind> }) {
  if (kind === "happy") {
    return (
      <g fill="none" stroke="#2B3330" strokeWidth="6" strokeLinecap="round">
        <path d="M62 122 Q78 108 94 122" />
        <path d="M106 122 Q122 108 138 122" />
      </g>
    );
  }
  if (kind === "sleepy") {
    return (
      <g fill="none" stroke="#2B3330" strokeWidth="6" strokeLinecap="round">
        <path d="M60 128 Q78 122 94 128" />
        <path d="M106 128 Q122 122 140 128" />
      </g>
    );
  }
  if (kind === "sad") {
    return (
      <g>
        <ellipse cx="76" cy="128" rx="18" ry="20" fill="#fff" />
        <ellipse cx="124" cy="128" rx="18" ry="20" fill="#fff" />
        <ellipse cx="76" cy="136" rx="7" ry="9" fill="#2B3330" />
        <ellipse cx="124" cy="136" rx="7" ry="9" fill="#2B3330" />
        <path d="M60 108 L78 116" stroke="#2B3330" strokeWidth="4" strokeLinecap="round" />
        <path d="M140 108 L122 116" stroke="#2B3330" strokeWidth="4" strokeLinecap="round" />
      </g>
    );
  }
  const wide = kind === "wide";
  return (
    <g>
      <ellipse cx="76" cy="124" rx={wide ? 22 : 18} ry={wide ? 24 : 20} fill="#fff" />
      {kind === "wink" ? (
        <path d="M108 124 Q124 114 140 124" fill="none" stroke="#2B3330" strokeWidth="6" strokeLinecap="round" />
      ) : (
        <ellipse cx="124" cy="124" rx={wide ? 22 : 18} ry={wide ? 24 : 20} fill="#fff" />
      )}
      <ellipse cx="76" cy="128" rx="7" ry="10" fill="#2B3330" />
      {kind !== "wink" && <ellipse cx="124" cy="128" rx="7" ry="10" fill="#2B3330" />}
      <circle cx="70" cy="116" r="4.5" fill="#fff" />
      {kind !== "wink" && <circle cx="118" cy="116" r="4.5" fill="#fff" />}
    </g>
  );
}

function Glasses() {
  return (
    <g fill="none" stroke="#2B3330" strokeWidth="5">
      <circle cx="76" cy="124" r="24" />
      <circle cx="124" cy="124" r="24" />
      <path d="M100 118 v12" strokeWidth="6" />
      <path d="M52 124 h-8" />
      <path d="M148 124 h8" />
    </g>
  );
}

function Headphones() {
  return (
    <g>
      <path d="M48 112 Q100 58 152 112" fill="none" stroke="#9B6BFF" strokeWidth="10" />
      <rect x="32" y="108" width="22" height="34" rx="10" fill="#9B6BFF" />
      <rect x="146" y="108" width="22" height="34" rx="10" fill="#9B6BFF" />
    </g>
  );
}

function Nightcap() {
  return (
    <g>
      <path d="M70 78 Q100 28 148 70 L130 86 Q100 54 78 90Z" fill="#5B9FFF" />
      <circle cx="150" cy="72" r="10" fill="#F4F7FB" />
    </g>
  );
}

function IcePack() {
  return <ellipse cx="100" cy="70" rx="28" ry="14" fill="#7EC8FF" />;
}

function Heart({ x, y }: { x: number; y: number }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <path fill="#FF6B9D" d="M0 12 C0 2 12 -4 16 6 C20 -4 32 2 32 12 C32 24 16 34 16 34 C16 34 0 24 0 12Z" />
    </g>
  );
}

function Stethoscope() {
  return (
    <g fill="none" stroke="#5B9FFF" strokeWidth="5" strokeLinecap="round">
      <path d="M70 188 Q100 210 130 188" />
      <circle cx="100" cy="214" r="8" fill="#5B9FFF" stroke="none" />
    </g>
  );
}
