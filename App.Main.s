; SpaceHarrier GS — Apple IIgs GS/OS S16 application
; Porting FTA's Space Harrier (1989) one routine at a time
;
; Step 2: Compiled sprite engine — compile and draw Harrier via FTA's system

            REL
            DSK    MAINSEG

            use    Misc.Macs.s
            use    EDS.GSOS.Macs.s
            use    Util.Macs.s
            use    FTA.Macs.s

            mx     %00

; === Hardware registers ===
NEW_VIDEO_REG equ  $E0C029
SHADOW_REG    equ  $E0C035
STATEREG      equ  $E0C068  ; State Register: bit5=RAMRD, bit4=RAMWRT
KBD_DATA      equ  $E0C000
KBD_STROBE    equ  $E0C010
SHR_SCREEN    equ  $E12000
SHR_SCB       equ  $E19D00
SHR_PALETTES  equ  $E19E00

; === FTA compiled routine addresses ===
NEWPAGE0        equ  $0F00
TABLE_ROUT      equ  $03F100
Damier_Rout     equ  $040000
TSB_Rout        equ  $050000
Buf_SCB         equ  $05FF00
Clear_Rout      equ  $0E0000     ; moved from $060000 (our code bank)
Man_Rout        equ  $070000
Mountain_Rout   equ  $080000
ROUT0           equ  $0B0000
ROUT1           equ  $0C0000
ROUT2           equ  $0D0000
Chiffre_Rout    equ  $0F0000

; === FTA game constants ===
Box_Lgn         equ  $1C
Box_NbLgn       equ  $C4-$1C
Box_Col         equ  $0
Box_NbCol       equ  $80
Clear_NbLgn     equ  $A8-$3C+$11-$E

; === FTA shape data addresses ===
Decor_Mountain  equ  $090000
Tree_Shape      equ  $0A0004
Explo_Shape     equ  $0A2804
Tir_Shape       equ  $0A4004
Pierre_Shape    equ  $0A4404
Chiffre_Shape   equ  $0A5000
Ombre_Shape     equ  $0A6004
Buisson_Shape   equ  $0A7004
Ship_Shape      equ  $0A8004
Trident_Shape   equ  $0A9004
Divers_Shape    equ  $0AA204
Face_Shape      equ  $0C5004
Der_Shape       equ  $0C7004
Mid_Shape       equ  $0C9004
Back_Shape      equ  $0CB004

; === Shape counts ===
Nb_Tree         equ  16
Nb_Explo        equ  11
Nb_Tir          equ  11
Nb_Pierre       equ  8
Nb_Ombre        equ  8
Nb_Buisson      equ  14
Nb_Ship         equ  15
Nb_Trident      equ  9
Nb_Shape        equ  32
Taille          equ  16

; =====================================================================
; Entry point
; =====================================================================
            phk
            plb
            sta    MyUserId
            tdc
            sta    MyDirectPage

            _MTStartUp

            jsr    SHR_Init
            jsr    SetupLoadPalette
            jsr    LoadAssets

            jsr    CompileSprites
            jsr    SetupPalettes

; =====================================================================
; Game loop — draw Harrier sprite, wait for ESC
; =====================================================================
; The compiled sprite expects Y = screen address (TBA[row] + col).
; After JSL, the compiled routine handles RAMRD/RAMWRT internally.

