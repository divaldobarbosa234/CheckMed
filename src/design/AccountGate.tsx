import { StyleSheet, Text, View } from 'react-native';

import { Button } from './Button';
import { Character } from './Character';
import { SpeechBubble } from './SpeechBubble';
import { colors, radii, space, type } from './tokens';

type AccountGateProps = {
  visible: boolean;
  onCreateAccount: () => void;
  onDismiss: () => void;
};

export function AccountGate({ visible, onCreateAccount, onDismiss }: AccountGateProps) {
  if (!visible) return null;

  return (
    <View style={styles.overlay} accessibilityViewIsModal>
      <View style={styles.card}>
        <Character size={88} />
        <SpeechBubble text="An account keeps this prescription with you. Guest can browse Home — cloud scan waits for a real session." />
        <Text style={styles.title}>Account required to sync</Text>
        <Text style={styles.body}>
          Photo and PDF stay on this phone until you sign in. Then Phase 3 can sync to your CheckMed account.
        </Text>
        <Button label="Create account" onPress={onCreateAccount} />
        <Button label="Keep browsing as guest" variant="ghost" onPress={onDismiss} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  overlay: {
    ...StyleSheet.absoluteFill,
    backgroundColor: 'rgba(60, 60, 60, 0.45)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: space.lg,
    zIndex: 20,
  },
  card: {
    width: '100%',
    backgroundColor: colors.background,
    borderRadius: radii.lg,
    padding: space.xl,
    gap: space.md,
    alignItems: 'center',
  },
  title: {
    ...type.title,
    textAlign: 'center',
  },
  body: {
    ...type.body,
    color: colors.muted,
    textAlign: 'center',
    lineHeight: 22,
  },
});
