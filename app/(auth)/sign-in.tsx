import { useRouter } from 'expo-router';
import { StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { SafetyCaption } from '@/design/SafetyCaption';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, radii, space, type } from '@/design/tokens';
import { useSession } from '@/features/auth/session';
import { COMPANION_NAME } from '@/features/today/mockPath';

export default function SignInScreen() {
  const router = useRouter();
  const { continueAsGuest } = useSession();

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.hero}>
        <View style={styles.companionRow}>
          <Character size={88} />
          <SpeechBubble
            text={`Accounts keep your path with you. Magic link lands in Phase 1 — until then, I can still host today's mock path.`}
          />
        </View>
        <Text style={styles.title}>Sign in to CheckMed</Text>
        <Text style={styles.body}>
          Magic link on web and iPhone. Sign in with Apple on iPhone. {COMPANION_NAME} stays with the
          account, not the install.
        </Text>
      </View>

      <View style={styles.form}>
        <Text style={styles.label}>Email</Text>
        <TextInput
          accessibilityLabel="Email"
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="email-address"
          placeholder="you@email.com"
          placeholderTextColor={colors.muted}
          style={styles.input}
        />
        <Button label="Send magic link" onPress={() => router.push('/(auth)/check-email')} />
        <Button
          label="Continue as guest"
          variant="secondary"
          onPress={() => {
            continueAsGuest();
            router.replace('/home');
          }}
        />
        <Button label="Back" variant="ghost" onPress={() => router.back()} />
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
    paddingTop: space.xxl,
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
  form: {
    gap: space.md,
    paddingBottom: space.xl,
  },
  label: {
    ...type.caption,
    textTransform: 'uppercase',
    letterSpacing: 0.8,
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
});
