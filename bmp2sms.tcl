#! /usr/bin/env tclsh
#
# bmp2sms by Julien Verneuil - 02/11/2014 - last updated : 28/01/2019
# License: BSDv2
#
# this tool was only tested with TCL 8.6.*
#
# this tool is basically a 'clone' of bmp2tile made by Maxim : http://www.smspower.org/maxim/Software/BMP2Tile
# rewrote it as a TCL study and most importantly with portability in mind
#
# its purpose is to convert 16 colors images files to a format suitable for inclusion in Sega Master System programs (written with wla-dx but other tools may work as well)
#
# bmp2sms support PNG/GIF/PPM/PGM by default without the TkImg package (see below)
# images should have a width / height that are multiples of 8 otherwise padding will be added.
#
# there is some things differing from bmp2tile:
#      - target system is the Sega Master System (no support for Game Gear altough adding it would be easy)
#      - the program perform 'smart' colours conversion if image colours does not match the SMS palette
#      - indexed images are loaded as normal images (the palette is ignored), a palette is instead automatically generated
#      - it load a complete directory instead of only one file at a time, there is planned support to save all files in one go
#      - some features from bmp2tile are missing like 8x16 mode and cl123 palette output mode
#      - palette order may be different so tiles value may be different on the same image (because bmp2tile will load indexed images while bmp2sms always generate it)
#      - no commandline mode
#      - no status bar
#
# then there is some features:
#      - palette index picker : select a palette index and click somewhere on the image to change the palette color
#      - palette editor : double click on a palette color square or drag around a color square to organize the palette
#
# if the package TkImg is found then these additional images format will be supported: BMP/JPEG/PCX/XPM/TGA
#
# this program also support compression plugins made for bmp2tile : https://github.com/maxim-zhao/bmp2tile-compressors
# compression plugins support require the Ffidl TCL package
#
# Note for .bmp images: The image should not include colour space information (see BMP export compatibility options for GIMP) otherwise the image will fail to load.
#
# this is a first try at TCL programming, an interesting scripting language with great libraries
#

package require Tk

set use_tkimg 1
set use_ffidl 1

set dirName [pwd]

# === check program argument for options
foreach {name} $argv {
	if {$name eq "-without_TkImg"} {
		set use_tkimg 0
	} elseif {$name eq "-without_Ffidl"} {
		set use_ffidl 0
	}
}


# === tkImg related
set img_format_support ".png,.PNG,.gif,.GIF,.ppm,.PPM,.pgm,.PGM"

if {$use_tkimg} {
    if {[catch {package require Img}]} {
        puts "\n BMP/JPEG/PCX/XPM/TGA support disabled because TkImg package cannot be found. \
             \n  * Solution : Install libtk-img from your package manager.  \
             \n Turn this warning off with '-without_TkImg' program argument.\n" 
    } else {
        set img_format_support [append img_format_support ",.bmp,.BMP,.jpg,.jpeg,.JPG,.JPEG,.pcx,.PCX,.xpm,.XPM,.tga,.TGA"]
    }
}


# === compression plugins related
set operating_system $tcl_platform(os)

set plugins_file_list [list]

set tiles_plugins   [dict create]
set tilemap_plugins [dict create]

if {$use_ffidl} {
	if {[catch {package require Ffidl}] || 
	    [catch {package require Ffidlrt}]} {
        puts "\n Compression plugins support disabled because Ffidl package cannot be found. \
             \n  * Solution : Install Ffidl : http://elf.org/ffidl \
             \n Turn this warning off with '-without_Ffidl' program argument.\n" 
	} else {
		# scan the program folder to find the plugins shared libraries
		if {$operating_system eq "Linux"     || 
			$operating_system eq "FreeBSD"   || 
			$operating_system eq "DragonFly" || 
			$operating_system eq "NetBSD"    || 
			$operating_system eq "OpenBSD"} {
			set plugins_file_list [glob -nocomplain -types {r f} *.so]
		} elseif {[string match -nocase "*win*" $operating_system]} {
			set plugins_file_list [glob -nocomplain -types {r f} *.dll]]
		} elseif {$operating_system eq "MacOS" || 
		          $operating_system eq "Darwin"} {
		    set plugins_file_list [glob -nocomplain -types {r f} *.dylib]]
		}
		
		# for each libraries, check if it is a compression plugin based on the symbols name
		# if it is then create a TCL command based on the library name and the symbol name
		# and make it available for either tiles or tilemap export (or both)
		foreach plugin_filename $plugins_file_list {
			if {[catch {::ffidl::symbol "[pwd]/$plugin_filename" "getName"} gn_addr]} {
				puts "Can't get \"getName\" symbol for the plugin \"$plugin_filename\", this plugin will be ignored."
				continue
			}
		
			if {[catch {::ffidl::symbol "[pwd]/$plugin_filename" "getExt"} ge_addr]} {
				puts "Can't get \"getExt\" symbol for the plugin \"$plugin_filename\", this plugin will be ignored."
				continue
			}

			set library_rootname [file rootname $plugin_filename]
				
			set cmd_get_name $library_rootname
			append cmd_get_name "_getName"
				
			set cmd_get_ext $library_rootname
			append cmd_get_ext "_getExt"
				
			set cmd_compress_tiles $library_rootname
			append cmd_compress_tiles "_compressTiles"
				
			set cmd_compress_tilemap $library_rootname
			append cmd_compress_tilemap "_compressTilemap"
				
			::ffidl::callout $cmd_get_name {} {pointer-utf8} $gn_addr
			::ffidl::callout $cmd_get_ext  {} {pointer-utf8} $ge_addr
				
			if {[catch {::ffidl::symbol "[pwd]/$plugin_filename" "compressTiles"} ct_addr]} {

			} else {
				::ffidl::callout $cmd_compress_tiles {pointer-byte uint32 pointer-byte uint32} {uint32} $ct_addr

				dict set tiles_plugins $library_rootname [list [$cmd_get_name] [$cmd_get_ext]]
			}

			if {[catch {::ffidl::symbol "[pwd]/$plugin_filename" "compressTilemap"} cm_addr]} {

			} else {
				::ffidl::callout $cmd_compress_tilemap {pointer-byte uint32 uint32 pointer-byte uint32} {uint32} $cm_addr

				dict set tilemap_plugins $library_rootname [list [$cmd_get_name] [$cmd_get_ext]]
			}
			
			if {[dict exists $tiles_plugins $library_rootname]   == 0 && 
			    [dict exists $tilemap_plugins $library_rootname] == 0} {
				puts "Can't get \"compressTiles\" and \"compressTilemap\" symbols for the plugin \"$plugin_filename\", this plugin will be ignored."
			}
		}
	}
}


