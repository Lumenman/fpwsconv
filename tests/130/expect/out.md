<!-- Revised by Robert J. Sawyer on Tuesday, December 26, 2023 -->

**LJ6DTP**

**LJ6DTP**

█████████████████████████████████████████████████████████████████

**A Desktop-Publishing PDF for**

**LaserJet Printers**

**For WordStar for DOS 6.0 and 7.0**

█████████████████████

███████████

Manual Copyright ☻ 1990 and 1997 by Robert J. Sawyer

WordStar PDF for LaserJet 4 originally modified by **Robert J. Sawyer**

PDF updated for LaserJet 5 and 6 by **Karl Fuss**

Documentation by **Robert J. Sawyer**

sawyer@sfwriter.com

█████████████████████████████████████████████████████████████████

Features

This manual describes a Printer Description File for WordStar for DOS 6.0 and 7.0 that gives 
easy access to several features of HP LaserJet printers:

- proper quotation marks
- special symbols (em dash, en dash, ellipsis points, copyright symbol)
- gray scaling
- HP graphics patterns
- printing white text on a black background
- kerning of lowercase letter pairs

Files

This package consists of two files:

| LJ6DTP.DOC | This manual |
|---|---|
| LJ6DTP.PDF | A specially modified WordStar PDF |

Using LJ6DTP.PDF

This PDF can be used with WordStar 6.0 and 7.0, but only modified with WordStar 7.0 
Revision D. It should work well with any printer that emulates the HP LaserJet 4, LaserJet 5, 
LaserJet 6, or greater printers, and for printing to disk for conversion to Adobe Acrobat PDF 
(Portable Document Format) files via **PrintFilePrinter** (which you'll find in 
C:\WS\PrintFilePrinter). Print out this document, then compare the contents of this file to the 
printout to see how the effects were accomplished.

---

<!-- Header: LJ6DTP Desktop-Publishing PDF ∙ # -->

By default, WordStar is set up to use the PC-8 IBM extended-character set. Unfortunately, the 
single open quote (reverse apostrophe) and single close quote (apostrophe) characters in the 
PC-8 symbol set are truly ugly. The open quote is a diagonal straight line and the close quote 
is a vertical straight line. This makes it impossible to double these characters up to make 
proper double open and close quotes.

However, the LaserJet 4 and above printers contain several symbol sets, including some that 
do have attractive single open and close quotes that are mirror images of each other _ ideal 
for making proper quotation marks. For instance, in the DeskTop symbol set, these characters 
look like this:

`

'

WordStar's PDFEDIT (Printer Description File editor) allows you to mix and match characters 
from various symbol sets. In the accompanying PDF, we've replaced the ugly PC-8 single 
quotes with the elegant ones from the DeskTop symbol set. (Except for the modifications 
described herein, this is simply a standard WordStar 7.0 LaserJet 4P PDF.)

Unfortunately, you can't just swap one character for another and expect right justification to 
still work. You also have to patch the proportional spacing tables for the PDF to use the 
appropriate values from the other symbol set. We've done this as well in this PDF.

Finally, to be able to double up these single quote characters to get attractive double quotes, 
the pairs should be kerned (tucked closer together), so we've also added these two pairs to the 
PDF kerning tables:

``

''

Now, when kerning is on, which is the default (although you can set it specifically to on or off 
with the .KR dot command, as I did for the examples below), those pairs will look great:

``These quotation marks are too loose because kerning is turned off.''

``But these quotation marks are just right because kerning is turned on.''

Using the same techniques of (1) character-set translation, (2) character substitution, and (3) 
adjusting proportional-spacing tables, we've added several other characters to this PDF that are 
useful for desktop publishing:

---

| ☻ | copyright symbol (some fonts only) |
|---|---|
| ☼ | ellipsis points |
| _ | em dash (long dash) |
| ≡ | en dash (short dash) |
| « | double open quotes (individual character) |
| » | double close quotes (individual character) |
| ♥ | upper-left rounded box corner (Univers only) |
| ♦ | upper-right rounded box corner (Univers only) |
| ♣ | lower-left rounded box corner (Univers only) |
| ♠ | lower-right rounded box corner (Univers only) |

Note that we've only made these substitutions in the proportional fonts; we've left the 
fixed-width fonts Courier, Letter Gothic, and Line Printer unmodified.

You can use either two single quotes or one double quote character, but I don't recommend 
mixing them in the same document, since the spacing between the two single quotes might not 
exactly match that between the two components of the double-quote character.

The copyright symbol comes from the PS Math symbol set. That symbol set actually contains 
two different copyright symbols. Hex character E3 has a sans-serif *C* in the center of the 
circle, like this: ☻.  We've mapped that one into the Arial, Omega, and Univers fonts. And 
hex character D3 has a serif *C* in the center of the circle, like this: ☻. We've mapped that one 
into the Times and Times New Roman fonts. ***Note:*** The use of the copyright symbol is only 
supported in the following typeface families: Arial, Omega, Times, Times Roman, and 
Univers (we've mapped a copyright symbol to character position 02 in all the typefaces, but 
WordStar will not accept a proportional-spacing value there in the other typefaces).

To access the special characters in LJ6DTP.PDF refer to the following chart.

**You type Shows on screen as Prints as**

^P02<Enter> ☻ ☻ copyright symbol

^P03<Enter> ♥ ♥ upper-left rounded box corner

^P04<Enter> ♦ ♦ upper-right rounded box corner

^P05<Enter> ♣ ♣ lower-left rounded box corner

^P06<Enter> ♠ ♠ lower-right rounded box corner

^P015<Enter> ☼ ☼ ellipsis points

' (apostrophe) ' ' single close quote

_ (underscore) _ _ em dash

` (single open quote) ` ` single open quote

