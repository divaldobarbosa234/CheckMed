import * as Linking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';

import { signInWithAppleNative } from './apple';
import { getAuthRedirectUri, isSupabaseConfigured, NOT_CONFIGURED_MESSAGE } from './config';
import { getSupabase } from './supabase';

WebBrowser.maybeCompleteAuthSession();

export type OAuthProvider = 'google' | 'facebook' | 'apple';

type AuthAttempt = {
  cancelled: boolean;
};

function parseAuthParams(url: string) {
  const hashIndex = url.indexOf('#');
  const queryIndex = url.indexOf('?');
  const params = new URLSearchParams();

  if (queryIndex >= 0) {
    const query = url.slice(queryIndex + 1, hashIndex >= 0 ? hashIndex : undefined);
    new URLSearchParams(query).forEach((value, key) => params.set(key, value));
  }
  if (hashIndex >= 0) {
    new URLSearchParams(url.slice(hashIndex + 1)).forEach((value, key) => params.set(key, value));
  }

  return {
    code: params.get('code'),
    access_token: params.get('access_token'),
    refresh_token: params.get('refresh_token'),
    error: params.get('error_description') || params.get('error'),
  };
}

export async function createSessionFromUrl(url: string) {
  const client = getSupabase();
  if (!client) return null;

  const parsed = parseAuthParams(url);
  if (parsed.error) {
    throw new Error(parsed.error);
  }

  if (parsed.code) {
    const { data, error } = await client.auth.exchangeCodeForSession(parsed.code);
    if (error) throw error;
    return data.session;
  }

  if (parsed.access_token && parsed.refresh_token) {
    const { data, error } = await client.auth.setSession({
      access_token: parsed.access_token,
      refresh_token: parsed.refresh_token,
    });
    if (error) throw error;
    return data.session;
  }

  return null;
}

export async function sendMagicLink(email: string) {
  if (!isSupabaseConfigured) {
    throw new Error(NOT_CONFIGURED_MESSAGE);
  }
  const client = getSupabase();
  if (!client) throw new Error(NOT_CONFIGURED_MESSAGE);

  const trimmed = email.trim().toLowerCase();
  if (!trimmed.includes('@')) {
    throw new Error('Enter a valid email so Phil can send a magic link.');
  }

  const { error } = await client.auth.signInWithOtp({
    email: trimmed,
    options: {
      emailRedirectTo: getAuthRedirectUri(),
      shouldCreateUser: true,
    },
  });
  if (error) throw error;
  return trimmed;
}

export async function signInWithOAuthProvider(provider: OAuthProvider): Promise<AuthAttempt> {
  if (!isSupabaseConfigured) {
    throw new Error(NOT_CONFIGURED_MESSAGE);
  }
  const client = getSupabase();
  if (!client) throw new Error(NOT_CONFIGURED_MESSAGE);

  const redirectTo = getAuthRedirectUri();
  const { data, error } = await client.auth.signInWithOAuth({
    provider,
    options: {
      redirectTo,
      skipBrowserRedirect: true,
      queryParams: provider === 'google' ? { access_type: 'offline', prompt: 'consent' } : undefined,
    },
  });
  if (error) throw error;
  if (!data.url) {
    throw new Error('No sign-in page came back. Check that this provider is enabled in Supabase.');
  }

  const result = await WebBrowser.openAuthSessionAsync(data.url, redirectTo);
  if (result.type === 'cancel' || result.type === 'dismiss') {
    return { cancelled: true };
  }
  if (result.type !== 'success' || !('url' in result) || !result.url) {
    throw new Error('Sign-in did not finish. You can try again or continue as a guest.');
  }

  await createSessionFromUrl(result.url);
  return { cancelled: false };
}

export async function signInWithApple(): Promise<AuthAttempt> {
  try {
    const result = await signInWithAppleNative();
    if (result === 'signed-in') return { cancelled: false };
    if (result === 'cancelled') return { cancelled: true };
  } catch {
    // Expo Go / Simulator often cannot complete native Apple — fall through to OAuth.
  }

  return signInWithOAuthProvider('apple');
}

export function subscribeToAuthLinks(onUrl: (url: string) => void) {
  const sub = Linking.addEventListener('url', ({ url }) => onUrl(url));
  void Linking.getInitialURL().then((url) => {
    if (url) onUrl(url);
  });
  return () => sub.remove();
}