# === main program

set window_width  800
set window_height 600
set window_x 0
set window_y 0

# the fixed font used for the palette read-only entry (font should be fixed because it should stay aligned with the palette rectangles)
set fixed_font [font create -size 10 -family Monospace -weight bold]

set TILE_WIDTH  8
set TILE_HEIGHT 8

set host_palette_data ""

set paletteEntryText ""

set currPalTag ""
set indexedImageData ""

set tilesData ""
set listBoxCurrentIndex 0

array set tiledImageData {}
array set tiledDataIndex {}

# store already loaded data (which save data between images selections)
set loaded_data [dict create]

# checkbox/spinbox-linked variables
set check_rmdup           0
set check_tmirror         0
set check_t8x16           0
set check_use_sprite_pal  0
set check_front_of_sprite 0

set tindex_value 0


proc initializeSMSPalette {} {
    set pal [dict create]

    for {set i 0} {$i < 64} {incr i} {
        set hex_r [format %2.2x [expr {($i >> 0 & 3) * 85}]]
        set hex_g [format %2.2x [expr {($i >> 2 & 3) * 85}]]
        set hex_b [format %2.2x [expr {($i >> 4 & 3) * 85}]]
        
        set hex_i [format %2.2X $i]

        dict set pal "#$hex_r$hex_g$hex_b" "\$$hex_i"
    }
    
    return $pal
}

# the host full palette is stored here
# it is used for the color selection dialog and for colors checks
set dstPalette [initializeSMSPalette]

# if the argument is not an empty string this add an error message in the frame directory and set the directory input background to red
# if the argument is an empty string it remove the error message and set the directory input background back to white
proc setDirFrameError m {
	if {[string eq $m ""]} then {
		grid remove .frame_directory.m
		.frame_directory.e configure -bg "#ffffff"
		return
	}
	
	grid .frame_directory.m - -sticky we -row 1 -padx 1m -pady 1m -in .frame_directory
	
	.frame_directory.m configure -text $m
	.frame_directory.e configure -bg "#ff0000"
	
	.frame_tabs.notebook tab 0 -state disabled
	.frame_tabs.notebook tab 1 -state disabled
	.frame_tabs.notebook tab 2 -state disabled
}

proc loadDir {} {
    global dirName img_format_support loaded_data
    
    .frame_files.list delete 0 end
    preview_image blank

    if {![file exists $dirName]} then {
    	setDirFrameError "Invalid path."
    	return
    }
        
    if {![file isdirectory $dirName]} then {
    	setDirFrameError "Not a directory."
    	return
    }

    if {[catch {glob -type f -directory $dirName *{$img_format_support}} file_list]} then {
	    setDirFrameError "There is no supported images in this directory."
	    return
    }

    # clear cache
    set loaded_data [dict create]
        
    setDirFrameError ""
    
    .frame_directory.e configure -bg "#FFFFFF"
    
	foreach i [lsort $file_list] {
		.frame_files.list insert end [file tail $i]
	}
	
	.frame_files.list selection set 0
	listBoxSelect
	
	.frame_tabs.notebook select 0
}

proc selectAndLoadDir {} {
    global dirName
    
    set dir [tk_chooseDirectory -initialdir $dirName -parent . -mustexist 1]
    if {$dir ne ""} {
		set dirName $dir
		loadDir
    }
}

# generate map data
proc updateTileMapData {} {
    global tiledImageData tiledDataIndex check_use_sprite_pal check_front_of_sprite TILE_WIDTH tindex_value
    
    set width  [image width preview_image]

    set tw [expr {$width / $TILE_WIDTH}]
    
    set i 0
    set l 0

    .tilemap_text delete 0.0 end
    
    .tilemap_text insert end ".dw "
    foreach index [lsort -dictionary [array names tiledImageData]] {
        set tindex [expr {$tiledDataIndex($index) + $tindex_value}]

        if {$check_use_sprite_pal} {
            set tindex [expr {$tindex | 2048}]
        }
        
        if {$check_front_of_sprite} {
            set tindex [expr {$tindex | 4096}]
        }

        #if {[string range $tiledImageData($index) 0 0] eq " "} {
        #    .tilemap_text insert end "\$[format %04X [string range $tiledImageData($index) 1 end]] "
            
            #puts [string range $tiledImageData($index) 1 end]]
        #} else {
            .tilemap_text insert end "\$[format %04X [expr {$tindex}]] "
        #}
        
        incr i
        
        if {[expr {$i % $tw}] == 0} {
            .tilemap_text insert end "\n.dw "
        
            incr l
        }
    }
    
    .tilemap_text delete [.tilemap_text count -lines 0.0 end].0 end
}

