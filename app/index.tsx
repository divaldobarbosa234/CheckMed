import { useRouter } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { SafetyCaption } from '@/design/SafetyCaption';
import { colors, space, type } from '@/design/tokens';
import { useSession } from '@/features/auth/session';

export default function WelcomeScreen() {
  const router = useRouter();
  const { kind, displayName } = useSession();

  const signedIn = kind === 'authenticated';

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.hero}>
        <Character size={148} />
        <Text style={styles.wordmark}>CheckMed</Text>
        <Text style={styles.tagline}>
          Hi, I{'\u2019'}m Phil. I help you understand, organize, and follow your treatments — one path at a
          time.
        </Text>
      </View>

      <View style={styles.actions}>
        {signedIn ? (
          <Button
            label={`Continue, ${displayName}`}
            onPress={() => router.replace('/home')}
            accessibilityHint="Opens today's path with your signed-in account."
          />
        ) : (
          <Button
            label="Get started"
            onPress={() => router.push('/(onboarding)')}
            accessibilityHint="Opens a short intro with Phil, then sign in."
          />
        )}
        <Button
          label="I already have an account"
          variant="secondary"
          onPress={() => router.push('/(auth)/sign-in')}
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
