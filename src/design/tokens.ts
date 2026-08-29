import { Platform } from 'react-native';

export const colors = {
  canvas: '#D7F0C5',
  background: '#FFF8EE',
  surface: '#FFFFFF',
  primary: '#58CC02',
  primaryShadow: '#46A302',
  primaryInk: '#FFFFFF',
  ink: '#3C3C3C',
  muted: '#777777',
  locked: '#E5E5E5',
  pathLine: '#D4D4D4',
  current: '#1CB0F6',
  currentShadow: '#1899D6',
  done: '#58CC02',
  streak: '#FF9600',
  skip: '#FFC800',
  danger: '#FF4B4B',
  guestBg: '#FFF4CC',
  guestBorder: '#FFC800',
  super: '#CE82FF',
  safety: '#8A5A00',
  bubble: '#FFFFFF',
  cheek: '#FF8FAB',
  belly: '#E8FFD4',
  beak: '#FF9600',
  apple: '#000000',
  facebook: '#1877F2',
} as const;

export const space = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
} as const;

export const radii = {
  sm: 12,
  md: 16,
  lg: 22,
  pill: 999,
} as const;

export const fonts = {
  rounded: Platform.select({
    ios: 'ui-rounded',
    android: 'sans-serif-medium',
    web: 'Nunito, ui-rounded, system-ui, sans-serif',
    default: 'system-ui',
  }) as string,
};

export const type = {
  display: {
    fontFamily: fonts.rounded,
    fontSize: 34,
    fontWeight: '900' as const,
    letterSpacing: 0.2,
    color: colors.ink,
  },
  title: {
    fontFamily: fonts.rounded,
    fontSize: 22,
    fontWeight: '800' as const,
    color: colors.ink,
  },
  body: {
    fontFamily: fonts.rounded,
    fontSize: 16,
    fontWeight: '700' as const,
    color: colors.ink,
  },
  caption: {
    fontFamily: fonts.rounded,
    fontSize: 13,
    fontWeight: '700' as const,
    color: colors.muted,
  },
  button: {
    fontFamily: fonts.rounded,
    fontSize: 16,
    fontWeight: '800' as const,
    letterSpacing: 0.5,
  },
};

export const layout = {
  phoneMaxWidth: 430,
} as const;
