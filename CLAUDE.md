# Code Style

Build the simplest thing that works, with these constraints:

## Best Practices

Follow established best practices when they make the code or project simpler. Ignore them when they add complexity without benefit.

## Core Principles

- **No visual styling.** Don't add visual styles (padding, margin, colors, borders, shadows, fonts, etc.) — whether via Tailwind classes, inline styles, CSS, SVG positioning, or any other mechanism. Do not try to bypass this rule by moving style-like decisions into another format. Only use layout primitives: like `display`, `flex`, `grid`, `position`, `width`/`height`/`overflow` for structural layout. The user has their own taste and will style things themselves.
- **Single source of truth.** Define data, types, and configuration in one place. Derive everything else from the source. Use Pinia for shared state across components.
- **Direct mapping from input → actions.** Avoid intermediate representations unless they reduce total code and duplication.
- **Avoid encode/decode round-trips.** Don't transform data just to reconstruct it later. Keep information in the form that will be consumed.
- **Use recursion only when it simplifies code.**
- **Don't add structure for structure's sake.** Avoid unnecessary abstractions, boilerplate, and configuration layers. Components and modules are fine when they serve the UI.
- **No premature "robustness".** Skip heavy validation, performance optimizations, and edge-case handling unless asked. Let runtime errors throw naturally.
- **No backward compatibility by default.** Prefer deleting and rebuilding derived or local state over migrations or upgrade paths. Ask the user before adding compatibility work when it appears necessary.
- **Keep control flow obvious.** Minimal state, minimal branching, minimal helpers. Don't refactor for elegance if it adds indirection.
- **Fewer concepts over "best practices".** Output should be short and simple; prioritize fewer moving parts over convention.
- **If unsure between two implementations**, pick the one with fewer moving parts and less duplication, even if it's less general.
- **If adding a helper, encoding step, validation, or optimization doesn't remove more code than it adds, don't add it.**
- **TypeScript types at declaration site.** Define types at function signatures, API boundaries, and state initialization. Let TypeScript infer derived values.
- **No aria** Don’t add aria attributes for simplicity

See [design/00-code-style-examples.md](design/00-code-style-examples.md) for examples.

See [design/00-design-document-style.md](design/00-design-document-style.md) for design document guidance.
