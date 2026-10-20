# Office Review

Inspect Lemulip's generated files in desktop Microsoft Word, Excel, and
PowerPoint on a Mac. The review archive contains eight actual conversion
outputs with small synthetic inputs. **Microsoft Office acceptance remains
Not Reviewed** until these comparisons are completed in the target apps.

## Get the Review Archive

Open the relevant **Build and Verify** run on
[GitHub Actions](https://github.com/osmankaankars/lemulip/actions/workflows/build.yml)
and download **Lemulip-Office-Review-arm64** from its artifacts. Extract the
enclosed ZIP and open the `Lemulip-Office-Review` folder. Use a completed run
whose artifact includes all eight cases.

The folder also contains this guide, `REVIEW_RESULTS.md`, `manifest.json`, and
`SHA256SUMS.txt`. Check the manifest's version and commit against the run you
intend to review. Keep the captured files together and unchanged.

## Review in the Target Apps

Use the desktop Microsoft apps, and record their actual versions in
`REVIEW_RESULTS.md`. If an app is unavailable, leave its cases as **Not
Reviewed**. A browser preview, another reader, or a passing automated test does
not complete this review.

Open the source and converted files side by side where both are supported.
All eight outputs should open without a file-repair prompt. Record any prompt
before accepting a repair. For edits, duplicate the converted file into a
separate working folder; keep the captured copies unchanged.

### Word: Text, Formatting, and Pages

Use **View → Print Layout** and the same zoom for the source and converted
documents. If Word hides the page margins, its
[margin-display instructions](https://support.microsoft.com/en-us/word/my-top-margin-is-missing)
explain how to show the white space again.

| Case | Files in `cases/` | What to Inspect |
| --- | --- | --- |
| `word-text` | `source.txt` → `converted.docx` | Paragraph and blank-line order, tabs, repeated spaces, literal `&` and `<Symbols>`, and readable `İstanbul • 東京`. This route adds no rich layout. |
| `word-rtf` | `source.rtf` → `converted.docx` | “Orchard Notes” stays centered, bold and italic in Arial 14 pt. “Second Paragraph” remains left-aligned in Arial 11 pt. Compare paragraph spacing and note any font substitution. Native RTF export does not reconstruct page layout or margins. |
| `word-layout` | `source.docx` → `intermediate.odt` → `converted.docx` | The source and converted Word documents both show two pages, with the explicit page break retained. Compare the heading, Unicode paragraph, two-by-two table, page margins, and second-page content. Nothing should be clipped, missing, or unexpectedly moved onto a third page. |
| `word-html` | `source.html` → `converted.docx` | “Orchard Notes” is a level-one heading. “bold phrase” and “italic phrase” retain their emphasis. `İstanbul · 東京 & < >` remains readable. The table has headers “Fruit” and “Count”, then “Lemon” and “12”; “After the Table” follows it. |
| `word-markdown` | `source.md` → `converted.docx` with the built-in writer | Check the same heading, emphasis, Unicode, and table as the HTML case. “Lemon” and “Pistachio” form a bulleted list; “First Step” and “Second Step” form a numbered list. The three-line code block keeps its literal text and spacing, as shown below. |

For `word-layout`, inspect the source and final DOCX first. The intermediate
ODT is included to help locate a difference if one appears. An installed-font
name in the file is only part of the check; look at the rendered text too.

For `word-html` and `word-markdown`, open the source in a text editor and inspect
the converted document in Word. Check that the title uses a heading style and
that lists remain lists, rather than text with manually typed markers. The HTML
source uses character entities; the Word output should show the decoded `&`,
`<`, and `>` characters, rather than their entity names.

The Markdown code block should appear on three lines exactly as follows:

```text
  keep  two spaces
    four spaces
**literal** <tag> & end
```

The first line begins with two spaces and also has two spaces between “keep”
and “two”. The second line begins with four spaces. The asterisks and angle
brackets on the last line remain literal code; they must not become emphasis
or disappear as markup. Check the table's two rows and two columns, then confirm
that “After the Table” is outside the table and follows it.

The HTML and Markdown sources contain no images, stylesheets, scripts,
hyperlinks, or external resources. They assess basic structure through
LibreOffice and Lemulip's built-in Markdown writer, respectively. Browser
layout and richer Markdown fallback through Pandoc are outside these comparisons.

### Excel: Literal Values and Recalculation

In `excel-text/converted.xlsx`, confirm there is one
**Sheet1**. Inspect the formula bar as well as the cells: `00123`, the complete
`12345678901234567890`, `_x0041_`, and `12/03/2026` remain literal text.
`=1+2` must display as text, rather than calculate to `3`. Compare the generated
`source.csv` in a text editor; importing that CSV into Excel can apply different
type guesses. Widen columns temporarily if a value is visually clipped.

In `excel-formulas`, compare `source.xlsx` with `converted.xlsx`. **Budget**
comes before **Summary**. Check the two-decimal number display, preserved text
identifiers, and the following values:

| Cell | Initial Value | After the Edit |
| --- | --- | --- |
| `Budget!B2` | 12.5 | Change this to 22.5 |
| `Budget!B3` | 7.5 | 7.5 |
| `Budget!B4` | 20, from `SUM(B2:B3)` | 30 |
| `Summary!A1` | 40, from `Budget!B4*2` | 60 |

Make the edit in a duplicate of `converted.xlsx`, then use Excel's **Calculate
Now** command to request recalculation. Microsoft documents this command in
[Updating Stale Values](https://support.microsoft.com/en-us/excel/stale-value-formatting).
Verify that both dependent cells update, and that their formulas remain
formulas. Record the result; discard the edited copy or save it under a new
name. This checks two representative expressions, not general Excel formula
compatibility.

### PowerPoint: Order and Appearance

Open `powerpoint-layout/source.pptx` and `converted.pptx`. Both contain two
widescreen slides: **Orchard Overview**,
then **Lemon Details**. Check Arial 24 pt text, complete titles, and the green
panel's size and position. The second slide's panel sits farther to the right.
Compare the source and converted presentation in editing view, then choose
**Slide Show → Play From Start** and inspect both full-size slides. See
Microsoft's [slide-show guide](https://support.microsoft.com/en-us/powerpoint/present-your-slide-show)
for the Mac controls. Look for clipped text, shifted shapes, and changed colors.

## Record the Outcome

Fill in `REVIEW_RESULTS.md`. Mark each case **Pass**
when its stated observations agree, **Needs Review** when an observed
difference needs explanation, or **Fail** when a repair prompt, lost
content, incorrect calculation, or clear layout defect appears. Add a short
observation and the affected page, cell, or slide for every non-passing result.
Leave cases you could not inspect as **Not Reviewed**.

Record the manifest commit and Microsoft app versions; macOS version is optional.
Omit account details, computer names, and local paths. Crop screenshots to the
generated document content. Capture and packaging do not upload the report.

Passing results apply to these examples and app versions. They do not establish
support for macros, charts, pivot tables, embedded objects, or animations.
