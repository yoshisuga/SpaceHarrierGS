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
SHADOW_REG    equ  $E1C035
STATEREG      equ  $E0C068  ; State Register: bit5=RAMRD, bit4=RAMWRT
KBD_DATA      equ  $E0C000
KBD_STROBE    equ  $E0C010
SHR_SCREEN    equ  $E12000
SHR_SCB       equ  $E19D00
SHR_PALETTES  equ  $E19E00

; === FTA compiled routine addresses (banks $44-$4C) ===
NEWPAGE0        equ  $0F00
TABLE_ROUT      equ  $44F100     ; dispatch table (bank $44)
Damier_Rout     equ  $450000     ; compiled checkerboard (bank $45)
TSB_Rout        equ  $450000
Buf_SCB         equ  $45FF00
Clear_Rout      equ  $460000     ; compiled clear routine (bank $46)
Man_Rout        equ  $470000     ; compiled Harrier sprites (bank $47)
Mountain_Rout   equ  $480000
ROUT0           equ  $490000
ROUT1           equ  $4A0000
ROUT2           equ  $4B0000
Chiffre_Rout    equ  $4C0000

; === FTA game constants ===
Box_Lgn         equ  $1C
Box_NbLgn       equ  $C4-$1C
Box_Col         equ  $0
Box_NbCol       equ  $80
Clear_NbLgn     equ  $A8-$3C+$11-$E

; === FTA shape data addresses ===
Decor_Mountain  equ  $400000
Tree_Shape      equ  $410004
Explo_Shape     equ  $412804
Tir_Shape       equ  $414004
Pierre_Shape    equ  $414404
Chiffre_Shape   equ  $415000
Ombre_Shape     equ  $416004
Buisson_Shape   equ  $417004
Ship_Shape      equ  $418004
Trident_Shape   equ  $419004
Divers_Shape    equ  $41A204
Face_Shape      equ  $425004
Der_Shape       equ  $427004
Mid_Shape       equ  $429004
Back_Shape      equ  $42B004
Sidebar_Data    equ  $430000

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

            jsr    ClaimMemory       ; tell GS/OS we're using these banks

            jsr    SHR_Init
            jsr    SetupLoadPalette

            sep    #$20
            lda    #$01              ; border 1 = loading assets
            stal   $E0C034
            rep    #$20
            jsr    LoadAssets

            sep    #$20
            lda    #$02              ; border 2 = checkerboard gen
            stal   $E0C034
            rep    #$20
            jsr    ENTER

            sep    #$20
            lda    #$03              ; border 3 = compiling sprites
            stal   $E0C034
            rep    #$20
            jsr    CompileSprites

            sep    #$20
            lda    #$04              ; border 4 = setting palettes
            stal   $E0C034
            rep    #$20
            jsr    SetupPalettes

            sep    #$20
            lda    #$05              ; border 5 = entering game loop
            stal   $E0C034
            rep    #$20

            ; Initialize Harrier state
            lda    #140
            sta    HarrierRow
            lda    #60
            sta    HarrierCol
            stz    Shape_Man
            stz    FrameTimer
            stz    QuitFlag
            jsr    InitObjects

            rep    #$30

            jsr    INIT_MOUSE

            ; One-time clear of SHR screen so sky pixels are color 0
            jsr    ClearScreen

            ; Blit sidebar graphic from loaded SIDEBAR data to SHR screen
            ; Source: Sidebar_Data ($0D0000), 32 bytes/row × 200 rows (linear)
            ; Dest:   SHR screen, bytes 128-159 per row (160 bytes/row)
            jsr    BlitSidebar

            ; Border off: entering game loop
            sep    #$20
            lda    #$00
            stal   $E0C034
            rep    #$20

; =====================================================================
; Game loop — erase old sprite, draw new, handle input, animate
; =====================================================================

