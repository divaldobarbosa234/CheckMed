import Ionicons from '@expo/vector-icons/Ionicons';
import { useRouter } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Character } from '@/design/Character';
import { GuestBanner } from '@/design/GuestBanner';
import { PathNode } from '@/design/PathNode';
import { SafetyCaption } from '@/design/SafetyCaption';
import { SpeechBubble } from '@/design/SpeechBubble';
import { colors, fonts, radii, space, type } from '@/design/tokens';
import { COMPANION_NAME, GUEST_GREETING, MOCK_STREAK_DAYS, PATH_OFFSETS } from '@/features/today/mockPath';
import { useTodayPath } from '@/features/today/useTodayPath';

export default function HomeScreen() {
  const router = useRouter();
  const path = useTodayPath();

  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <GuestBanner onCreateAccount={() => router.push('/(auth)/sign-in')} />

        <View style={styles.topRow}>
          <View>
            <Text style={styles.greeting}>{GUEST_GREETING}</Text>
            <Text style={styles.subtitle}>Today{"'"}s path with {COMPANION_NAME}</Text>
          </View>
          <View style={styles.streak} accessibilityLabel={`${MOCK_STREAK_DAYS} day streak`}>
            <Text style={styles.streakFlame}>🔥</Text>
            <Text style={styles.streakCount}>{MOCK_STREAK_DAYS}</Text>
          </View>
        </View>

        <View style={styles.host}>
          <Character size={96} mood={path.mood} />
          <SpeechBubble text={path.bubble} />
        </View>

        <View style={styles.progress}>
          <View style={styles.progressTrack}>
            <View
              style={[
                styles.progressFill,
                { width: `${Math.round((path.completed / path.total) * 100)}%` },
              ]}
            />
          </View>
          <Text style={styles.progressLabel}>
            {path.pathComplete ? 'Path complete' : `${path.completed} of ${path.total} today`}
          </Text>
        </View>

        <View style={styles.path}>
          {path.nodes.map((node, index) => (
            <PathNode
              key={node.id}
              node={node}
              offset={PATH_OFFSETS[index] ?? 0}
              showConnector={index < path.nodes.length - 1}
              onTake={path.takeCurrent}
              onSkip={path.skipCurrent}
            />
          ))}
        </View>

        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Scan a prescription"
          onPress={() => router.push('/scan')}
          style={({ pressed }) => [styles.scan, pressed && styles.scanPressed]}>
          <View style={styles.scanOrb}>
            <Ionicons name="camera" size={28} color={colors.primaryInk} />
          </View>
          <Text style={styles.scanLabel}>Scan</Text>
        </Pressable>

        <SafetyCaption />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scroll: {
    padding: space.lg,
    paddingBottom: space.xxl,
    gap: space.lg,
  },
  topRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  greeting: {
    ...type.title,
  },
  subtitle: {
    ...type.caption,
    marginTop: 2,
  },
  streak: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: radii.pill,
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    gap: 4,
    borderWidth: 2,
    borderColor: '#F3D7A0',
  },
  streakFlame: {
    fontSize: 18,
  },
  streakCount: {
    fontFamily: fonts.rounded,
    fontWeight: '900',
    fontSize: 18,
    color: colors.streak,
  },
  host: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: space.md,
  },
  progress: {
    gap: space.sm,
  },
  progressTrack: {
    height: 12,
    borderRadius: radii.pill,
    backgroundColor: colors.locked,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: colors.primary,
    borderRadius: radii.pill,
  },
  progressLabel: {
    ...type.caption,
  },
  path: {
    paddingTop: space.sm,
  },
  scan: {
    alignSelf: 'center',
    alignItems: 'center',
    gap: space.sm,
    marginVertical: space.sm,
  },
  scanOrb: {
    width: 72,
    height: 72,
    borderRadius: 36,
    backgroundColor: colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
    borderBottomWidth: 6,
    borderBottomColor: colors.primaryShadow,
  },
  scanPressed: {
    transform: [{ translateY: 3 }],
  },
  scanLabel: {
    ...type.button,
    color: colors.ink,
    textTransform: 'uppercase',
  },
});
