import { useLocalSearchParams, useRouter } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, space, type } from '@/design/tokens';

export default function CheckEmailScreen() {
  const router = useRouter();
  const { email } = useLocalSearchParams<{ email?: string }>();

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
          You can wait here and tap the link, or go back to sign in.
        </Text>
      </View>
      <View style={styles.actions}>
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
