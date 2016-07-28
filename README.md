# bmp2sms

this tool was only tested with TCL 8.6.*

this tool is basically a 'clone' of bmp2tile made by Maxim [bmp2tile](http://www.smspower.org/maxim/Software/BMP2Tile)
rewrote it for fun and because i am not under Windows, i also needed extra-features

its purpose is to convert 16 colors images files (PNG/GIF/PPM/PGM) to a format suitable for inclusion in Sega Master System programs (written with wla-dx but other tools may work as well)

there is some things differing from bmp2tile:
 - the program target/focus system is the Sega Master System altough Game Gear could be supported easily
 - the program perform 'smart' colours conversion if your image has colours which does not match the SMS palette
 - indexed images are loaded as normal images (the palette is ignored), a palette is instead automatically generated
 - it load a complete directory instead of loading only one file, there is ongoing support to save all files in one go
 - some features are half implemented right now like 8x16 mode and tile mirroring

then there is some special features:
 - palette index picker (click somewhere on the image)
 - palette editor (double click on a palette color square or drag around a color square to organize the palette)

if the package TkImg is found then these additional images format will be supported: BMP/JPEG/PCX/XPM/TGA

this program also support compression plugins made for bmp2tile [bmp2tile plugins](https://github.com/maxim-zhao/bmp2tile-compressors), this feature require the Ffidl Tcl package

Note for .bmp images: The image should not include colour space information (see BMP export compatibility options for GIMP) otherwise the image will fail to load.

this is a first try at TCL, an interesting programming language with great libraries

### Screenshots ###

![Alt text](http://garzul.tonsite.biz/bmp2sms/bmp2sms.png "bmp2sms")

![Alt text](http://garzul.tonsite.biz/bmp2sms/bmp2sms_2.png "bmp2sms tiles")

![Alt text](http://garzul.tonsite.biz/bmp2sms/bmp2sms-3.png "bmp2sms tilemap")

![Alt text](http://garzul.tonsite.biz/bmp2sms/bmp2sms-4.png "bmp2sms picker")