:gameloop
            ; Draw Harrier at row 100, col 60
            lda    #100
            asl
            tax
            lda    TBA,x
            clc
            adc    #60
            tay
            jsl    TABLE_ROUT+4       ; Man frame 0 (entry 1)

            ; Large tree (frame 0) at row 20, col 5
            lda    #20
            asl
            tax
            lda    TBA,x
            clc
            adc    #5
            tay
            jsl    TABLE_ROUT+$60     ; Tree frame 0 (entry 24) — largest

            ; Medium tree (frame 8) at row 60, col 40
            lda    #60
            asl
            tax
            lda    TBA,x
            clc
            adc    #40
            tay
            jsl    TABLE_ROUT+$80     ; Tree frame 8 (entry 32)

            ; Small tree (frame 15) at row 80, col 10
            lda    #80
            asl
            tax
            lda    TBA,x
            clc
            adc    #10
            tay
            jsl    TABLE_ROUT+$9C     ; Tree frame 15 (entry 39) — smallest

            ; Buisson/bush (frame 0) at row 30, col 100
            lda    #30
            asl
            tax
            lda    TBA,x
            clc
            adc    #100
            tay
            jsl    TABLE_ROUT+$138    ; Buisson frame 0 (entry 78) — largest

            ; Pierre/rock (frame 0) at row 50, col 70
            lda    #50
            asl
            tax
            lda    TBA,x
            clc
            adc    #70
            tay
            jsl    TABLE_ROUT+$F8     ; Pierre frame 0 (entry 62) — largest

            ; Ship (frame 0) at row 10, col 110
            lda    #10
            asl
            tax
            lda    TBA,x
            clc
            adc    #110
            tay
            jsl    TABLE_ROUT+$170    ; Ship frame 0 (entry 92) — largest

            ; Explosion (frame 5) at row 40, col 130
            lda    #40
            asl
            tax
            lda    TBA,x
            clc
            adc    #130
            tay
            jsl    TABLE_ROUT+$B4     ; Explo frame 5 (entry 45)

            ; Trident (frame 0) at row 15, col 55
            lda    #15
            asl
            tax
            lda    TBA,x
            clc
            adc    #55
            tay
            jsl    TABLE_ROUT+$1AC    ; Trident frame 0 (entry 107) — largest

            ; Poll keyboard
            sep    #$20
            mx     %10
            ldal   KBD_DATA
            bpl    :nokey
            and    #$7F
            stal   KBD_STROBE
            cmp    #$1B
            beq    :quit
:nokey
            rep    #$20
            mx     %00
            jmp    :gameloop

:quit       rep    #$20
            mx     %00

DoQuit      jsr    SHR_Off
            _MTShutDown
            _QuitGS qtRec
            brk    $00

; =====================================================================
; SetupLoadPalette — minimal palette for load indicator bar
; =====================================================================
SetupLoadPalette
            lda    #0
            ldx    #0
:clr        stal   SHR_PALETTES,x
            inx
            inx
            cpx    #$200
            bcc    :clr
            lda    #$00F0
            stal   SHR_PALETTES+2  ; color 1 = green
            lda    #$0F00
            stal   SHR_PALETTES+4  ; color 2 = red
            lda    #$0FF0
            stal   SHR_PALETTES+$12 ; color 9 = yellow (marker 1)
            lda    #$000F
            stal   SHR_PALETTES+$1A ; color D = blue (marker 2)
            lda    #$0FFF
            stal   SHR_PALETTES+$1E ; color F = white (marker 3)
            lda    #$0F0F
            stal   SHR_PALETTES+$14 ; color A = magenta (marker 4)
            lda    #$0888
            stal   SHR_PALETTES+$0A ; color 5 = gray (marker 5)
            rts

; =====================================================================
; SetupPalettes — set sprite and background colors in all palettes
;
; FTA copies palette 0 to all 16 palettes, then patches sky colors.
; For now: set sprite colors in palette 0 and copy to all palettes.
; =====================================================================
SetupPalettes
            ; First clear all palettes
            lda    #0
            ldx    #0
