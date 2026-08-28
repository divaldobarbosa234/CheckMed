import { useRouter } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { SafetyCaption } from '@/design/SafetyCaption';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, space, type } from '@/design/tokens';

export default function ScanScreen() {
  const router = useRouter();

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.hero}>
        <Character size={112} />
        <SpeechBubble text="Scan comes next: photo or PDF, I read with you, you verify. Cloud upload waits for an account." />
        <Text style={styles.title}>Scan hub</Text>
        <Text style={styles.body}>
          File picker on web. Camera on iPhone. Extract → verify → organize is Phase 4. I never
          recommend a medicine or a dose.
        </Text>
      </View>
      <View style={styles.actions}>
        <Button label="Back to today's path" onPress={() => router.back()} />
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
