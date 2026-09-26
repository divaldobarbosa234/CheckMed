import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, Platform, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, space, type } from '@/design/tokens';
import { createSessionFromUrl } from '@/features/auth/oauth';
import { useSession } from '@/features/auth/session';

export default function AuthCallbackScreen() {
  const router = useRouter();
  const { kind, error } = useSession();
  const [localError, setLocalError] = useState<string | null>(null);

  useEffect(() => {
    if (kind === 'authenticated') {
      router.replace('/home');
      return;
    }

    if (Platform.OS !== 'web') return;
    const href = window.location.href;
    if (!href.includes('code=') && !href.includes('access_token')) return;

    void createSessionFromUrl(href)
      .then((session) => {
        if (session) router.replace('/home');
      })
      .catch((err) => {
        setLocalError(err instanceof Error ? err.message : 'Could not finish sign-in.');
      });
  }, [kind, router]);

  const message = localError || error;

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.hero}>
        <Character size={120} />
        <SpeechBubble
          text={
            message
              ? 'That link did not stick. Try sign-in again.'
              : 'Finishing sign-in. Hold on a second.'
          }
        />
        <Text style={styles.title}>{message ? 'Could not sign in' : 'Signing you in'}</Text>
        {message ? <Text style={styles.body}>{message}</Text> : <ActivityIndicator color={colors.primaryShadow} />}
      </View>
      <View style={styles.actions}>
        <Button label="Back to sign in" onPress={() => router.replace('/(auth)/sign-in')} />
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: colors.background,
    paddingHorizontal: space.xl,
    justifyContent: 'space-between',
  },
  hero: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: space.lg,
  },
  title: {
    ...type.title,
    textAlign: 'center',
  },
  body: {
    ...type.body,
    color: colors.muted,
    textAlign: 'center',
    lineHeight: 22,
  },
  actions: {
    gap: space.md,
    paddingBottom: space.xl,
  },
});
