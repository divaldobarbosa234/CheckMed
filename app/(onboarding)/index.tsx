import { useRouter } from 'expo-router';
import { useState } from 'react';
import { StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, radii, space, type } from '@/design/tokens';
import { useSession } from '@/features/auth/session';
import { COMPANION_NAME } from '@/features/today/mockPath';

const BEATS = [
  {
    title: `Hi! I'm ${COMPANION_NAME}.`,
    bubble: "I'll stick with you — like a streak pal for your medicines. What should I call you?",
    caption: 'Name your companion and yourself. Phil is the host, not a decoration.',
  },
  {
    title: 'Scan · we organize · you check',
    bubble: 'Photograph or import a prescription. I structure what was written. You verify every field.',
    caption: 'OCR is a reading aid. I never recommend a medicine, a dose, or a diagnosis.',
  },
  {
    title: 'Today is a path',
    bubble: 'Home is dose nodes, not a clinical table first. Taken celebrates. Skip does not break the streak.',
    caption: 'Alarms land in Phase 5. Super never locks taking a dose.',
  },
  {
    title: 'Want me to remind you?',
    bubble: 'Medication reminders, treatment alerts, important pings. You can change this later in Profile.',
    caption: 'Display name stays with the account once you sign in.',
  },
] as const;

export default function OnboardingScreen() {
  const router = useRouter();
  const { saveOnboardingNames, continueAsGuest, displayName, companionName } = useSession();
  const [step, setStep] = useState(0);
  const [name, setName] = useState(displayName === 'there' ? '' : displayName);
  const [companion, setCompanion] = useState(companionName || COMPANION_NAME);
  const beat = BEATS[step];
  const last = step === BEATS.length - 1;

  async function persistNames() {
    await saveOnboardingNames(name, companion);
  }

  async function next() {
    await persistNames();
    if (last) {
      router.push('/(auth)/sign-in');
      return;
    }
    setStep((current) => current + 1);
  }

  async function skipToGuest() {
    await persistNames();
    await continueAsGuest();
    router.replace('/home');
  }

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.top}>
        <Text style={styles.step}>{step + 1}/{BEATS.length}</Text>
        <View style={styles.dots}>
          {BEATS.map((_, index) => (
            <View key={index} style={[styles.dot, index === step && styles.dotOn]} />
          ))}
        </View>
      </View>

      <View style={styles.hero}>
        <Character size={128} />
        <SpeechBubble text={beat.bubble} />
        <Text style={styles.title}>{beat.title}</Text>
        <Text style={styles.caption}>{beat.caption}</Text>
      </View>

      {step === 0 ? (
        <View style={styles.fields}>
          <Text style={styles.label}>Your name</Text>
          <TextInput
            accessibilityLabel="Your name"
            placeholder="Alex"
            placeholderTextColor={colors.muted}
            value={name}
            onChangeText={setName}
            style={styles.input}
          />
          <Text style={styles.label}>Companion name</Text>
          <TextInput
            accessibilityLabel="Companion name"
            placeholder={COMPANION_NAME}
            placeholderTextColor={colors.muted}
            value={companion}
            onChangeText={setCompanion}
            style={styles.input}
          />
        </View>
      ) : null}

      <View style={styles.actions}>
        <Button label={last ? 'Create account' : 'Continue'} onPress={() => void next()} />
        {last ? (
          <Button label="Continue as guest" variant="secondary" onPress={() => void skipToGuest()} />
        ) : (
          <Button
            label="Back"
            variant="ghost"
            onPress={() => {
              if (step === 0) router.back();
              else setStep((current) => current - 1);
            }}
          />
        )}
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
  top: {
    paddingTop: space.md,
    alignItems: 'center',
    gap: space.sm,
  },
  step: {
    ...type.caption,
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  dots: {
    flexDirection: 'row',
    gap: 8,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.locked,
  },
  dotOn: {
    backgroundColor: colors.primary,
    width: 18,
  },
  hero: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: space.md,
  },
  title: {
    ...type.title,
    textAlign: 'center',
  },
  caption: {
    ...type.body,
    color: colors.muted,
    textAlign: 'center',
    lineHeight: 22,
  },
  fields: {
    gap: space.sm,
    paddingBottom: space.md,
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
  actions: {
    gap: space.md,
    paddingBottom: space.xl,
  },
});