:clr        stal   SHR_PALETTES,x
            inx
            inx
            cpx    #$200
            bcc    :clr

            ; FTA game palette (from sprite .PIC files: ARBRE, ENEMI, MAN, etc.)
            ; All sprite source files share this palette for colors 0-F.
            lda    #$0000           ; 0: black (background/transparent)
            stal   SHR_PALETTES+$00
            lda    #$0244           ; 1: dark blue
            stal   SHR_PALETTES+$02
            lda    #$0466           ; 2: blue-grey
            stal   SHR_PALETTES+$04
            lda    #$0449           ; 3: blue
            stal   SHR_PALETTES+$06
            lda    #$00F6           ; 4: bright green
            stal   SHR_PALETTES+$08
            lda    #$0092           ; 5: green
            stal   SHR_PALETTES+$0A
            lda    #$0640           ; 6: red-brown
            stal   SHR_PALETTES+$0C
            lda    #$0699           ; 7: blue-grey
            stal   SHR_PALETTES+$0E
            lda    #$0D94           ; 8: orange/skin
            stal   SHR_PALETTES+$10
            lda    #$0FD4           ; 9: bright yellow (hair)
            stal   SHR_PALETTES+$12
            lda    #$0D40           ; A: red-orange (shirt)
            stal   SHR_PALETTES+$14
            lda    #$069D           ; B: medium blue (pants)
            stal   SHR_PALETTES+$16
            lda    #$00D4           ; C: green
            stal   SHR_PALETTES+$18
            lda    #$0062           ; D: dark green
            stal   SHR_PALETTES+$1A
            lda    #$0094           ; E: green (transparent in sprites)
            stal   SHR_PALETTES+$1C
            lda    #$0FFF           ; F: white
            stal   SHR_PALETTES+$1E

            ; Copy palette 0 to all other palettes (1-15)
            ldx    #0
:cppal      lda    SHR_PALETTES+$00,x
            stal   SHR_PALETTES+$20,x
            stal   SHR_PALETTES+$40,x
            stal   SHR_PALETTES+$60,x
            stal   SHR_PALETTES+$80,x
            stal   SHR_PALETTES+$A0,x
            stal   SHR_PALETTES+$C0,x
            stal   SHR_PALETTES+$E0,x
            stal   SHR_PALETTES+$100,x
            stal   SHR_PALETTES+$120,x
            stal   SHR_PALETTES+$140,x
            stal   SHR_PALETTES+$160,x
            stal   SHR_PALETTES+$180,x
            stal   SHR_PALETTES+$1A0,x
            stal   SHR_PALETTES+$1C0,x
            stal   SHR_PALETTES+$1E0,x
            inx
            inx
            cpx    #$20
            bne    :cppal

            ; Fill screen with sky color (color 0)
            lda    #0
            ldx    #0
:sky        stal   SHR_SCREEN,x
            inx
            inx
            cpx    #$7D00
            bcc    :sky
            rts

; =====================================================================
; CompileSprites — compile all shapes using FTA's sprite compiler
;
; Create_Sprite requires its parameter table at DP offsets $00-$17.
; We use DP offsets $18-$23 for our own loop variables.
; =====================================================================

; Extra DP offsets for CompileSprites (outside sprite table $00-$17)
_FrmTblPtr  equ   $18    ; 3 bytes: 24-bit ptr to per-frame table
_ShpBase    equ   $1C    ; 4 bytes: base shape ADRL
_FrmCnt     equ   $20    ; 2 bytes: remaining frame count
_FrmIdx     equ   $22    ; 2 bytes: offset into per-frame table (×6)

CompileSprites
            lda    MyDirectPage
            tcd

            ; Store code bank for indirect long addressing later
            phk
            sep    #$20
            pla
            sta    _FrmTblPtr+2
            rep    #$20

            ; =========================================
            ; Man — 19 frames, all 48 rows × 16 bytes
            ; =========================================
            ldx    #0
:cpman      lda    Man_Tbl,x
            sta    $00,x
            inx
            inx
            cpx    #$18
            bne    :cpman

            lda    #19
            sta    _FrmCnt
