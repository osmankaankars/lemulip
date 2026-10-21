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

## Optional, Independently Installed Engines

Lemulip detects these tools if they are already installed. It neither downloads
nor bundles them. Their own licenses and notices apply to those installations:

| Engine | Project and licensing information |
| --- | --- |
| FFmpeg | <https://ffmpeg.org/legal.html> |
| ImageMagick | <https://imagemagick.org/script/license.php> |
| LibreOffice | <https://www.libreoffice.org/about-us/licenses/> |
| Pandoc | <https://pandoc.org/> and <https://github.com/jgm/pandoc/blob/main/COPYING.md> |

If distributing a modified application that bundles any of these engines, review
and satisfy the licenses of the exact binaries and codecs you distribute.

## Independent Implementation

Lemulip's application code, icon, and product artwork are original to this
project. Third-party components and optional engines are documented above.

## Website Illustrations

`site/assets/morning-light.jpg` is a generated fictional sample landscape made
for the Lemulip website. The feature previews are HTML/CSS illustrations using
that sample and synthetic data; they are not native app recordings.
`site/assets/sample-walk.mp4` is a four-second pan/zoom of that generated
landscape, used as a real playable sample clip. It is not a recording of the app.
`docs/assets/demo-preview.png` is the earlier illustrated product workspace
preview. None of these assets contains customer files or personal photographs.
