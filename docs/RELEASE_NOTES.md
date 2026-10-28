# Release Notes

What's new in each Lemulip public preview. Release pages show the matching
version below, followed by the installation note.

## 0.1.17 · Ready For More Files

- Include FFmpeg and ImageMagick in the Mac download. No separate media or image engine installation.
- Install Pandoc from Settings with explicit approval and checksum verification.
- Show real conversion progress and retry failed or cancelled conversions with the same settings.
- Stop helper processes when a conversion is cancelled or times out.
- Check engine versions and supported codecs before conversion.
- Keep the CLI connected to the engines inside its neighboring Lemulip.app.
- Refresh the website and README with cropped, real Mac screenshots.

LibreOffice remains optional for richer Office conversions. Originals and saved settings are preserved.

## 0.1.16 · Easier to Navigate

- Give the manual wheel a readable selection and accessibility actions for choosing operations, modes, and pages. Use **Shift-Tab** to go back a mode.
- Make audio trim's **S/E** shortcuts follow the keyboard layout. Holding **Space** now changes playback only once per press.
- Give each file shelf's Finder button a clear action label with its file name.
- Restore the workspace's saved position and recover an unreachable window after a display changes.

No new app dependencies. Hands-on VoiceOver and multiple-display review remain pending.

[Workspace Guide](USER_GUIDE.md#the-workspace) · [Audio Trim Guide](USER_GUIDE.md#audio-waveform-trim)

## 0.1.15 · Markdown, Ready for Word

- Convert basic **Markdown → DOCX** without installing another engine.
- Keep editable headings, flat lists, tables, bold and italic text, and code spacing.
- Check the whole selection before export. Advanced Markdown continues through **Pandoc** when installed.

No new app dependencies. Visual review in Microsoft Office is still pending.

[Markdown Guide](USER_GUIDE.md#convert-html-or-markdown-to-word) · [Supported Formats](FORMATS.md#documents-slides-and-spreadsheets)

## 0.1.14 · HTML Notes, Ready for Word

- Fix **HTML and HTM → DOCX** conversion when LibreOffice opens the input as a web document.
- Improve export checks for headings, emphasis, Unicode, tables, and Markdown lists and code spacing.
- Add HTML and Markdown examples to the **Office Review** kit, now with eight generated comparisons.

HTML → DOCX requires **LibreOffice**; Markdown → DOCX requires **Pandoc**.
Visual review in Microsoft Office is still pending.

[HTML and Markdown Guide](USER_GUIDE.md#convert-html-or-markdown-to-word) · [Office Review](OFFICE_REVIEW.md)

## 0.1.13 · Simple Files, Ready for Office

- Create basic **DOCX** files from **TXT** or supported **RTF** using native macOS tools. Keep supported RTF font and paragraph formatting without installing Office or LibreOffice.
- Turn **CSV** and **TSV** into single-sheet **XLSX** workbooks. Cells stay as text, preserving leading zeros and keeping formula-like content literal.
- Improve compatibility with standard metadata in basic RTF documents while keeping that metadata out of the exported copy.
- Add six generated comparisons for reviewing Word documents, spreadsheets, and slides.

Rich Office conversions still use optional engines. Visual review and formula
recalculation in Microsoft Office are still pending.

[Office Export Guide](USER_GUIDE.md#basic-office-exports) · [Office Review](OFFICE_REVIEW.md)

## 0.1.9 · A Brighter First Impression

- Give the green and cream ribbon a warm white icon tile.
- Bring shared rounded branding to the workspace, Settings, and website.
- Clear the idle green wash from the drop area and improve the **Choose Files** keyboard hint.
- Refresh the product page, browser walkthrough artwork, and website appearance controls, including small-screen and high-contrast layouts.

**Orchard Night** stays the default. Your saved appearance and settings are retained.

[Appearance](USER_GUIDE.md#choose-a-theme)

## 0.1.8 · Bring Your PDFs Together

- Preview PDFs before merging, with a first-page thumbnail, page count, and output page range for each document.
- Drag documents into order or use **Move Earlier** and **Move Later**. Page ranges and the total update as you arrange them.
- Remove documents from the pending copy and revise your choices with **Undo**, **Redo**, and **Reset**.
- Use **Create Copy** to merge the retained documents, preserving text and vector content while leaving the originals unchanged.

[PDF Merge Guide](USER_GUIDE.md#merge-pdf)

## 0.1.7 · Put Every Page in Place

- Open a PDF as page thumbnails. Drag pages into order or use **Move Earlier** and **Move Later**.
- Select several pages to rotate or remove from the copy. Revise the arrangement with **Undo** and **Reset**.
- Use **Extract Selected** to save selected pages in their displayed order, or **Create Copy** to export the whole arrangement.
- Keep the original pages' text and vector content through native macOS tools. Your source PDF stays unchanged.

[PDF Organizer Guide](USER_GUIDE.md#organize-pdf)

## 0.1.6 · Frame It Your Way

- Crop a video with a movable selection over its native preview, familiar aspect ratios, and visible output dimensions.
- Apply the selected frame to the full clip while retaining its audio. Use **Trim** separately to shorten the video.
- Save a new **MP4** or **MOV** with native macOS tools, leaving the original unchanged.
- Use crop controls and keyboard movement consistent with the image editor, in any of Lemulip's three appearances.

[Video Crop Guide](USER_GUIDE.md#visual-video-crop)

## 0.1.5 · Watch What You Keep

- Trim video in a native preview with a thumbnail strip, range handles, editable timestamps, and a visible selected duration.
- Seek through the clip and use **Play Selection** to watch your chosen range before saving.
- Export a new **MP4** or **MOV** using native macOS tools, preserving the source orientation and original file.

Export re-encodes the selection; media boundaries can affect its exact duration.

[Video Trim Guide](USER_GUIDE.md#visual-video-trim)

## 0.1.4 · Three Themes, Visual Crop, and Audio Trim

- Choose **Orchard Night**, **Vivid Pistachio**, or **Lemon Drop**. Lemulip remembers your appearance across the workspace, wheel, and editors.
- Crop an image with a visible selection, resize handles, aspect ratios, and precise pixel dimensions.
- Trim audio with a waveform, range handles, editable timestamps, and **Play Selection** before saving.
- Create a new **M4A**, **WAV**, or **AIFF** from the selected audio range using native macOS tools. Your original stays unchanged.

[Image Crop Guide](USER_GUIDE.md#visual-image-crop) · [Audio Trim Guide](USER_GUIDE.md#audio-waveform-trim)

## Installation

macOS 13+ · Apple Silicon and Intel. Download the DMG or app ZIP under **Assets**.

[Installation Guide](INSTALL.md#first-launch) · [User Guide](USER_GUIDE.md) · [Full Changelog](RELEASE_NOTES.md)
