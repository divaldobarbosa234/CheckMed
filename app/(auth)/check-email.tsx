import { useLocalSearchParams, useRouter } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, space, type } from '@/design/tokens';
import { useSession } from '@/features/auth/session';

export default function CheckEmailScreen() {
  const router = useRouter();
  const { email } = useLocalSearchParams<{ email?: string }>();
  const { continueAsGuest } = useSession();

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.hero}>
        <Character size={120} />
        <SpeechBubble text="I sent a magic link. Open it on this phone or in this browser and I'll keep your path with the account." />
        <Text style={styles.title}>Check your email</Text>
        <Text style={styles.body}>
          {email
            ? `Tap the link we sent to ${email}. It brings you back into CheckMed.`
            : 'Tap the magic link in your inbox. It brings you back into CheckMed.'}{' '}
          You can still continue as a guest while you wait.
        </Text>
      </View>
      <View style={styles.actions}>
        <Button
          label="Continue as guest"
          onPress={async () => {
            await continueAsGuest();
            router.replace('/home');
          }}
        />
        <Button label="Back to sign in" variant="secondary" onPress={() => router.back()} />
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
