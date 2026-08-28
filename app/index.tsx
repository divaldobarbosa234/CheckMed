import { useRouter } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { SafetyCaption } from '@/design/SafetyCaption';
import { colors, space, type } from '@/design/tokens';
import { useSession } from '@/features/auth/session';
import { COMPANION_NAME } from '@/features/today/mockPath';

export default function WelcomeScreen() {
  const router = useRouter();
  const { continueAsGuest } = useSession();

  function enterAsGuest() {
    continueAsGuest();
    router.replace('/home');
  }

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.hero}>
        <Character size={148} />
        <Text style={styles.wordmark}>CheckMed</Text>
        <Text style={styles.tagline}>
          Hi, I{'\u2019'}m {COMPANION_NAME}. I help you understand, organize, and follow your treatments —
          one path at a time.
        </Text>
      </View>

      <View style={styles.actions}>
        <Button
          label="Get started"
          onPress={() => router.push('/(auth)/sign-in')}
          accessibilityHint="Opens sign in. Account required before cloud sync."
        />
        <Button
          label="I already have an account"
          variant="secondary"
          onPress={() => router.push('/(auth)/sign-in')}
        />
        <Button
          label="Continue as guest"
          variant="ghost"
          onPress={enterAsGuest}
          accessibilityHint="Opens today's path without an account. Scanning will not sync."
        />
        <SafetyCaption />
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
  wordmark: {
    ...type.display,
  },
  tagline: {
    ...type.body,
    textAlign: 'center',
    color: colors.muted,
    paddingHorizontal: space.lg,
    lineHeight: 24,
  },
  actions: {
    gap: space.md,
    paddingBottom: space.xl,
  },
});