# generate tiles/map & update preview image
proc updateImage {} {
    global tiledImageData tiledDataIndex host_palette_data indexedImageData tilesData TILE_WIDTH TILE_HEIGHT check_rmdup check_tmirror check_t8x16 tindex_value

    set width  [image width  preview_image]
    set height [image height preview_image]

    array unset tiledImageData *
    array set tiledImageData {}
    array set tiledHFlipImageData {}
    array set tiledVFlipImageData {}
    array set tiledHVFlipImageData {}
    
    set tw [expr {$width / $TILE_WIDTH}]
    
    set y 0
    set yi 0
    
    set dst_data [list]
    foreach line $indexedImageData {
        set l ""

        set x 0
        set ti $yi
        set xi 0
        
        set b0 0
        set b1 0
        set b2 0
        set b3 0

        set hfb0 0
        set hfb1 0
        set hfb2 0
        set hfb3 0
        
        foreach pal_index [split $line " "] {
            append l " [.canvas_palette itemcget pal_color_$pal_index -fill]"

            set bpos [expr {7 - ($x & 7)}]
            
            set b0 [expr {$b0 | (( $pal_index & 1)       << $bpos)}]
            set b1 [expr {$b1 | ((($pal_index & 2) >> 1) << $bpos)}]
            set b2 [expr {$b2 | ((($pal_index & 4) >> 2) << $bpos)}]
            set b3 [expr {$b3 | ((($pal_index & 8) >> 3) << $bpos)}]

            # hflip the easy way
            set bpos [expr {$x & 7}]
            set hfb0 [expr {$hfb0 | (( $pal_index & 1)       << $bpos)}]
            set hfb1 [expr {$hfb1 | ((($pal_index & 2) >> 1) << $bpos)}]
            set hfb2 [expr {$hfb2 | ((($pal_index & 4) >> 2) << $bpos)}]
            set hfb3 [expr {$hfb3 | ((($pal_index & 8) >> 3) << $bpos)}]
            
            incr x

            if {[expr {$x % $TILE_WIDTH}] == 0} {
                # HFlip
                set hfb0 [format %02X $hfb0]
                set hfb1 [format %02X $hfb1]
                set hfb2 [format %02X $hfb2]
                set hfb3 [format %02X $hfb3]

                if {[catch {
		            set hfliptdata [concat $tiledHFlipImageData($ti) " \$$hfb0 \$$hfb1 \$$hfb2 \$$hfb3"]
                }]} then {
                    set hfliptdata "\$$hfb0 \$$hfb1 \$$hfb2 \$$hfb3"
                }

                # tile data
                set b0 [format %02X $b0]
                set b1 [format %02X $b1]
                set b2 [format %02X $b2]
                set b3 [format %02X $b3]
            
                if {[catch {
		            set tdata [concat $tiledImageData($ti) " \$$b0 \$$b1 \$$b2 \$$b3"]
                }]} then {
                    set tdata "\$$b0 \$$b1 \$$b2 \$$b3"
                }

                # first pass VFlip (flip bitplanes)
                if {[catch {
		            set vfliptdata [concat $tiledVFlipImageData($ti) " \$$b3 \$$b2 \$$b1 \$$b0"]
                }]} then {
                    set vfliptdata "\$$b3 \$$b2 \$$b1 \$$b0"
                }

                # first pass HFlip + VFlip (flip bitplanes)
                if {[catch {
		            set hvfliptdata [concat $tiledHVFlipImageData($ti) " \$$hfb3 \$$hfb2 \$$hfb1 \$$hfb0"]
                }]} then {
                    set hvfliptdata "\$$hfb3 \$$hfb2 \$$hfb1 \$$hfb0"
                }
                
                set b0 0
                set b1 0
                set b2 0
                set b3 0

                set hfb0 0
                set hfb1 0
                set hfb2 0
                set hfb3 0
                
                set tiledImageData($ti) $tdata
                set tiledHFlipImageData($ti) $hfliptdata
                set tiledVFlipImageData($ti) $vfliptdata
                set tiledHVFlipImageData($ti) $hvfliptdata

                incr xi
                incr ti
            }
        }
        
        set dst_data "$dst_data {$l}"
        
        incr y
        
        if {[expr {$y % $TILE_HEIGHT}] == 0} {
            incr yi $tw
        }
    }

    foreach index [lsort -dictionary [array names tiledVFlipImageData]] {
        # second pass VFlip
        set tiledVFlipImageData($index) [join [lreverse [split $tiledVFlipImageData($index)]] " "]
        # second pass VFlip for HFlip + VFlip
        set tiledHVFlipImageData($index) [join [lreverse [split $tiledHVFlipImageData($index)]] " "]
    }

    # remove trailing newline at the end of tiles/tilemap
    #string trimright $string \n
    
    .tiles_text   delete 0.0 end

    # generate tiles data
    array unset tiledDataIndex *
    array set tiledDataIndex {}

    array set tiledDataDuplicate {}
    array set tiledDataMirrored {}
    array set tiledDataHMirrored {}
    array set tiledDataVMirrored {}

    set tiles_count [array size tiledImageData]

    set i 0
    for {set index 0} {$index < $tiles_count} {incr index} {
        if {$check_rmdup} {
            # remove duplicate
            for {set index2 [expr {$index+1}]} {$index2 < $tiles_count} {incr index2} {
                if {$tiledImageData($index) eq $tiledImageData($index2)} {
                    if {![info exists tiledDataDuplicate($index)] &&
                        ![info exists tiledDataMirrored($index)]} {
                        set tiledDataDuplicate($index2) 0
                        set tiledDataIndex($index2) $i
                    }
                }
            }

            # remove mirrored tiles & flag it into the tilemap
            if {$check_tmirror} {
                for {set index2 [expr {$index+1}]} {$index2 < $tiles_count} {incr index2} {
                    if {![info exists tiledDataDuplicate($index)] &&
                        ![info exists tiledDataDuplicate($index2)] &&
                        ![info exists tiledDataMirrored($index)]} {
                        # remove H mirrored
                        if {$tiledHFlipImageData($index) eq $tiledImageData($index2)} {
                            set tiledDataMirrored($index2) 0
                            set tiledDataIndex($index2) [expr {$i | 512}]
                        # remove V mirrored
                        } elseif {$tiledVFlipImageData($index) eq $tiledImageData($index2)} {
                            set tiledDataMirrored($index2) 0
                            set tiledDataIndex($index2) [expr {$i | 1024}]
                        # remove H+V mirrored
                        } elseif {$tiledHVFlipImageData($index) eq $tiledImageData($index2)} {
                            set tiledDataMirrored($index2) 0
                            set tiledDataIndex($index2) [expr {$i | 1536}]
                        }
                    }
                }
            }
        }

        # regular tile
        if {![info exists tiledDataDuplicate($index)] &&
            ![info exists tiledDataMirrored($index)]} {
            set tiledDataIndex($index) $i
            incr i
        }
    }

    # tiles output
    set i $tindex_value
    for {set index 0} {$index < [array size tiledImageData]} {incr index} {
        if {![info exists tiledDataDuplicate($index)] &&
            ![info exists tiledDataMirrored($index)]} {
            .tiles_text insert end "; Tile index \$[format %03X $i]\n.db $tiledImageData($index)\n"

            incr i
        }
    }

    # generate tilemap
    updateTileMapData
   
    preview_image put $dst_data
}

# create a new palette filled with black color
proc initializePalette {} {
    for {set i 0} {$i < 16} {incr i} {
        .canvas_palette itemconfigure "pal_color_$i" -fill "#000000"
        
        setPaletteColor $i "#000000"
    }
}

proc setPaletteData {i color} {
    global host_palette_data dstPalette loaded_data listBoxCurrentIndex

    lset host_palette_data $i [dict get $dstPalette $color]
    
    set selectionName [.frame_files.list get $listBoxCurrentIndex]
    
    dict set loaded_data "pal $selectionName" $host_palette_data
}

proc updatePaletteData {} {
    global host_palette_data paletteEntryText loaded_data
	
    for {set i 0} {$i < 16} {incr i} {
        setPaletteData $i [.canvas_palette itemcget "pal_color_$i" -fill]
    }
 
    set paletteEntryText [lindex $host_palette_data 0]
    
    for {set i 1} {$i < 16} {incr i} {
        set paletteEntryText "$paletteEntryText [lindex $host_palette_data $i]"
    }
}

