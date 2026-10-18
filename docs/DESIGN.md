# Design

Lemulip should feel lively, useful, and at home on a Mac. Choose from **Orchard
Night**, **Vivid Pistachio**, and **Lemon Drop**. Orchard Night is the default:
deep orchard-green surfaces, vivid lime accents, and warm white text. All three
themes share the dimensional folded-ribbon icon. Photos, pages, and waveforms
keep their own colors.

## Color System

| Role | Orchard Night | Vivid Pistachio | Lemon Drop |
| --- | --- | --- | --- |
| Canvas | `#14251D` | `#FFF9EB` | `#FFFAED` |
| Content Surface | `#1C3024` | `#FFFEF6` | `#FFFEF7` |
| Raised Surface | `#2C4331` | `#EDF1DC` | `#FFF0C0` |
| Main Text | `#F2F7E9` | `#173C2A` | `#3C3318` |
| Supporting Text | `#B5C7A5` | `#526448` | `#6E6040` |
| Links and Symbols | `#BDF620` | `#27591F` | `#76551C` |
| Primary Action Fill | `#BDF620` | `#BDF620` | `#FFDB23` |
| Text on Primary Actions | `#173C2A` | `#173C2A` | `#3C3318` |
| Borders | `#42583D` | `#D2DEC5` | `#E7D9B5` |
| Warm Accent | `#FF9C45` | `#FF9C45` | `#FF9C45` |

Use the bright fill for selection and the main action. Use each theme's
functional color for links and symbols, including the darker green and warm
brown on light surfaces. A bright brand color is not automatically a readable
text color.

Choose a native theme in **Settings → Appearance → Theme**. Selection applies
across the workspace, option panels, drag wheel, file shelves, and native
controls, and is remembered between launches. Orchard Night uses a dark system
appearance; Vivid Pistachio and Lemon Drop use a light one. Selection follows
the app preference rather than switching automatically with macOS. Missing or
unknown preferences use Orchard Night.

The website has a separate **Appearance** selector and remembers only that
selection locally when browser storage is available. Sample files and activity
are not saved. The web walkthrough is an illustrated simulation, not a native
app screenshot.

## Materials and Depth

Use Liquid Glass for navigation and controls above the content. Keep file lists,
editor canvases, and inspection details on legible content surfaces. Avoid nested
glass surfaces or a blur effect on every card. This follows Apple's
[Materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials)
and [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/).

The native navigation chrome uses SwiftUI's `glassEffect` when built with a
supporting toolchain and run on macOS 26 or later. Earlier systems use standard
material. Reduce Transparency and Increase Contrast use an opaque fallback.
Native Liquid Glass also responds to the system's Reduce Motion setting.
See [Applying Liquid Glass to Custom Views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

The website uses CSS to suggest the same hierarchy. It does not implement or
claim Apple's native rendering material.

## Icon

The green and cream folded-ribbon mark connects a sheet of paper to the motion
of the wheel. It should remain recognizable at small sizes without text or tiny
decorative details. The source artwork is original generated artwork; its
provenance is retained and its exact bytes are checked by the public-source
privacy guard.

`Resources/AppIcon.png` is the single master. The build script prepares the
required icon sizes and an ICNS with AppKit. The app ships the ICNS rather than
the source master. The website reuses the same master at deployment time.

This is a static dimensional icon. A layered Icon Composer asset with system
lighting and appearance variants remains a separate milestone, guided by
[Apple's App Icons guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons).

## Copy and Controls

- Use Title Case for English headings, navigation, and action labels:
  **Get Started**, **Choose Files**, **Create Copy**, **Play Selection**.
- Use sentence case for explanations and status messages.
- Name an action after its result. Keep keyboard focus visible and pair color
  with labels, symbols, or selection indicators.
- Let the wheel stand on its own. Keep its operation labels and essential mode
  controls, with no enclosing rectangular panel or repeated instruction below it.
  Retain nonvisual guidance for assistive technology.
- Label Office outputs by the application and format people recognize. Keep
  engine setup details in Settings, missing-engine help, and the format guide.
- Mark simulations and planned editors clearly. Show actual exported output
  before describing a capability as finished.

## Keep the App Small

The visual refresh adds no package dependency, embedded browser, 3D runtime,
continuous decorative animation, or background asset download. Icon rendering
happens during the build. Native material effects are limited to navigation.

Measure the compiled app's download size, installed size, idle memory, CPU, and
launch time before publishing performance claims. Targets and the editor work
are tracked in the [Roadmap](ROADMAP.md#keep-it-lightweight).

## Product Name

**Lemulip** is the product name. Use this spelling for the app, website,
documentation, and release titles. Use lowercase `lemulip` for the command-line
executable and repository name. **Orchard Night** names the default appearance;
it is not a second product name.

Use the approved folded-ribbon icon consistently. Credit **Kaan Kars** as the
creator and maintainer. Keep headings clear and let the name, color, and icon
carry the identity without repeating a slogan on every screen.

The rename preserves the existing preferences domain and repository history.
See [Installation](INSTALL.md#upgrading-from-freewheel) for existing app copies
and [Development](DEVELOPMENT.md#product-and-internal-names) for compatibility
identifiers.