:gameloop
            ; --- Game logic (doesn't touch screen) ---

            ; Check if player is dead
            lda    PlayerDead
            beq    :alive

            ; --- Death state: skip input, play death animation ---
            ; Still allow ESC
            jsr    HandleInput
            lda    QuitFlag
            BNEL   _quit

            ; Keep scenery moving during death
            jsr    Shape_Action

            bra    :skipAlive

:alive
            ; Poll keyboard — movement + ESC
            jsr    HandleInput
            lda    QuitFlag
            BNEL   _quit

            ; Update horizon from Harrier's vertical position
            jsr    UpdateHorizon

            ; Move objects closer, spawn new ones
            jsr    Shape_Action

            ; Check for shooting
            jsr    Tir_Action

:skipAlive

            ; Lateral ground scroll based on Harrier's X position
            ; FTA: Table_Vitesse[COL] gives speed -3..+3
            ; Mouse: HarrierCol 0-127, /2 → index 0-63
            lda    HarrierCol
            lsr                       ; /2 → index into Table_Vitesse
            tax
            sep    #$20
            lda    Table_Vitesse,x
            sta    V_X
            stz    V_X+1
            bpl    :vxPos
            lda    #$FF
            sta    V_X+1             ; sign-extend negative velocity
:vxPos      rep    #$20
            lda    Coordonnee_X
            clc
            adc    V_X
            sta    Coordonnee_X

            ; Shift all objects by V_X so they track with the camera
            ; This makes lateral scrolling purely visual (perspective only)
            lda    V_X
            beq    :noShift        ; skip if no scroll
            ldy    #0
:shiftLoop  lda    ObjArray+S_Profondeur,y
            bmi    :shiftNext      ; inactive, skip
            lda    ObjArray+S_Coor_Hori,y
            clc
            adc    V_X
            sta    ObjArray+S_Coor_Hori,y
:shiftNext  tya
            clc
            adc    #OBJ_SIZE
            tay
            cpy    #MAX_OBJECTS*OBJ_SIZE
            bcc    :shiftLoop
:noShift

            ; Advance ground scroll (forward motion)
            sep    #$20
            lda    Coordonnee_Y
            sec
            sbc    #8                 ; scroll speed (was 1)
            bpl    :yok
            clc
            adc    #30                ; wrap into 0-29 range
:yok        sta    Coordonnee_Y
            rep    #$20

            ; --- Inhibit SHR shadowing ---
            ; All writes to aux RAM are invisible to the display.
            ; Display freezes on the previous frame's content.
            sep    #$20
            lda    #$1C              ; bits 2,3,4 = inhibit all SHR shadow regions
            stal   $E1C035
            rep    #$20

            ; Clear play area (invisible — shadow inhibited)
            jsr    ClearScreen

            ; Set up SCBs: checker palette banding + sky gradient
            jsr    SetupDamierSCB
            jsr    SetupSkySCB

            ; Y = screen address of horizon row
            lda    Ligne_Damier
            asl
            tax
            lda    TBA,x
            tay

            ; X = IMAGE frame offset (scroll position)
            lda    Coordonnee_X
            and    #$0007
            asl
            tax
            lda    Table_Damier,x
            tax

            ; Set DBR to IMAGE bank (must be AFTER reads from code bank)
            sep    #$20
            lda    #^IMAGE
            pha
            plb
            rep    #$20

            jsl    Damier_Rout

            ; Restore DBR to code bank
            phk
            plb

            ; Draw mountains — 14 rows above horizon, parallax at half speed
            ; Y = SHR address of (Ligne_Damier - 14)
            lda    Ligne_Damier
            sec
            sbc    #14
            asl
            tax
            lda    TBA,x
            tay
            ; X = Mountain_Pos/2, frame select on odd/even
            lda    Coordonnee_X
            lsr                       ; Mountain_Pos = Coordonnee_X / 2
            and    #$00FF
            lsr                       ; /2 → byte offset 0-127
            bcc    :mtnEven
            clc
            adc    #$0E00            ; odd: use second frame
:mtnEven    tax
            ; Set DBR to MOUNT data bank
            sep    #$20
            lda    #^Decor_Mountain
            pha
            plb
            rep    #$20
            jsl    Mountain_Rout
            ; Restore DBR
            phk
            plb

            ; Draw world objects (trees etc.) depth-sorted
            jsr    Print_Shape

            ; Draw Harrier at current position
            lda    HarrierRow
            asl
            tax
            lda    TBA,x
            clc
            adc    HarrierCol
            tay

            ; Self-modifying JSL — patched with correct frame address
            jsl    TABLE_ROUT+4       ; operand patched below
_DrawMan    equ    *-3                ; points to the 3-byte JSL operand

            ; --- Re-enable shadowing + TSB pass ---
            ; Re-enable SHR shadowing, then "touch" every byte in the play
            ; area to force the shadow copy from aux RAM → display ($E1).
            ; TSB dp with A=0 reads each byte and writes it back unchanged;
            ; the write triggers the hardware shadow copy.
            jsr    WaitVBL            ; sync before revealing new frame
            sep    #$20
            lda    #$00
            stal   $E1C035            ; re-enable shadowing
            rep    #$20
            jsr    TSBScreen          ; copy aux → display

            ; Hit flash: show red border while timer active
            lda    HitFlashTimer
            beq    :noFlash
            dec
            sta    HitFlashTimer
            sep    #$20
            lda    #$01              ; red border
            stal   $E0C034
            rep    #$20
            bra    :flashDone
:noFlash    sep    #$20
            lda    #$00              ; black border (normal)
            stal   $E0C034
            rep    #$20
:flashDone

            ; Animate Harrier sprite
            lda    PlayerDead
            bne    :deathAnim

            ; Select frame based on position (arcade-style)
            lda    HarrierRow
            cmp    #130               ; on/near ground?
            bcc    :airborne

            ; --- Ground: walking cycle frames 0-7 ---
            lda    FrameTimer
            inc
            sta    FrameTimer
            and    #$0003             ; new frame every 4 VBLs
            BNEL   :noAnim
            lda    Shape_Man
            cmp    #8                 ; if not in walk range, reset
            bcs    :resetWalk
            inc
            cmp    #8
            bcc    :setFrame
:resetWalk  lda    #0
:setFrame   sta    Shape_Man
            brl    :noAnim

            ; --- Airborne: select pose by position ---
:airborne   lda    HarrierRow
            cmp    #60                ; high up threshold
            bcs    :notHigh

            ; High up: check lateral
            lda    V_X
            bmi    :highLeft
            beq    :highCenter
            lda    #11                ; high + right
            bra    :setFly
:highLeft   lda    #12                ; high + left
            bra    :setFly
:highCenter lda    #10                ; high + center
            bra    :setFly

:notHigh    ; Normal altitude: check lateral
            lda    V_X
            bmi    :flyLeft
            beq    :flyCenter
            lda    #8                 ; leaning right
            bra    :setFly
:flyLeft    lda    #9                 ; leaning left
            bra    :setFly
:flyCenter  lda    #10                ; center flying
:setFly     sta    Shape_Man
            brl    :noAnim

            ; Death animation: cycle frames 13-18, then respawn
:deathAnim  lda    DeathTimer
            dec
            sta    DeathTimer
            bne    :deathCont
            ; Death over — respawn
            stz    PlayerDead
            stz    Shape_Man          ; back to frame 0 (running)
            lda    #140               ; reset to default height
            sta    HarrierRow
            bra    :noAnim
:deathCont  ; Fall toward ground
            lda    HarrierRow
            cmp    #145               ; ground level during death
            bcs    :atGround
            clc
            adc    #4                 ; fall speed: 4 pixels/frame
            cmp    #145
            bcc    :setRow
            lda    #145               ; clamp to ground
:setRow     sta    HarrierRow
:atGround
            ; Once on the ground, hold frame 17 then recover with 18
            lda    HarrierRow
            cmp    #145
            bcc    :deathFalling
            ; On ground: show frame 17 (landed), then 18 (crouch-up)
            lda    DeathTimer
            cmp    #16                ; last 16 frames = recovery
            bcs    :holdLanded
            lda    #18                ; crouch-up frame
            sta    Shape_Man
            bra    :noAnim
:holdLanded lda    #17                ; hold landed pose
            sta    Shape_Man
            bra    :noAnim

            ; Still falling: cycle frames 13-17
:deathFalling
            lda    FrameTimer
            inc
            sta    FrameTimer
            and    #$0007
            bne    :noAnim
            lda    Shape_Man
            inc
            cmp    #18                ; past frame 17?
            bcc    :deathSet
            lda    #13                ; loop back
:deathSet   sta    Shape_Man
:noAnim

            ; Update JSL target: TABLE_ROUT + (Shape_Man+1)*4
            lda    Shape_Man
            inc                       ; +1 because entry 0 is unused
            asl
            asl                       ; *4
            clc
            adc    #TABLE_ROUT
            sta    _DrawMan
            sep    #$20
            lda    #^TABLE_ROUT
            sta    _DrawMan+2
            rep    #$20

            jmp    :gameloop
_quit

DoQuit      jsr    SHR_Off
            _MTShutDown
            _QuitGS qtRec
            brk    $00

; =====================================================================
; WaitVBL — wait for vertical blanking period
; =====================================================================
WaitVBL
            sep    #$20
:notVBL     ldal   $E0C019
            bmi    :notVBL           ; wait while bit 7=1 (display active)
            rep    #$20
            rts

; =====================================================================
; BlitSidebar — copy sidebar graphic to right 32 bytes of each SHR row
;
; Source: Sidebar_Data ($0D0000), 32 bytes/row × 200 rows (linear)
; Dest:   SHR screen $E12000, bytes 128-159 per row
; Uses X for long indexed loads; saves X, switches to screen X, writes
; =====================================================================
BlitSidebar
            stz    _sbSrcOff          ; source offset in Sidebar_Data
            stz    _sbDstOff          ; dest offset in SHR screen
            lda    #200
            sta    _sbCount
:sbRow
            ; Phase 1: load 16 words from source via LDAL,X into temp
            ldx    _sbSrcOff
            ldal   Sidebar_Data+0,x
            sta    _sbTmp+0
            ldal   Sidebar_Data+2,x
            sta    _sbTmp+2
            ldal   Sidebar_Data+4,x
            sta    _sbTmp+4
            ldal   Sidebar_Data+6,x
            sta    _sbTmp+6
            ldal   Sidebar_Data+8,x
            sta    _sbTmp+8
            ldal   Sidebar_Data+10,x
            sta    _sbTmp+10
            ldal   Sidebar_Data+12,x
            sta    _sbTmp+12
            ldal   Sidebar_Data+14,x
            sta    _sbTmp+14
            ldal   Sidebar_Data+16,x
            sta    _sbTmp+16
            ldal   Sidebar_Data+18,x
            sta    _sbTmp+18
            ldal   Sidebar_Data+20,x
            sta    _sbTmp+20
            ldal   Sidebar_Data+22,x
            sta    _sbTmp+22
            ldal   Sidebar_Data+24,x
            sta    _sbTmp+24
            ldal   Sidebar_Data+26,x
            sta    _sbTmp+26
            ldal   Sidebar_Data+28,x
            sta    _sbTmp+28
            ldal   Sidebar_Data+30,x
            sta    _sbTmp+30
            ; Phase 2: store temp to SHR screen via STAL,X
            ldx    _sbDstOff
            lda    _sbTmp+0
            stal   $E12000+128,x
            lda    _sbTmp+2
            stal   $E12000+130,x
            lda    _sbTmp+4
            stal   $E12000+132,x
            lda    _sbTmp+6
            stal   $E12000+134,x
            lda    _sbTmp+8
            stal   $E12000+136,x
            lda    _sbTmp+10
            stal   $E12000+138,x
            lda    _sbTmp+12
            stal   $E12000+140,x
            lda    _sbTmp+14
            stal   $E12000+142,x
            lda    _sbTmp+16
            stal   $E12000+144,x
            lda    _sbTmp+18
            stal   $E12000+146,x
            lda    _sbTmp+20
            stal   $E12000+148,x
            lda    _sbTmp+22
            stal   $E12000+150,x
            lda    _sbTmp+24
            stal   $E12000+152,x
            lda    _sbTmp+26
            stal   $E12000+154,x
            lda    _sbTmp+28
            stal   $E12000+156,x
            lda    _sbTmp+30
            stal   $E12000+158,x
            ; Advance offsets
            lda    _sbSrcOff
            clc
            adc    #32                ; 32 bytes per sidebar row
            sta    _sbSrcOff
            lda    _sbDstOff
            clc
            adc    #160               ; 160 bytes per screen row
            sta    _sbDstOff
            dec    _sbCount
            beq    :sbDone
            brl    :sbRow
:sbDone     rts

_sbSrcOff   ds     2
_sbDstOff   ds     2
_sbCount    ds     2
_sbTmp      ds     32

; =====================================================================
; ClearScreen — clear full SHR screen via STAL
; Temporary — will be replaced by FTA's compiled Clear_Rout
; =====================================================================
ClearScreen
            ; Clear play area (128 bytes/row × 200 rows) via DP trick
            ldal   $E1C068
            ora    #$30               ; enable RAMRD+RAMWRT
            stal   $E1C068

            lda    #$2000             ; SHR screen base
            tcd                       ; DP = first row
            ldx    #200               ; all 200 rows

:row        stz    $00
            stz    $02
            stz    $04
            stz    $06
            stz    $08
            stz    $0A
            stz    $0C
            stz    $0E
            stz    $10
            stz    $12
            stz    $14
            stz    $16
            stz    $18
            stz    $1A
            stz    $1C
            stz    $1E
            stz    $20
            stz    $22
            stz    $24
            stz    $26
            stz    $28
            stz    $2A
            stz    $2C
            stz    $2E
            stz    $30
            stz    $32
            stz    $34
            stz    $36
            stz    $38
            stz    $3A
            stz    $3C
            stz    $3E
            stz    $40
            stz    $42
            stz    $44
            stz    $46
            stz    $48
            stz    $4A
            stz    $4C
            stz    $4E
            stz    $50
            stz    $52
            stz    $54
            stz    $56
            stz    $58
            stz    $5A
            stz    $5C
            stz    $5E
            stz    $60
            stz    $62
            stz    $64
            stz    $66
            stz    $68
            stz    $6A
            stz    $6C
            stz    $6E
            stz    $70
            stz    $72
            stz    $74
            stz    $76
            stz    $78
            stz    $7A
            stz    $7C
            stz    $7E               ; 64 STZ = 128 bytes = play area only
            tdc
            clc
            adc    #$A0              ; next row
            tcd
            dex
            beq    :clrDone
            brl    :row
:clrDone

            lda    #0
            tcd                       ; restore DP = 0
            ldal   $E1C068
            and    #$FFCF            ; disable RAMRD+RAMWRT
            stal   $E1C068
            rts

; =====================================================================
; TSBScreen — force shadow copy of play area (aux RAM → $E1 display)
;
; Uses TSB dp with A=0 to read-modify-write every byte in the play area.
; With shadowing enabled, each write triggers the hardware copy to $E1.
; This makes the frame visible on the display.
; =====================================================================
TSBScreen
            ldal   $E1C068
            ora    #$30               ; enable RAMRD+RAMWRT
            stal   $E1C068

            lda    #$2000             ; SHR screen base
            tcd
            lda    #0                 ; A=0: TSB won't change data
            ldx    #200               ; all 200 rows

:trow       tsb    $00
            tsb    $02
            tsb    $04
            tsb    $06
            tsb    $08
            tsb    $0A
            tsb    $0C
            tsb    $0E
            tsb    $10
            tsb    $12
            tsb    $14
            tsb    $16
            tsb    $18
            tsb    $1A
            tsb    $1C
            tsb    $1E
            tsb    $20
            tsb    $22
            tsb    $24
            tsb    $26
            tsb    $28
            tsb    $2A
            tsb    $2C
            tsb    $2E
            tsb    $30
            tsb    $32
            tsb    $34
            tsb    $36
            tsb    $38
            tsb    $3A
            tsb    $3C
            tsb    $3E
            tsb    $40
            tsb    $42
            tsb    $44
            tsb    $46
            tsb    $48
            tsb    $4A
            tsb    $4C
            tsb    $4E
            tsb    $50
            tsb    $52
            tsb    $54
            tsb    $56
            tsb    $58
            tsb    $5A
            tsb    $5C
            tsb    $5E
            tsb    $60
            tsb    $62
            tsb    $64
            tsb    $66
            tsb    $68
            tsb    $6A
            tsb    $6C
            tsb    $6E
            tsb    $70
            tsb    $72
            tsb    $74
            tsb    $76
            tsb    $78
            tsb    $7A
            tsb    $7C
            tsb    $7E               ; 64 TSB = 128 bytes = play area only
            ; advance to next row
            tdc
            clc
            adc    #$A0
            tcd
            lda    #0                 ; reset A for next row
            dex
            beq    :tsbDone
            brl    :trow
:tsbDone
            lda    #0
            tcd                       ; restore DP = 0
            ldal   $E1C068
            and    #$FFCF            ; disable RAMRD+RAMWRT
            stal   $E1C068
            rts

; =====================================================================
; UpdateHorizon — map Harrier's Y position to horizon row (Ligne_Damier)
;
; FTA uses Ligne_Damier 137-153 (Table_Lgn). We use 137-139.
; At 137, ground = rows 137-196 (only 3 rows uncovered at bottom).
; At 139, ground = rows 139-198 (1 row uncovered).
; HarrierRow 0-183, /64 → 0-2, +137 = 137-139.
; =====================================================================
UpdateHorizon
            lda    HarrierRow
            lsr
            lsr
            lsr
            lsr
            lsr
            lsr                       ; /64 → 0..2
            clc
            adc    #137
            cmp    #140
            bcc    :ok
            lda    #139
:ok         sta    Ligne_Damier
            rts

; =====================================================================
; SetupSkySCB — assign sky gradient palettes per row (per-frame)
; Reads Table_Ciel from horizon upward to row 0.
; =====================================================================
SetupSkySCB
            sep    #$20
            ldx    Ligne_Damier       ; start at horizon
            ldy    #0
:skyloop    lda    Table_Ciel,y
            stal   SHR_SCB,x
            dex
            bmi    :skyDone           ; went past row 0
            iny
            bra    :skyloop
:skyDone    rep    #$20
            rts

; =====================================================================
; SetupDamierSCB — perspective-correct palette banding for checkerboard
; Ported from FTA's SPACE.S: thick bands at bottom, thin at horizon
; Uses palettes 0 and 1 alternating. Coordonnee_Y = vertical scroll.
; =====================================================================
SetupDamierSCB
            sep    #$30               ; 8-bit A and X/Y
            lda    Coordonnee_Y
            cmp    #15
            bcs    :range2

            ; Range 1: Coordonnee_Y < 15
            ldx    #0                 ; start palette = 0
            lda    Ligne_Damier
            clc
            adc    #$3C              ; + 60 = bottom of ground
            sec
            sbc    Coordonnee_Y
            bra    :flipchk

:range2     ldx    #1                 ; start palette = 1
            lda    Ligne_Damier
            clc
            adc    #$3C+15
            sec
            sbc    Coordonnee_Y

            ; Flip palette assignment every 8 scroll steps (FTA's Select_X)
:flipchk    pha
            lda    Coordonnee_X
            and    #$08
            beq    :noFlip
            txa
            eor    #1
            tax
:noFlip     pla

:updown     sta    _PNT1
            stx    _PNT2
            cmp    #$C5
            bcs    :cycle2

            ; Fill from PNT1 to $C4 with current palette
            lda    _PNT2
            ldx    _PNT1
:fill1      stal   SHR_SCB,x
            inx
            cpx    #$C5
            bcc    :fill1

:cycle2     lda    _PNT2
            eor    #1
            sta    _PNT2

            ; Compute band width: (distance_from_horizon/2 + 1) / 2
            lda    _PNT1
            sec
            sbc    Ligne_Damier
            lsr
            inc
            lsr
            cmp    #2
            bcc    :final

            ; new_start = PNT1 - band_width
            sec
            sbc    _PNT1
            eor    #$FF
            inc
            tay                       ; Y = new start row
            tax                       ; X = new start row
            lda    _PNT2
:fill2      stal   SHR_SCB,x
            inx
            cpx    #$C5
            bcs    :finpal
            cpx    _PNT1
            bcc    :fill2
:finpal     sty    _PNT1
            bra    :cycle2

            ; Near horizon: single-scanline alternation
:final      ldx    _PNT1
:finloop    dex
            cpx    Ligne_Damier
            bcc    :done
            lda    _PNT2
            stal   SHR_SCB,x
            and    #%1
            eor    #1
            sta    _PNT2
            bra    :finloop

:done       rep    #$30
            rts

_PNT1       ds     1
_PNT2       ds     1
Coordonnee_Y da    0

; =====================================================================
; HandleInput — read mouse + check ESC key
; =====================================================================
; Mouse sets HarrierCol/HarrierRow directly (analog position).
; ESC key still quits.
; =====================================================================
HandleInput
            stz    QuitFlag
            jsr    READ_MOUSE      ; TEMP: skip mouse to test keyboard

            ; Check keys (all 8-bit compares before any REP #$20)
            sep    #$20
            ldal   KBD_DATA
            bpl    :noKey
            and    #$7F
            stal   KBD_STROBE
            cmp    #$1B              ; ESC
            beq    :doEsc
            cmp    #$20              ; spacebar
            beq    :doFire
            cmp    #'N'              ; 'N' = next stage
            beq    :nextStg
            cmp    #'n'
            beq    :nextStg
            bra    :noKey
:doFire     rep    #$20
            lda    #1
            sta    FireFlag
            bra    :noKey
:nextStg    rep    #$20
            lda    CurrentStage
            inc
            cmp    #NUM_STAGES
            bcc    :stgOk
            lda    #0
:stgOk      sta    CurrentStage
            jsr    ApplyStageTheme
            bra    :noKey
:doEsc      rep    #$20
            lda    #1
            sta    QuitFlag
            rts
:noKey      rep    #$20
            rts

; =====================================================================
; Mouse driver — ADB mouse via softswitches (from FTA's MOUSE2.S)
; Reads delta X/Y from $E1C024, accumulates into HarrierCol/HarrierRow.
; =====================================================================
Status_Reg  equ   $E1C027
Mouse_Data  equ   $E1C024

Mouse_Xmin  equ   0
Mouse_Xmax  equ   116               ; keep sprite within play area (16px wide)
Mouse_Ymin  equ   0
Mouse_Ymax  equ   148               ; keep sprite above bottom of play area

INIT_MOUSE
            rep    #$30
            lda    #60
            sta    HarrierCol
            lda    #140
            sta    HarrierRow
            jsr    READ_MOUSE        ; flush any pending data
            rep    #$30
            lda    #60
            sta    HarrierCol
            lda    #140
            sta    HarrierRow
            rts

READ_MOUSE
            sep    #$30              ; 8-bit A, X, Y
            ldal   Status_Reg
            bpl    :noData           ; bit 7=0: no data available
            and    #%00000010        ; bit 1: Y data (0=X data ready)
            beq    :xReady
            ldal   Mouse_Data        ; discard Y-only read
:noData     rep    #$30              ; return in 16-bit mode
            rts

:xReady     ldal   Mouse_Data        ; 8-bit: read delta X (7-bit + sign in bit 6)
            sta    MouseTmp          ; save raw byte
            rep    #$30              ; 16-bit for accumulation
            lda    MouseTmp          ; load into 16-bit A (high byte=0)
            and    #$007F            ; mask to 7 bits
            bit    #$0040            ; test sign (bit 6)
            beq    :addX
            ora    #$FF80            ; sign-extend negative
:addX       clc
            adc    HarrierCol
            sta    HarrierCol

            sep    #$30              ; 8-bit for Y delta read
            ldal   Mouse_Data        ; read delta Y + button in bit 7
            sta    MouseTmp          ; save raw byte
            and    #$80              ; isolate button bit (0=pressed)
            bne    :noBtn            ; bit 7 set = NOT pressed
            rep    #$30
            lda    #1
            sta    FireFlag
            bra    :gotBtn
:noBtn      rep    #$30
:gotBtn     lda    MouseTmp
            and    #$007F            ; mask to 7 bits (strip button)
            bit    #$0040            ; test sign (bit 6)
            beq    :addY
            ora    #$FF80            ; sign-extend negative
:addY       clc
            adc    HarrierRow
            sta    HarrierRow

            ; Clamp X to 0..Mouse_Xmax-1
            lda    HarrierCol
            bmi    :clampXmin
            cmp    #Mouse_Xmax
            bcc    :xOk
            lda    #Mouse_Xmax-1
            sta    HarrierCol
            bra    :xOk
:clampXmin  lda    #Mouse_Xmin
            sta    HarrierCol
:xOk
            ; Clamp Y to 0..Mouse_Ymax-1
            lda    HarrierRow
            bmi    :clampYmin
            cmp    #Mouse_Ymax
            bcc    :yOk
            lda    #Mouse_Ymax-1
            sta    HarrierRow
            bra    :yOk
:clampYmin  lda    #Mouse_Ymin
            sta    HarrierRow
:yOk
            rts

MouseTmp    ds    2                  ; temp for sign-extension
FireFlag    ds    2                  ; 1 = fire requested (spacebar)

; =====================================================================
; Object System Constants
; =====================================================================
OBJ_SIZE     equ  8          ; bytes per object slot
MAX_OBJECTS  equ  16         ; max simultaneous objects
; Object field offsets within each slot
S_Coor_Hori  equ  0          ; horizontal world coordinate (16-bit)
S_Profondeur equ  2          ; depth 0-15, $FFFF=inactive
S_Nature     equ  4          ; 0=tree, 1=pierre, 2=buisson, $83=ship
S_Altitude   equ  6          ; vertical altitude (0=ground)

SCENERY_END   equ  8          ; slots 0-7: scenery (tree/rock/bush)
ENEMY_START   equ  8          ; slots 8-11: enemies (ship/trident)
BULLET_START  equ  12         ; slots 12-15: bullets
BULLET_NATURE equ  $81        ; FTA's bullet nature code
EXPLO_NATURE  equ  $82        ; explosion (dying enemy)
SHIP_NATURE   equ  $83        ; FTA's ship nature code

; =====================================================================
; InitObjects — mark all object slots inactive
; =====================================================================
InitObjects
            ldx    #0
            lda    #$FFFF
:loop       sta    ObjArray+S_Profondeur,x
            txa
            clc
            adc    #OBJ_SIZE
            tax
            cpx    #MAX_OBJECTS*OBJ_SIZE
            bcc    :loop
            rts

; =====================================================================
; Shape_Action — move objects closer each frame, spawn new ones
; =====================================================================
Shape_Action
            rep    #$30
            ldx    #0
:saLoop     lda    ObjArray+S_Profondeur,x
            bmi    :trySpawn       ; $FFFF = inactive → try spawn
            ; Check if this is an explosion (scenery got shot)
            lda    ObjArray+S_Nature,x
            and    #$00FF
            cmp    #EXPLO_NATURE
            bne    :saMove
            ; Explosion countdown
            lda    ObjArray+S_Altitude,x
            dec
            sta    ObjArray+S_Altitude,x
            bne    :saNext         ; still animating
            lda    #$FFFF          ; done → deactivate
            sta    ObjArray+S_Profondeur,x
            bra    :saNext
:saMove     ; Active: decrease depth (approach player)
            lda    ObjArray+S_Profondeur,x
            dec
            bpl    :saStore
            lda    #$FFFF          ; passed player → deactivate
:saStore    sta    ObjArray+S_Profondeur,x
            bra    :saNext

:trySpawn   jsr    ALEA
            and    #$FF
            cmp    #$FC            ; ~1.5% chance to spawn per slot
            bcc    :saNext
            ; Random nature: tree(0), rock(1), bush(2), rock(3→1)
            jsr    ALEA
            and    #$03              ; 0-3
            cmp    #3
            bcc    :natOk
            lda    #1                ; 3 → rock (50% rocks, 25% tree, 25% bush)
:natOk      sta    ObjArray+S_Nature,x
            ; Rocks fly in the sky; trees/bushes on ground
            lda    ObjArray+S_Nature,x
            cmp    #1
            bne    :onGround
            ; FTA rock altitude: (ALEA & $FF) >> 3 + $38 → range $38-$57
            jsr    ALEA
            and    #$FF
            lsr
            lsr
            lsr                       ; 0-31
            clc
            adc    #$38              ; altitude $38-$57 (56-87)
            sta    ObjArray+S_Altitude,x
            lda    #7                ; Pierre has 8 entries (depth 0-7)
            bra    :setDepth
:onGround   stz    ObjArray+S_Altitude,x
            lda    #15
:setDepth   sta    ObjArray+S_Profondeur,x
            ; Random horizontal position: ±64 around view center
            jsr    ALEA
            and    #$7F            ; 0-127
            sec
            sbc    #$40            ; -64 to +63
            clc
            adc    Coordonnee_X
            sta    ObjArray+S_Coor_Hori,x

:saNext     txa
            clc
            adc    #OBJ_SIZE
            tax
            cpx    #SCENERY_END*OBJ_SIZE
            BCCL   :saLoop

            ; --- Enemy slots (8-11): move active enemies every frame ---
:enLoop     lda    ObjArray+S_Profondeur,x
            BMIL   :enNext         ; inactive → skip
            lda    ObjArray+S_Nature,x
            and    #$00FF          ; mask off speed in high byte
            cmp    #EXPLO_NATURE
            beq    :enExplo
            cmp    #SHIP_NATURE
            BNEL   :enNext

            ; Apply horizontal drift from ShipXCurve
            lda    ObjArray+S_Profondeur,x
            tay
            lda    ShipXCurve,y
            and    #$00FF           ; curve velocity (unsigned magnitude)
            sta    _tempAlt
            lda    ObjArray+S_Altitude,x
            and    #$FF00           ; high byte = direction ($FF=left, $01=right)
            beq    :enNoDrift
            bmi    :enDriftNeg
            ; Positive direction: add curve value
            lda    ObjArray+S_Coor_Hori,x
            clc
            adc    _tempAlt
            sta    ObjArray+S_Coor_Hori,x
            bra    :enNoDrift
:enDriftNeg ; Negative direction: subtract curve value
            lda    ObjArray+S_Coor_Hori,x
            sec
            sbc    _tempAlt
            sta    ObjArray+S_Coor_Hori,x
:enNoDrift

            ; Advance depth: decrement by speed (high byte of S_Nature)
            lda    ObjArray+S_Nature,x
            xba
            and    #$00FF           ; speed = depth steps per frame
            sta    _tempAlt
            lda    ObjArray+S_Profondeur,x
            sec
            sbc    _tempAlt         ; depth -= speed
            bpl    :enAlive
            lda    #$FFFF          ; passed player → deactivate
            sta    ObjArray+S_Profondeur,x
            bra    :enNext
:enAlive    sta    ObjArray+S_Profondeur,x
            ; Update altitude from curve table
            tay
            lda    ShipAltCurve,y
            and    #$00FF
            sta    _tempAlt
            lda    ObjArray+S_Altitude,x
            and    #$FF00
            ora    _tempAlt
            sta    ObjArray+S_Altitude,x

            bra    :enNext

            ; --- Explosion countdown ---
:enExplo    lda    ObjArray+S_Altitude,x
            dec
            sta    ObjArray+S_Altitude,x
            bne    :enNext         ; still animating
            ; Explosion done — deactivate slot
            lda    #$FFFF
            sta    ObjArray+S_Profondeur,x

:enNext     txa
            clc
            adc    #OBJ_SIZE
            tax
            cpx    #BULLET_START*OBJ_SIZE
            BCCL   :enLoop

            ; --- Wave spawn: periodically spawn a formation of 4 ships ---
            lda    PlayerDead
            bne    :wvDone            ; no new waves during death
            lda    WaveTimer
            beq    :waveSpawn
            dec    WaveTimer
            bra    :wvDone
:waveSpawn  lda    #90              ; ~1.5 seconds between waves
            sta    WaveTimer
            ldx    #ENEMY_START*OBJ_SIZE
            ldy    #0               ; wave slot index (0,2,4,6)
:wvLoop     ; DEBUG: force overwrite regardless of occupancy
            ; Spawn ship: high byte=speed (1=normal), low byte=nature
            lda    #$0100+SHIP_NATURE
            sta    ObjArray+S_Nature,x
            lda    #14              ; start at far depth (horizon)
            sta    ObjArray+S_Profondeur,x
            ; Altitude: low byte from curve, high byte = direction sign
            lda    ShipAltCurve+14
            and    #$00FF
            ora    WaveShipDir,y
            sta    ObjArray+S_Altitude,x
            ; Horizontal: staggered positions across screen
            lda    WaveShipHori,y
            clc
            adc    Coordonnee_X
            sta    ObjArray+S_Coor_Hori,x
:wvSkip     txa
            clc
            adc    #OBJ_SIZE
            tax
            iny
            iny
            cpy    #8               ; 4 ships × 2 bytes
            bcc    :wvLoop
:wvDone
            ; --- Bullet slots (12-15): move toward horizon ---
            ldx    #BULLET_START*OBJ_SIZE
:saLoop2    lda    ObjArray+S_Profondeur,x
            bmi    :saNext2        ; inactive
            inc                     ; bullet moves away from player
            cmp    #11             ; past max depth?
            bcc    :saStore2
            lda    #$FFFF          ; deactivate
:saStore2   sta    ObjArray+S_Profondeur,x
:saNext2    txa
            clc
            adc    #OBJ_SIZE
            tax
            cpx    #MAX_OBJECTS*OBJ_SIZE
            bcc    :saLoop2

            ; --- Bullet-enemy collision detection ---
            jsr    CheckCollisions
            rts

; =====================================================================
; CheckCollisions — test each bullet against each enemy
; Flash border red on hit, deactivate both
; Now checks bullets vs ALL objects (scenery + enemies)
; =====================================================================
CheckCollisions
            rep    #$30
            ldx    #BULLET_START*OBJ_SIZE
:colBullet  lda    ObjArray+S_Profondeur,x
            BMIL   :colNextB       ; bullet inactive
            sta    _colBDepth
            lda    ObjArray+S_Altitude,x
            and    #$00FF
            sta    _colBAlt        ; bullet altitude

            ldy    #0              ; check ALL object slots (0-11)
:colTarget  cpy    #BULLET_START*OBJ_SIZE
            bcs    :colNextB       ; past last target slot
            lda    ObjArray+S_Profondeur,y
            bmi    :colNextT       ; inactive
            ; Skip bullets and explosions
            lda    ObjArray+S_Nature,y
            and    #$00FF
            cmp    #BULLET_NATURE
            beq    :colNextT
            cmp    #EXPLO_NATURE
            beq    :colNextT
            sta    _colNature      ; save nature for altitude check

            ; Check depth match (within ±1)
            lda    ObjArray+S_Profondeur,y
            sec
            sbc    _colBDepth
            bpl    :colDAbs
            eor    #$FFFF
            inc
:colDAbs    cmp    #2
            bcs    :colNextT

            ; Check horizontal proximity
            lda    ObjArray+S_Coor_Hori,x    ; bullet X
            sec
            sbc    ObjArray+S_Coor_Hori,y    ; target X
            bpl    :colHAbs
            eor    #$FFFF
            inc
:colHAbs    cmp    #$10            ; within 16 world units?
            bcs    :colNextT

            ; Altitude check (skip for trees — they're tall)
            lda    _colNature
            beq    :colHit         ; nature 0 = tree, skip alt check
            ; Compare bullet altitude vs target altitude
            lda    ObjArray+S_Altitude,y
            and    #$00FF
            sec
            sbc    _colBAlt
            bpl    :colAAbs
            eor    #$FFFF
            inc
:colAAbs    cmp    #$18            ; within 24 altitude units?
            bcs    :colNextT

:colHit     ; HIT! Kill bullet, convert target to explosion
            lda    #$FFFF
            sta    ObjArray+S_Profondeur,x   ; kill bullet

            ; Convert target to explosion
            lda    #EXPLO_NATURE
            sta    ObjArray+S_Nature,y
            lda    #10
            sta    ObjArray+S_Altitude,y     ; explosion timer

            lda    #8
            sta    HitFlashTimer
            bra    :colNextB       ; bullet used up, next bullet

:colNextT   tya
            clc
            adc    #OBJ_SIZE
            tay
            bra    :colTarget

:colNextB   txa
            clc
            adc    #OBJ_SIZE
            tax
            cpx    #MAX_OBJECTS*OBJ_SIZE
            BCCL   :colBullet

            ; Player-enemy collision now handled in Print_Shape
            rts

_colBDepth  ds     2
_colBAlt    ds     2
_colNature  ds     2
HitFlashTimer da   0               ; frames remaining for hit flash
PlayerDead    da   0               ; non-zero = death animation active
DeathTimer    da   0               ; frames remaining in death anim

; =====================================================================
; Tir_Action — spawn bullet when spacebar pressed
; =====================================================================
Tir_Action
            rep    #$30
            lda    FireFlag
            beq    :noFire
            stz    FireFlag

            ; Find a free bullet slot (12-15)
            ldx    #BULLET_START*OBJ_SIZE
:findSlot   lda    ObjArray+S_Profondeur,x
            bmi    :fireOk           ; $FFFF = free
            txa
            clc
            adc    #OBJ_SIZE
            tax
            cpx    #MAX_OBJECTS*OBJ_SIZE
            bcc    :findSlot
:noFire     rts                      ; all slots full or no fire

:fireOk     stz    ObjArray+S_Profondeur,x ; depth 0 (foreground)
            lda    #BULLET_NATURE
            sta    ObjArray+S_Nature,x
            ; Altitude: pixels above ground, scaled for /32 in Print_Shape
            ; ground_row at depth 0 ≈ Ligne_Damier + 26
            ; raw = ground_row - HarrierRow, then *3/4 to compensate *40/32
            lda    Ligne_Damier
            clc
            adc    #26
            sec
            sbc    HarrierRow
            and    #$FF
            pha                       ; save raw
            lsr
            lsr                       ; raw/4
            sta    ObjArray+S_Altitude,x ; temp
            pla                       ; raw
            sec
            sbc    ObjArray+S_Altitude,x ; raw - raw/4 = raw*3/4
            sta    ObjArray+S_Altitude,x
            ; Horizontal: convert screen delta to world coords
            ; Projection multiplies by 2.5 at depth 0, so divide by ~2
            lda    HarrierCol
            and    #$FF
            sec
            sbc    #$40              ; signed screen delta from center
            cmp    #$8000
            ror                       ; arithmetic shift right = signed /2
            clc
            adc    Coordonnee_X
            sta    ObjArray+S_Coor_Hori,x
            rts

; =====================================================================
; Print_Shape — depth-sorted render (back to front: 15→0)
; Only draws trees (nature=0) for now.
; =====================================================================
Print_Shape
            rep    #$30
            lda    #15
            sta    _Profondeur

:psDepth    ldx    #0
:psObj      lda    ObjArray+S_Profondeur,x
            cmp    _Profondeur
            BNEL   :psNextO
            ; This object is at the current depth — render it
            stx    _Exploreur

            ; Determine shape number from nature + depth
            lda    ObjArray+S_Nature,x
            and    #$00FF           ; mask off speed byte in high
            beq    :psTree
            cmp    #1
            beq    :psRock
            cmp    #2
            beq    :psBush
            cmp    #BULLET_NATURE
            beq    :psBullet
            cmp    #EXPLO_NATURE
            beq    :psExplo
            cmp    #SHIP_NATURE
            beq    :psShip
            brl    :psSkip           ; skip unknown natures

:psTree     lda    ObjArray+S_Profondeur,x
            clc
            adc    #24               ; tree entries: 24-39
            sta    _Nbr_Shape
            bra    :psProject

:psRock     lda    ObjArray+S_Profondeur,x
            cmp    #8                ; Pierre has 8 entries (depths 0-7)
            BCSL   :psSkip
            clc
            adc    #62               ; Pierre entries: 62-69
            sta    _Nbr_Shape
            bra    :psProject

:psBush     lda    ObjArray+S_Profondeur,x
            cmp    #14               ; bushes only at depths 0-13
            BCSL   :psSkip
            clc
            adc    #78               ; bush entries: 78-91
            sta    _Nbr_Shape
            bra    :psProject

:psBullet   lda    ObjArray+S_Profondeur,x
            cmp    #11               ; bullet depths 0-10
            BCSL   :psSkip
            clc
            adc    #51               ; bullet entries: 51-61
            sta    _Nbr_Shape
            bra    :psProject

:psExplo    lda    ObjArray+S_Profondeur,x
            cmp    #11               ; Explo has 11 entries (depths 0-10)
            BCSL   :psSkip
            clc
            adc    #40               ; Explo entries: 40-50
            sta    _Nbr_Shape
            bra    :psProject

:psShip     lda    ObjArray+S_Profondeur,x
            cmp    #15               ; Ship has 15 entries (depths 0-14)
            BCSL   :psSkip
            clc
            adc    #92               ; Ship entries: 92-106
            sta    _Nbr_Shape

:psProject  ; === Horizontal projection ===
            ; screen_col = |delta| * Decalage_Y[depth] / 16, signed, + $40
            lda    ObjArray+S_Coor_Hori,x
            sec
            sbc    Coordonnee_X    ; signed delta
            sta    _horiDelta
            Inverse                ; make positive
            cmp    #$FF
            bcc    :psOkV
            lda    #$FF            ; clamp to 255
:psOkV      sep    #$30
            pha                    ; save 8-bit distance
            ldx    _Profondeur
            lda    Decalage_Y,x    ; perspective factor for this depth
            tay
            pla
            jsr    MULTI           ; A(8) × Y(8) → A(16)
            mx     %00            ; tell assembler: MULTI returns in 16-bit mode
            lsr
            lsr
            lsr
            lsr                    ; /16
            ldx    _horiDelta      ; test sign of original delta
            bpl    :psPos
            eor    #$FFFF
            inc                    ; negate
:psPos      clc
            adc    #$40            ; center on screen
            ; Bounds check (matches FTA):
            ; Accept $FFE0-$FFFF (partial left edge) and $0000-$007F
            cmp    #$FFE0            ; col >= -32?
            bcs    :psColOk          ; yes — accept (left-edge partial)
            cmp    #$80              ; col >= $80?
            BCSL   :psSkip           ; yes — off right / in sidebar
:psColOk
            sta    _Colonne_Shape

            ; === Altitude offset (16-bit, before entering 8-bit section) ===
            ; alt_pixels = altitude * Decalage_Y[depth] / 32
            ldx    _Exploreur
            lda    ObjArray+S_Altitude,x
            and    #$00FF
            beq    :zeroAlt
            sep    #$30
            pha                    ; 8-bit altitude
            ldx    _Profondeur
            lda    Decalage_Y,x
            tay
            pla
            jsr    MULTI          ; A(8) × Y(8) → A(16)
            mx     %00
            lsr
            lsr
            lsr
            lsr
            lsr                    ; /32
            bra    :storeAlt
:zeroAlt    lda    #0
:storeAlt   sta    _altOffset

            ; === Vertical projection ===
            ; row = Ligne_Damier + Decalage_Y[depth] - Shape_Hauteur[shape] - altOffset
            sep    #$30            ; 8-bit A,X,Y
            ldx    _Profondeur
            lda    Decalage_Y,x    ; rows below horizon for this depth
            clc
            adc    Ligne_Damier    ; absolute screen row (bottom of shape)
            ldx    _Nbr_Shape
            sec
            sbc    Shape_Hauteur,x ; subtract sprite height → top row
            sec
            sbc    _altOffset      ; subtract altitude (lifts airborne objects)
            ; Row bounds check
            cmp    #200
            bcs    :psSkip8        ; skip if row >= 200 (unsigned wraps too)

            rep    #$30
            and    #$00FF
            sta    _screenRow      ; save screen row for collision
            tax                    ; X = screen row

            ; --- Player-enemy collision (uses screen coords) ---
            lda    PlayerDead
            bne    :noPlHit        ; already dead
            lda    _Profondeur
            cmp    #2
            bcs    :noPlHit        ; only check depth 0-1
            ldx    _Exploreur
            lda    ObjArray+S_Nature,x
            and    #$00FF
            cmp    #SHIP_NATURE
            bne    :noPlHit
            ; Screen column overlap
            lda    _Colonne_Shape
            and    #$00FF
            sec
            sbc    HarrierCol
            bpl    :plhAbs
            eor    #$FFFF
            inc
:plhAbs     cmp    #8              ; within 8 bytes (~16 pixels)
            bcs    :noPlHit
            ; Screen row overlap
            lda    _screenRow
            sec
            sbc    HarrierRow
            bpl    :plvAbs
            eor    #$FFFF
            inc
:plvAbs     cmp    #40             ; within 40 rows (sprite height)
            bcs    :noPlHit
            ; HIT! Player is dead
            lda    #1
            sta    PlayerDead
            lda    #48
            sta    DeathTimer
            lda    #13
            sta    Shape_Man
            ; Kill this enemy
            lda    #$FFFF
            sta    ObjArray+S_Profondeur,x
:noPlHit
            ldx    _screenRow      ; restore screen row into X
            lda    _Nbr_Shape      ; A = shape number
            ldy    _Colonne_Shape  ; Y = column (byte offset)
            jsr    Draw_Shape
            bra    :psSkip
:psSkip8    rep    #$30

:psSkip     ldx    _Exploreur
:psNextO    txa
            clc
            adc    #OBJ_SIZE
            tax
            cpx    #MAX_OBJECTS*OBJ_SIZE
            BCCL   :psObj
            dec    _Profondeur
            lda    _Profondeur
            BPLL   :psDepth
            rts

; =====================================================================
; Draw_Shape — dispatch compiled sprite via TABLE_ROUT
;   A = shape number (TABLE_ROUT entry)
;   X = screen row
;   Y = column (byte offset in row)
; =====================================================================
Draw_Shape
            asl
            asl                    ; ×4
            clc
            adc    #TABLE_ROUT     ; low 16 bits of entry address
            stal   _dsJSL+1
            sep    #$20
            lda    #^TABLE_ROUT
            stal   _dsJSL+3        ; bank byte
            rep    #$20

            txa
            asl
            tax
            tya                    ; column byte offset
            clc
            adc    TBA,x           ; + row SHR address
            tay                    ; Y = SHR destination

_dsJSL      jsl    TABLE_ROUT      ; operand patched above
            rts

; =====================================================================
; MULTI — 8-bit × 8-bit → 16-bit multiply via lookup tables
; Input:  A = factor 1 (8-bit), Y = factor 2 (8-bit)
; Output: A = 16-bit product (returns in REP #$30 mode)
; Ported from FTA's SPACE.S
; =====================================================================
; Simple loop multiply: A(8) × Y(8) → A(16)
; Y is the scale factor (1-40 max), used as loop count
MULTI       rep    #$30
            and    #$00FF         ; A = distance (0-255), zero-extend
            sta    _PROD          ; save as addend
            tya
            and    #$00FF         ; A = scale (1-40), zero-extend
            beq    :mulZero
            tax                   ; X = loop count
            lda    #0
:mulLoop    clc
            adc    _PROD
            dex
            bne    :mulLoop
            rts
:mulZero    lda    #0
            rts

; =====================================================================
; ALEA — 16-bit LFSR pseudo-random number generator
; Returns random value in A (16-bit). Mixes in VBL counter for entropy.
; =====================================================================
ALEA        lda    RandSeed
            lsr
            bcc    :noTap
            eor    #$D008         ; primitive polynomial: x^16+x^15+x^13+x^4+1
:noTap      sta    RandSeed
            rts

RandSeed    da     $3ACE          ; initial seed (non-zero)

; MULTI temp variables
_NB1        ds     1
_NB2        ds     1
_PROD       ds     2

; Object system variables
_Profondeur ds     2
_Exploreur  ds     2
_Nbr_Shape  ds     2
_horiDelta  ds     2
_Colonne_Shape ds  2
_altOffset  ds  2
_screenRow  ds  2
_tempAlt    ds  2

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
            ; Colors $4/$E are the two checkerboard stripe colors.
            lda    #$0000           ; 0: black (background/transparent)
            stal   SHR_PALETTES+$00
            lda    #$0000           ; 1: black (sidebar strip)
            stal   SHR_PALETTES+$02
            lda    #$0466           ; 2: blue-grey
            stal   SHR_PALETTES+$04
            lda    #$0449           ; 3: blue
            stal   SHR_PALETTES+$06
            lda    #$0ADA           ; 4: light green (checker light)
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
            lda    #$07A7           ; E: medium green (checker dark)
            stal   SHR_PALETTES+$1C
            lda    #$0FFF           ; F: white
            stal   SHR_PALETTES+$1E

            ; Copy palette 0 to all other palettes (1-15)
            ldx    #0
:cppal      ldal   SHR_PALETTES+$00,x
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

            ; Apply stage theme (sky gradient + checker colors)
            jsr    ApplyStageTheme
            rts

; =====================================================================
; ApplyStageTheme — apply per-stage palette from StageThemes table
;
; Reads CurrentStage, indexes into StageThemes to get:
;   - 2 checker colors (palette 0 color $4, color $E; palette 1 swapped)
;   - 12 sky gradient colors (palettes 4-15: color 0, $4, $E)
;   - Color 1 = black in all sky palettes (sidebar)
; =====================================================================
ApplyStageTheme
            ; Calculate offset into StageThemes: CurrentStage * STAGE_SIZE
            lda    CurrentStage
            and    #$00FF
            ; STAGE_SIZE = 28 bytes (2 checker + 2 padding + 12 sky × 2)
            asl                        ; ×2
            sta    _stgOff
            asl                        ; ×4
            asl                        ; ×8
            asl                        ; ×16
            sec
            sbc    _stgOff             ; ×16 - ×2 = ×14
            asl                        ; ×28
            tax

            ; Checker colors: first 2 words in theme data
            lda    StageThemes+0,x     ; checker light color
            sta    _chkLight
            stal   SHR_PALETTES+$08    ; pal 0 color $4
            lda    StageThemes+2,x     ; checker dark color
            sta    _chkDark
            stal   SHR_PALETTES+$1C    ; pal 0 color $E

            ; Palette 1: swap checker colors
            lda    _chkLight
            stal   SHR_PALETTES+$3C    ; pal 1 color $E
            lda    _chkDark
            stal   SHR_PALETTES+$28    ; pal 1 color $4

            ; Sky gradient: 12 colors at offset +4 in theme data
            ; Each color → palette N: color 0, color $4, color $E
            ldy    #0                  ; sky palette offset (0-11)
:skyLoop    lda    StageThemes+4,x     ; sky color for this palette
            pha
            ; Compute SHR palette offset: (4+Y) * $20
            tya
            clc
            adc    #4                  ; palette number = 4+Y
            asl
            asl
            asl
            asl
            asl                        ; ×32 = palette offset
            sta    _stgOff
            pla
            ; Write to color 0
            phx
            ldx    _stgOff
            stal   SHR_PALETTES,x      ; color 0
            ; Write to color $4 (offset +$08)
            stal   SHR_PALETTES+$08,x  ; color $4
            ; Write to color $E (offset +$1C)
            stal   SHR_PALETTES+$1C,x  ; color $E
            ; Color 1 = black (sidebar)
            lda    #$0000
            stal   SHR_PALETTES+$02,x  ; color 1
            plx
            inx
            inx                        ; next sky color in theme data
            iny
            cpy    #12
            bcc    :skyLoop

            rts

_stgOff     ds     2
_chkLight   ds     2
_chkDark    ds     2
CurrentStage ds    2

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
            ; Damier — checkerboard blit routine
            ; =========================================
            ; Border $02 = before Damier compile
            sep    #$20
            lda    #$02
            stal   $E0C034
            rep    #$20

            ldx    #0
:cpdam      lda    Damier_Tbl,x
            sta    $00,x
            inx
            inx
            cpx    #$18
            bne    :cpdam

            ; Border $03 = about to call Create_Sprite for Damier
            sep    #$20
            lda    #$03
            stal   $E0C034
            rep    #$20

            lda    MyDirectPage
            jsr    Create_Sprite

            ; Border $0C = after Damier compile
            sep    #$20
            lda    #$0C
            stal   $E0C034
            rep    #$20

            ; =========================================
            ; Mountain — 14 rows × 128 bytes, FDFD mode
            ; =========================================
            ldx    #0
:cpmtn      lda    Mountain_Tbl,x
            sta    $00,x
            inx
            inx
            cpx    #$18
            bne    :cpmtn

            lda    MyDirectPage
            jsr    Create_Sprite

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
; ClaimMemory — allocate memory from GS/OS so we don't trash OS structures
;
; Uses NewHandle with attrFixed+attrAddr+attrLocked to claim specific
; address ranges before loading assets or compiling sprites into them.
; =====================================================================
ClaimMemory
            ; Allocate all game memory in banks $40-$4D (high banks, away from GS/OS)
            ; Single block: $400000-$4DFFFF = 14 banks ($0E0000 bytes)
            pha                        ; result space (handle hi)
            pha                        ; result space (handle lo)
            pea    $000E              ; size hi ($0E0000 = 14 × 64KB)
            pea    $0000              ; size lo
            lda    MyUserId
            pha                        ; user ID
            pea    $C040              ; attrFixed | attrAddr | attrLocked
            pea    $0040              ; location hi (bank $40)
            pea    $0000              ; location lo
            ldx    #$0902             ; NewHandle
            jsl    $E10000
            bcc    :ok1
            ; Allocation failed — halt (border won't show pre-SHR)
            brk    $01
:ok1        pla                        ; discard handle lo
            pla                        ; discard handle hi
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
            PUT    Checkerboard

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
; Compiled sprite parameter tables
; =====================================================================

; Damier_Tbl — checkerboard blit routine (compiled as "decor" sprite)
; Uses $FEFE00 mask mode: emits LDA abs,X to read from IMAGE buffer
Damier_Tbl  adrl   Damier_Rout        ; $00: output addr
            adrl   $0                 ; $04: shape data (not used for decor)
            adrl   $FEFE00            ; $08: Restore_Dec mode
            da     0                  ; $0C: TblNb (entry 0, not in TABLE_ROUT)
            da     $3C               ; $0E: NbLgn = 60 rows
            da     $80               ; $10: NbCol = 128 bytes (full width)
            da     $FFFF             ; $12: Lgn = dynamic
            da     $FFFF             ; $14: Col = dynamic
            da     $00               ; $16: Pixel_Shape = 0

; Table_Damier — offsets for 8 horizontal scroll positions
; Each frame in IMAGE is $1E00 bytes apart
Table_Damier
]_A         =      0
            lup    8
            da     _LONGUEUR*]_A
]_A         =      ]_A+1
            --^

; Mountain_Tbl — mountain blit routine (compiled as decor, $FDFD mode)
; MOUNT data: 14 rows × 256-byte stride, 2 frames for pixel scroll
Mountain_Tbl
            adrl   Mountain_Rout      ; $00: output addr
            adrl   $0                 ; $04: shape data (not used for decor)
            adrl   $FDFD00            ; $08: Mountain special mode
            da     0                  ; $0C: TblNb = 0 (not in TABLE_ROUT)
            da     $0E               ; $0E: NbLgn = 14 rows
            da     $80               ; $10: NbCol = 128 bytes (full width)
            da     $FFFF             ; $12: Lgn = dynamic
            da     $FFFF             ; $14: Col = dynamic
            da     $00               ; $16: Pixel_Shape = 0

; =====================================================================
; Man_Tbl — Harrier sprite parameter table
; Compiled into TABLE_ROUT entries 1-19.
; Each frame has a 4-byte header in SHAPE.RUN that gets skipped.
; =====================================================================
Man_Tbl
Man_RoutAdr adrl   Man_Rout         ; $00: output addr for compiled code
Man_ShpAdr  adrl   $41B004          ; $04: SHAPE.RUN data + skip header
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
            adrl   $450000         ; MUS/BLUE.WBNK (temp, overwritten by sprites)
            adrl   _pBLUEW
            adrl   $440000         ; MUS/BLUE.MONDAY (temp, overwritten by sprites)
            adrl   _pBLUEM
            adrl   $41B000         ; SHAPE.RUN
            adrl   _pSHAPER
            adrl   $400000         ; MOUNT
            adrl   _pMOUNT
            adrl   $410000         ; PIC/TREE.SHAPE
            adrl   _pTREE
            adrl   $412800         ; PIC/EXPLO.SHP
            adrl   _pEXPLO
            adrl   $414000         ; PIC/TIR.SHP
            adrl   _pTIR
            adrl   $414400         ; PIC/PIERRE.SHP
            adrl   _pPIERRE
            adrl   $415000         ; PIC/NUM.SHP
            adrl   _pNUM
            adrl   $416000         ; PIC/OMBRE.SHP
            adrl   _pOMBRE
            adrl   $417000         ; PIC/BUISSON.SHP
            adrl   _pBUISSO
            adrl   $418000         ; PIC2/SHIP.SHP
            adrl   _pSHIP
            adrl   $419000         ; PIC2/TRIDENT.SHP
            adrl   _pTRIDEN
            adrl   $41A200         ; PIC2/DIVERS.SHP
            adrl   _pDIVERS
            adrl   $425000         ; DRAGON/FACE.SHP
            adrl   _pFACE
            adrl   $427000         ; DRAGON/DER.SHP
            adrl   _pDER
            adrl   $429000         ; DRAGON/MID.SHP
            adrl   _pMID
            adrl   $42B000         ; DRAGON/BACK.SHP
            adrl   _pBACK
            adrl   $430000         ; SIDEBAR
            adrl   _pSIDEBAR
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
_pSIDEBAR   da    7
            asc   'SIDEBAR'

; =====================================================================
; Stage Themes — per-stage palette data
;
; Each stage: 28 bytes
;   +0: checker light color (IIgs $0RGB) — palette 0 color $4
;   +2: checker dark color  (IIgs $0RGB) — palette 0 color $E
;   +4: 12 sky gradient colors (palettes 4-15, horizon→top)
;
; STAGE_SIZE = 28
; =====================================================================
STAGE_SIZE  equ    28
NUM_STAGES  equ    5

StageThemes
; --- Stage 1: Moot (green/cream checker, green→lavender sky) ---
            da     $0ADA              ; checker light: pale green
            da     $07A7              ; checker dark: sage
            da     $05C6              ; sky 4 (horizon): strong green
            da     $06C7              ; sky 5: bright green
            da     $07B8              ; sky 6: lighter green
            da     $08A9              ; sky 7: green-teal
            da     $099A              ; sky 8: teal
            da     $0A9B              ; sky 9: teal-purple
            da     $0B9C              ; sky 10: blue-lavender
            da     $0B9D              ; sky 11: light lavender
            da     $0C9E              ; sky 12: medium lavender
            da     $0CAE              ; sky 13: lavender
            da     $0CAE              ; sky 14: lavender
            da     $0CAE              ; sky 15: lavender

; --- Stage 2: Geeza (blue/white checker, blue→pink sky) ---
            da     $0DAF              ; checker light: light blue
            da     $068B              ; checker dark: med blue
            da     $04A8              ; sky 4: deep blue
            da     $05A9              ; sky 5: blue
            da     $069A              ; sky 6: blue-teal
            da     $079B              ; sky 7
            da     $08AC              ; sky 8: lighter blue
            da     $09BD              ; sky 9
            da     $0ABD              ; sky 10
            da     $0BCE              ; sky 11: pink-blue
            da     $0CCE              ; sky 12
            da     $0DDF              ; sky 13: pink
            da     $0DDF              ; sky 14
            da     $0DDF              ; sky 15

; --- Stage 3: Amar (red/orange checker, red→purple sky) ---
            da     $0FB6              ; checker light: bright orange
            da     $0A63              ; checker dark: dark red
            da     $0944              ; sky 4: dark red
            da     $0A55              ; sky 5
            da     $0B56              ; sky 6: red
            da     $0B67              ; sky 7
            da     $0C78              ; sky 8
            da     $0C79              ; sky 9: reddish purple
            da     $0D8A              ; sky 10
            da     $0D8B              ; sky 11: purple
            da     $0E9C              ; sky 12
            da     $0EAD              ; sky 13: blue-purple
            da     $0EAD              ; sky 14
            da     $0EAD              ; sky 15

; --- Stage 4: Ceiceil (yellow/brown checker, orange→blue sky) ---
            da     $0EC8              ; checker light: gold
            da     $0963              ; checker dark: brown
            da     $0874              ; sky 4: dark orange
            da     $0985              ; sky 5: orange
            da     $0A86              ; sky 6
            da     $0A97              ; sky 7
            da     $0BA8              ; sky 8
            da     $0CA9              ; sky 9
            da     $0CAA              ; sky 10: teal
            da     $0DBB              ; sky 11
            da     $0DBC              ; sky 12
            da     $0ECD              ; sky 13: blue
            da     $0ECD              ; sky 14
            da     $0ECD              ; sky 15

; --- Stage 5: Olisis (grey/white checker, grey→blue sky) ---
            da     $0CCC              ; checker light: light grey
            da     $0888              ; checker dark: medium grey
            da     $0677              ; sky 4: dark grey
            da     $0788              ; sky 5
            da     $0899              ; sky 6
            da     $089A              ; sky 7
            da     $099B              ; sky 8
            da     $0A9C              ; sky 9
            da     $0AAD              ; sky 10
            da     $0BAE              ; sky 11
            da     $0BBF              ; sky 12
            da     $0CCF              ; sky 13: blue-grey
            da     $0CCF              ; sky 14
            da     $0CCF              ; sky 15

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

; --- Game state ---
HarrierRow  ds    2
HarrierCol  ds    2
Shape_Man   ds    2
FrameTimer  ds    2
QuitFlag    ds    2
Ligne_Damier da   $C5-$3C           ; horizon line (same as FTA)
Coordonnee_X da   0                 ; horizontal scroll position
V_X          ds   2                  ; lateral scroll velocity (signed)

; Table_Vitesse — lateral scroll speed from Harrier X position
; Mouse: HarrierCol/2 → index 0-63. 64 entries.
Table_Vitesse
            ds    7,$FD               ; far left: speed -3
            ds    7,$FE               ; speed -2
            ds    7,$FF               ; speed -1
            ds    14,$00              ; center: no scroll
            ds    7,$01               ; speed +1
            ds    7,$02               ; speed +2
            ds    7,$03               ; far right: speed +3
            ds    2,$03               ; padding to cover max index

; Table_Ciel — sky gradient palette assignments per row
; Read from horizon upward. Arcade Stage 1: green near mountains → lavender.
Table_Ciel
            ds    2,4                ; horizon: strong green
            ds    3,5                ; bright green
            ds    3,6                ; lighter green
            ds    3,7                ; green-teal
            ds    2,8                ; teal
            ds    2,9                ; teal-purple
            ds    2,10               ; blue-lavender
            ds    2,11               ; light lavender
            ds    2,12               ; medium lavender
            ds    119,13             ; lavender (rest of sky)
            ds    5,5
            ds    5,4                ; top: darkest
            ds    28,4               ; padding to cover max 140 sky rows

; =====================================================================
; Object array — MAX_OBJECTS slots × OBJ_SIZE bytes
; =====================================================================
ObjArray    ds     MAX_OBJECTS*OBJ_SIZE

WaveTimer   da     0                ; 0 = spawn wave immediately on first frame
ShipMoveCount da   0                ; (unused, kept for alignment)

; Ship altitude curve indexed by depth (0=close, 14=far)
; Low at horizon, rises to peak mid-flight, descends as it passes player
ShipAltCurve
            dfb    $20              ; depth 0: low (swooping past)
            dfb    $28              ; depth 1
            dfb    $35              ; depth 2
            dfb    $40              ; depth 3
            dfb    $4A              ; depth 4
            dfb    $55              ; depth 5: rising
            dfb    $5E              ; depth 6
            dfb    $65              ; depth 7: peak
            dfb    $60              ; depth 8
            dfb    $58              ; depth 9: descending
            dfb    $4E              ; depth 10
            dfb    $42              ; depth 11
            dfb    $38              ; depth 12
            dfb    $30              ; depth 13: low at horizon
            dfb    $2A              ; depth 14: spawn altitude

; Wave formation: 4 ships, horizontal offsets from Coordonnee_X
WaveShipHori
            da     $FFD0            ; ship 0: -48 (left)
            da     $FFE8            ; ship 1: -24 (center-left)
            da     $0018            ; ship 2: +24 (center-right)
            da     $0030            ; ship 3: +48 (right)

; Wave formation: direction sign (stored in high byte of S_Altitude)
; $0100 = drift right, $FF00 = drift left
WaveShipDir
            da     $0100            ; ship 0: drift right
            da     $0100            ; ship 1: drift right
            da     $FF00            ; ship 2: drift left
            da     $FF00            ; ship 3: drift left

; Ship horizontal velocity curve indexed by depth (0=close, 14=far)
; Magnitude only — direction comes from WaveShipDir
; Starts slow at horizon, accelerates as ships get closer
ShipXCurve
            dfb    $06              ; depth 0: fast (close, swooping past)
            dfb    $06              ; depth 1
            dfb    $05              ; depth 2
            dfb    $05              ; depth 3
            dfb    $04              ; depth 4
            dfb    $04              ; depth 5
            dfb    $03              ; depth 6
            dfb    $03              ; depth 7: mid-flight
            dfb    $02              ; depth 8
            dfb    $02              ; depth 9
            dfb    $02              ; depth 10
            dfb    $01              ; depth 11
            dfb    $01              ; depth 12
            dfb    $01              ; depth 13
            dfb    $00              ; depth 14: stationary at spawn

; =====================================================================
; Decalage_Y — perspective scaling per depth level (FTA's SPACE.S)
; Index by depth (0=near, 15=far). Value = rows below horizon.
; =====================================================================
Decalage_Y  dfb    40,32,26,22,18,15,13,11,9,7,6,5,4,3,2,1

; =====================================================================
; Shape_Hauteur — sprite height (rows) indexed by TABLE_ROUT entry
; Entries 0-23 unused (damier/man), padded with zeros.
; =====================================================================
Shape_Hauteur
            ds     24,0           ; padding for entries 0-23

            ; Tree (entries 24-39, depths 0-15)
            dfb    $79,$50,$3C,$30,$28,$21,$1D,$19
            dfb    $17,$14,$13,$11,$11,$10,$0F,$0E

            ; Explosion (entries 40-50)
            dfb    36,29,23,19,18,15,14,12,10,9,8

            ; Tir (entries 51-61)
            dfb    14,14,10,8,7,6,5,4,4,4,3

            ; Pierre (entries 62-69)
            dfb    29,20,14,11,10,9,7,6

            ; Ombre (entries 70-77)
            dfb    12,9,6,5,4,3,2,1

            ; Buisson (entries 78-91)
            dfb    29,18,14,11,9,8,7,6,5,5,4,4,4,2

            ; Ship (entries 92-106)
            dfb    35,22,16,13,10,9,7,6,6,5,4,4,4,3,3

            ; Trident (entries 107-115)
            dfb    48,42,34,23,18,15,12,11,7

; =====================================================================
; MULTI lookup tables (FTA's SPACE.S)
; =====================================================================

; HAUTBAS — high nibble of Y replicated across all positions
HAUTBAS     hex    00000000000000000000000000000000
            hex    01010101010101010101010101010101
            hex    02020202020202020202020202020202
            hex    03030303030303030303030303030303
            hex    04040404040404040404040404040404
            hex    05050505050505050505050505050505
            hex    06060606060606060606060606060606
            hex    07070707070707070707070707070707
            hex    08080808080808080808080808080808
            hex    09090909090909090909090909090909
            hex    0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A
            hex    0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B
            hex    0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C
            hex    0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D
            hex    0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E
            hex    0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F

; BASHAUT — low nibble of Y shifted to high nibble
BASHAUT     hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0
            hex    00102030405060708090A0B0C0D0E0F0

; BASBAS — low nibble identity
BASBAS      hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F
            hex    000102030405060708090A0B0C0D0E0F

; MULTIT1 — 4-bit × 4-bit product table (256 bytes)
MULTIT1     hex    00000000000000000000000000000000
            hex    000102030405060708090A0B0C0D0E0F
            hex    00020406080A0C0E10121416181A1C1E
            hex    000306090C0F1215181B1E2124272A2D
            hex    0004080C1014181C2024282C3034383C
            hex    00050A0F14191E23282D32373C41464B
            hex    00060C12181E242A30363C42484E545A
            hex    00070E151C232A31383F464D545B6269
            hex    00081018202830384048505860687078
            hex    0009121B242D363F48515A636C757E87
            hex    000A141E28323C46505A646E78828C96
            hex    000B16212C37424D58636E79848F9AA5
            hex    000C1824303C4854606C7884909CA8B4
            hex    000D1A2734414E5B6875828F9CA9B6C3
            hex    000E1C2A38465462707E8C9AA8B6C4D2
            hex    000F1E2D3C4B5A69788796A5B4C3D2E1

; MULTIT2 — crossed-nibble correction table (512 bytes)
MULTIT2     hex    00000000000000000000000000000000
            hex    00000000000000000000000000000000
            hex    00001000200030004000500060007000
            hex    80009000A000B000C000D000E000F000
            hex    00002000400060008000A000C000E000
            hex    00012001400160018001A001C001E001
            hex    0000300060009000C000F00020015001
            hex    8001B001E001100240027002A002D002
            hex    000040008000C000000140018001C001
            hex    000240028002C002000340038003C003
            hex    00005000A000F00040019001E0013002
            hex    8002D00220037003C00310046004B004
            hex    00006000C00020018001E0014002A002
            hex    00036003C00320048004E0044005A005
            hex    00007000E0005001C0013002A0021003
            hex    8003F0036004D0044005B00520069006
            hex    00008000000180010002800200038003
            hex    00048004000580050006800600078007
            hex    000090002001B0014002D0026003F003
            hex    80041005A0053006C0065007E0077008
            hex    0000A0004001E00180022003C0036004
            hex    0005A0054006E00680072008C0086009
            hex    0000B00060011002C00270032004D004
            hex    80053006E00690074008F008A009500A
            hex    0000C000800140020003C00380044005
            hex    0006C006800740080009C009800A400B
            hex    0000D000A001700240031004E004B005
            hex    800650072008F008C009900A600B300C
            hex    0000E000C001A0028003600440052006
            hex    0007E007C008A009800A600B400C200D
            hex    0000F000E001D002C003B004A0059006
            hex    800770086009500A400B300C200D100E

; =====================================================================
; Quit record / app state
; =====================================================================
qtRec       adrl  $0000
MyDirectPage ds   2
MyUserId     ds   2