proc setPaletteColor {index color} {
    set x1 [expr {$index * 32 + 1}]
    set x2 [expr {$x1 + 31}]

    .canvas_palette itemconfigure "pal_color_$index" -fill $color
}

proc loadImage {file} {
    if {[catch {
		preview_image configure -file $file
    }]} then {
        return -1
    }

    return 0
}

proc selectionLoadFailed {msg detail} {
	set currSelectionIndex [.frame_files.list curselection]

	.frame_files.list itemconfigure $currSelectionIndex -bg \#ff0000 -selectbackground \#ff0000
	.frame_tabs.notebook tab 0 -state disabled
	.frame_tabs.notebook tab 1 -state disabled
	.frame_tabs.notebook tab 2 -state disabled
	
	tk_messageBox -message $msg -detail $detail -icon error -title "Error"
}

proc listBoxSelect {} {
    global dirName dstPalette indexedImageData host_palette_data listBoxCurrentIndex
    global TILE_WIDTH TILE_HEIGHT
    global loaded_data

    if {[.frame_files.list curselection] eq ""} {
    	return
    }
    
    set currSelectionIndex [.frame_files.list curselection]
    set selectionName [.frame_files.list get $currSelectionIndex]
    
    set file [file join $dirName $selectionName]
    
    preview_image configure -width 0 -height 0
    
    if {[loadImage $file] eq -1} {
        if {[string tolower [file extension $file]] eq ".bmp"} {
		    selectionLoadFailed "Image format not supported" "NOTE : the image should not include colour space informations"
        } else {
            selectionLoadFailed "Image format not supported" ""
        }
	    
	    return
    }
    
    set listBoxCurrentIndex $currSelectionIndex
    
    set fixed_img_width  [expr {int(ceil([image width  preview_image] / double($TILE_WIDTH))  * $TILE_WIDTH)}]
    set fixed_img_height [expr {int(ceil([image height preview_image] / double($TILE_HEIGHT)) * $TILE_HEIGHT)}]

    .frame_image_name configure -text "[file rootname $selectionName] ([append "" $fixed_img_width x $fixed_img_height])"
    
    preview_image configure -width $fixed_img_width -height $fixed_img_height
    
    set src_data [preview_image data -background "#000000"]
    
    initializePalette
		
    if {[catch {set indexedImageData [dict get $loaded_data "image $selectionName"] 
    	        set palette          [dict get $loaded_data "pal $selectionName"]}]} {
		set dst_data [list]
		set palette [dict create]
		set i 0
		
		set indexedImageData ""
		set host_palette_data ""
	
		foreach line $src_data {
		    set l ""
		    set hl ""
		    foreach hex_color [split $line " "] {
		        lassign [winfo rgb . $hex_color] r g b

		        set color ""
		        
		        if {[dict size $palette] >= 16} {
					selectionLoadFailed "The image have too many colours." "(max: 16)"
			
		        	return
		        }
		           
		        if {[dict exists $dstPalette $hex_color]} {
		            set color $hex_color
		        } else {
		            set r [format "%02x" [expr {int($r / 256 / 85.0) * 85}]]
		            set g [format "%02x" [expr {int($g / 256 / 85.0) * 85}]]
		            set b [format "%02x" [expr {int($b / 256 / 85.0) * 85}]]
		            
		            set color "#$r$g$b"
		        }
		        
		        if {![dict exists $palette $color]} {
		            dict set palette $color $i
		                        
		            setPaletteColor $i $color

		            incr i
		        }
		        
		        append hl "[dict get $palette $color] "
		        
		        append l "$color "
		    }
		    
		    set hl [string trimleft  $hl " "]
		    set l  [string trimleft  $l  " "]
		    set hl [string trimright $hl " "]
		    set l  [string trimright $l  " "]
		    
		    set dst_data "$dst_data {$l}"
		    set indexedImageData "$indexedImageData {$hl}"
		}
		
		updatePaletteData
		
		dict set loaded_data "image $selectionName" $indexedImageData
    } else {
    	set i 0
    	foreach {pal_index} $palette {
			dict for {key value} $dstPalette {
				if {$value == $pal_index} {
					setPaletteColor $i $key
					break
				}
			}
			
			incr i
    	}

    	updatePaletteData
    }
    
    #preview_image put $dst_data
    
    updateImage

    if {[.frame_tabs.notebook tab 0 -state] ne "normal"} {
        .frame_tabs.notebook tab 0 -state normal
        .frame_tabs.notebook select 0
    }
        
    .frame_tabs.notebook tab 1 -state normal
    .frame_tabs.notebook tab 2 -state normal
}

# === Color dragging of the palette
proc itemStartDrag {c x y} {
    global lastX lastY currPalTag
    
    set i [expr {int([$c canvasx $x]/32.0)}]
    set lastX [expr {$i *32}]

    set tag_list [.canvas_palette gettags current]
    set index [lsearch $tag_list "pal_color_*"]
    
    if {$index != -1} {
        set currPalTag [lindex $tag_list $index]
        
        $c moveto "selection" [expr {$i * 32 + 11}] ""
    } 
}

proc itemDrag {c x y} {
    global lastX lastY indexedImageData currPalTag
    
    set tag_list [.canvas_palette gettags current]
    set index [lsearch $tag_list "pal_color_*"]
    
    if {$index == -1} {
        return
    } 
    
    set i [expr {int([$c canvasx $x]/32.0)}]
    
    if {$i < 0 || $i >= 16} {
        return
    }
    
    set x [expr {$i * 32}]
    
    $c raise current "pal_color_$i"
    
    set old_tag [lindex [$c gettags current] 0]
    set new_tag "pal_color_$i"
    
    set old_index [lindex [split $old_tag "_"] 2]
    set new_index [lindex [split $new_tag "_"] 2]
    
    if {$old_tag eq $new_tag} {
        return
    }
    
    set old_id [$c find withtag $new_tag]
    set current_id [$c find withtag $old_tag]
    
    $c dtag "pal_color_$i" $new_tag
    $c dtag current $old_tag
    
    $c move $old_id [expr {-($x-$lastX)}] 0
    
    $c itemconfigure $old_id -tags $old_tag
    $c itemconfigure current -tags [list $new_tag current]
    
    set currPalTag $new_tag
    $c moveto "selection" [expr {$i * 32 + 11}] ""
    
    $c move current [expr {$x-$lastX}] 0
    set lastX $x
    
    updatePaletteData
}

