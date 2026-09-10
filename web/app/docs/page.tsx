import { RoutePlaceholder } from "@/components/route-placeholder";

export default function DocsPage() {
  return (
    <RoutePlaceholder
      eyebrow="Docs"
      title="Understand the route."
      summary="Contract, finality, custody, and risk guidance will live here as reviewed documentation."
      unavailableTitle="Documentation surface unavailable"
      unavailableDescription="The documentation route is reserved for the reviewed product and protocol guide."
    />
  );
}
