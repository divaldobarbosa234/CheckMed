import { NOT_CONFIGURED_MESSAGE } from './config';

export function messageFromAuthError(error: unknown): string {
  if (!error) return 'Something went wrong. Try again, or continue as a guest.';
  const raw =
    error instanceof Error
      ? error.message
      : typeof error === 'string'
        ? error
        : 'Something went wrong. Try again, or continue as a guest.';
  const text = raw.toLowerCase();

  if (text.includes('not configured') || text.includes('supabase_url')) {
    return NOT_CONFIGURED_MESSAGE;
  }
  if (text.includes('provider is not enabled') || text.includes('unsupported provider')) {
    return 'That provider is not enabled yet. Turn it on in Supabase → Authentication → Providers, paste the client ID and secret, then try again. Guest still works.';
  }
  if (text.includes('redirect') || text.includes('redirect_uri') || text.includes('invalid request')) {
    return 'Redirect URL mismatch. Add the URL shown on Sign in to Supabase → Authentication → URL configuration, plus checkmed://auth/callback.';
  }
  if (text.includes('rate limit') || text.includes('over_email_send_rate_limit')) {
    return 'Too many emails just now. Wait a minute, then send another magic link.';
  }
  if (text.includes('invalid login') || text.includes('otp')) {
    return raw;
  }
  return raw;
}