proc stopDrag { } {
    updateImage
}

# center a window in its parent
proc centerWindow {parent w} {
    update idletasks

    set parent_x [winfo rootx $parent]
    set parent_y [winfo rooty $parent]
   
    set parent_width  [winfo width $parent]
    set parent_height [winfo height $parent]
    
    set w_width  [winfo width  $w]
    set w_height [winfo height $w]
    
    wm geom $w +[expr {$parent_x + abs($parent_width / 2 - $w_width / 2)}]+[expr {$parent_y + abs($parent_height / 2 - $w_height / 2)}]
}

# called when a color is selected in the color chooser window
proc changeColor {color} {
    global currPalTag

    .canvas_palette itemconfigure $currPalTag -fill $color
    updatePaletteData
    
    updateImage
}

proc imageClick {x y} {
    global indexedImageData
    
    set i [lindex [lindex $indexedImageData $y] $x]
    
    if {[string length $i] > 0} {
        .canvas_palette moveto "selection" [expr {$i * 32 + 11}] ""
    }
}

# === export procedures (TODO: clean code duplicata)
proc savePalette {type multiple} {
    global paletteEntryText listBoxCurrentIndex indexedImageData

    set selectedFile [file rootname [.frame_files.list get $listBoxCurrentIndex]]
    set selectedFile [append selectedFile " (palette)"]
    set selectedFile [append selectedFile $type]
        
    if {$multiple == 0} {
        set types [list [list [list] [list $type]]]

        set file [tk_getSaveFile -defaultextension $type -initialfile $selectedFile -filetypes $types -parent .]
    } else {
		set dir [tk_chooseDirectory -title "Choose a directory"]
        #set file [append $path $selectedFile]
        
    	if {$dir eq ""} {
    		return
    	}
    }

    .frame_files.list select set $listBoxCurrentIndex
        
    if {$file == ""} {
        return
    }

    set max_pal_index 0
    foreach line $indexedImageData {
        foreach pal_index [split $line " "] {
            if {$pal_index > $max_pal_index} {
                set max_pal_index $pal_index
            }
        }
    }
    
    set n 0
    set d 0
    set f [catch {set fid [open $file w+]}]
    
    if {$type eq ".inc"} {
        set inc_data ".db"
        foreach c [split $paletteEntryText " "] {
            set inc_data "$inc_data $c"
            
            incr n
            
            if {$n > $max_pal_index} {
                break
            }
        }
        
        set d [catch {puts $fid $inc_data}]
    } else {
        catch {fconfigure $fid -translation binary}

        foreach i [split $paletteEntryText "$"] {
            if {$i eq ""} {
                continue
            }
            
            if {[catch {puts -nonewline $fid [binary decode hex [string trim $i " "]]}]} {
                set d 1
            }
                    
            incr n
            
            if {$n > $max_pal_index} {
                break
            }
        }
    }
    
    set c [catch {close $fid}]
    if {$f || $d || $c || ![file exists $file] || ![file isfile $file] || ![file readable $file]} {
        tk_messageBox -parent . -icon error -message "An error occurred while saving \"$file\"."
    }
}

proc saveTiles {type multiple} {
    global listBoxCurrentIndex tiles_plugins
    
    if {![catch {set plugin [dict get $tiles_plugins $type]}]} {
		set plugin_name $type

    	set type .[lindex $plugin 1]
    }
    
    set selectedFile [file rootname [.frame_files.list get $listBoxCurrentIndex]]
    set selectedFile [append selectedFile " (tiles)"]
    set selectedFile [append selectedFile $type]

    if {$multiple == 0} {
        set types [list [list [list] [list $type]]]

        set file [tk_getSaveFile -defaultextension $type -initialfile $selectedFile -filetypes $types -parent .]
    } else {
    	set dir [tk_chooseDirectory -title "Choose a directory"]
        #set file [append $path $selectedFile]
        
    	if {$dir eq ""} {
    		return
    	}
    }

    .frame_files.list select set $listBoxCurrentIndex
        
    if {$file == ""} {
        return
    }
    
    set tilesData [.tiles_text get 0.0 end]
    
    set ti 0
    set n 0
    set d 0
    set f [catch {set fid [open $file w+]}]
    if {$type eq ".inc"} {
        set d [catch {puts $fid $tilesData}]
    } else {
    	catch {fconfigure $fid -translation binary}
    	
        set tilesData [string map {".db " ""} $tilesData]
        set tilesData [split $tilesData "\n"]
        
        set bin [list]
        
        foreach l $tilesData {
            if {[expr {$n % 2} == 0]} {
                incr n
                incr ti
            
                continue
            }
            
            foreach i [split $l "$"] {
                if {$i eq ""} {
                    continue
                }
                
                scan [string trim $i " "] %x decimal
                
                lappend bin $decimal
            }
       
            incr n
        }
        
        set ti [expr {$ti - 1}]
        
    	set cmd $plugin_name
    	append cmd "_compressTiles"
    	
		set uint8size [::ffidl::info sizeof uint8]

		set out [binary format @[expr {$ti * 32}]]
		
		set in [binary format [::ffidl::info format uint8]* $bin]
		
		set length [$cmd $in $ti $out [expr {$ti * 32}]]

		binary scan $out "B[expr {$length * 8}]" bits
		
		puts -nonewline $fid [binary format B* $bits]
    }
    
    set c [catch {close $fid}]
    if {$f || $d || $c || ![file exists $file] || ![file isfile $file] || ![file readable $file]} {
        tk_messageBox -parent . -icon error -message "An error occurred while saving \"$file\"."
    }
}

