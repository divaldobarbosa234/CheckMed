import { useLocalSearchParams, useRouter } from 'expo-router';

import { PlaceholderScreen } from '@/design/PlaceholderScreen';

export default function MedicineScreen() {
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id: string }>();

  return (
    <PlaceholderScreen
      title="Medicine"
      bubble={`This card is ${id ?? 'a medicine'}. How to take it, timeline, and the original prescription stay with the treatment you verified.`}
      body="Detail, how-to-take, and knowledge screens from principal screens stay shells until Phase 4. Not medical advice."
      primaryLabel="Back to treatment"
      onPrimary={() => router.back()}
    />
  );
}
