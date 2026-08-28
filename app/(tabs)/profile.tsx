import { useRouter } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, radii, space, type } from '@/design/tokens';
import { COMPANION_NAME } from '@/features/today/mockPath';

export default function ProfileScreen() {
  const router = useRouter();

  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <Text style={styles.title}>Profile</Text>
        <View style={styles.host}>
          <Character size={72} />
          <SpeechBubble text="Guest for now. Create an account and I follow you — not this phone. Super never blocks Taken." />
        </View>

        <View style={styles.card}>
          <Text style={styles.eyebrow}>Account</Text>
          <Text style={styles.cardTitle}>Guest</Text>
          <Text style={styles.cardBody}>
            Sign out and delete account land with real auth. Cloud scan stays behind an account.
          </Text>
          <Button label="Create account" onPress={() => router.push('/(auth)/sign-in')} />
        </View>

        <Row label="Companion" value={COMPANION_NAME} />
        <Row label="Notifications" value="On (preview)" />
        <Row label="Voice & language" value="English" />
        <Row label="Super CheckMed" value="Free" />
        <Row label="Family profiles" value="1 of 1" />

        <Pressable disabled style={styles.disabled}>
          <Text style={styles.disabledLabel}>Sign out</Text>
        </Pressable>
        <Pressable disabled style={styles.disabled}>
          <Text style={[styles.disabledLabel, styles.danger]}>Delete account & data</Text>
        </Pressable>
      </ScrollView>
    </SafeAreaView>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={styles.rowValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scroll: {
    padding: space.lg,
    gap: space.md,
    paddingBottom: space.xxl,
  },
  title: {
    ...type.display,
    fontSize: 28,
  },
  host: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: space.md,
    marginBottom: space.sm,
  },
  card: {
    backgroundColor: colors.surface,
    borderRadius: radii.lg,
    padding: space.lg,
    borderWidth: 2,
    borderColor: '#EFEFEF',
    gap: space.md,
  },
  eyebrow: {
    ...type.caption,
    textTransform: 'uppercase',
    letterSpacing: 0.8,
  },
  cardTitle: {
    ...type.title,
  },
  cardBody: {
    ...type.body,
    color: colors.muted,
    lineHeight: 22,
  },
  row: {
    backgroundColor: colors.surface,
    borderRadius: radii.md,
    padding: space.lg,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: '#EFEFEF',
  },
  rowLabel: {
    ...type.body,
  },
  rowValue: {
    ...type.caption,
  },
  disabled: {
    paddingVertical: space.md,
    alignItems: 'center',
  },
  disabledLabel: {
    ...type.caption,
    opacity: 0.45,
  },
  danger: {
    color: colors.danger,
    opacity: 0.6,
  },
});
