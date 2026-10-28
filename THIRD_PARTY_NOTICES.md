# Third-Party Components

Lemulip's original source code is distributed under the MIT license in `LICENSE`.

## Components Provided by the Operating System

The macOS application links to Apple's AppKit, SwiftUI, Foundation, CoreGraphics,
ImageIO, PDFKit, Vision, AVFoundation, and related system frameworks. These are
provided by macOS and are not redistributed in Lemulip's source package.

The archive bridge links to the operating system's **libarchive** library. It
does not bundle a separate runtime implementation.

## Bundled Libarchive Declaration Headers

Some macOS SDKs omit libarchive's public declaration headers. Lemulip includes
the following two unmodified headers from **libarchive 3.5.3** in the private
`Sources/CLemulipArchive/LibarchiveHeaders/` directory. They provide compile-time
declarations only; the application continues to use the system library.

Upstream project: <https://github.com/libarchive/libarchive>.
Pinned commit: `673c1eae896c837081a627807b9d5e990684dbf7`.

| File | Original source | SHA-256 |
| --- | --- | --- |
| `archive.h` | <https://github.com/libarchive/libarchive/blob/673c1eae896c837081a627807b9d5e990684dbf7/libarchive/archive.h> | `82b8c029b3840bde2d7473449eb529a40ecb667ba0a502d56e8c25f5ecd88f35` |
| `archive_entry.h` | <https://github.com/libarchive/libarchive/blob/673c1eae896c837081a627807b9d5e990684dbf7/libarchive/archive_entry.h> | `159bb1114c55183b4e6193ca08d3cf29b33b3cc39fc86e880a9e4b969201aff4` |

The original copyright notices are:

```text
archive.h:
Copyright (c) 2003-2010 Tim Kientzle
All rights reserved.

archive_entry.h:
Copyright (c) 2003-2008 Tim Kientzle
Copyright (c) 2016 Martin Matuska
All rights reserved.
```

Both files use these BSD 2-Clause terms, retained in full in each header:

```text
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Conversion Engines

Mac release packages from 0.1.17 include standalone FFmpeg and ImageMagick helpers.
Their complete component notices, original source archives, build recipes and
architecture-specific build records are inside the app at
`Contents/Resources/EngineSupport/ffmpeg` and
`Contents/Resources/EngineSupport/imagemagick`.

The FFmpeg build enables GPL components including libx264; nonfree components
are disabled. ImageMagick includes separately licensed image codecs, including
LGPL libheif and libde265. Corresponding source and rebuild instructions are
provided for the complete helpers. These licenses apply to the included
components; Lemulip's original source remains under its MIT license.

LibreOffice remains independently installed. Pandoc can be downloaded from its
official GitHub release after explicit user approval and checksum verification.
No engine binary is committed to this source repository. Upstream references:

| Engine | Project and licensing information |
| --- | --- |
| FFmpeg | <https://ffmpeg.org/legal.html> |
| ImageMagick | <https://imagemagick.org/script/license.php> |
| LibreOffice | <https://www.libreoffice.org/about-us/licenses/> |
| Pandoc | <https://pandoc.org/> and <https://github.com/jgm/pandoc/blob/main/COPYING.md> |

The optional Pandoc installer uses the unmodified 3.12.1 archive. Its source and
license are available at <https://github.com/jgm/pandoc/tree/3.12.1> and
<https://github.com/jgm/pandoc/blob/3.12.1/COPYING.md>.

If distributing an application that bundles any of these engines, review
and satisfy the licenses of the exact binaries and codecs you distribute.

## Independent Implementation

Lemulip's application code, icon, and product artwork are original to this
project. Third-party components and optional engines are documented above.

## Website Illustrations

`site/assets/morning-light.jpg` is a generated fictional sample landscape.
`docs/assets/demo-preview.png` is an illustrated product preview.
`site/assets/app-*.webp` are actual Lemulip window captures from the native
macOS verification run recorded in `site/assets/screenshots.json`. The desktop
and window shadows are excluded; metadata is removed. No interface is generated
or repainted.

`site/assets/finder-conversion.mp4` is an actual, silent Finder-to-Lemulip screen
recording. Only the desktop edges are cropped; playback timing is not accelerated.
Its poster is extracted from the same recording. Capture and processing provenance
is in `site/assets/native-recording.json`.

The website's interactive Desktop and Finder demo uses sample data. It is separate
from the opt-in native recording in the same display area. These assets contain
only generated test files, not customer files or personal photographs.
