import { RoutePlaceholder } from "@/components/route-placeholder";

export default function CreatePage() {
  return (
    <RoutePlaceholder
      eyebrow="Create"
      title="Create a launch."
      summary="Prepare a fixed-supply token launch after deployment and wallet foundations are reviewed."
      unavailableTitle="Launch creation unavailable"
      unavailableDescription="Wallet readiness, contract configuration, and transaction simulation arrive in the next foundation task."
    />
  );
}
