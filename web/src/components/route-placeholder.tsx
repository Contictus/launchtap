import { EmptyState, UnavailableState } from "./primitives";

type RoutePlaceholderProps = {
  eyebrow: string;
  title: string;
  summary: string;
  unavailableTitle: string;
  unavailableDescription: string;
  emptyTitle?: string;
  emptyDescription?: string;
};

/** Task 2 route boundary: establishes stable navigation destinations without product flows. */
export function RoutePlaceholder({
  eyebrow,
  title,
  summary,
  unavailableTitle,
  unavailableDescription,
  emptyTitle,
  emptyDescription,
}: RoutePlaceholderProps) {
  return (
    <div className="page-stack">
      <section className="page-hero" aria-labelledby="route-placeholder-title">
        <div>
          <div className="section-kicker">{eyebrow}</div>
          <h1 id="route-placeholder-title">{title}</h1>
          <p className="hero-summary">{summary}</p>
        </div>
      </section>
      {emptyTitle && emptyDescription ? (
        <EmptyState title={emptyTitle} description={emptyDescription} />
      ) : null}
      <UnavailableState title={unavailableTitle} description={unavailableDescription} />
    </div>
  );
}
