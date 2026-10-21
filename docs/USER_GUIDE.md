# Using Lemulip

## Your First Conversion

Add local files with **⌘O**, drag them into Workspace, or use **Open With → Lemulip**. Choose an operation and review any options before creating the output.

## The Drag Wheel

Keep Lemulip running with **Drag Wheel Enabled**. Start dragging files on the desktop or in Finder, then tap **⇧ Shift** for formats, **⌘ Command** for tools, or **⌃ Control** for actions. Drop onto an operation. The center and outside of the wheel cancel without converting.

You do not need to hold the modifier key. Use Workspace or **Open Wheel** when a source app does not provide a compatible local-file drag.

## The Workspace

Add files, select an operation, and use the job queue. **Activity** shows current-session results and errors. Click an output to reveal it in Finder. The floating shelf keeps selected files close.

## Choose a Theme

**Settings → Appearance → Theme** offers Orchard Night, Vivid Pistachio, and Lemon Drop. The choice is remembered across the workspace, wheel, and editors.

## Set Options Before a Job

Editors and option panels open for operations that need a selection. **Create Copy** saves the result under an unused name.

### Visual Image Crop

Move and resize the crop selection, choose an aspect ratio, and review the composition before creating the copy.

### Audio Waveform Trim

Select a start and end point on the waveform. Play the selection before saving. **S/E** set boundaries and **Space** controls playback. Native export supports M4A, WAV, and AIFF where codecs allow; other routes use FFmpeg.

### Visual Video Trim

Preview the clip, set the start and end points, and create the shorter copy. Native export uses MP4 or MOV where supported.

### Visual Video Crop

Move the selection over the native preview and review output dimensions. Crop applies to the full clip and retains audio. Use Trim separately to shorten it.

### Organize PDF

Reorder page thumbnails, rotate or remove selected pages, and use Undo or Reset to revise the pending copy. **Extract Selected** exports the selection in displayed order; **Create Copy** saves the full arrangement.

### Merge PDF

Arrange documents using drag-and-drop or **Move Earlier / Move Later**. Page ranges update as documents move or are removed. **Create Copy** merges the retained documents while preserving text and vector content.

### PDF Compression

Compression creates a flattened image-based copy. Searchable text, links, forms, signatures, and accessibility structure are removed from that copy. The app asks for acknowledgement and keeps the original.

## Find Results and Manage Jobs

Activity lists completed outputs, notes, and errors for the current session. Preferences persist between launches; Activity does not.

### Choose an Output Folder

By default, a job saves beside its first input. PDF merge uses the first retained document in the arranged list. Disable **Save in the First File's Folder** to choose a destination per job.

### File Actions

AirDrop, floating shelf, copy, move, copy path, and opening the containing folder in Terminal are available in the Mac app. **Move To…** relocates originals. A partially failed copy or move keeps completed transfers; Activity lists them.

## Basic Office Exports

Microsoft Office is not required for conversion. Exact routes and supported subsets are in [Formats](FORMATS.md#documents-slides-and-spreadsheets).

### Create a Word Document

TXT, basic RTF, and supported Markdown can become DOCX with built-in writers. Supported RTF font and paragraph formatting is retained.

### Create an Excel Workbook

CSV or TSV becomes one XLSX worksheet. Every cell is stored as text, including leading zeros and formula-like strings. CSV and TSV can also be converted to each other.

## Convert HTML or Markdown to Word

Basic Markdown supports headings, flat lists, emphasis, code, and pipe tables. Richer Markdown uses Pandoc for the whole selection; mixing Markdown with other document types also uses Pandoc. HTML and complex RTF conversion use LibreOffice.

## Convert Existing Office Files

LibreOffice handles supported Word, Excel, and PowerPoint routes. Inspect important layout, fonts, and formulas after conversion. CSV/TSV exports contain the active sheet and do not preserve workbook formulas or formatting. [Formats](FORMATS.md#rich-office-conversion) records the limits; [Office Review](OFFICE_REVIEW.md) tracks target-app checks.

## Optional Engines

Install the required helper, then use **Settings → Local Engines → Refresh**. See [Installation](INSTALL.md#optional-engines). Lemulip does not install engines automatically.

## Command-Line Use

The app ZIP includes `lemulip`; local builds place it in `dist`. From source, use `swift run lemulip` instead of `./dist/lemulip`.

```bash
./dist/lemulip --help
./dist/lemulip list photo.heic
./dist/lemulip engines
```

### Convert and Combine

```bash
./dist/lemulip convert png photo.heic
./dist/lemulip run pdf.merge first.pdf second.pdf
./dist/lemulip run archive.createZip image.png notes.txt
```

### Use Operation Settings

```bash
./dist/lemulip run image.resize photo.jpg --size 1600
./dist/lemulip run pdf.extract report.pdf --pages 1,3-5
./dist/lemulip run media.trim clip.mp4 --start 5 --end 25
./dist/lemulip convert png "Sample photo.heic" --output "./Converted files"
```

`--output` takes an existing destination folder. Output paths go to standard output; errors and notes go to standard error. Native Apple converters require macOS. Portable routes can run on Linux, where the macOS helper sandbox is not applied.

## If Something Fails

Read Activity for the missing engine, codec, setting, or file limit. For a hidden wheel, check **Drag Wheel Enabled** and begin the drag before tapping a modifier.

Pandoc template errors usually require a build with embedded data files, such as its official installer. Protected PDFs require an unlocked copy; encrypted archives are rejected. Compression can produce a larger file when the source is already optimized.

Report the app and macOS versions, operation, input format, and error using a non-private sample. Security-sensitive findings belong in [private vulnerability reporting](../SECURITY.md).
