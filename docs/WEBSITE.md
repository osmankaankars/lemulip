# Website Brief

Updated 2 November 2026. Read this before changing `site/`, alongside [DESIGN.md](DESIGN.md) for shared direction and [MARKETING.md](MARKETING.md) for product facts. This brief preserves decisions across sessions; a new reference does not silently replace them.

## Purpose And Scope

The website is **Persuade**: help someone understand Lemulip’s drag interaction, see real results and choose the Mac download. Its character comes from the file, the wheel and the result. The native app is **Operate**: help someone finish a task with familiar platform behavior. Website styling is not an instruction to redesign the app. Product changes require their own review.

## Protected Choices

- Keep the genuine Lemulip icon and wordmark, platform sans-serif font system, and all three themes: **Orchard, Pistachio and Lemonade**. Preserve theme selection and contrast. A reference’s preferred font or palette does not override this identity.
- Keep the main line **“File tools. Right where you drag.”** Give its supporting sentence a concrete explanation. Retain the existing static HTML, CSS and JavaScript stack.
- Preserve **all nine sample families**: images, PDF, audio, video, documents, spreadsheets, presentations, subtitles and archives. Keep Desktop/Finder origins and Convert/Tools/Actions modes. The browser example uses sample state; it does not read, upload or convert visitors’ files.
- Preserve the genuine **2× native captures**: 1020 × 700 logical windows rendered at 2040 × 1400 pixels. Keep the gallery at **510 CSS pixels maximum**. Do not enlarge 1× captures, repaint controls, or replace them with invented interface art.
- Keep the verified **v0.1.20** [DMG](https://github.com/osmankaankars/lemulip/releases/download/v0.1.20/Lemulip-0.1.20-macOS-universal.dmg), release notes and installation links until their exact replacements are verified. Requirements remain macOS 13+, Apple silicon and Intel. Describe the download as a public preview where release status matters.
- Keep the real Finder recording distinct from the interactive example. **“Watch Mac recording”** opens that recording. The separately approved 25-second illustrated promotional film is a standalone advertising asset, not a Mac recording. Do not substitute it into the recording slot or autoplay its voiceover.
- Derive counts and capabilities from the native catalog. Local processing is the supported promise; optional engine installation and user-selected sharing have their documented network behavior. Conversion creates a new copy; **Move To…** explicitly relocates an original.

## Page Argument

The order is intentional:

1. **Hero and example:** explain dragging, tapping a key and choosing an operation. Show one primary **“Download for Mac”** action with requirements and installation help nearby.
2. **Compact key guide:** explain Shift/Convert, Command/Tools and Control/Actions once. This is an operating guide, not another set of slogans.
3. **Real gallery:** Workspace, PDF pages, Crop video and Trim audio show specific tasks. Captions explain the visible operation and useful result.
4. **Compact catalog:** show catalog-derived counts in the disclosure summary. Keep the detailed searchable directory behind its accessible disclosure, with clear empty-result recovery.
5. **Local processing and download:** state that processing happens on the Mac and repeat the same download label. Close with the real maker credit, source, guide and license links.

Each section must add information. Do not restore a separate large statistics section or expand compact supporting content simply to fill a template.

## Language And Motion

Supporting copy should read as ordinary English: name the file, operation, choice or output. Keep actual product terms consistent. Remove repeated promises, staged introductions, forced three-part phrasing and vague claims of effortless or revolutionary work. Do not manufacture warmth through slang, typos, testimonials, performance numbers or a founder story. Keep the owner’s preference against long dashes.

The example starts with the visitor. **Play runs one selected example and stops at its result**; replay and manual controls remain available, and the nine samples remain selectable. If Play is visible but most of the example is clipped, bring the example and Pause into view once. Leave an already framed example in place. Keep ordinary page and focus scrolling immediate so an earlier scroll cannot carry the example away after Play. Pause offscreen, and stop playback when the visitor takes over.

Keep the wheel as the focal movement, with short feedback and stable result states. Use transforms for cursor/drag movement and coalesce pointer updates. Reduced motion retains complete controls and understandable states. No new animation runtime, background video, remote font or decorative motion quota is required.

## Reference Roles

These are research snapshots, not dependencies or separate authorities over the brief.

| Role | Reference And Pinned Revision | Apply |
| --- | --- | --- |
| Plan | [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/tree/3a13158ff1f32156cbe144108de48eda2ecaed9a) | Product fit, information order, accessibility and existing-stack constraints. |
| Compose and build | [Taste](https://github.com/Leonxlnx/taste-skill/tree/12af471f627f866411b4bd785b19646d3672784c) | Product-specific idea, claim-and-proof sections, genuine assets and browser comparison. |
| Direct and review | [Impeccable](https://github.com/pbakaus/impeccable/tree/e89e3ada3e875a89ac2c5d33d11e65ebef6fe285) | Hierarchy, consistency, clarity and bounded quality review. |
| Finish | [Jakub Krehel](https://github.com/jakubkrehel/skills/tree/60bf140e43c98b248e6594487384ec967e89d98a) | Labels, typography, wrapping, focus and responsive interaction details. |

[Humanizer](https://github.com/blader/humanizer/blob/0ef9fe5bc3572734fd3ae6c448fe00a30cd5dcf0/SKILL.md) informs prose editing while preserving facts and deliberate brand language. It does not establish human authorship or an AI-detection score.

[iart’s motion collection](https://github.com/iart-ai/motion-skills/tree/238dfc55aac123d4649be39adfe58c43193ca349) and its [web pack](https://github.com/iart-ai/web-animation-skills/tree/b6dba3eb759726845a44163ff0bad70dd9e7fbb6) inform feedback, continuity and reduced motion. [MotionClone](https://motionclone.lol/agents) and [HyperFrames](https://github.com/heygen-com/hyperframes/tree/f6536e9f5deab41ffe30132543ed1586e2b16088) concern reference-led video production; they do not require website dependencies or migration of the approved film.

## Review And Later App Ideas

Inspect the actual desktop and mobile output, all themes and the changed interaction paths. Fix observed problems in one batch, then confirm. Technical checks and screenshots do not justify a fabricated quality score.

The current native captures and Swift source suggest three separate app follow-ups:

- **Workspace:** consider replacing repeated engine descriptions with useful output distinctions. Keep engine status visible when support needs installation. See `DashboardView.swift` and `LemulipCore/Catalog.swift`; search and pinning already exist.
- **PDF pages:** label the editable ordering field **Position**, with the original page number as secondary information. Consider moving the long shortcut explanation into contextual help. See `PDFOrganizeView.swift`; direct position entry, multiple selection and undo already exist.
- **Audio trim:** consider defaulting to the source format when it is supported. `AudioTrimView.swift` currently chooses the first available format, with M4A first, including for the pictured WAV source. Keep the existing 16-bit WAV/AIFF output limit explicit; matching the extension does not promise bit-for-bit preservation.

These are proposals for a later app review, not app changes or findings from running the macOS build.

