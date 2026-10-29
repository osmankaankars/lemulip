# Lemulip Design Direction

Updated 29 October 2026. This is the shared direction for the quality roadmap, the public website and the later promotional film.

## Character

Lemulip is a precise, lively Mac utility. The distinctive moment is a file becoming a choice: drag, tap a modifier, select an operation, find the result. Make that sequence feel immediate, fluid and tactile. The existing Lemulip icon, orchard green, pistachio and lemon palettes carry the identity.

The website is an invitation to experience that interaction. The app is a place to finish work. The same visual language serves both, with quieter feedback in frequently repeated native tasks.

## Type and Composition

- Use the platform sans-serif family. The large hero title introduces the product; section headings orient; ordinary sentence-case copy explains. Preserve macOS, product names, acronyms and filenames as written.
- Keep explanations specific: what the person can do, what changes, and where the output goes. Count formats and operations from the app catalog. Only describe released behavior as available to download.
- Give the demo one focal stage. Put deeper information behind clear, accessible disclosures. Each real screenshot needs a useful task and an appropriate display size.
- Keep the native interface readable at its intended size. Capture the running production view at genuine high density; record its revision and dimensions. An enlarged image is not a new Retina capture.

## Motion

**Focal moment:** the operation wheel opens around a file task, then the result appears as the next state of that same interaction. Keep all controls immediately usable, including cancel and another choice.

**Continuity:** manual screenshot changes dissolve within a stable frame. A catalog reveal introduces its contents without shifting or animating the whole page. Native PDF moves preserve selection identity and show the insertion location before committing.

**Feedback:** brief color/pressed states, a clear selected operation, visible output confirmation, and the optional native selection cue. Keyboard focus must remain on a useful control after each transition.

**Budget:** 120 ms control feedback; 180–280 ms routine reveals. Keep animation to the bounded demo, active screenshot or opened disclosure. Use existing CSS and native APIs, with no new animation runtime, continuous shader, background video or remote font. Stop automatic examples when hidden or offscreen. Reduce Motion removes the spatial transitions while retaining all states and controls.

## Finish and Marketing Readiness

Review a few complete scenarios in each theme and input mode. Check empty, loading, selected, invalid, canceled and finished states; labels, spacing and focus must tell the same story. Fix observed defects instead of treating a component inventory as proof of quality.

Before promotion, prepare a verified download, current genuine screenshots, an accurate feature description, and a concise first-run/install guide. Keep references in `docs/ROADMAP.md`, including the decision each one informed. The promotional film is the final stage, after these product and presentation decisions are in the released app.
