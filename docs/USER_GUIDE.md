# Using Lemulip

Lemulip has three ways to work: a wheel beside your drag, a regular workspace, and a command-line tool. They share the same conversion engine.

New here? [Install Lemulip](INSTALL.md) first. For specific input and output combinations, use the [format guide](FORMATS.md).

## Your First Conversion

Open Lemulip and add a small image with **⌘O**. Choose **Convert**, then a different format, such as PNG for a JPEG input. When the job finishes, open **Activity** and click its output to reveal it in Finder.

The original stays in place. The new file is saved in the first selected file's folder unless you change the output preference.

## The Drag Wheel

![Illustrated workflow: drag a file, tap Shift, and drop onto a format.](assets/workflow.svg)

With Lemulip running, begin dragging a local file in Finder. Press a modifier after the drag starts:

| Key | Menu | Typical Use |
| --- | --- | --- |
| **⇧ Shift** | Convert | Pick a new format |
| **⌘ Command** | Tools | Resize an image, split a PDF, trim media |
| **⌃ Control** | Actions | Copy, move, AirDrop, or open a file shelf |

Drop onto a segment to choose it. Releasing the modifier alone keeps the wheel open. The center is a cancel area. A drop outside the wheel submits no conversion, although the app underneath may handle that drop.

The menu follows the selected file types. Selecting unrelated types together may leave only archive tools and file actions. Scroll over the wheel to move through additional pages when available.

The current keys are fixed. You can pause the wheel using **Drag Wheel Enabled** in the menu bar, or **Settings → Drag Wheel**.

Finder drag behavior is still being tested across Mac setups and source applications. If a drag is not recognized, use the workspace.

## The Workspace

Use **Add Files**, **⌘O**, or drag files into the main window. You can also use Finder's **Open With → Lemulip**.

Choose **Convert**, **Tools**, or **Actions** above the operation cards. Removing a file from this selection does not delete it from disk. **Clear** empties the selection.

For jobs where order matters, use the up and down arrows beside each file. The displayed order controls PDF merges and the page order when combining images into a PDF.

**Open Wheel** opens a clickable version of the wheel for the current selection. In this mode:

| Control | Action |
| --- | --- |
| Arrow keys | Select an operation |
| Return | Choose the selected operation |
| Tab | Cycle Convert, Tools, and Actions |
| Page Up / Page Down | Change the menu page |
| Escape | Close the wheel |

## Set Options Before a Job

Some operations run as soon as you select them. Others open a panel with relevant settings and a **Create Copy** button.

| Tool | What to Set |
| --- | --- |
| Compress | Quality; PDF compression also has a maximum dimension |
| Resize | Maximum dimension in pixels; keeps the aspect ratio and does not enlarge smaller images |
| Crop | Exact width and height; the crop is centered |
| Rotate | 90°, 180°, or 270° clockwise |
| Trim | Start and end time in seconds |
| Extract PDF pages | Page numbers and ranges, such as `1,3-5,8` |
| Change speed | Playback multiplier from 0.5× to 4× |
| Adjust volume | Level from 0% to 300% |

PDF page numbers start at 1. Crop dimensions must fit within the image. Media tools require FFmpeg in the desktop interface.

### PDF Compression

This tool renders pages as images in a new PDF. Text selection, links, forms, signatures, and accessibility structure are lost in the output. The original remains untouched, and some files may become larger.

Select **Create a Flattened Copy** only when that result suits your purpose. To keep editable or searchable content, use another PDF operation.

## Find Results and Manage Jobs

Conversion jobs run one at a time in a queue. **Activity** shows waiting, running, completed, failed, and cancelled jobs.

Use the cancel button for a queued or running conversion. A failed or cancelled conversion attempt removes its temporary staging files. Completed outputs are revealed with the file and folder buttons.

**Clear Finished** removes completed entries from Activity. It does not delete outputs. Activity is kept in memory and is cleared when the app quits.

### Choose an Output Folder

In **Settings**, leave **Save in the First File's Folder** on to save all outputs of each job beside its first input. This also applies when inputs come from different folders.

Turn it off to choose a destination for each job. Existing files are not replaced; Lemulip chooses a new name. **Reveal Finished Files** controls whether Finder opens automatically after success.

### File Actions

**Copy To…** and **Move To…** ask for a destination. Move relocates your selected originals. Both choose unused names. If a multi-file transfer stops partway through, completed transfers remain in place and are listed in Activity.

**Float** keeps the selected files in a small shelf above other windows. **Copy Path** copies their absolute paths to the clipboard. **Terminal** opens the first selected file's containing folder, or the folder itself when selected. **AirDrop** opens the system sharing flow when available.

## Optional Engines

**Settings → Local Engines** shows which helpers Lemulip can find. Install the engines you need, then click **Refresh**. Installation instructions are in [Installation](INSTALL.md#optional-engines).

A dimmed operation or a dependency message means its helper is missing. It is not a paid feature. Available input codecs also depend on macOS and the installed helper's build.

The interface language can be changed between English and Turkish in **Settings → Language**.

## Command-Line Use

From a source checkout, prefix commands with `swift run`. A local app build also produces `dist/lemulip`, which runs directly:

```bash
./dist/lemulip --help
./dist/lemulip list photo.heic
./dist/lemulip list report.pdf --mode tools
./dist/lemulip engines
```

### Convert and Combine

```bash
./dist/lemulip convert png photo.heic
./dist/lemulip convert vtt subtitles.srt
./dist/lemulip run pdf.merge first.pdf second.pdf
./dist/lemulip run archive.createZip image.png notes.txt
./dist/lemulip run archive.extract example.zip
```

### Use Operation Settings

```bash
./dist/lemulip run image.resize photo.jpg --size 1600
./dist/lemulip run image.crop photo.jpg --width 1000 --height 1000
./dist/lemulip run pdf.extract report.pdf --pages 1,3-5
./dist/lemulip run media.trim clip.mp4 --start 5 --end 25
./dist/lemulip run media.speed clip.mp4 --speed 1.5
```

Use `--output` with an existing destination folder. Quote paths containing spaces:

```bash
./dist/lemulip convert png "Sample photo.heic" --output "./Converted files"
```

The command prints output paths. Errors and conversion notes go to standard error. Finder, shelf, and AirDrop actions are available only in the desktop app.

The desktop interface and Apple framework converters require macOS. Portable text and archive operations, plus supported external-engine routes, can also run on Linux. The macOS helper sandbox is not applied on Linux.

## If Something Fails

Read the message in Activity before retrying. It may identify a missing engine, unsupported codec, locked PDF, invalid setting, or file limit. [FAQ](FAQ.md) covers common cases.

For a bug report, include the Lemulip version, macOS version, input format, operation, and error text. Use a synthetic example when possible. Remove private paths and file contents before posting a log.