:manloop    lda    MyDirectPage
            jsr    Create_Sprite
            clc
            lda    $04               ; _ShapeAdr (auto-advanced past data)
            adc    #4                ; skip next frame's 4-byte header
            sta    $04
            dec    _FrmCnt
            bne    :manloop

            ; =========================================
            ; Object shapes — common DP fields
            ; =========================================
            lda    #$FF00
            sta    $08               ; _MskAdr = $FFFF00 (auto-mask)
            lda    #$00FF
            sta    $0A
            lda    #$FFFF
            sta    $12               ; _Lgn = dynamic
            sta    $14               ; _Col = dynamic
            stz    $16               ; _Pixel = 0
            lda    #24
            sta    $0C               ; _TblNb = 24 for objects

            ; --- ROUT0 group ($0B0000): Tree, Explo, Tir, Pierre, Ombre ---
            stz    $00
            sep    #$20
            lda    #^ROUT0
            sta    $02
            stz    $03
            rep    #$20

            lda    #Tbl_Tree
            sta    _FrmTblPtr
            lda    #Tree_Shape
            sta    _ShpBase
            sep    #$20
            lda    #^Tree_Shape
            sta    _ShpBase+2
            stz    _ShpBase+3
            rep    #$20
            lda    #Nb_Tree
            sta    _FrmCnt
            jsr    CompileOneType

            lda    #Tbl_Explo
            sta    _FrmTblPtr
            lda    #Explo_Shape
            sta    _ShpBase
            sep    #$20
            lda    #^Explo_Shape
            sta    _ShpBase+2
            stz    _ShpBase+3
            rep    #$20
            lda    #Nb_Explo
            sta    _FrmCnt
            jsr    CompileOneType

            lda    #Tbl_Tir
            sta    _FrmTblPtr
            lda    #Tir_Shape
            sta    _ShpBase
            sep    #$20
            lda    #^Tir_Shape
            sta    _ShpBase+2
            stz    _ShpBase+3
            rep    #$20
            lda    #Nb_Tir
            sta    _FrmCnt
            jsr    CompileOneType

            lda    #Tbl_Pierre
            sta    _FrmTblPtr
            lda    #Pierre_Shape
            sta    _ShpBase
            sep    #$20
            lda    #^Pierre_Shape
            sta    _ShpBase+2
            stz    _ShpBase+3
            rep    #$20
            lda    #Nb_Pierre
            sta    _FrmCnt
            jsr    CompileOneType

            lda    #Tbl_Ombre
            sta    _FrmTblPtr
            lda    #Ombre_Shape
            sta    _ShpBase
            sep    #$20
            lda    #^Ombre_Shape
            sta    _ShpBase+2
            stz    _ShpBase+3
            rep    #$20
            lda    #Nb_Ombre
            sta    _FrmCnt
            jsr    CompileOneType

            ; --- ROUT1 group ($0C0000): Buisson, Ship, Trident ---
            stz    $00
            sep    #$20
            lda    #^ROUT1
            sta    $02
            stz    $03
            rep    #$20

            lda    #Tbl_Buisson
            sta    _FrmTblPtr
            lda    #Buisson_Shape
            sta    _ShpBase
            sep    #$20
            lda    #^Buisson_Shape
            sta    _ShpBase+2
            stz    _ShpBase+3
            rep    #$20
            lda    #Nb_Buisson
            sta    _FrmCnt
            jsr    CompileOneType

            lda    #Tbl_Ship
            sta    _FrmTblPtr
            lda    #Ship_Shape
            sta    _ShpBase
            sep    #$20
            lda    #^Ship_Shape
            sta    _ShpBase+2
            stz    _ShpBase+3
            rep    #$20
            lda    #Nb_Ship
            sta    _FrmCnt
            jsr    CompileOneType

            lda    #Tbl_Trident
            sta    _FrmTblPtr
            lda    #Trident_Shape
            sta    _ShpBase
            sep    #$20
            lda    #^Trident_Shape
            sta    _ShpBase+2
            stz    _ShpBase+3
            rep    #$20
            lda    #Nb_Trident
            sta    _FrmCnt
            jsr    CompileOneType

            ; Restore DP
            lda    #0
            tcd
            rts