proc saveTilemap {type multiple} {
    global listBoxCurrentIndex tilemap_plugins
    
    if {![catch {set plugin [dict get $tilemap_plugins $type]}]} {
		set plugin_name $type

    	set type .[lindex $plugin 1]
    }
    
    set selectedFile [file rootname [.frame_files.list get $listBoxCurrentIndex]]
    set selectedFile [append selectedFile " (tilemap)"]
    set selectedFile [append selectedFile $type]

    if {$multiple == 0} {
        set types [list [list [list] [list $type]]]

        set file [tk_getSaveFile -defaultextension $type -initialfile $selectedFile -filetypes $types -parent .]
    } else {
    	set dir [tk_chooseDirectory -title "Choose a directory"]
    	
    	if {$dir eq ""} {
    		return
    	}
        #set file [append $path $selectedFile]
    }

    .frame_files.list select set $listBoxCurrentIndex
        
    if {$file == ""} {
        return
    }
    
    set tilemapData [.tilemap_text get 0.0 end]
    
    set ti 0
    set d 0
    set th 0
    set f [catch {set fid [open $file w+]}]
    if {$type eq ".inc"} {
        set d [catch {puts $fid $tilemapData}]
    } else {
    	catch {fconfigure $fid -translation binary}
    	
        set tilemapData [string map {".dw " ""} $tilemapData]
        set tilemapData [split $tilemapData "\n"]
        
        set bin [list]
       
        foreach l $tilemapData {
        	set tw 0
            foreach i [split $l "$"] {
                if {$i eq ""} {
                    continue
                }
                
                scan [string trim $i " "] %2x%2x decimal decimal2
                
                lappend bin $decimal $decimal2
                
                incr tw
            }
            
            incr th
        }
        
        puts $tw

        #set tw [expr {$ti - 1}]
        
    	set cmd $plugin_name
    	append cmd "_compressTilemap"
    	
		set uint8size [::ffidl::info sizeof uint8]

		set out [binary format @[expr {$ti * 32}]]
		
		set in [binary format [::ffidl::info format uint8]* $bin]
		
		set length [$cmd $in $ti $out [expr {$ti * 32}]]

		binary scan $out "B[expr {$length * 8}]" bits
		
		puts -nonewline $fid [binary format B* $bits]
    }
    
    set c [catch {close $fid}]
    if {$f || $d || $c || ![file exists $file] || ![file isfile $file] || ![file readable $file]} {
        tk_messageBox -parent . -icon error -message "An error occurred while saving \"$file\"."
    }
}

proc showColorSelector {} {
    global dstPalette

    if {[winfo exists .color_selector]} {
        raise .color_selector .
        focus .color_selector
        return
    }
    
    tk::toplevel .color_selector
    wm title .color_selector "Color"
    
    centerWindow . .color_selector
    
    wm resizable .color_selector 0 0
    if {[catch {
        wm attributes .color_selector -type utility
    }]} then {
        if {[catch {
            wm attributes .color_selector -type toolwindow
        }]} then {}
    }
    
    wm geometry .color_selector
    
    set i 0
    set x 0
    set y 0
    dict for {key value} $dstPalette {
        if {$x eq 8} {
            set x 0
            incr y
        }
        
        set frame_path .color_selector.frame_color_${i}
        set label_path .color_selector.label_color_${i}
        
        frame $frame_path -width 48 -height 48 -background $key
        label $label_path -text $value
        grid $frame_path -row [expr {$y * 2}] -column $x -padx 2 -pady 2
        grid $label_path -row [expr {$y * 2 + 1}] -column $x -sticky s -padx 2 -pady 0
        
        $frame_path configure -cursor hand1
        
        bind $frame_path <1> [list changeColor $key]
        
        incr x
        incr i
    }
}

# setup app window
wm title . "bmp2sms"
wm geometry . ${window_width}x${window_height}+${window_x}+${window_y}

frame .app_frame
    pack .app_frame -fill both -expand 1


# setup the listbox/main content pane
panedwindow .pane -sashpad 0
    grid .pane -row 1 -column 0 -sticky wens -padx 1m -pady 1m -in .app_frame

    grid columnconfigure .pane 0 -weight 1 -uniform 1
    grid rowconfigure .pane 1 -weight 1


# setup directory selection part
labelframe .frame_directory -text "Directory:"

    entry .frame_directory.e -textvariable dirName 

    button .frame_directory.b -pady 0 -padx 2m -text "Select Dir." -command "selectAndLoadDir"
    label .frame_directory.m
    bind .frame_directory.e <Return> "loadDir"


# setup files list part
labelframe .frame_files -text "Files:"

    listbox .frame_files.list -yscrollcommand ".frame_files.scroll set"
    scrollbar .frame_files.scroll -command ".frame_files.list yview"

    bind .frame_files.list <<ListboxSelect>> "listBoxSelect"

# tabs aka main content
frame .frame_tabs

ttk::notebook .frame_tabs.notebook
ttk::notebook::enableTraversal .frame_tabs.notebook
	.frame_tabs.notebook add [frame .frame_tabs.notebook.image   ] -text "Image"   -sticky wens -underline 0 -state disabled
	.frame_tabs.notebook add [frame .frame_tabs.notebook.tiles   ] -text "Tiles"   -sticky wens -underline 0 -state disabled
	.frame_tabs.notebook add [frame .frame_tabs.notebook.tilemap ] -text "Tilemap" -sticky wens -underline 4 -state disabled
#	.frame_tabs.notebook add [frame .frame_tabs.notebook.options ] -text "Options" -sticky wens -underline 0
    .frame_tabs.notebook select 0

# right click menu
menu .text_menu -tearoff 0
    .text_menu add command -label "Select all"
    .text_menu add separator
    .text_menu add command -label "Copy all"
    .text_menu add command -label "Copy"

# tiles export menu
menu .tiles_export_menu -tearoff 0
    .tiles_export_menu add command -label "Include file (*.inc)" -command {
        saveTiles ".inc" 0
    }
    .tiles_export_menu add separator
    dict for {plugin_name data} $tiles_plugins {
    	set plugin_id [lindex $data 0]
    
    	.tiles_export_menu add command -label "$plugin_id  (*.[lindex $data 1])" -command [list saveTiles $plugin_name 0]
    }
   
# tilemap export menu
menu .tilemap_export_menu -tearoff 0
    .tilemap_export_menu add command -label "Include file (*.inc)" -command {
        saveTilemap ".inc" 0
    }
    .tilemap_export_menu add separator
    dict for {plugin_name data} $tilemap_plugins {
    	set plugin_id [lindex $data 0]
    
    	.tilemap_export_menu add command -label "$plugin_id  (*.[lindex $data 1])" -command [list saveTilemap $plugin_name 0]
    }

# list export menu
menu .export_menu -tearoff 0
    
# palette export cascade menu
menu .export_menu.cascade_palette_menu -tearoff 0
    .export_menu.cascade_palette_menu add command -label "Include file (*.inc)" -command [list savePalette ".inc" 1]
    .export_menu.cascade_palette_menu add command -label "Binary file  (*.bin)" -command [list savePalette ".bin" 1]
    
# tiles export cascade menu
menu .export_menu.cascade_tiles_menu -tearoff 0
    dict for {plugin_name data} $tiles_plugins {
    	set plugin_id [lindex $data 0]
    
    	.export_menu.cascade_tiles_menu add command -label "$plugin_id  (*.[lindex $data 1])" -command [list saveTilemap $plugin_name 1]
    }

