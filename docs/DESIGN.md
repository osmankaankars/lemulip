# Design

Freewheel should feel bright, useful, and at home on a Mac. The visual direction
combines vivid pistachio and lime with warm neutral surfaces, a dimensional
folded-ribbon icon, and clear controls. Photos, pages, and waveforms keep their
own colors.

## Color System

| Role | Light Appearance | Dark Appearance |
| --- | --- | --- |
| Canvas | `#FFF9EB` | `#14251D` |
| Content Surface | `#FFFEF6` | `#1C3024` |
| Raised Surface | `#EDF1DC` | `#2C4331` |
| Main Text | `#173C2A` | `#F2F7E9` |
| Supporting Text | `#526448` | `#B5C7A5` |
| Links and Symbols | `#27591F` | `#BDF620` |
| Primary Action Fill | `#BDF620` | `#BDF620` |
| Text on Primary Actions | `#173C2A` | `#173C2A` |
| Warm Accent | `#FF9C45` | `#FF9C45` |

Use the bright fill for selection and the main action. Use the darker functional
green for small text on light surfaces. A bright brand color is not automatically
a readable text color.

The native palette follows the system appearance. The web walkthrough has an
intentional light product-page presentation; it is not a native app screenshot.

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
- Mark simulations and planned editors clearly. Show actual exported output
  before describing a capability as finished.

## Keep the App Small

The visual refresh adds no package dependency, embedded browser, 3D runtime,
continuous decorative animation, or background asset download. Icon rendering
happens during the build. Native material effects are limited to navigation.

Measure the compiled app's download size, installed size, idle memory, CPU, and
launch time before publishing performance claims. Targets and the editor work
are tracked in the [Roadmap](ROADMAP.md#keep-it-lightweight).

## Naming

Freewheel remains the repository and product identity while naming is explored.
A future name should be short, pronounceable, and checked against existing
products, projects, and registrations. A search without a match is not proof
that a name has never been used. Renaming will include a migration plan for
bundle identity, preferences, links, and existing installations.
