import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { PhoneShell } from '@/design/PhoneShell';
import { colors } from '@/design/tokens';
import { SessionProvider } from '@/features/auth/session';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  useEffect(() => {
    SplashScreen.hideAsync();
  }, []);

  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: colors.canvas }}>
      <SafeAreaProvider>
        <SessionProvider>
          <PhoneShell>
            <StatusBar style="dark" />
            <Stack screenOptions={{ headerShown: false, animation: 'fade' }}>
              <Stack.Screen name="index" />
              <Stack.Screen name="(auth)" />
              <Stack.Screen name="(tabs)" />
              <Stack.Screen name="scan" options={{ presentation: 'modal', animation: 'slide_from_bottom' }} />
            </Stack>
          </PhoneShell>
        </SessionProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
