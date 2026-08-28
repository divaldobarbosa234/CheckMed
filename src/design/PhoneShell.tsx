import type { ReactNode } from 'react';
import { StyleSheet, View } from 'react-native';

import { colors, layout } from './tokens';

type PhoneShellProps = {
  children: ReactNode;
  backgroundColor?: string;
};

export function PhoneShell({ children, backgroundColor = colors.background }: PhoneShellProps) {
  return (
    <View style={styles.canvas}>
      <View style={[styles.phone, { backgroundColor }]}>{children}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  canvas: {
    flex: 1,
    backgroundColor: colors.canvas,
    alignItems: 'center',
  },
  phone: {
    flex: 1,
    width: '100%',
    maxWidth: layout.phoneMaxWidth,
    overflow: 'hidden',
  },
});