^P0174<Enter> « « double open quote

^P0175<Enter> » » double close quote

^P0240<Enter> ≡ ≡ en dash

---

Note that WordStar's Advanced Page Preview knows nothing about these character 
substitutions, so you won't see the special characters until you actually print your document.

Kerning Lowercase Letter Pairs

As distributed, WordStar's WINSTALL.EXE only installs kerning values greater than ±7, 
which means no lowercase letter pairs (such as «wo») get kerned. Kerning tables take up a lot 
of room in the PDF, which is why WordStar sets the threshold value so high. But for three 
typeface families _ Optima, Times, and Univers _ we've installed all kerning values greater 
than ±2. Use these typefaces when you want kerning of lowercase letter pairs.

That Box Around The Front Page

Hey! How, you might ask, did I get that nifty box outline around these pages? That was done 
using WordStar custom print controls (of the type created with the ^P! command) that contain 
code in Hewlett-Packard's PCL printer-control language. The tag is included on each page of 
this document; the first one is on page 1, line 11).

The tag was produced with **LSRBOX** utility, which I also wrote. You'll find it in 
**C:\WS\LSRBOX** (and the documentation there will show you some super-powerful things you 
can do with WordStar's merge-print capability _ WordStar *invented* merge printing). 
LSRBOX can do a lot of things with lines and boxes, such as creating the racing-stripe design 
below:

---

«Color» Mappings

WordStar's ^P- menu lists colors. For the LaserJet 4 and above, these colors have been 
mapped to gray-scale shading values and fill patterns. The PDFs that accompany this manual 
were created with WordStar 7.0 Rev. D and use the color-mapping scheme below (note that 
WordStar's Advanced Page Preview will still show shadings as different colors).

Here are the mappings available with this PDF. The samples were created by printing nine 
solid blocks using character 219 from WordStar's ^P0 Extended Characters Menu, but you can 
apply these special effects to plain text, too.

| Black | █████████ |
|---|---|
| Shading 85% | █████████ |
| Shading 75% | █████████ |
| Shading 50% | █████████ |
| Shading 25% | █████████ |
| Shading 15% | █████████ |
| Shading   5% | █████████ |
| Shading   2% | █████████ |
| Black | █████████ |
| HP1 - | █████████ |
| HP2 \| | █████████ |
| HP3 / | █████████ |
| HP4 \ | █████████ |
| HP5 + | █████████ |
| HP6 X | █████████ |
| White | █████████ |

---

White Text on a Black Background

To print white text on a black background, first you have to make the black background. From 
the ^P- menu, select «Black.» Then select a font with which to draw the background. The font 
used for the background should be of a bigger point size than the text that will appear in the 
foreground. You'll have to experiment a bit to get it just right, but I find that a font two points 
larger than what you plan to use for the white text is usually a good starting place.

Use character decimal 219 (the solid block, █ ) to draw the background. You can enter this 
character from WordStar's ^P0 Extended Character Menu. (If you plan to do a lot of 
white-on-black text, you may find it simplest to program a function key to issue this character.) 
Draw the background by repeatedly entering this character (or enter it once, delete it with ^T, 
then repeatedly unerase it with ^U). Note the inches indicator in the status line _ it will tell 
you how long your background will be. Now, issue WordStar's Overprint line command 
(^PM). If you've done this correctly, a «-» will show in the flag column.

Now select «White» from the ^P- menu. Select an appropriate font for your text (remember, it 
should be a smaller point size than what you used for the background) and type away. When 
finished, select «Black» from the ^P- menu (otherwise the rest of your text will be invisible _ 
white letters on a white background). You may want to adjust the background length, or center 
both the background and foreground, like so:

█████████████████

**White Text on a Black Background _ *Wow!***

If you want a full line of black that is precisely the length of your ruler line, you can do the 
black background in two parts that overlap. Do some on one line, issue the overprint line 
command, insert a flush-right command (^O]), then create the rest of the black background. 
Overprint again for the white text line. Here's a sample using that technique:

████████████████████████

████████████████████████

**WordStar for DOS is a perfect word processor for touch typists _ your fingers never leave the home row!**

And if you want a background that's somewhere between one and two lines high, overprint 
two lines of █ characters made with one of the two *non-scalable* Courier typefaces we've 
installed into this PDF _ either COURIER PC 10 or COURIER PC 12 (10 or 12 characters 
per inch, respectively), and superscript the second line the appropriate amount: 

███████████████████████

^███████████████████████^

PRETTY NEAT, HUH?

(WordStar reduces the point size for superscripted *scalable* fonts; you must use the special 
non-scalable COURIER PC 10 or COURIER PC 12 choices from the ^P= menu if you want 
to use superscript or subscript rolling without the font size also being reduced.)

You can use a similar technique to get black text on a gray-scaled backgrounds:

████████████

Black Text on a Gray Background

---

Proportional Spacing Tables

The proportional-spacing values installed in this PDF for the substituted characters appear 
below. Blank entries were left at their default PC-8 values; italicized lines have all values 
identical to those in the preceding line. Symbol sets are DeskTop (DT), MS Publishing (PB), 
Pi Font (PI), and PS Math (PS). All copyright symbols are taken from the PS Math symbol 
set: Arial, Omega, and Univers use the sans-serif version, which is character E3; Times and 
Times New Roman use the serif version, which is character D3.

