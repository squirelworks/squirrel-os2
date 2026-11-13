; Warp 4 theme (W.1): every colour and size the window manager, the widgets
; and the desktop draw with. Colours are palette indices: the text mode's EGA
; palette, which the DAC keeps in mode 13h (bright colours at 0x38-0x3F).
; Code uses these names, never the numbers (documentation/kernel/windows.md).

TH_DESKTOP          equ 0x03    ; cyan desktop
TH_FACE             equ 0x07    ; 3D face grey
TH_LIGHT            equ 0x3F    ; bevel highlight, white
TH_SHADOW           equ 0x38    ; bevel shadow, dark grey
TH_DARK             equ 0x00    ; outer bevel edge, black
TH_FRAME            equ 0x3F    ; window frame
TH_TITLE            equ 0x01    ; title bar of the focused window, blue
TH_TITLE_IDLE       equ 0x38    ; title bar of the others, dark grey
TH_TITLE_TEXT       equ 0x3F    ; title text, white
TH_CLIENT           equ 0x07    ; client area, light grey
TH_TEXT             equ 0x00    ; text on the client area, black
TH_BTN_FACE         equ 0x3F    ; button face
TH_POINTER          equ 0x0F    ; the mouse pointer (mouse.asm)
TH_SELECT           equ 0x01    ; a chosen menu row (2.2-sysmenu)
TH_SELECT_TEXT      equ 0x3F
TH_BEVEL_W          equ 2       ; rings in a bevel (gfx_bevel)