; ---------------------------------------------------------------------
; CompileOneType — compile all frames of one shape type
;   Reads per-frame table via [_FrmTblPtr],Y (offset, NbLgn, NbCol)
;   Adds offset to _ShpBase for _ShapeAdr
;   _RoutAdr and _TblNb auto-advance via Create_Sprite
; ---------------------------------------------------------------------
CompileOneType
            stz    _FrmIdx
:cotLoop    ldy    _FrmIdx
            ; _ShapeAdr = _ShpBase + offset
            lda    [_FrmTblPtr],y
            clc
            adc    _ShpBase
            sta    $04               ; _ShapeAdr low word
            lda    _ShpBase+2
            adc    #0
            sta    $06               ; _ShapeAdr bank
            ; _NbLgn
            iny
            iny
            lda    [_FrmTblPtr],y
            sta    $0E
            ; _NbCol
            iny
            iny
            lda    [_FrmTblPtr],y
            sta    $10
            ; Advance frame index by 6 (3 words per entry)
            lda    _FrmIdx
            clc
            adc    #6
            sta    _FrmIdx
            ; Compile this frame
            lda    MyDirectPage
            jsr    Create_Sprite
            dec    _FrmCnt
            bne    :cotLoop
            rts


; =====================================================================
; LoadAssets — walk AssetTbl, load each file, draw indicator block.
; =====================================================================
LoadAssets
            stz    FileIdx
            stz    LoadCount
            ldy    #0
:loop
            lda    AssetTbl+0,y
            ora    AssetTbl+2,y
            beq    :done
            lda    AssetTbl+0,y
            sta    LF_DestAddr+0
            lda    AssetTbl+2,y
            sta    LF_DestAddr+2
            lda    AssetTbl+4,y
            sta    LF_Path+0
            lda    AssetTbl+6,y
            sta    LF_Path+2
            phy
            jsr    LoadOneFile
            jsr    DrawFileBlock
            ply
            inc    FileIdx
            tya
            clc
            adc    #8
            tay
            bra    :loop
:done       rts

; =====================================================================
; LoadOneFile — open, read to fixed address, close.
; =====================================================================
LoadOneFile
            stz    LoadSuccess
            lda    LF_Path+0
            sta    _opPath+0
            lda    LF_Path+2
            sta    _opPath+2
            _OpenGS _opRec
            bcc    :opened
            brl    :exit
:opened
            lda    _opRefNum
            sta    _eofRefNum
            sta    _rdRefNum
            sta    _clRefNum
            _GetEOFGS _eofRec
            bcc    :gotEOF
            brl    :closeExit
:gotEOF
            lda    LF_DestAddr+0
            sta    _rdBuffer
            lda    LF_DestAddr+2
            sta    _rdBuffer+2
            lda    _eofEOF
            sta    _rdReqCount
            lda    _eofEOF+2
            sta    _rdReqCount+2
            _ReadGS _rdRec
            bcc    :readOK
            brl    :closeExit
:readOK
            _CloseGS _clRec
            lda    FileIdx
            asl
            asl
            tax
            lda    LF_DestAddr+0
            sta    AssetPtrs,x
            lda    LF_DestAddr+2
            sta    AssetPtrs+2,x
            lda    #1
            sta    LoadSuccess
            inc    LoadCount
            rts
:closeExit  _CloseGS _clRec
:exit       rts

; =====================================================================
; DrawFileBlock — 8x8 green/red indicator at top of screen.
; =====================================================================
DrawFileBlock
            lda    LoadSuccess
            bne    :green
            lda    #$2222
            bra    :setc
:green      lda    #$1111
:setc       sta    _bcolor
            lda    FileIdx
            asl
            asl
            asl
            sta    _bbase
            ldy    #8
