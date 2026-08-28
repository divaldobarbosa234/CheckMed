import { StyleSheet, Text, View } from 'react-native';

import { colors, fonts, radii, space, type } from './tokens';

type SpeechBubbleProps = {
  text: string;
};

export function SpeechBubble({ text }: SpeechBubbleProps) {
  return (
    <View style={styles.wrap} accessibilityRole="text">
      <View style={styles.tail} />
      <View style={styles.bubble}>
        <Text style={styles.text}>{text}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    flexGrow: 1,
    flexShrink: 1,
    minWidth: 0,
    alignSelf: 'stretch',
  },
  bubble: {
    backgroundColor: colors.bubble,
    borderRadius: radii.lg,
    borderWidth: 2.5,
    borderColor: colors.ink,
    paddingHorizontal: space.lg,
    paddingVertical: space.md,
  },
  tail: {
    position: 'absolute',
    left: -8,
    top: 22,
    width: 16,
    height: 16,
    backgroundColor: colors.bubble,
    borderLeftWidth: 2.5,
    borderBottomWidth: 2.5,
    borderColor: colors.ink,
    transform: [{ rotate: '48deg' }],
    zIndex: 1,
  },
  text: {
    ...type.body,
    fontFamily: fonts.rounded,
    lineHeight: 22,
  },
});
