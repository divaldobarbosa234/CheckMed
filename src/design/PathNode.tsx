import { Pressable, StyleSheet, Text, View } from 'react-native';

import { colors, fonts, radii, space, type } from './tokens';

export type PathStatus = 'done' | 'current' | 'locked' | 'skipped';

export type PathNodeData = {
  id: string;
  time: string;
  medicine: string;
  status: PathStatus;
};

type PathNodeProps = {
  node: PathNodeData;
  offset: number;
  showConnector?: boolean;
  onTake?: () => void;
  onSkip?: () => void;
};

export function PathNode({ node, offset, showConnector = true, onTake, onSkip }: PathNodeProps) {
  const isCurrent = node.status === 'current';
  const ringColor =
    node.status === 'done'
      ? colors.done
      : node.status === 'current'
        ? colors.current
        : node.status === 'skipped'
          ? colors.skip
          : colors.locked;

  const glyph =
    node.status === 'done' ? '✓' : node.status === 'skipped' ? '–' : node.status === 'locked' ? '•' : '!';

  return (
    <View style={[styles.row, { marginLeft: offset }]}>
      <View style={styles.rail}>
        <View style={[styles.ring, { borderColor: ringColor, backgroundColor: isCurrent ? colors.current : colors.surface }]}>
          <Text style={[styles.glyph, isCurrent && styles.glyphCurrent]}>{glyph}</Text>
        </View>
        {showConnector ? <View style={styles.connector} /> : null}
      </View>
      <View style={styles.card}>
        <Text style={styles.time}>{node.time}</Text>
        <Text style={styles.medicine} numberOfLines={2}>
          {node.medicine}
        </Text>
        {isCurrent ? (
          <View style={styles.actions}>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={`Mark ${node.medicine} as taken`}
              onPress={onTake}
              style={({ pressed }) => [styles.take, pressed && styles.pressed]}>
              <Text style={styles.takeLabel}>Taken</Text>
            </Pressable>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={`Skip ${node.medicine}`}
              onPress={onSkip}
              style={({ pressed }) => [styles.skip, pressed && styles.pressed]}>
              <Text style={styles.skipLabel}>Skip</Text>
            </Pressable>
          </View>
        ) : (
          <Text style={styles.statusLabel}>
            {node.status === 'done' ? 'Logged' : node.status === 'skipped' ? 'Skipped' : 'Locked'}
          </Text>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: space.md,
    marginBottom: space.sm,
  },
  rail: {
    width: 64,
    alignItems: 'center',
  },
  ring: {
    width: 58,
    height: 58,
    borderRadius: 29,
    borderWidth: 6,
    alignItems: 'center',
    justifyContent: 'center',
  },
  glyph: {
    fontFamily: fonts.rounded,
    fontSize: 22,
    fontWeight: '900',
    color: colors.done,
  },
  glyphCurrent: {
    color: colors.primaryInk,
  },
  connector: {
    width: 6,
    flexGrow: 1,
    minHeight: 28,
    backgroundColor: colors.pathLine,
    borderRadius: 3,
    marginTop: 4,
  },
  card: {
    flex: 1,
    backgroundColor: colors.surface,
    borderRadius: radii.md,
    padding: space.md,
    borderWidth: 2,
    borderColor: '#EFEFEF',
  },
  time: {
    ...type.caption,
    color: colors.muted,
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  medicine: {
    ...type.title,
    fontSize: 18,
    marginTop: 2,
  },
  statusLabel: {
    ...type.caption,
    marginTop: space.sm,
  },
  actions: {
    flexDirection: 'row',
    gap: space.sm,
    marginTop: space.md,
  },
  take: {
    backgroundColor: colors.primary,
    borderRadius: radii.pill,
    paddingVertical: 10,
    paddingHorizontal: space.lg,
    borderBottomWidth: 4,
    borderBottomColor: colors.primaryShadow,
  },
  skip: {
    backgroundColor: colors.surface,
    borderRadius: radii.pill,
    paddingVertical: 10,
    paddingHorizontal: space.lg,
    borderWidth: 2,
    borderColor: colors.ink,
  },
  takeLabel: {
    ...type.button,
    color: colors.primaryInk,
  },
  skipLabel: {
    ...type.button,
    color: colors.ink,
  },
  pressed: {
    transform: [{ translateY: 2 }],
    borderBottomWidth: 2,
  },
});
