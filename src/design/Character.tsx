import { useEffect, useRef } from 'react';
import { Animated, Platform, StyleSheet, View } from 'react-native';

import { colors } from './tokens';

export type CompanionMood = 'idle' | 'celebrate' | 'skip' | 'complete';

type CharacterProps = {
  size?: number;
  mood?: CompanionMood;
};

export function Character({ size = 112, mood = 'idle' }: CharacterProps) {
  const bob = useRef(new Animated.Value(0)).current;
  const scale = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    const idle = Animated.loop(
      Animated.sequence([
        Animated.timing(bob, {
          toValue: -8,
          duration: mood === 'celebrate' ? 280 : 900,
          useNativeDriver: Platform.OS !== 'web',
        }),
        Animated.timing(bob, {
          toValue: 0,
          duration: mood === 'celebrate' ? 280 : 900,
          useNativeDriver: Platform.OS !== 'web',
        }),
      ]),
    );

    if (mood === 'celebrate' || mood === 'complete') {
      Animated.sequence([
        Animated.timing(scale, { toValue: 1.12, duration: 180, useNativeDriver: Platform.OS !== 'web' }),
        Animated.timing(scale, { toValue: 1, duration: 180, useNativeDriver: Platform.OS !== 'web' }),
      ]).start();
    }

    idle.start();
    return () => idle.stop();
  }, [bob, mood, scale]);

  const body = size;
  const eye = Math.max(10, size * 0.16);
  const pupil = eye * 0.45;

  return (
    <Animated.View
      accessibilityRole="image"
      accessibilityLabel="Phil, the CheckMed companion"
      style={{
        width: body,
        height: body * 1.12,
        transform: [{ translateY: bob }, { scale }, { rotate: mood === 'skip' ? '-8deg' : '0deg' }],
      }}>
      <View style={[styles.leaf, { left: body * 0.42, top: -size * 0.02 }]} />
      <View
        style={[
          styles.body,
          {
            width: body,
            height: body,
            borderRadius: body / 2.1,
            backgroundColor: colors.primary,
          },
        ]}>
        <View
          style={[
            styles.belly,
            {
              width: body * 0.62,
              height: body * 0.48,
              borderRadius: body,
              bottom: body * 0.12,
            },
          ]}
        />
        <View style={[styles.eyes, { top: body * 0.28 }]}>
          <Eye size={eye} pupil={pupil} />
          <Eye size={eye} pupil={pupil} />
        </View>
        <View style={[styles.beak, { top: body * 0.48 }]} />
        <View style={[styles.cheeks, { top: body * 0.46, width: body * 0.7 }]}>
          <View style={styles.cheek} />
          <View style={styles.cheek} />
        </View>
      </View>
    </Animated.View>
  );
}

function Eye({ size, pupil }: { size: number; pupil: number }) {
  return (
    <View style={[styles.eye, { width: size, height: size, borderRadius: size }]}>
      <View
        style={{
          width: pupil,
          height: pupil,
          borderRadius: pupil,
          backgroundColor: colors.ink,
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  leaf: {
    position: 'absolute',
    width: 18,
    height: 22,
    borderRadius: 10,
    backgroundColor: colors.primaryShadow,
    transform: [{ rotate: '-18deg' }],
    zIndex: 2,
  },
  body: {
    alignItems: 'center',
    overflow: 'hidden',
    borderBottomWidth: 6,
    borderBottomColor: colors.primaryShadow,
  },
  belly: {
    position: 'absolute',
    backgroundColor: colors.belly,
  },
  eyes: {
    position: 'absolute',
    flexDirection: 'row',
    gap: 14,
  },
  eye: {
    backgroundColor: '#FFFFFF',
    alignItems: 'center',
    justifyContent: 'center',
  },
  beak: {
    position: 'absolute',
    width: 0,
    height: 0,
    borderLeftWidth: 6,
    borderRightWidth: 6,
    borderTopWidth: 8,
    borderLeftColor: 'transparent',
    borderRightColor: 'transparent',
    borderTopColor: colors.beak,
  },
  cheeks: {
    position: 'absolute',
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  cheek: {
    width: 12,
    height: 8,
    borderRadius: 8,
    backgroundColor: colors.cheek,
    opacity: 0.85,
  },
});
