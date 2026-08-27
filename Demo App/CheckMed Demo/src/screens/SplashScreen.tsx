export function SplashScreen() {
  return (
    <div className="splash" role="img" aria-label="CheckMed">
      <div className="splash-face">
        <svg viewBox="0 0 240 200" aria-hidden>
          <path
            fill="#E8B40A"
            d="M120 12 C138 12 148 28 150 44 C184 36 220 62 224 102 C228 146 196 182 120 190 C44 182 12 146 16 102 C20 62 56 36 90 44 C92 28 102 12 120 12Z"
          />
          <ellipse cx="74" cy="108" rx="52" ry="54" fill="#fff" />
          <ellipse cx="166" cy="108" rx="52" ry="54" fill="#fff" />
          <ellipse className="splash-pupil" cx="74" cy="114" rx="17" ry="24" fill="#2B3330" />
          <ellipse className="splash-pupil" cx="166" cy="114" rx="17" ry="24" fill="#2B3330" />
          <circle cx="64" cy="98" r="8" fill="#fff" />
          <circle cx="156" cy="98" r="8" fill="#fff" />
          <ellipse cx="120" cy="154" rx="22" ry="14" fill="#FF8C32" />
        </svg>
      </div>
      <div className="splash-brand">
        <span className="ekg-heart" aria-hidden>
          ♥
        </span>
        <p className="splash-wordmark">checkmed</p>
      </div>
    </div>
  );
}
