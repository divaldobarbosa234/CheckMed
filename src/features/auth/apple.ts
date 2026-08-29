import * as AppleAuthentication from 'expo-apple-authentication';

import { NOT_CONFIGURED_MESSAGE } from './config';
import { getSupabase } from './supabase';

function isAppleCancel(error: unknown) {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    (error as { code: string }).code === 'ERR_REQUEST_CANCELED'
  );
}

export async function signInWithAppleNative(): Promise<'unavailable' | 'cancelled' | 'signed-in'> {
  const available = await AppleAuthentication.isAvailableAsync();
  if (!available) return 'unavailable';

  try {
    const credential = await AppleAuthentication.signInAsync({
      requestedScopes: [
        AppleAuthentication.AppleAuthenticationScope.FULL_NAME,
        AppleAuthentication.AppleAuthenticationScope.EMAIL,
      ],
    });
    if (!credential.identityToken) {
      throw new Error('Apple did not return an identity token.');
    }
    const client = getSupabase();
    if (!client) throw new Error(NOT_CONFIGURED_MESSAGE);
    const { error } = await client.auth.signInWithIdToken({
      provider: 'apple',
      token: credential.identityToken,
    });
    if (error) throw error;
    return 'signed-in';
  } catch (error) {
    if (isAppleCancel(error)) return 'cancelled';
    throw error;
  }
}