| PC-8: | 02 | 03 | 04 | 05 | 06 | 0F | 27 | 5F | 60 | AE | AF | F0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| On-screen: | ☻ | ♥ | ♦ | ♣ | ♠ | ☼ | ' | _ | ` | « | » | ≡ |
| Char. Set: | PS | PI | PI | PI | PI | DT | DT | DT | DT | DT | DT | DT |
| Substituted: |  | 62 | 72 | 63 | 73 | AC | 27 | AB | 60 | B0 | B1 | AA |
| Albertus |  |  |  |  |  | 8294 | 2765 | 8294 | 2765 | 4716 | 4716 | 5529 |
| Albertus Ital |  |  |  |  |  | *8294* | *2765* | * 8294* | *2765* | *4716* | *4716* | *5529* |
| Albertus Bold |  |  |  |  |  | 8619 | 3253 | 8619 | 3253 | 5692 | 5692 | 5855 |
| Albertus BI |  |  |  |  |  | *8619* | *3253* | * 8619* | *3253* | *5692* | *5692* | *5855* |
| AntOli |  |  |  |  |  | 8945 | 2277 | 8945 | 2277 | 3415 | 3415 | 5204 |
| AntOli Italic |  |  |  |  |  | 8782 | 2602 | 8782 | 2602 | 3903 | 3903 | 5204 |
| AntiOli Bold |  |  |  |  |  | 10083 | 2227 | 10083 | 2227 | 3740 | 3740 | 5855 |
| AntiOli BI |  |  |  |  |  | *10083* | *2227* | *10083* | *2227* | *3740* | *3740* | *5855* |
| Arial | 1509 |  |  |  |  | 2048 | 455 | 2048 | 455 | 682 | 682 | 1139 |
| Arial Italic | *1509* |  |  |  |  | *2048* | * 455* | * 2048* | * 455* | * 682* | * 682* | *1139* |
| Arial Bold | 1509 |  |  |  |  | 2048 | 569 | 2048 | 569 | 1024 | 1024 | 1139 |
| Arial BI | *1509* |  |  |  |  | *2048* | * 569* | * 2048* | * 569* | *1024* | *1024* | *1139* |
| ClarenCB |  |  |  |  |  | 5855 | 1952 | 5855 | 1952 | 3578 | 3578 | 3903 |
| Coronet |  |  |  |  |  | 4554 | 1464 | 4554 | 1464 | 2439 | 2439 | 3578 |
| Garamond |  |  |  |  |  | 7156 | 2439 | 7156 | 2439 | 3740 | 3740 | 4228 |
| Garamond Ital |  |  |  |  |  | 6830 | 2114 | 6830 | 2114 | 3578 | 3578 | 4228 |
| Garamond Bold |  |  |  |  |  | 7318 | 2277 | 7318 | 2277 | 4066 | 4066 | 4391 |
| Garamond BI |  |  |  |  |  | 7318 | 2277 | 7318 | 2277 | 3740 | 3740 | 4391 |
| Marigold |  |  |  |  |  | 6017 | 1301 | 6017 | 1301 | 2114 | 2114 | 3903 |
| Optima (all) | 4391 |  |  |  |  | 7806 | 2439 | 7806 | 2439 | 3740 | 3740 | 4879 |
| Times | 4391 |  |  |  |  | 7806 | 2927 | 7806 | 2927 | 4554 | 4554 | 4391 |
| Times Italic | 4391 |  |  |  |  | 7806 | 2927 | 7806 | 2927 | 4391 | 4391 | 4391 |
| Times Bold | 4391 |  |  |  |  | 7806 | 2927 | 7806 | 2927 | 5042 | 5042 | 4391 |
| Times BI | 4391 |  |  |  |  | 7806 | 2927 | 7806 | 2927 | 4716 | 4716 | 4391 |
| TNRoman | 1556 |  |  |  |  | 2048 | 682 | 2048 | 682 | 909 | 909 | 1024 |
| TNRoman Ital | 1556 |  |  |  |  | 1821 | 682 | 1821 | 682 | 1139 | 1139 | 1024 |
| TNRoman Bold | 1530 |  |  |  |  | 2048 | 682 | 2048 | 682 | 1024 | 1024 | 1024 |
| TNRoman BI | 1530 |  |  |  |  | 2048 | 682 | 2048 | 682 | 1024 | 1024 | 1024 |
| Univers (all) | 4391 | 8782 | 8782 | 8782 | 8782 | 88782 | 2927 | 88782 | 2927 | 4391 | 4391 | 5529 |
| UniversC |  |  |  |  |  | 5855 | 1952 | 5855 | 1952 | 3090 | 3090 | 4066 |
| UniversC Ital |  |  |  |  |  | *5855* | *1952* | * 5855* | *1952* | *3090* | *3090* | *4066* |
| UniversC Bold |  |  |  |  |  | *5855* | *1952* | * 5855* | *1952* | *3090* | *3090* | *4066* |
| UniversC BI |  |  |  |  |  | 5855 | 1952 | 5855 | 1952 | 3415 | 3415 | 4228 |

---

Acknowledgments

Thanks to **Julie Rosenberg** for introducing me to the Ventura International symbol set, which 
formed the basis of the earlier LJ3DTP.PDF and LJ4DTP.PDF; to **Kevin Lee** for testing a 
prototype PDF; to **Joe Masters**, **Laurie Ozone**, and **Tom Pinch**, formerly of WordStar 
International, for responding to my queries about patching proportional spacing tables; and to 
**Karl Fuss** for updating LJ4DTP.PDF to work with LaserJet series 5 and above printers.

Who is Robert J. Sawyer?

Glad you asked! I'm a Hugo and Nebula Award-winning Canadian science-fiction writer, and 
this is «Buy-My-Book Ware:» if you find this package useful, please buy a copy of one of my 
novels, either for yourself or for a friend.

For more information about my writing, please see my website _ over 800 documents all 
handcoded in HTML using WordStar's non-document mode _ at *https://sfwriter.com*.

---
