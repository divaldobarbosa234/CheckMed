import { Pressable, StyleSheet, Text, View } from 'react-native';

import { colors, radii, space, type } from './tokens';

type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger';

type ButtonProps = {
  label: string;
  onPress: () => void;
  variant?: ButtonVariant;
  accessibilityHint?: string;
  disabled?: boolean;
  busy?: boolean;
};

export function Button({
  label,
  onPress,
  variant = 'primary',
  accessibilityHint,
  disabled = false,
  busy = false,
}: ButtonProps) {
  const isPrimary = variant === 'primary';
  const isGhost = variant === 'ghost';
  const isDanger = variant === 'danger';
  const locked = disabled || busy;

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityHint={accessibilityHint}
      accessibilityState={{ disabled: locked, busy }}
      disabled={locked}
      onPress={onPress}
      style={({ pressed }) => [pressed && !isGhost && !locked && styles.pressed, locked && styles.locked]}>
      <View
        style={[
          styles.base,
          isPrimary && styles.primary,
          variant === 'secondary' && styles.secondary,
          isGhost && styles.ghost,
          isDanger && styles.danger,
        ]}>
        <Text
          style={[
            styles.label,
            isPrimary && styles.labelPrimary,
            isDanger && styles.labelPrimary,
            variant !== 'primary' && variant !== 'danger' && styles.labelInk,
          ]}>
          {busy ? 'Please wait…' : label}
        </Text>
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  base: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 14,
    paddingHorizontal: space.xl,
    borderRadius: radii.pill,
  },
  primary: {
    backgroundColor: colors.primary,
    borderBottomWidth: 5,
    borderBottomColor: colors.primaryShadow,
  },
  secondary: {
    backgroundColor: colors.surface,
    borderWidth: 2,
    borderColor: colors.ink,
  },
  ghost: {
    backgroundColor: 'transparent',
    paddingVertical: 8,
  },
  danger: {
    backgroundColor: colors.danger,
    borderBottomWidth: 5,
    borderBottomColor: '#CC2F2F',
  },
  locked: {
    opacity: 0.55,
  },
  label: {
    ...type.button,
    textTransform: 'uppercase',
  },
  labelPrimary: {
    color: colors.primaryInk,
  },
  labelInk: {
    color: colors.ink,
  },
  pressed: {
    transform: [{ translateY: 3 }],
    opacity: 0.96,
  },
});
