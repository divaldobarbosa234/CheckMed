import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Character } from '@/design/Character';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, radii, space, type } from '@/design/tokens';
import { COMPANION_NAME } from '@/features/today/mockPath';

export default function TreatmentsScreen() {
  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      <Text style={styles.title}>Treatments</Text>
      <View style={styles.host}>
        <Character size={72} />
        <SpeechBubble text="This is where we organize what you verified. One mock treatment lives here until scan and editor land." />
      </View>
      <View style={styles.card}>
        <Text style={styles.cardEyebrow}>Active</Text>
        <Text style={styles.cardTitle}>Morning + evening routine</Text>
        <Text style={styles.cardBody}>
          Vitamin D · Metformin · Atorvastatin. Remaining days and the original document arrive with
          import. {COMPANION_NAME} will keep the path in order.
        </Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: colors.background,
    padding: space.lg,
    gap: space.lg,
  },
  title: {
    ...type.display,
    fontSize: 28,
  },
  host: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: space.md,
  },
  card: {
    backgroundColor: colors.surface,
    borderRadius: radii.lg,
    padding: space.lg,
    borderWidth: 2,
    borderColor: '#EFEFEF',
    gap: space.sm,
  },
  cardEyebrow: {
    ...type.caption,
    textTransform: 'uppercase',
    letterSpacing: 0.8,
    color: colors.primaryShadow,
  },
  cardTitle: {
    ...type.title,
  },
  cardBody: {
    ...type.body,
    color: colors.muted,
    lineHeight: 22,
  },
});
