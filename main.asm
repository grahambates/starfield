                incdir  includes/
                include "macros.i"

                xdef    _start
_start:
                include "PhotonsMiniWrapper1.04!.S"


********************************************************************************
* Constants:
********************************************************************************

POINTS_COUNT = 608
ZOOM = 200

; Display window:
DIW_W = 320
DIW_H = 256
BPLS = 3
SCROLL = 0                              ; enable playfield scroll
INTERLEAVED = 1
DPF = 0                                 ; enable dual playfield

; Screen buffer:
; Add padding around screen buffers so we can skip out-of-bounds checks
SCREEN_W = DIW_W
SCREEN_H = DIW_H+1

DMA_SET = DMAF_SETCLR!DMAF_MASTER!DMAF_RASTER!DMAF_COPPER!DMAF_BLITTER

;-------------------------------------------------------------------------------
; Derived

COLORS = 1<<BPLS
SCREEN_BW = SCREEN_W/16*2               ; byte-width of 1 bitplane line
                ifne    INTERLEAVED
SCREEN_MOD = SCREEN_BW*(BPLS-1)         ; modulo (interleaved)
SCREEN_BPL = SCREEN_BW                  ; bitplane offset (interleaved)
                else
SCREEN_MOD = 0                          ; modulo (non-interleaved)
SCREEN_BPL = SCREEN_BW*SCREEN_H         ; bitplane offset (non-interleaved)
                endc
SCREEN_SIZE = SCREEN_BW*SCREEN_H*BPLS   ; byte size of screen buffer
DIW_BW = DIW_W/16*2
DIW_MOD = SCREEN_BW-DIW_BW+SCREEN_MOD-SCROLL*2
DIW_SIZE = DIW_BW*DIW_H*BPLS
DIW_XSTRT = ($242-DIW_W)/2
DIW_YSTRT = ($158-DIW_H)/2
DIW_XSTOP = DIW_XSTRT+DIW_W
DIW_YSTOP = DIW_YSTRT+DIW_H
DIW_STRT = (DIW_YSTRT<<8)!DIW_XSTRT
DIW_STOP = ((DIW_YSTOP-256)<<8)!(DIW_XSTOP-256)
DDF_STRT = ((DIW_XSTRT-17)>>1)&$00fc-SCROLL*8
DDF_STOP = ((DIW_XSTRT-17+(((DIW_W>>4)-1)<<4))>>1)&$00fc
BPLCON0V = BPLS<<(12+DPF)!DPF<<10!$200


********************************************************************************
* Entry points:
********************************************************************************

********************************************************************************
Demo:
;-------------------------------------------------------------------------------
                lea     custom,a6
                move.l  #Cop,cop1lc(a6)
                move.w  #DMA_SET,dmacon(a6)

; Init points
                lea     Points,a3
                move.w  #POINTS_COUNT-1,d7
.p:
; X
                bsr     Rand
                ext.w   d0
                move.w  d0,(a3)+
; Y
                bsr     Rand
                ext.w   d0
                move.w  d0,(a3)+
; Z
                bsr     Rand
                and.w   #$ff,d0         ; always positive 0-255
                move.w  d0,(a3)+
                dbf     d7,.p

MainLoop:
                bsr     SwapBuffers
                bsr     ClearScreen

; Calculate x/y/z movement speeds
                move.l  VBlank(pc),d0   ; d0 = frame
                add.w   d0,d0
                and.w   #$7fe,d0        ; d0 = sin/cos offset 1
                move.w  d0,d1
                add.w   d1,d1           ; Double for second offset
                and.w   #$7fe,d1        ; d1 = sin/cos offset 2
                moveq   #0,d2
                lea     Sin(pc),a0
                move.w  (a0,d0.w),d2
                add.w   (a0,d1.w),d2
                move.w  d2,d4           ; d4 = sin(t)+sin(2t) = x speed
                lea     Cos(pc),a1
                move.w  (a1,d0.w),d2
                add.w   (a1,d1.w),d2
                move.w  d2,d5           ; d5 = cos(t)+cos(2t) = y speed
                move.w  d1,d6           ; d6 = 2t + sin(2t) =  z speed
                add.w   (a0,d1.w),d6

                lea     Points,a0       ; a0 = points array
                move.l  DrawBuffer(pc),a1 ; a1 = draw buffer
                lea     DIW_H*BPLS/2*SCREEN_BW+DIW_BW/2(a1),a1 ; center
                lea     Log(pc),a2      ; a2 = log
                lea     ZOOM*2(a2),a3   ; a3 = log with Z offset
                lea     ExpX(pc),a4     ; a4 = expX: pre-computed byte offset and bit set values for plot
                lea     ExpY(pc),a5     ; a5 = expY: pre-computed multiplied by SCREEN_BW
                move.w  #SCREEN_BW,a6   ; a6 = SCREEN_BW
                move.l  a7,SpBak        ; back up SP for an extra register!
                move.l  #170*2,a7       ; a7 = z const 1 for bpl offset

; This needs to be a macro for dynamic labels in a REPT loop
AddBplOffset    macro
                cmp.w   a7,d2
                bhi.s   .\@
                add.w   a6,d0
                cmp.w   #85*2,d2        ; No free register for this :-(
                bhi.s   .\@
                add.w   a6,d0