# tilemap export cascade menu
menu .export_menu.cascade_tilemap_menu -tearoff 0
    dict for {plugin_name data} $tilemap_plugins {
    	set plugin_id [lindex $data 0]
    
    	.export_menu.cascade_tilemap_menu add command -label "$plugin_id  (*.[lindex $data 1])" -command [list saveTilemap $plugin_name 1]
    }
    
    .export_menu add cascade -menu .export_menu.cascade_palette_menu -label "Palette"
    .export_menu add cascade -menu .export_menu.cascade_tiles_menu   -label "Tiles"
    .export_menu add cascade -menu .export_menu.cascade_tilemap_menu -label "Tilemap"
    
# palette save menu
menu .pal_save_menu -tearoff 0
    .pal_save_menu add command -label "Include file (*.inc)" -command {savePalette ".inc" 0}
    .pal_save_menu add command -label "Binary file  (*.bin)" -command {savePalette ".bin" 0}

# global export button
#button .button_export -pady 0 -padx 2m -text "Export all files" -width 8
#bind .button_export <ButtonPress> {
#    tk_popup .export_menu %X %Y
#}

#grid .button_export -sticky wens -row 1 -column 0 -padx 1m -pady 1m -in .frame_files

# tiles tab content
text .tiles_text -wrap none -borderwidth 0 -highlightthickness 0 -yscrollcommand ".tiles_scroll_y set" -xscrollcommand ".tiles_scroll_x set"

bind .tiles_text <3> {
    tk_popup .text_menu %X %Y
    .text_menu entryconfigure 3 -command {
        catch {
            clipboard clear
            clipboard append [selection get]
        }
    }
    
    .text_menu entryconfigure 2 -command {
        clipboard clear
        clipboard append [.tiles_text get 0.0 end]
    }
    
    .text_menu entryconfigure 0 -command {
        .tiles_text tag add sel 0.0 end
    }
}

checkbutton .check_rm_duplicate   -text "Remove duplicates" -variable check_rmdup -command {
    global check_rmdup

    if {$check_rmdup} {
        .check_tile_mirroring configure -state normal
    } else {
        .check_tile_mirroring configure -state disabled
        .check_tile_mirroring deselect
    }

    updateImage
}

checkbutton .check_tile_mirroring -text "Use tile mirroring" -variable check_tmirror -state disabled -command {
    updateImage
}
#checkbutton .check_8x16 -text "Treat as 8x16" -variable check_t8x16 -command {
#    updateImage
#}

ttk::spinbox .spinbox_tindex -from 0 -to 999999999 -increment 1 -width 8 -textvariable tindex_value -command "updateImage" -validate all -validatecommand {
    set v %P
    
    if {[string is integer $v]} {
        if {$v >= 0} {
            set tindex_value $v
                
            updateImage
            
            # adjust cursor when adding/deleting character
            if {%d == 1} {
                .spinbox_tindex icursor [expr {%i + 1}]
            } elseif {%d == 0} {
                .spinbox_tindex icursor [expr {%i}]
            }
            
            return 1
        }
    } elseif {$v ne ""} {
        return 0
    }

    return 1
}

label .label_tindex -text "First tile index: "

button .button_save_tiles -pady 0 -padx 2m -text "Save"
bind .button_save_tiles <ButtonPress> {
    tk_popup .tiles_export_menu %X %Y
}

grid .check_rm_duplicate   -sticky wn  -row 2 -column 0 -padx 0 -pady 0 -in .frame_tabs.notebook.tiles
grid .check_tile_mirroring -sticky wn  -row 3 -column 0 -padx 0 -pady 0 -in .frame_tabs.notebook.tiles
#grid .check_8x16           -sticky w   -row 2 -column 1 -padx 0 -pady 0 -in .frame_tabs.notebook.tiles
grid .spinbox_tindex       -sticky wne -row 2 -column 3 -padx 0 -pady 0 -in .frame_tabs.notebook.tiles
grid .label_tindex         -sticky wne -row 2 -column 2 -padx 0 -pady 0 -in .frame_tabs.notebook.tiles
grid .button_save_tiles    -sticky wne -row 3 -column 3 -padx 0 -pady 0 -in .frame_tabs.notebook.tiles

scrollbar .tiles_scroll_x -orient horizontal -command ".tiles_text xview"
scrollbar .tiles_scroll_y -command ".tiles_text yview"

bind .tiles_text <Control-a> {
    %W tag add sel 0.0 end; break;
}

bind .tiles_text <Control-c> {
    clipboard clear
    clipboard append [selection get]
}

bind .tiles_text <KeyPress> break

grid .tiles_scroll_x -sticky nwe -row 1 -column 0 -columnspan 4 -padx 2 -pady 0 -in .frame_tabs.notebook.tiles
grid .tiles_scroll_y -sticky nse -row 0 -column 4               -padx 0 -pady 2 -in .frame_tabs.notebook.tiles

grid .tiles_text -sticky wens -row 0 -column 0 -columnspan 4 -padx 1 -pady 1 -in .frame_tabs.notebook.tiles

grid columnconfigure .frame_tabs.notebook.tiles 0 -weight 1
grid rowconfigure    .frame_tabs.notebook.tiles 0 -weight 1
grid columnconfigure .frame_tabs.notebook.tiles 1 -weight 999999
grid rowconfigure    .frame_tabs.notebook.tiles 1 -weight 0
grid columnconfigure .frame_tabs.notebook.tiles 2 -weight 0
grid rowconfigure    .frame_tabs.notebook.tiles 2 -weight 0
grid columnconfigure .frame_tabs.notebook.tiles 3 -weight 0
grid rowconfigure    .frame_tabs.notebook.tiles 3 -weight 0

# tilemap tab content
text .tilemap_text -wrap none -borderwidth 0 -highlightthickness 0 -yscrollcommand ".tilemap_scroll_y set" -xscrollcommand ".tilemap_scroll_x set"
bind .tilemap_text <3> {
    tk_popup .text_menu %X %Y
    .text_menu entryconfigure 3 -command {
        catch {
            clipboard clear
            clipboard append [selection get]
        }
    }
    
    .text_menu entryconfigure 2 -command {
        clipboard clear
        clipboard append [.tilemap_text get 0.0 end]
    }
    
    .text_menu entryconfigure 0 -command {
        .tilemap_text tag add sel 0.0 end
    }
} 

checkbutton .check_use_sprite_palette -text "Use sprite palette"  -variable check_use_sprite_pal -command {
    updateTileMapData
}
checkbutton .check_front_sprite       -text "In front of sprites" -variable check_front_of_sprite -command {
    updateTileMapData
}

