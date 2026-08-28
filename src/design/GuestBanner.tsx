import { Pressable, StyleSheet, Text, View } from 'react-native';

import { colors, fonts, radii, space, type } from './tokens';

type GuestBannerProps = {
  onCreateAccount: () => void;
};

export function GuestBanner({ onCreateAccount }: GuestBannerProps) {
  return (
    <View style={styles.banner} accessibilityRole="summary">
      <View style={styles.copy}>
        <Text style={styles.title}>Browsing as a guest</Text>
        <Text style={styles.body}>
          Create an account before a prescription photo or PDF can sync to the cloud.
        </Text>
      </View>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Create an account"
        onPress={onCreateAccount}
        style={styles.cta}>
        <Text style={styles.ctaLabel}>Sign in</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  banner: {
    backgroundColor: colors.guestBg,
    borderColor: colors.guestBorder,
    borderWidth: 2,
    borderRadius: radii.md,
    padding: space.md,
    flexDirection: 'row',
    alignItems: 'center',
    gap: space.md,
  },
  copy: {
    flex: 1,
    minWidth: 0,
  },
  title: {
    ...type.body,
    fontSize: 14,
  },
  body: {
    ...type.caption,
    marginTop: 2,
    color: colors.ink,
  },
  cta: {
    backgroundColor: colors.ink,
    borderRadius: radii.pill,
    paddingVertical: 8,
    paddingHorizontal: space.md,
  },
  ctaLabel: {
    fontFamily: fonts.rounded,
    color: colors.primaryInk,
    fontWeight: '800',
    fontSize: 13,
  },
});
