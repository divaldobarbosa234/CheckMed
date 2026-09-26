import AsyncStorage from '@react-native-async-storage/async-storage';
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { User } from '@supabase/supabase-js';

import { COMPANION_NAME } from '@/features/today/mockPath';

import {
  COMPANION_NAME_KEY,
  DISPLAY_NAME_KEY,
  getAuthRedirectUri,
  GUEST_STORAGE_KEY,
  isSupabaseConfigured,
} from './config';
import { messageFromAuthError } from './errors';
import {
  createSessionFromUrl,
  sendMagicLink as sendMagicLinkRequest,
  signInWithApple,
  signInWithOAuthProvider,
  subscribeToAuthLinks,
  type OAuthProvider,
} from './oauth';
import { getSupabase } from './supabase';

export type SessionKind = 'loading' | 'unknown' | 'authenticated';

type SessionValue = {
  kind: SessionKind;
  configured: boolean;
  canSync: boolean;
  user: User | null;
  email: string | null;
  displayName: string;
  companionName: string;
  error: string | null;
  redirectUri: string;
  signOut: () => Promise<void>;
  deleteAccount: () => Promise<void>;
  sendMagicLink: (email: string) => Promise<string>;
  signInWithProvider: (provider: OAuthProvider) => Promise<boolean>;
  saveOnboardingNames: (displayName: string, companionName: string) => Promise<void>;
  clearError: () => void;
};

const SessionContext = createContext<SessionValue | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const [kind, setKind] = useState<SessionKind>('loading');
  const [user, setUser] = useState<User | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [displayName, setDisplayName] = useState('there');
  const [companionName, setCompanionName] = useState(COMPANION_NAME);
  const redirectUri = getAuthRedirectUri();

  useEffect(() => {
    let cancelled = false;
    const client = getSupabase();

    async function hydrate() {
      const [storedName, storedCompanion] = await Promise.all([
        AsyncStorage.getItem(DISPLAY_NAME_KEY),
        AsyncStorage.getItem(COMPANION_NAME_KEY),
      ]);
      if (cancelled) return;
      if (storedName) setDisplayName(storedName);
      if (storedCompanion) setCompanionName(storedCompanion);
      await AsyncStorage.removeItem(GUEST_STORAGE_KEY);

      if (!client) {
        setKind('unknown');
        return;
      }

      const { data } = await client.auth.getSession();
      if (cancelled) return;
      if (data.session?.user) {
        setUser(data.session.user);
        setKind('authenticated');
        await AsyncStorage.removeItem(GUEST_STORAGE_KEY);
        const fromEmail = data.session.user.email?.split('@')[0];
        if (!storedName && fromEmail) setDisplayName(fromEmail);
      } else {
        setKind('unknown');
      }
    }

    void hydrate();

    const { data: authSub } = client?.auth.onAuthStateChange((_event, session) => {
      if (session?.user) {
        setUser(session.user);
        setKind('authenticated');
        setError(null);
        void AsyncStorage.removeItem(GUEST_STORAGE_KEY);
        const fromEmail = session.user.email?.split('@')[0];
        if (fromEmail) {
          setDisplayName((current) => (current === 'there' ? fromEmail : current));
        }
      } else {
        setUser(null);
      }
    }) ?? { data: { subscription: { unsubscribe() {} } } };

    const unsubLinks = subscribeToAuthLinks((url) => {
      if (!url.includes('access_token') && !url.includes('code=')) return;
      void createSessionFromUrl(url).catch((err) => {
        setError(messageFromAuthError(err));
      });
    });

    return () => {
      cancelled = true;
      authSub.subscription.unsubscribe();
      unsubLinks();
    };
  }, []);

  const value = useMemo<SessionValue>(
    () => ({
      kind,
      configured: isSupabaseConfigured,
      canSync: kind === 'authenticated',
      user,
      email: user?.email ?? null,
      displayName,
      companionName,
      error,
      redirectUri,
      clearError: () => setError(null),
      signOut: async () => {
        const client = getSupabase();
        try {
          await client?.auth.signOut();
        } catch (err) {
          setError(messageFromAuthError(err));
        }
        await AsyncStorage.removeItem(GUEST_STORAGE_KEY);
        setUser(null);
        setKind('unknown');
      },
      deleteAccount: async () => {
        // Cloud wipe of treatments lands in Phase 6. Session must still clear now.
        const client = getSupabase();
        try {
          await client?.auth.signOut();
        } catch (err) {
          setError(messageFromAuthError(err));
        }
        await AsyncStorage.multiRemove([GUEST_STORAGE_KEY, DISPLAY_NAME_KEY, COMPANION_NAME_KEY]);
        setUser(null);
        setKind('unknown');
        setError(
          'You are signed out here. Deleting the cloud account and synced data is Phase 6 — run it from Profile after Super polish, or delete the user in Supabase → Authentication → Users.',
        );
      },
      sendMagicLink: async (email: string) => {
        setError(null);
        try {
          return await sendMagicLinkRequest(email);
        } catch (err) {
          const message = messageFromAuthError(err);
          setError(message);
          throw new Error(message);
        }
      },
      signInWithProvider: async (provider) => {
        setError(null);
        try {
          const attempt = provider === 'apple' ? await signInWithApple() : await signInWithOAuthProvider(provider);
          return !attempt.cancelled;
        } catch (err) {
          const message = messageFromAuthError(err);
          setError(message);
          throw new Error(message);
        }
      },
      saveOnboardingNames: async (nextDisplay, nextCompanion) => {
        const display = nextDisplay.trim() || 'there';
        const companion = nextCompanion.trim() || COMPANION_NAME;
        setDisplayName(display);
        setCompanionName(companion);
        await AsyncStorage.multiSet([
          [DISPLAY_NAME_KEY, display],
          [COMPANION_NAME_KEY, companion],
        ]);
      },
    }),
    [companionName, displayName, error, kind, redirectUri, user],
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
