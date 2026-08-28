import { useRouter } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, space, type } from '@/design/tokens';
import { useSession } from '@/features/auth/session';

export default function CheckEmailScreen() {
  const router = useRouter();
  const { continueAsGuest } = useSession();

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.hero}>
        <Character size={120} />
        <SpeechBubble text="Check your inbox. I'll keep today's path ready while the magic link is still being wired up." />
        <Text style={styles.title}>Check your email</Text>
        <Text style={styles.body}>
          Real magic-link sessions arrive in Phase 1. You can still tap through Home as a guest.
        </Text>
      </View>
      <View style={styles.actions}>
        <Button
          label="Continue as guest"
          onPress={() => {
            continueAsGuest();
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
