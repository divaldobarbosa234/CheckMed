import type { PathNodeData } from '@/design/PathNode';

export const MOCK_STREAK_DAYS = 3;
export const COMPANION_NAME = 'Phil';
export const GUEST_GREETING = 'Hey there';

export const MOCK_TODAY_PATH: PathNodeData[] = [
  {
    id: 'dose-1',
    time: '08:00',
    medicine: 'Vitamin D 1000 IU',
    status: 'done',
  },
  {
    id: 'dose-2',
    time: '13:00',
    medicine: 'Metformin 500 mg',
    status: 'current',
  },
  {
    id: 'dose-3',
    time: '21:00',
    medicine: 'Atorvastatin 20 mg',
    status: 'locked',
  },
];

export const PATH_OFFSETS = [0, 28, -8];