:row
            lda    _bbase
            tax
            lda    _bcolor
            stal   SHR_SCREEN,x
            inx
            inx
            stal   SHR_SCREEN,x
            inx
            inx
            stal   SHR_SCREEN,x
            inx
            inx
            stal   SHR_SCREEN,x
            lda    _bbase
            clc
            adc    #160
            sta    _bbase
            dey
            bne    :row
            rts

; =====================================================================
; SHR_Init — enable Super Hi-Res, clear screen.
; =====================================================================
SHR_Init
            sep    #$20
            mx     %10
            ldal   SHADOW_REG
            and    #$F7            ; clear bit 3: enable SHR shadowing
            stal   SHADOW_REG
            lda    #$C1
            stal   NEW_VIDEO_REG
            rep    #$20
            mx     %00
            lda    #0
            ldx    #0
:scb        stal   SHR_SCB,x
            inx
            inx
            cpx    #200
            bcc    :scb
            ldx    #0
:clr        stal   SHR_SCREEN,x
            inx
            inx
            cpx    #$7D00
            bcc    :clr
            rts

; =====================================================================
; SHR_Off — disable Super Hi-Res before quitting.
; =====================================================================
SHR_Off
            sep    #$20
            mx     %10
            lda    #$00
            stal   NEW_VIDEO_REG
            ldal   SHADOW_REG
            ora    #$08
            stal   SHADOW_REG
            rep    #$20
            mx     %00
            rts

; =====================================================================
; FTA Compiled Sprite Engine (ported from CREATE.SPRITE.S)
; =====================================================================
            PUT    Create.Sprite

; =====================================================================
; GS/OS inline parameter records
; =====================================================================
_opRec
_opPCount   da     2
_opRefNum   da     0
_opPath     adrl   0

_clRec
_clPCount   da     1
_clRefNum   da     0

_eofRec
_eofPCount  da     2
_eofRefNum  da     0
_eofEOF     da     0
_eofEOFhi   da     0

_rdRec
_rdPCount   da     4
_rdRefNum   da     0
_rdBuffer   adrl   0
_rdReqCount da     0
_rdReqCtHi  da     0
_rdXferCount da    0
_rdXferCtHi da     0

; =====================================================================
; Man_Tbl — Harrier sprite table for Create_Sprite
;
; 19 animation frames, all 48×16 (48 rows, 16 bytes = 32 pixels wide).
; Compiled into TABLE_ROUT entries 1-19.
; Each frame has a 4-byte header in SHAPE.RUN that gets skipped.
; =====================================================================
Man_Tbl
Man_RoutAdr adrl   Man_Rout         ; $00: output addr for compiled code
Man_ShpAdr  adrl   $0AB004          ; $04: SHAPE.RUN data + skip header
            adrl   $FFFF00          ; $08: auto-mask
            da     1                ; $0C: TblNb (TABLE_ROUT index)
            da     $30              ; $0E: Nb_Lgn (48 bytes per shape row)
            da     $10              ; $10: Nb_Col (16 bytes = 32 pixels)
            da     $FFFF            ; $12: Lgn (dynamic)
            da     $FFFF            ; $14: Col (dynamic)
            da     $00              ; $16: Pixel_Shape

