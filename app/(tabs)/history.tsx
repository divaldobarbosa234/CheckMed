import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Character } from '@/design/Character';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, radii, space, type } from '@/design/tokens';

export default function HistoryScreen() {
  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      <Text style={styles.title}>History</Text>
      <View style={styles.host}>
        <Character size={72} />
        <SpeechBubble text="Taken days count for the streak. Skip does not break it. Missed will — when real logs land." />
      </View>
      <View style={styles.card}>
        <Text style={styles.time}>Today · 08:00</Text>
        <Text style={styles.item}>Vitamin D 1000 IU</Text>
        <Text style={styles.status}>Taken</Text>
      </View>
      <Text style={styles.empty}>Later doses appear here after you tap Taken or Skip on Home.</Text>
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
  },
  time: {
    ...type.caption,
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  item: {
    ...type.title,
    marginTop: 4,
  },
  status: {
    ...type.body,
    color: colors.primaryShadow,
    marginTop: 6,
  },
  empty: {
    ...type.caption,
    lineHeight: 18,
  },
});
