# Lemulip Product Story

Working reference for the next promotion pass, updated 29 October 2026. The public
download is **0.1.19 / build 22**. Product improvements in draft pull requests are
not part of that download. This document prepares the message; it is not a launch
announcement or a promotional-film storyboard.

## The Main Idea

**File tools, right where you drag.**

Lemulip brings local file tools to your Mac's desktop and Finder. Drag a file,
tap a key, and choose what happens next. Convert images, crop and trim media,
or arrange PDF pages. Workspace gives you another way to select files and tools.
Lemulip is free and open source, with no account or subscription.

**Turkish adaptation**

**Dosyanın olduğu yerde, ihtiyacın olan araç.**

Lemulip, dosya araçlarını Mac'inin masaüstüne ve Finder'a getirir. Dosyanı sürükle,
bir tuşa dokun, yapmak istediğin işlemi seç. Görselleri dönüştür, video ve ses
dosyalarını düzenle, PDF sayfalarını sırala. Dosyalarını ve araçlarını Çalışma
Alanı'ndan da seçebilirsin. Lemulip ücretsiz ve açık kaynaklıdır; hesap veya
abonelik gerektirmez.

Keep the drag, choice and useful result at the center of the presentation. The
three themes and the operation wheel give the product its own visual identity.
Explain a concrete job before listing the whole catalog.

## Three Released Workflows to Show

| Story | What to demonstrate | Proof and limits |
| --- | --- | --- |
| An image in the format you need | Drag a local HEIC or PNG, tap Shift, drop onto JPG, find the new copy | The existing [Finder recording](../site/assets/finder-conversion.mp4) shows a real conversion. [Its capture record](../site/assets/native-recording.json) records the source and processing. |
| Keep the useful part | Choose a video crop or audio range, inspect the selection, create the output | The gallery contains actual crop and waveform editors. Codec availability depends on the input and output; [the format guide](FORMATS.md) defines the routes. |
| Bring PDF pages together | Inspect the page list, arrange it, then create a new PDF | Merge and Organize are released. The newer ordering commands, numeric position entry and revised drag interaction remain pending in [PR #20](https://github.com/osmankaankars/lemulip/pull/20). |

Conversion outputs preserve the original. **Move To…** is a separate file action
that relocates the selected original; do not extend the conversion promise to
every action.

## Facts for Public Copy

| Fact | Source and wording boundary |
| --- | --- |
| macOS 13+, Apple silicon and Intel | [Installation](INSTALL.md), release metadata and verified universal packages. The download is a public preview. |
| 35 conversion output formats, 26 tools, 6 file actions | [The catalog](../site/catalog.js), generated from [native operations](../Sources/LemulipCore/Catalog.swift). These are output formats and catalog entries, not a claim that every input converts to every output. |
| Local processing | [The user guide](USER_GUIDE.md) and the native engines. Optional engine installation needs an internet connection; AirDrop sends files only when chosen. |
| Included image and media support | FFmpeg and ImageMagick ship with the Mac download. Pandoc and LibreOffice remain optional; describe that distinction when demonstrating advanced document routes. |
| Free and open source | [MIT license](../LICENSE), with [third-party notices](../THIRD_PARTY_NOTICES.md) for the bundled components. |

Use measured size figures only for the version available from the adjacent
download link. Candidate package savings belong in [the quality roadmap](ROADMAP.md)
until the smaller package is released. Do not claim instantaneous processing,
lossless output for every format, universal document fidelity, or customer usage
figures without evidence.

## Visual Assets

The existing screenshots are genuine native captures with source commit,
workflow, dimensions and hashes in [the screenshot inventory](../site/assets/screenshots.json).
Their 1020-pixel width supports a maximum 510 CSS-pixel presentation at two source
pixels per CSS pixel. The website and repository preview use that scale.

The next asset set must show the verified updated app, including one useful PDF
arrangement. Record the source commit, logical window size, actual pixel size,
capture method and hashes. A larger bitmap alone does not establish a fresh
high-density render. Retain the original captures; export web derivatives after
visual review. Do not generate, repaint or artificially sharpen product controls.

Prepare the social preview image from that final asset set. Keep a readable
headline, a real product moment and the existing brand; omit invented ratings,
customer logos and unsupported claims. No promotional video work starts yet.

## From the Website to the First Result

The primary download opens the verified version's DMG. The adjacent **Install &
first steps** link leads to [installation and a first conversion](INSTALL.md#try-your-first-conversion).
The built-in practice file lets someone try the Finder gesture immediately.
Workspace remains available when a source app cannot supply a compatible local
file drag. [Activity and troubleshooting](USER_GUIDE.md#if-something-fails) explain
where to look when a job needs attention.

## Before the Promotional Film

Complete the PDF interaction review, release the verified native changes and
smaller package, then update the real captures and public feature story to that
same version. Check the website's download and first-use path against the released
app. Only then choose the film's shot list and record the final workflows. The
film should show the product people can download at that moment.
