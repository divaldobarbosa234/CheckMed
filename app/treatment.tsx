import { useRouter } from 'expo-router';

import { PlaceholderScreen } from '@/design/PlaceholderScreen';

export default function TreatmentScreen() {
  const router = useRouter();

  return (
    <PlaceholderScreen
      title="Treatment"
      bubble="This is the editor after you verify. Remaining days and the original document arrive with import."
      body="Phase 2 shell. Phase 3 stores treatments locally. Open a medicine to see the detail placeholder."
      primaryLabel="Open a medicine"
      onPrimary={() => router.push('/medicine/vitamin-d')}
      secondaryLabel="Back"
      onSecondary={() => router.back()}
    />
  );
}
