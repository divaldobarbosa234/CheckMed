import { Pressable, StyleSheet, Text, View } from 'react-native';

import type { OAuthProvider } from '@/features/auth/oauth';

import { colors, radii, space, type } from './tokens';

const LABELS: Record<OAuthProvider, string> = {
  apple: 'Continue with Apple',
  google: 'Continue with Google',
  facebook: 'Continue with Facebook',
};

type ProviderButtonProps = {
  provider: OAuthProvider;
  onPress: () => void;
  disabled?: boolean;
  busy?: boolean;
};

export function ProviderButton({ provider, onPress, disabled = false, busy = false }: ProviderButtonProps) {
  const locked = disabled || busy;
  const label = busy ? 'Please wait…' : LABELS[provider];

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={LABELS[provider]}
      accessibilityState={{ disabled: locked, busy }}
      disabled={locked}
      onPress={onPress}
      style={({ pressed }) => [pressed && !locked && styles.pressed, locked && styles.locked]}>
      <View style={[styles.base, styles[provider]]}>
        <Text style={[styles.label, provider === 'google' ? styles.labelInk : styles.labelLight]}>{label}</Text>
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
  apple: {
    backgroundColor: colors.apple,
  },
  google: {
    backgroundColor: colors.surface,
    borderWidth: 2,
    borderColor: colors.ink,
  },
  facebook: {
    backgroundColor: colors.facebook,
  },
  label: {
    ...type.button,
    textTransform: 'uppercase',
  },
  labelLight: {
    color: colors.primaryInk,
  },
  labelInk: {
    color: colors.ink,
  },
  pressed: {
    transform: [{ translateY: 2 }],
    opacity: 0.96,
  },
  locked: {
    opacity: 0.55,
  },
});
