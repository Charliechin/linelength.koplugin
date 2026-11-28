# Line Length: a line-length checker for KOReader

Shows how many characters are on a line of your book and whether that is a good length for reading:
**Excellent**, **Comfortable**, **Still readable** or **Too long**. Change the font size and the margins until
the line reads Excellent, without leaving the e-reader.

There is a [project page](https://charliechin.github.io/linelength.koplugin/) with a demo you can try in the browser.

- **Select a line.** The highlight dialog gets one extra button, `Line: 58 chars · Excellent`. Tap it for the details.
- **The whole page.** *Line length: this page* in the Typeset menu rates the longest lines on the page and has
  steppers for the margins and the text size, so you can adjust until it reads Excellent.

| <img src="docs/selection-dialog.png" width="400" alt="The selection dialog in KOReader with an extra last button reading Line: 56 chars, Excellent"> | <img src="docs/details-card.png" width="400" alt="The details card: 56 characters, Excellent, counts with and without spaces, words, and the four ranges"> |
|:---:|:---:|
| *The extra button in the selection dialog.* | *Its card: the counts and the four ranges, yours marked.* |
| <img src="docs/menu-item.png" width="400" alt="KOReader's Typeset menu with the last item, Line length: this page, highlighted"> | <img src="docs/page-card-controls.png" width="400" alt="The page card: 70 characters in the longest line, Comfortable, the three longest lines L5, L12 and L23 with 70, 66 and 64 characters, the four ranges, the Margins and Text size steppers at 10 and 22, and Cancel and Done buttons"> |
| *The whole-page mode starts from the Typeset menu.* | *The whole-page card with the steppers and buttons (L5 is the fifth line of the page). Drawn by a desktop build of KOReader at the Libra Colour's size, with sample text.* |

The first three are screenshots from a Kobo Libra Colour running KOReader v2026.07.2. The last one is drawn by a
desktop build of KOReader at the same size, with sample text.

## Why this exists

I wanted the lines of a book to land in the recommended range of characters per line. KOReader has no way to
show that number, so I used to retype a line into a word counter, read off the characters, go back to the
e-reader, change a setting and start again. This does the counting where the text is.

## Using it

**A line you select.** Long-press the first word of a line and drag to the end of it, then tap the last button in
the dialog. The card shows the count with and without spaces, the word count and the four ranges. Select one line;
in justified text the lines differ by a few characters, so check two or three.

**The whole page.** Open the Typeset menu and tap **Line length: this page** (it is also in the gesture list). The
card shows the longest line, its verdict and the three longest lines as `L5: start of the text … 54`, where `L5` is
the fifth line from the top of the page. The verdict is the longest line's, not an average: the last line of every
paragraph is short, so an average would say more about the paragraphs than about the lines.

Under the ranges are **Margins** and **Text size** steppers:

- **+** makes the lines shorter (wider margins, bigger text) and **−** makes them longer. A tap changes the text
  width by about 5%. The numbers are the ones in KOReader's Typeset menu, and the settings are saved with the book
  the same way.
- A tap shrinks the card to the number and the controls, so you can watch the page change. **Accept** keeps the
  change and shows the full card again; **Cancel** puts the margins and the text size back to how they were when
  you opened the card.
- On the full card, **Done** closes it and keeps the changes; **Cancel** closes it and puts everything back. The X
  and a tap outside the card keep the changes.
- Margins are the left and right ones together. A grey button has reached KOReader's limit.
- Changing a setting lays the whole book out again, so a long book can take a moment, and the page may start a
  little earlier or later. Cancel brings it back.
- In landscape the card has two columns, so that it fits the screen.

The number is for one page. Dialogue, indents and headings have other line lengths, so an Excellent line here is a
good start, not a guarantee. It works in books that reflow (EPUB, FB2 and the like), not in a PDF or a comic.

Thanks to the reddit user [Zanzel_Melancthones](https://www.reddit.com/user/Zanzel_Melancthones) for the suggestion to implement it this way.

## Tuning a book by itself

Three more entries in the Typeset menu:

- **Line length: this book (sample)** measures the longest line of a few pages of the book and
  reports the median, the shortest and the longest. The pages are read off screen, so the e-ink
  panel does not move and the reader keeps its place.
- **Line length: tune this book** moves the margins of the book until the lines hold the length the
  auto-tune aims for, and says what came of it.
- **Line length: settings** holds what the reader chooses for the tuning, below.

The sample and the tune are also actions, so they can be put on a gesture.

| Setting                     | What it means                                     | Default |
|:----------------------------|:--------------------------------------------------|--------:|
| Auto-tune when a book opens | tune the book when it is opened at its first page | off     |
| Smallest margin             | how narrow the margins may go                     | 10      |
| Biggest margin              | how wide the margins may go                       | 50      |

The size of the text is never touched: it is the reader's own, and the margins are what the length
of a line is made of. The top and bottom margins are left alone too: they change how many lines fit
on a page, not how many characters a line holds.

The rest of the tuning is the auto-tune's own: the band of line lengths it aims at (56 to 60
characters), the length it aims for inside the band (58 characters), the size of a step (6
characters) and the number of steps at most (6). The pages that are measured are the auto-tune's as
well: none at the start, six from the middle, none at the end. They live in the plugin, not in the
settings.

The margins are saved with the book, the way KOReader saves the margins a reader sets by hand, and
the book is tuned every time it is opened at its first page. A book that is already within the band
keeps the margins it has.

## What the ranges are

A character is a Unicode character of the line, including spaces and punctuation (`é` is one; invisible characters
are not counted). The ranges come from print typography and accessibility guidance on the length of a line:

| Characters | Verdict | Basis |
|---|---|---|
| under 50 | Short | Below the 50 where Baymard and Ruder start |
| 50–66 | Excellent | Ruder's 50–60 up to the 66 Bringhurst calls ideal |
| 67–75 | Comfortable | Inside Bringhurst's 45–75 and Baymard's 50–75, past the ideal |
| 76–80 | Still readable | Past 75, within the 80 of WCAG 1.4.8 |
| 81 and more | Too long | Over the 80 of WCAG 1.4.8 |

These are guidelines, not measurements of your reading, and the sources do not agree to the character. They are for
one column of Latin text: Bringhurst gives 40 to 50 for two columns (so a good two-column line shows as Short) and
WCAG gives 40 glyphs for Chinese, Japanese and Korean.

If a line ends in a hyphenated word, selecting snaps to the whole word, so the button counts all of it. The whole-page
check counts only the letters that are on that line.

On a colour screen with KOReader's colour rendering on, the number, the verdict and the ranges are drawn in the
Okabe–Ito palette, which stays distinguishable with common forms of colour blindness. Otherwise they are in the
normal text colour.

## Install

1. Download `linelength.koplugin.zip` from the [latest release](../../releases/latest) and extract it.
2. Copy the `linelength.koplugin` folder into KOReader's plugins folder (on a Kobo, `.adds/koreader/plugins/`) and
   restart KOReader.

It should work wherever KOReader runs, in black and white on a screen without colour, but only a Kobo Libra Colour
(firmware 4.45, KOReader v2026.07.2) has been tried.

**Upgrading from Word count.** Before version 0.7.0 this plugin was called Word count, in a folder named
`wordcount.koplugin`. Delete that folder before you copy the new one, or both load and everything shows up twice.
A gesture you set to *Line length: this page* keeps working.

## Development

```
python3 -m venv .venv && .venv/bin/pip install lupa
.venv/bin/python tests/run.py
```

That runs the unit tests; no Lua install is needed. The other tests in `tests/` need a desktop build of KOReader and
say how to run them in the header of each file.

## License

AGPL-3.0-or-later, the same as KOReader. See [LICENSE](LICENSE).

## Sources

- Robert Bringhurst, *The Elements of Typographic Style*, as quoted in [2.1.2 Choose a comfortable
  measure](http://webtypography.net/2.1.2): 45 to 75 characters is satisfactory for a single column, 66 is ideal,
  and 40 to 50 is better for multiple columns.
- Baymard Institute, [Readability: The Optimal Line Length](https://baymard.com/research-articles/line-length-readability):
  50–60 characters per line is optimal (Emil Ruder), and up to 75 is acceptable.
- W3C, [Understanding Success Criterion 1.4.8: Visual Presentation](https://www.w3.org/WAI/WCAG22/Understanding/visual-presentation.html):
  width is no more than 80 characters or glyphs (40 if CJK).
