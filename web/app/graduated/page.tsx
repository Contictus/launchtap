import { RoutePlaceholder } from "@/components/route-placeholder";

export default function GraduatedPage() {
  return (
    <RoutePlaceholder
      eyebrow="Graduated"
      title="Graduated routes."
      summary="Review completed launch routes when the indexed deployment is connected."
      emptyTitle="No graduated routes yet"
      emptyDescription="Graduation history will appear here once the API is available."
      unavailableTitle="Graduated discovery unavailable"
      unavailableDescription="A reviewed API and deployment are required before graduated routes can be shown."
    />
  );
}