.\@:
                endm

UNROLL = 16                             ; Unroll inner loop
                move.w  #POINTS_COUNT/UNROLL-1,d7
.p:
                rept    UNROLL
                movem.w (a0)+,d0-d2     ; x/y/z
                add.b   d4,d0           ; increment X
                ext.w   d0
                sub.b   d5,d1           ; increment Y
                ext.w   d1
                sub.b   d6,d2           ; increment Z - no need to ext, always positive 0-255

; Apply perspective:
; Use exp/log LUT to avoid divs:
; a/b=exp2(log2(a)-log2(b))
                add.w   d0,d0           ; *2 for offset
                add.w   d1,d1           ; "
                add.w   d2,d2           ; "
                move.w  (a2,d0.w),d0    ; d0 = log2(x)
                move.w  (a2,d1.w),d1    ; d1 = log2(y)
                move.w  (a3,d2.w),d3    ; d3 = log2(z + ZOOM) (need to keep Z in d2 for bpl offset)
                sub.w   d3,d0           ; log2(x)-log2(z)
                sub.w   d3,d1           ; log2(y)-log2(z)
                add.w   d0,d0           ; x LUT contains 2 words - double the offset
                movem.w (a4,d0.w),d0/d3 ; d0 = x byte offset, d3 = bit to set
                add.w   (a5,d1.w),d0    ; d0 += y byte offset
                AddBplOffset
                bset.b  d3,(a1,d0.w)    ; Plot point
                endr

                dbf     d7,.p

                add.l   #1,VBlank       ; Increment frame

                move.l  SpBak(pc),a7
                lea     custom,a6
                ; move.w  #$f00,color00(a6) ; Show raster time
                bsr     WaitEOF
                bra     MainLoop


********************************************************************************
* Routines:
********************************************************************************

********************************************************************************
ClearScreen:
;-------------------------------------------------------------------------------
                move.l  ClearBuffer(pc),a0
                move.w  #0,bltdmod(a6)  ; Don't need to clear outside visible window
                move.l  #$01000000,bltcon0(a6)
                move.l  a0,bltdpt(a6)
                move.w  #SCREEN_H*BPLS*64+SCREEN_BW/2,bltsize(a6)
                rts

********************************************************************************
SwapBuffers:
;-------------------------------------------------------------------------------
                lea     DrawBuffer(pc),a0
                movem.l (a0),d0-d2
                exg     d0,d2
                exg     d0,d1
                movem.l d0-d2,(a0)
; Set bpl pointers in copper
                lea     CopBplPt+2,a1
                moveq   #BPLS-1,d0
.bpll:          move.l  d2,d1
                swap    d1
                move.w  d1,(a1)         ; high word of address
                move.w  d2,4(a1)        ; low word of address
                addq.w  #8,a1           ; next copper instruction
                add.l   #SCREEN_BPL,d2  ; next bpl ptr
                dbf     d0,.bpll
                rts

********************************************************************************
Rand:
;-------------------------------------------------------------------------------
                lea     .rand(pc),a0
                lea     4(a0),a1
                move.l  (a0),d0         ; AB
                move.l  (a1),d1         ; CD
                swap    d1              ; DC
                add.l   d1,(a0)         ; AB + DC
                add.l   d0,(a1)         ; CD + AB
                rts
.rand:          dc.l    $3e50b28c
                dc.l    $d461a7f9

********************************************************************************
* Variables
********************************************************************************

VBlank:         dc.l    0
DrawBuffer:     dc.l    Screen1
ClearBuffer:    dc.l    Screen2
ViewBuffer:     dc.l    Screen3
SpBak:          dc.l    0

********************************************************************************
* Data
********************************************************************************

                include "data/logExp.i"
                include "data/sin.i"


*******************************************************************************
                bss
*******************************************************************************

Points:         ds.w    POINTS_COUNT*3


*******************************************************************************
                data_c
*******************************************************************************

;--------------------------------------------------------------------------------
; Main copper list:
Cop:
                COP_MOVE 0,fmode
                COP_MOVE DIW_STRT,diwstrt
                COP_MOVE DIW_STOP,diwstop
                COP_MOVE DDF_STRT,ddfstrt
                COP_MOVE DDF_STOP,ddfstop
CopBplCon:
                COP_MOVE BPLCON0V,bplcon0
                COP_MOVE 0,bplcon1
                COP_MOVE 0,bplcon2
                COP_MOVE 0,bplcon3
CopBplMod:
                COP_MOVE DIW_MOD,bpl1mod
                COP_MOVE DIW_MOD,bpl2mod
CopBplPt:
                rept    BPLS*2
                COP_MOVE 0,bpl0pt+REPTN*2
                endr
CopPal:
                COP_MOVE $000,color00
                COP_MOVE $555,color01
                COP_MOVE $aaa,color02
                COP_MOVE $aaa,color03
                COP_MOVE $fff,color04
                COP_MOVE $fff,color05
                COP_MOVE $fff,color06
                COP_MOVE $fff,color07

                COP_END


*******************************************************************************
                bss_c
*******************************************************************************

Screen1:        ds.b    SCREEN_SIZE
Screen2:        ds.b    SCREEN_SIZE
Screen3:        ds.b    SCREEN_SIZE
