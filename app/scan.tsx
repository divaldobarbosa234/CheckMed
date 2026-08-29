import { useRouter } from 'expo-router';
import { useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AccountGate } from '@/design/AccountGate';
import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { SafetyCaption } from '@/design/SafetyCaption';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, space, type } from '@/design/tokens';
import { useSession } from '@/features/auth/session';

export default function ScanScreen() {
  const router = useRouter();
  const { canSync } = useSession();
  const [gate, setGate] = useState(false);

  function requestCloudScan() {
    if (!canSync) {
      setGate(true);
      return;
    }
    router.push('/review');
  }

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.hero}>
        <Character size={112} />
        <SpeechBubble
          text={
            canSync
              ? 'You are signed in. Photo and PDF import land in Phase 4 — I will read with you, you verify, then we organize.'
              : 'You can look around. A prescription photo or PDF only syncs after you create an account.'
          }
        />
        <Text style={styles.title}>Scan hub</Text>
        <Text style={styles.body}>
          Camera on iPhone. File picker on web. Extract → verify → organize is Phase 4. I never recommend a
          medicine or a dose.
        </Text>
      </View>
      <View style={styles.actions}>
        <Button
          label="Take a photo"
          onPress={requestCloudScan}
          accessibilityHint={canSync ? 'Opens the review placeholder' : 'Requires an account before cloud scan'}
        />
        <Button label="Choose PDF" variant="secondary" onPress={requestCloudScan} />
        <Button label="Back to today's path" variant="ghost" onPress={() => router.back()} />
        <SafetyCaption />
      </View>
      <AccountGate
        visible={gate}
        onCreateAccount={() => {
          setGate(false);
          router.push('/(auth)/sign-in');
        }}
        onDismiss={() => setGate(false)}
      />
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