grid .check_use_sprite_palette   -sticky wn -row 2 -column 0 -padx 0 -pady 0 -in .frame_tabs.notebook.tilemap
grid .check_front_sprite         -sticky wn -row 3 -column 0 -padx 0 -pady 0 -in .frame_tabs.notebook.tilemap

scrollbar .tilemap_scroll_x -orient horizontal -command ".tilemap_text xview"
scrollbar .tilemap_scroll_y -command ".tilemap_text yview"

bind .tilemap_text <Control-a> {
    %W tag add sel 0.0 end; break;
}

bind .tilemap_text <Control-c> {
    clipboard clear
    clipboard append [selection get]
}

bind .tilemap_text <KeyPress> break

button .button_save_tilemap -pady 0 -padx 2m -text "Save" -width 8
bind .button_save_tilemap <ButtonPress> {
    tk_popup .tilemap_export_menu %X %Y
}

grid .button_save_tilemap -sticky wse -row 3 -column 1 -padx 0 -pady 0 -in .frame_tabs.notebook.tilemap

grid .tilemap_scroll_x -sticky nwe -row 1 -column 0 -columnspan 2 -padx 2 -pady 0 -in .frame_tabs.notebook.tilemap
grid .tilemap_scroll_y -sticky nsw -row 0 -column 2 -padx 0 -pady 2 -in .frame_tabs.notebook.tilemap

grid .tilemap_text -sticky wens -columnspan 2 -row 0 -column 0 -padx 1 -pady 1 -in .frame_tabs.notebook.tilemap

grid columnconfigure .frame_tabs.notebook.tilemap 0 -weight 1
grid rowconfigure    .frame_tabs.notebook.tilemap 0 -weight 1
grid columnconfigure .frame_tabs.notebook.tilemap 1 -weight 0
grid rowconfigure    .frame_tabs.notebook.tilemap 1 -weight 0
grid columnconfigure .frame_tabs.notebook.tilemap 2 -weight 0

# image display widget
labelframe .frame_image_name -text "" -relief flat

image create photo preview_image

frame .image_frame
label .image -image preview_image
.image configure -cursor tcross

bind .image <1> "imageClick %x %y"
bind .image <B1-Motion> "imageClick %x %y"

grid .frame_image_name -row 0 -column 0 -padx 0m -pady 2m -in .frame_tabs.notebook.image
grid .image_frame -row 0 -column 0 -padx 1m -pady 3m -in .frame_image_name
grid .image -sticky wens -row 0 -column 0 -padx 0m -pady 0m -in .image_frame
grid columnconfigure .frame_tabs.notebook.image 0 -weight 1
grid rowconfigure .frame_image_name 0 -weight 1
grid columnconfigure .frame_image_name 0 -weight 1

# canvas used to show the image palette
labelframe .frame_palette -text "Image palette:"
canvas .canvas_palette -width 511 -height 50 -borderwidth 0 -highlightthickness 0

.canvas_palette configure -cursor hand1

bind .canvas_palette <1> "itemStartDrag .canvas_palette %x %y"
bind .canvas_palette <B1-Motion> "itemDrag .canvas_palette %x %y"
bind .canvas_palette <ButtonRelease-1> "stopDrag"
bind .canvas_palette <Double-1> "showColorSelector"

# palette entry
entry .palette_entry -textvariable paletteEntryText -state readonly -font $fixed_font
bind .palette_entry <3> {
    tk_popup .text_menu %X %Y
    .text_menu entryconfigure 3 -command {
        global paletteEntryText
        
        catch {
            clipboard clear
            clipboard append [selection get]
        }
    }
    
    .text_menu entryconfigure 2 -command {
        global paletteEntryText
        
        clipboard clear
        clipboard append $paletteEntryText
    }
    
    .text_menu entryconfigure 0 -command {
        .palette_entry selection range 0 end
    }
}

button .button_save_palette -pady 0 -padx 2m -text "Save" -width 6
bind .button_save_palette <ButtonPress> {
    tk_popup .pal_save_menu %X %Y
}

grid .frame_palette  -row 1 -column 0 -padx 1m -pady 1m -in .frame_tabs.notebook.image
grid .canvas_palette -row 0 -column 0 -padx 1m -pady 1m -in .frame_palette
grid .palette_entry  -sticky wens -row 2 -column 0 -padx 1m -pady 1m -in .frame_palette
grid .button_save_palette -sticky e -row 3 -column 0 -padx 1m -pady 1m -in .frame_palette

grid columnconfigure .frame_palette 0 -weight 1 -uniform 1
grid rowconfigure    .frame_palette 1 -weight 1

.canvas_palette create line 16 35 16 52 -arrow first -fill black -tags "selection" -smooth true
.canvas_palette create rectangle 0 0 512 31 -fill "#000000" -width 0

for {set i 0} {$i < 15} {incr i} {
    set x1 [expr {$i * 32}]
    set x2 [expr {$x1 + 31}]

    .canvas_palette create rectangle $x1 0 $x2 31 -fill "#000000" -width 0 -tags "pal_color_$i"
}

.canvas_palette create rectangle [expr {15 * 32}] 0 [expr {15 * 32 + 31}] 31 -fill "#000000" -width 0 -tags "pal_color_15"


# layout setup
.pane add .frame_files
.pane add .frame_tabs

grid .frame_directory - -row 0 -column 0 -sticky ew   -padx 1m -pady 1m -in .app_frame

grid .frame_directory.e -sticky we -row 0 -column 0 -padx 1m -pady 1m -in .frame_directory
grid .frame_directory.b -sticky we -row 0 -column 1 -padx 1m -pady 1m -in .frame_directory

grid .frame_files.list    -sticky wens -row 0 -column 0 -padx 1m -pady 1m -in .frame_files
grid .frame_tabs.notebook -sticky wens -row 0 -column 0 -padx 1m -pady 1m -in .frame_tabs

grid columnconfigure .frame_directory 0 -weight 1 -uniform 1
grid columnconfigure .frame_files 0     -weight 1 -uniform 1
grid columnconfigure .frame_tabs 0      -weight 1 -uniform 1
grid columnconfigure .app_frame 0       -weight 99999
grid columnconfigure .app_frame 1       -weight 1 -uniform 1
grid rowconfigure    .app_frame 1       -weight 1
grid rowconfigure    .frame_files 0     -weight 1
grid rowconfigure    .frame_tabs 0      -weight 1

loadDir
