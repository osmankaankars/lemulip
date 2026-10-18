# Contributing

Useful contributions fix a reproducible problem, improve a conversion route,
or make the app easier to use. Start with the [User Guide](docs/USER_GUIDE.md)
and [Development Guide](docs/DEVELOPMENT.md).

## Report a Problem

Include the app version, macOS version, conversion or action, expected result,
and actual result. A small generated sample is ideal. Remove private filenames,
account details, and document content from screenshots and logs.

Use private vulnerability reporting for security-sensitive findings as described
in [SECURITY.md](SECURITY.md).

## Send a Change

Keep each pull request focused and explain why it is needed. For a larger
feature, open an issue first so the behavior and scope are clear. Be direct and
respectful in discussion.

Preserve originals during conversion, keep output creation non-overwriting,
and retain failure and cancellation cleanup. The explicit Move action is the
exception to preserving the input location. Optional engines use argument
arrays and restricted environments, never shell command strings.

Run the relevant checks in the development guide. Tests should exercise real
behavior and generate small inputs in a temporary directory. Do not commit
generated fixtures, build output, local debug files, or redundant tests that
only mirror the implementation.

AppKit and SwiftUI changes need a macOS build and a hands-on check. A Linux build
does not verify the desktop interface. Describe any checks you could not run.

Public documentation is in English. Changes to the app's English and Turkish
text should keep the two interfaces consistent.

Use Title Case for English headings, navigation, menu items, and action labels:
**Get Started**, **User Guide**, **Crop Image**, and **Create Copy**. Keep articles
and short prepositions lowercase within a title, as in **Save in the First
File's Folder**. Use sentence case for explanatory prose and error messages.
Preserve API names, format acronyms, command names, and identifiers exactly.
