# Impeccable evidence

This task uses a code-led Operate-mode workflow. The PNGs in `mocks/` are visual direction
references only; they are not pixel-fidelity acceptance targets. The final shell deliberately
translates the airline-ticket route idea into a dark, dense, trust-first operating surface.

The `review/` PNGs are the committed visual QA captures for the required 360px phone, tablet,
small-laptop, wide desktop, and reduced-motion states. The previous generated comp-diff report
and build-phase state were removed because they recorded a contradicted score and forced fidelity
gate, which must not be presented as acceptance evidence.

Task 4 discovery evidence is prefixed `task4-` and covers both `/` (Explore) and `/graduated`
at 360, 768, 1280, and 1440 pixels, plus reduced-motion captures at 1440 pixels. These images
were captured from the production build after commit `fe8ad51`; they intentionally show the
honest unavailable state because no reviewed public API configuration is present.
