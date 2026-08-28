import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';

export type SessionKind = 'unknown' | 'guest';

type SessionValue = {
  kind: SessionKind;
  continueAsGuest: () => void;
};

const SessionContext = createContext<SessionValue | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const [kind, setKind] = useState<SessionKind>('unknown');

  const value = useMemo<SessionValue>(
    () => ({
      kind,
      continueAsGuest: () => setKind('guest'),
    }),
    [kind],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession() {
  const ctx = useContext(SessionContext);
  if (!ctx) {
    throw new Error('useSession must be used inside SessionProvider');
  }
  return ctx;
}
