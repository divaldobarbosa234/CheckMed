import { useRouter } from 'expo-router';
import { useState } from 'react';
import { ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { ProviderButton } from '@/design/ProviderButton';
import { SafetyCaption } from '@/design/SafetyCaption';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, radii, space, type } from '@/design/tokens';
import { NATIVE_AUTH_REDIRECT, WEB_AUTH_REDIRECT } from '@/features/auth/config';
import { useSession } from '@/features/auth/session';

export default function SignInScreen() {
  const router = useRouter();
  const session = useSession();
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState<'apple' | 'google' | 'facebook' | 'email' | null>(null);

  async function onProvider(provider: 'apple' | 'google' | 'facebook') {
    setBusy(provider);
    try {
      const signedIn = await session.signInWithProvider(provider);
      if (signedIn) router.replace('/home');
    } catch {
      // Error is shown from session.error.
    } finally {
      setBusy(null);
    }
  }

  async function onMagicLink() {
    setBusy('email');
    try {
      const sentTo = await session.sendMagicLink(email);
      router.push({ pathname: '/(auth)/check-email', params: { email: sentTo } });
    } catch {
      // session.error
    } finally {
      setBusy(null);
    }
  }

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <View style={styles.companionRow}>
          <Character size={88} />
          <SpeechBubble text="Save your streak. Magic link, Apple, Google, or Facebook — I follow the account, not this phone." />
        </View>
        <Text style={styles.title}>Sign in to CheckMed</Text>
        <Text style={styles.body}>
          Real session. Sign in with Apple, Google, or email. An account is required before a prescription photo or PDF
          syncs to the cloud.
        </Text>

        {session.error ? <Text style={styles.error}>{session.error}</Text> : null}
        {!session.configured ? (
          <Text style={styles.warn}>
            Supabase keys are not in .env yet. Provider buttons stay on screen and explain what to add.
          </Text>
        ) : null}

        <ProviderButton
          provider="apple"
          disabled={busy !== null}
          busy={busy === 'apple'}
          onPress={() => void onProvider('apple')}
        />
        <ProviderButton
          provider="google"
          disabled={busy !== null}
          busy={busy === 'google'}
          onPress={() => void onProvider('google')}
        />
        <ProviderButton
          provider="facebook"
          disabled={busy !== null}
          busy={busy === 'facebook'}
          onPress={() => void onProvider('facebook')}
        />

        <Text style={styles.label}>Email magic link</Text>
        <TextInput
          accessibilityLabel="Email"
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="email-address"
          placeholder="you@email.com"
          placeholderTextColor={colors.muted}
          value={email}
          onChangeText={setEmail}
          style={styles.input}
        />
        <Button
          label="Send magic link"
          disabled={busy !== null}
          busy={busy === 'email'}
          onPress={() => void onMagicLink()}
        />
        <Button label="Back" variant="ghost" disabled={busy !== null} onPress={() => router.back()} />

        <Text style={styles.hint}>
          Redirect this app uses: {session.redirectUri}
          {'\n'}Also allow {NATIVE_AUTH_REDIRECT} and {WEB_AUTH_REDIRECT} in Supabase.
        </Text>
        <SafetyCaption />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scroll: {
    paddingHorizontal: space.xl,
    paddingTop: space.xl,
    paddingBottom: space.xxl,
    gap: space.md,
  },
  companionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: space.md,
  },
  title: {
    ...type.title,
  },
  body: {
    ...type.body,
    color: colors.muted,
    lineHeight: 22,
  },
  error: {
    ...type.caption,
    color: colors.danger,
    lineHeight: 18,
  },
  warn: {
    ...type.caption,
    color: colors.safety,
    lineHeight: 18,
  },
  label: {
    ...type.caption,
    textTransform: 'uppercase',
    letterSpacing: 0.8,
    marginTop: space.sm,
  },
  input: {
    ...type.body,
    backgroundColor: colors.surface,
    borderWidth: 2,
    borderColor: colors.ink,
    borderRadius: radii.md,
    paddingHorizontal: space.lg,
    paddingVertical: 14,
  },
  hint: {
    ...type.caption,
    lineHeight: 18,
    textAlign: 'center',
  },
});
