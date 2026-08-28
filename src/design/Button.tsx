import { Pressable, StyleSheet, Text, View } from 'react-native';

import { colors, radii, space, type } from './tokens';

type ButtonVariant = 'primary' | 'secondary' | 'ghost';

type ButtonProps = {
  label: string;
  onPress: () => void;
  variant?: ButtonVariant;
  accessibilityHint?: string;
};

export function Button({ label, onPress, variant = 'primary', accessibilityHint }: ButtonProps) {
  const isPrimary = variant === 'primary';
  const isGhost = variant === 'ghost';

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityHint={accessibilityHint}
      onPress={onPress}
      style={({ pressed }) => [pressed && !isGhost && styles.pressed]}>
      <View
        style={[
          styles.base,
          isPrimary && styles.primary,
          variant === 'secondary' && styles.secondary,
          isGhost && styles.ghost,
        ]}>
        <Text
          style={[
            styles.label,
            isPrimary && styles.labelPrimary,
            variant !== 'primary' && styles.labelInk,
          ]}>
          {label}
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
