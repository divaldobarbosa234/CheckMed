import { useRouter } from 'expo-router';

import { PlaceholderScreen } from '@/design/PlaceholderScreen';

export default function ReviewScreen() {
  const router = useRouter();

  return (
    <PlaceholderScreen
      title="Review"
      bubble="You check every field. I never invent a medicine. Confirm is what turns a scan into today's path."
      body="Preview, raw text, and editable fields land in Phase 4. This shell keeps the click-through: Scan → Review → Treatment."
      primaryLabel="Continue to treatment"
      onPrimary={() => router.push('/treatment')}
      secondaryLabel="Back to scan"
      onSecondary={() => router.back()}
    />
  );
}