; =====================================================================
; Per-frame shape tables (from FTA's SPACE.S)
; Each entry: DA offset, NbLgn, NbCol (3 words = 6 bytes)
;   offset = byte offset from shape base address
;   NbLgn  = height in rows
;   NbCol  = width in bytes (2 pixels per byte in SHR 4bpp)
; =====================================================================

Tbl_Tree
            da     $0000,$79,$20
            da     $0F30,$50,$16
            da     $1620,$3C,$10
            da     $19F0,$30,$0C
            da     $1C40,$28,$0A
            da     $1DE0,$21,$0A
            da     $1F30,$1D,$08
            da     $2020,$19,$08
            da     $20F0,$17,$06
            da     $2180,$14,$06
            da     $2200,$13,$06
            da     $2278,$11,$06
            da     $22E8,$11,$04
            da     $2330,$10,$04
            da     $2378,$0F,$04
            da     $23C0,$0E,$04

Tbl_Explo
            da     0,36,48
            da     1732,29,44
            da     3012,23,32
            da     3752,19,30
            da     4326,18,24
            da     4762,15,22
            da     5096,14,20
            da     5380,12,16
            da     5576,10,14
            da     5720,9,12
            da     5832,8,12

Tbl_Tir
            da     0,14,16
            da     228,14,14
            da     428,10,10
            da     532,8,8
            da     600,7,6
            da     646,6,6
            da     686,5,6
            da     720,4,4
            da     740,4,4
            da     760,4,4
            da     780,3,3

Tbl_Pierre
            da     0,29,38
            da     1106,20,24
            da     1590,14,18
            da     1846,11,16
            da     2026,10,14
            da     2170,9,12
            da     2282,7,10
            da     2356,6,10

Tbl_Ombre
            da     0,12,26
            da     316,9,18
            da     482,6,14
            da     570,5,10
            da     624,4,8
            da     660,3,8
            da     688,2,6
            da     704,1,6

Tbl_Buisson
            da     0,29,36
            da     1048,18,24
            da     1484,14,18
            da     1740,11,14
            da     1898,9,12
            da     2010,8,10
            da     2094,7,10
            da     2168,6,8
            da     2220,5,8
            da     2264,5,6
            da     2298,4,6
            da     2326,4,6
            da     2354,4,6
            da     2383,2,6

Tbl_Ship
            da     0,35,46
            da     1614,22,30
            da     2278,16,24
            da     2666,13,18
            da     2904,10,16
            da     3068,9,14
            da     3198,7,12
            da     3286,6,10
            da     3350,6,8
            da     3402,5,8
            da     3446,4,8
            da     3482,4,8
            da     3518,4,6
            da     3546,3,6
            da     3568,3,6

Tbl_Trident
            da     0,48,32
            da     1540,42,28
            da     2720,34,24
            da     3540,23,16
            da     3912,18,14
            da     4168,15,12
            da     4352,12,10
            da     4476,11,8
            da     4568,7,4

; =====================================================================
; Asset table
; =====================================================================
AssetTbl
            adrl   $110000         ; MUS/BLUE.WBNK
            adrl   _pBLUEW
            adrl   $100000         ; MUS/BLUE.MONDAY
            adrl   _pBLUEM
            adrl   $0AB000         ; SHAPE.RUN
            adrl   _pSHAPER
            adrl   $090000         ; MOUNT
            adrl   _pMOUNT
            adrl   $0A0000         ; PIC/TREE.SHAPE
            adrl   _pTREE
            adrl   $0A2800         ; PIC/EXPLO.SHP
            adrl   _pEXPLO
            adrl   $0A4000         ; PIC/TIR.SHP
            adrl   _pTIR
            adrl   $0A4400         ; PIC/PIERRE.SHP
            adrl   _pPIERRE
            adrl   $0A5000         ; PIC/NUM.SHP
            adrl   _pNUM
            adrl   $0A6000         ; PIC/OMBRE.SHP
            adrl   _pOMBRE
            adrl   $0A7000         ; PIC/BUISSON.SHP
            adrl   _pBUISSO
            adrl   $0A8000         ; PIC2/SHIP.SHP
            adrl   _pSHIP
            adrl   $0A9000         ; PIC2/TRIDENT.SHP
            adrl   _pTRIDEN
            adrl   $0AA200         ; PIC2/DIVERS.SHP
            adrl   _pDIVERS
            adrl   $0C5000         ; DRAGON/FACE.SHP
            adrl   _pFACE
            adrl   $0C7000         ; DRAGON/DER.SHP
            adrl   _pDER
            adrl   $0C9000         ; DRAGON/MID.SHP
            adrl   _pMID
            adrl   $0CB000         ; DRAGON/BACK.SHP
            adrl   _pBACK
            adrl   0               ; sentinel
            adrl   0

; =====================================================================
; GS/OS path strings
; =====================================================================
_pBLUEW     da    13
            asc   'MUS/BLUE.WBNK'
_pBLUEM     da    15
            asc   'MUS/BLUE.MONDAY'
_pSHAPER    da    9
            asc   'SHAPE.RUN'
_pMOUNT     da    5
            asc   'MOUNT'
_pTREE      da    14
            asc   'PIC/TREE.SHAPE'
_pEXPLO     da    13
            asc   'PIC/EXPLO.SHP'
_pTIR       da    11
            asc   'PIC/TIR.SHP'
_pPIERRE    da    14
            asc   'PIC/PIERRE.SHP'
_pNUM       da    11
            asc   'PIC/NUM.SHP'
_pOMBRE     da    13
            asc   'PIC/OMBRE.SHP'
_pBUISSO    da    15
            asc   'PIC/BUISSON.SHP'
_pSHIP      da    13
            asc   'PIC2/SHIP.SHP'
_pTRIDEN    da    16
            asc   'PIC2/TRIDENT.SHP'
_pDIVERS    da    15
            asc   'PIC2/DIVERS.SHP'
_pFACE      da    15
            asc   'DRAGON/FACE.SHP'
_pDER       da    14
            asc   'DRAGON/DER.SHP'
_pMID       da    14
            asc   'DRAGON/MID.SHP'
_pBACK      da    15
            asc   'DRAGON/BACK.SHP'

; =====================================================================
; FTA Tables
; =====================================================================

; TBA — Screen row address table (200 entries, 2 bytes each)
; TBA[row] = $2000 + row * $A0
TBA
            hex   0020A0204021E02180222023C0236024
            hex   0025A0254026E02680272028C0286029
            hex   002AA02A402BE02B802C202DC02D602E
            hex   002FA02F4030E03080312032C0326033
            hex   0034A0344035E03580362037C0376038
            hex   0039A039403AE03A803B203CC03C603D
            hex   003EA03E403FE03F80402041C0416042
            hex   0043A0434044E04480452046C0466047
            hex   0048A0484049E049804A204BC04B604C
            hex   004DA04D404EE04E804F2050C0506051
            hex   0052A0524053E05380542055C0556056
            hex   0057A0574058E0588059205AC05A605B
            hex   005CA05C405DE05D805E205FC05F6060
            hex   0061A0614062E06280632064C0646065
            hex   0066A0664067E06780682069C069606A
            hex   006BA06B406CE06C806D206EC06E606F
            hex   0070A0704071E07180722073C0736074
            hex   0075A0754076E07680772078C0786079
            hex   007AA07A407BE07B807C207DC07D607E
            hex   007FA07F4080E08080812082C0826083
            hex   0084A0844085E08580862087C0876088
            hex   0089A089408AE08A808B208CC08C608D
            hex   008EA08E408FE08F80902091C0916092
            hex   0093A0934094E09480952096C0966097
            hex   0098A0984099E099809A209BC09B609C

; TBL_MSK — Auto-mask lookup (256 bytes)
; Color $E nibbles → mask bits $F
TBL_MSK
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   00000000000000000000000000000F00
            hex   F0F0F0F0F0F0F0F0F0F0F0F0F0F0FFF0
            hex   00000000000000000000000000000F00

; =====================================================================
; Variables
; =====================================================================

; --- LoadOneFile ---
LF_Path     ds    4
LF_DestAddr ds    4

; --- Asset loading state ---
LoadSuccess ds    2
LoadCount   ds    2
FileIdx     ds    2

; --- DrawFileBlock ---
_bcolor     ds    2
_bbase      ds    2

; --- AssetPtrs: 24-bit address of each loaded asset (4 bytes/slot) ---
AssetPtrs   ds    4*18

; =====================================================================
; Quit record / app state
; =====================================================================
qtRec       adrl  $0000
MyDirectPage ds   2
MyUserId     ds   2
