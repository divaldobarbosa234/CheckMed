import * as Linking from 'expo-linking';

export const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL?.trim() ?? '';
export const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY?.trim() ?? '';

export const isSupabaseConfigured = Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);

export const GUEST_STORAGE_KEY = 'checkmed.guest';
export const DISPLAY_NAME_KEY = 'checkmed.displayName';
export const COMPANION_NAME_KEY = 'checkmed.companionName';

/** Dashboard allow-list. Expo Go also emits an exp:// URL — see getAuthRedirectUri(). */
export const AUTH_CALLBACK_PATH = 'auth/callback';
export const NATIVE_AUTH_REDIRECT = 'checkmed://auth/callback';
export const NATIVE_AUTH_SCHEME = 'checkmed://';
export const WEB_AUTH_ORIGIN = 'http://localhost:8081';
export const WEB_AUTH_REDIRECT = 'http://localhost:8081/auth/callback';

export const NOT_CONFIGURED_MESSAGE =
  'Add EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY to a local .env (see .env.example), then restart Expo.';

export function getAuthRedirectUri() {
  return Linking.createURL(AUTH_CALLBACK_PATH);
}
