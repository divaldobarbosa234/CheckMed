import { useRouter } from 'expo-router';
import { Alert, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/design/Button';
import { Character } from '@/design/Character';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, radii, space, type } from '@/design/tokens';
import { useSession } from '@/features/auth/session';

export default function ProfileScreen() {
  const router = useRouter();
  const session = useSession();
  const signedIn = session.kind === 'authenticated';

  function confirmDelete() {
    const message =
      'This signs you out now. Wiping the cloud account is Phase 6. You can also delete the user in the Supabase dashboard.';
    if (Platform.OS === 'web') {
      if (window.confirm(`Delete account & data\n\n${message}`)) {
        void session.deleteAccount().then(() => router.replace('/'));
      }
      return;
    }
    Alert.alert('Delete account & data', message, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Sign out here',
        style: 'destructive',
        onPress: () => {
          void session.deleteAccount().then(() => router.replace('/'));
        },
      },
    ]);
  }

  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <Text style={styles.title}>Profile</Text>
        <View style={styles.host}>
          <Character size={72} />
          <SpeechBubble
            text={
              signedIn
                ? `You're in, ${session.displayName}. I follow this account — Super never blocks Taken.`
                : 'Guest for now. Create an account and I follow you — not this phone. Super never blocks Taken.'
            }
          />
        </View>

        <View style={styles.card}>
          <Text style={styles.eyebrow}>Account</Text>
          <Text style={styles.cardTitle}>{signedIn ? session.email ?? session.displayName : 'Guest'}</Text>
          <Text style={styles.cardBody}>
            {signedIn
              ? 'Session is real. Sign out anytime. Cloud treatments sync in Phase 3.'
              : 'Cloud scan stays behind an account. Magic link, Apple, Google, or Facebook.'}
          </Text>
          {signedIn ? (
            <Button
              label="Sign out"
              variant="secondary"
              onPress={() => {
                void session.signOut().then(() => router.replace('/'));
              }}
            />
          ) : (
            <Button label="Create account" onPress={() => router.push('/(auth)/sign-in')} />
          )}
        </View>

        <Row label="Companion" value={session.companionName} />
        <Pressable onPress={() => router.push('/family')} style={styles.row}>
          <Text style={styles.rowLabel}>Family profiles</Text>
          <Text style={styles.rowValue}>1 of 1</Text>
        </Pressable>
        <Pressable onPress={() => router.push('/paywall')} style={styles.row}>
          <Text style={styles.rowLabel}>Super CheckMed</Text>
          <Text style={styles.rowValue}>Free</Text>
        </Pressable>
        <Row label="Notifications" value="On (preview)" />
        <Row label="Voice & language" value="English" />

        {signedIn ? (
          <Pressable onPress={confirmDelete} style={styles.delete}>
            <Text style={styles.deleteLabel}>Delete account & data</Text>
          </Pressable>
        ) : null}

        {session.error ? <Text style={styles.error}>{session.error}</Text> : null}
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
  delete: {
    paddingVertical: space.md,
    alignItems: 'center',
  },
  deleteLabel: {
    ...type.caption,
    color: colors.danger,
  },
  error: {
    ...type.caption,
    color: colors.danger,
    textAlign: 'center',
  },
});
