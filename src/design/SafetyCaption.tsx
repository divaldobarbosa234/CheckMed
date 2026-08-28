import { StyleSheet, Text } from 'react-native';

import { colors, type } from './tokens';

export function SafetyCaption() {
  return (
    <Text style={styles.text} accessibilityRole="text">
      OCR is a reading aid. CheckMed never recommends medicines, dosages, or diagnoses.
    </Text>
  );
}

const styles = StyleSheet.create({
  text: {
    ...type.caption,
    color: colors.safety,
    textAlign: 'center',
    lineHeight: 18,
  },
});
