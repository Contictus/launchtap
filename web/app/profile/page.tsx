import { RoutePlaceholder } from "@/components/route-placeholder";

export default function ProfilePage() {
  return (
    <RoutePlaceholder
      eyebrow="Profile"
      title="Your signing context."
      summary="Wallet identity and account history remain user-controlled and will be added with the wallet foundation."
      unavailableTitle="Profile unavailable"
      unavailableDescription="No wallet is connected. Launchpad does not infer or create an account."
    />
  );
}
