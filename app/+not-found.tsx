import { Link, Stack } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';

import { colors, space, type } from '@/design/tokens';

export default function NotFoundScreen() {
  return (
    <>
      <Stack.Screen options={{ title: 'Oops', headerShown: true }} />
      <View style={styles.container}>
        <Text style={styles.title}>This screen is not on the path.</Text>
        <Link href="/" style={styles.link}>
          <Text style={styles.linkText}>Back to CheckMed</Text>
        </Link>
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    alignItems: 'center',
    justifyContent: 'center',
    padding: space.xl,
    gap: space.md,
  },
  title: {
    ...type.title,
    textAlign: 'center',
  },
  link: {
    padding: space.md,
  },
  linkText: {
    ...type.body,
    color: colors.current,
  },
});
