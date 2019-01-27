# bmp2sms

this tool was only tested with TCL 8.6.*

basically a 'clone' of [bmp2tile](http://www.smspower.org/maxim/Software/BMP2Tile) made by Maxim
rewrote it as a TCL study and with Linux as principal target

its purpose is to convert 16 colors images files (**PNG/GIF/PPM/PGM**) to a format suitable for inclusion in Sega Master System programs (written with wla-dx but other tools may work as well)

there is some things differing from bmp2tile:
 * target system is the Sega Master System (no support for Game Gear altough the implementation wouldn't differ by much)
 * the program perform 'smart' colours conversion if image colours does not match the SMS palette
 * indexed images are loaded as normal images (the palette is ignored), a palette is instead automatically generated
 * it load a complete directory instead of only one file at a time, there is planned support to save all files in one go
 * some features from bmp2tile are missing like 8x16 mode and cl123 palette output mode, tile mirroring is half implemented as of now
 * palette order may be different so tiles value may be different on the same image (because bmp2tile will load indexed images while bmp2sms always generate it)
 * no commandline mode

then there is some features:
 - palette index picker (click somewhere on the image)
 - palette editor (double click on a palette color square or drag around a color square to organize the palette)

if the package TkImg is found then these additional images format will be supported: **BMP/JPEG/PCX/XPM/TGA**

this program also support [compression plugins made for bmp2tile](https://github.com/maxim-zhao/bmp2tile-compressors), this feature require the **Ffidl Tcl package**

**Note for .bmp images:** The image should not include colour space information (see BMP export compatibility options for GIMP) otherwise the image will fail to load.

this is a first try at TCL, an interesting programming language with great libraries

### Usage ###

`tclsh8.6 bmp2sms.tcl`

### Screenshots ###

![Alt text](https://www.onirom.fr/assets/thumb/bmp2sms.png "bmp2sms")

