*-------------------------------------------------
* Create_Sprite — Compiled sprite engine
* Ported from FTA's CREATE.SPRITE.S (1989)
*
* Compiles shape data into native 65816 code that
* draws sprites via direct-page writes to SHR shadow RAM.
*
* Call: copy sprite table ($18 bytes) to bank $00 direct page,
*       LDA #dp_address / JSR Create_Sprite
*
* Sprite table format (24 bytes at DP offsets $00-$17):
*   $00 ADRL Rout_Adr    — output: where compiled code is written
*   $04 ADRL Shape_Adr   — input: shape pixel data (24-bit)
*   $08 ADRL Msk_Adr     — $000000=none, $FFFF00=auto, $FEFE00=decor
*   $0C DA   Tbl_Nb      — TABLE_ROUT index (updated by routine)
*   $0E DA   Nb_Lgn      — bytes per shape row
*   $10 DA   Nb_Col      — bytes per shape column
*   $12 DA   Lgn         — row ($FFFF=dynamic via Y register)
*   $14 DA   Col         — column
*   $16 DA   Pixel_Shape — $00=no sub-pixel, $01=half-pixel shift
*-------------------------------------------------

* Direct page parameter offsets
_RoutAdr    equ   $00
_ShapeAdr   equ   $04
_MskAdr     equ   $08
_TblNb      equ   $0C
_NbLgn      equ   $0E
_NbCol      equ   $10
_Lgn        equ   $12
_Col        equ   $14
_Pixel      equ   $16

*-------------------------------------------------
*           C R E A T E _ S P R I T E
*-------------------------------------------------

Create_Sprite REP  #$30

            PHD                     ; save caller's direct page
            TCD                     ; DP = A (points to sprite table in bank $00)

            STZ   _Pix

            LDX   #0
]loop       LDA   _ShapeAdr,X      ; save shape+mask addresses for Pixel_Shape restore
            STA   SaveShp,X
            INX
            INX
            CPX   #4*2
            BNE   ]loop

MAINLOOP_Pix =    *

* Write JML entry in TABLE_ROUT for this sprite
            LDA   _TblNb
            ASL
            ASL                     ; *4 (each TABLE_ROUT entry = 4 bytes)
            INC   _TblNb            ; advance for next sprite
            TAX
            SEP   #$20
            LDA   #$5C              ; JML opcode
            STAL  TABLE_ROUT,X
            REP   #$20
            LDA   _RoutAdr
            STAL  TABLE_ROUT+1,X    ; low word of compiled routine address
            LDA   _RoutAdr+1
            STAL  TABLE_ROUT+2,X    ; high word (bank byte in low position)

* Emit prologue (RAMRD/RAMWRT enable, CLC)
            SEP   #$30
            LDX   #Deb_Rout
            JSR   Insert_Rout
            REP   #$30


* Initialize row tracking
            LDA   _Lgn
            STA   _BufLgn
            LDA   _NbLgn
            STA   _BufNbLgn

            LDA   #$F562            ; dummy value (forces first LDA #imm to emit)
            STA   _Acc
            STZ   _ZPage
            STZ   _PosLgn

* If Lgn=$FFFF (dynamic position), emit TYA/TCD
            LDA   _Lgn
            BPL   MAINLOOP_Lgn
            LDA   #$5B98            ; $98=TYA, $5B=TCD
            JSR   _STA16

*=== Per-row loop ===
MAINLOOP_Lgn = *
            STZ   SEP20
            STZ   _Pos
            STZ   _CorShp
            LDA   #$FFFF
            STA   _CorMsk
            CLC
            LDA   _NbCol
            STA   _BufNbCol

* If fixed row, compute screen address from TBA
            LDA   _BufLgn
            BMI   No_Line
            ASL
            TAX
            LDA   TBA,X
            CLC
            ADC   _Col
            STA   _PosAdr
No_Line     = *

*=== Per-column loop ===
MAINLOOP_Col = *

* If in 8-bit mode from previous col, emit SEP/REP
            LDA   SEP20
            BEQ   NoSep20
            LDA   #$20E2            ; $E2=SEP, $20=#$20
            JSR   _STA16
NoSep20     LDA   #0                ; default mask value

* Check mask mode
            LDX   _Lgn
            CPX   #$FEFE
            BEQ   Index
            LDX   _MskAdr+1
            BEQ   PutMask
            BPL   MaskOn
            CPX   #$FDFD
            BNE   No_SpecialMount

* Mountain special mode ($FDFD)
            SEP   #$20
            LDA   #$BD              ; LDA abs,X opcode
            JSR   _STA
            REP   #$20
            LDA   _PosLgn
            XBA
            AND   #$FF00
            CLC
            ADC   _Pos
            JSR   _STA16
            BRL   PutOnScreen

            MX    %00
No_SpecialMount CPX #$FEFE
            BNE   AutoMask

* Decor restore mode ($FEFE)
            SEP   #$20
            LDA   #$BD              ; LDA abs,X
            JSR   _STA
            REP   #$20
            LDA   _PosLgn
            ASL
            ASL
            ASL
            ASL
            ASL
            ASL
            ASL
            CLC
            ADC   _Pos
            JSR   _STA16
            BRL   PutOnScreen

Index       = *
            SEC
            XCE
            SEP   #$30
            JMP   $FF59

*--- Auto-mask: generate mask from shape data using TBL_MSK ---
AutoMask    = *
            LDA   #0
            XBA
            SEP   #$30
            LDY   #1
            LDA   [_ShapeAdr],Y     ; high byte of shape word
            TAX
            LDA   TBL_MSK,X         ; look up mask for high nibble
            STA   Corraga           ; patch ORA operand below
            LDA   [_ShapeAdr]       ; low byte of shape word
            REP   #$30
            AND   #$00FF
            TAX
            LDA   TBL_MSK,X         ; mask for low byte
            AND   #$00FF
            ORA   #$FF00            ; high byte gets patched by Corraga
Corraga     = *-1
            BRA   PutMask

MaskOn      = *
            LDA   [_MskAdr]         ; read explicit mask

PutMask     = *
            STA   _Msk

* Pixel shift (for half-pixel alignment)
            LDA   _Pix
            BEQ   No_Dec0
            SEP   #$30
            LDX   #0
]loop       ROR   _CorMsk
            ROR   _Msk
            ROR   _Msk+1
            ROR   _Cor
            INX
            CPX   #4
            BNE   ]loop
            LDA   _Cor
            LSR
            LSR
            LSR
            LSR
            STA   _CorMsk
            REP   #$30

* Check if mask is needed (skip if $0000 or $FFFF)
No_Dec0     LDA   _Msk
            BEQ   PasLaPeine
            CMP   #$FFFF
            BEQ   PasLaPeine

* Emit: LDA screen_byte (read existing pixels for masking)
            JSR   Get_Screen

* Emit: AND #mask
            SEP   #$20
            LDA   #$29              ; AND # opcode
            JSR   _STA
            REP   #$20

            LDA   SEP20
            BEQ   NoSEP22
            SEP   #$20
            LDA   _Msk
            JSR   _STA
            REP   #$20
            BRA   PasLaPeine
NoSEP22     LDA   _Msk
            JSR   _STA16

*--- Process shape pixel data ---
PasLaPeine  = *
            LDA   #0
            XBA
            SEP   #$30
            LDY   #1
            LDA   [_ShapeAdr],Y     ; high byte
            TAX
            LDA   TBL_MSK,X
            STA   Corraga2          ; patch ORA operand
            LDA   [_ShapeAdr]       ; low byte
            REP   #$30
            AND   #$00FF
            TAX
            LDA   TBL_MSK,X
            AND   #$00FF
            ORA   #$FF00
Corraga2    = *-1
            EOR   #$FFFF            ; invert mask → keep non-transparent pixels
            AND   [_ShapeAdr]       ; mask out transparent nibbles from shape
            STA   _Shp

* Pixel shift
            LDA   _Pix
            BEQ   No_Dec1
            SEP   #$30
            LDX   #0
]loop       ROR   _CorShp
            ROR   _Shp
            ROR   _Shp+1
            ROR   _Cor
            INX
            CPX   #4
            BNE   ]loop
            LDA   _Cor
            LSR
            LSR
            LSR
            LSR
            STA   _CorShp
            REP   #$30

No_Dec1     LDA   _Shp
            CMP   #0
            BNE   ShapeOn

* No shape data — check if we had a mask that needs storing
            LDA   _Msk
            CMP   #$FFFF
            BEQ   ShapeOff
            CMP   #0
            BEQ   PutData
            BRA   PutOnScreen       ; had a mask, need to store result

ShapeOn     = *

* Check if mask was already applied
            LDA   _MskAdr+1
            BEQ   PutData
            LDA   _Msk
            CMP   #0
            BEQ   PutData
            CMP   #$FFFF
            BNE   AlreadyDone

* Emit: LDA #shape_data
PutData     LDA   _MskAdr+1
            BNE   NoTestaga
            LDA   _Shp
            CMP   _Acc
            STA   _Acc
NoTestaga   SEP   #$20
            LDA   #$A9              ; LDA # opcode
            JSR   _STA
            REP   #$20
            BRA   CtAlready

* Emit: ORA #shape_data (combine with masked background)
AlreadyDone = *
            SEP   #$20
            LDA   #$09              ; ORA # opcode
            JSR   _STA
CtAlready   REP   #$20
            LDA   SEP20
            BEQ   No_Sep23
            SEP   #$20
            LDA   _Shp
            JSR   _STA
            REP   #$20
            BRA   PutOnScreen
No_Sep23    LDA   _Shp
            JSR   _STA16

*--- Emit: STA screen_byte ---
PutOnScreen = *
            LDA   _Pos
            LDX   _Lgn
            BMI   NoFixBis
            JSR   TestZPage
NoFixBis    SEP   #$20
            PHA
            LDA   #$85              ; STA dp opcode
            JSR   _STA
            PLA
            JSR   _STA
            REP   #$20

*--- Advance to next column ---
ShapeOff    = *
            INC   _ShapeAdr         ; advance shape pointer
            LDA   SEP20
            BNE   No_IO
            INC   _ShapeAdr         ; +2 in 16-bit mode
No_IO       LDA   _MskAdr+1
            BEQ   NoUpdateMsk
            BMI   NoUpdateMsk
            INC   _MskAdr           ; advance mask pointer
            LDA   SEP20
            BNE   No_IO2
            INC   _MskAdr
No_IO2      = *
NoUpdateMsk = *

            INC   _Pos
            INC   _Pos

            DEC   _BufNbCol
            DEC   _BufNbCol
            LDA   _BufNbCol
            BEQ   EndLigne
            LDX   SEP20
            CPX   #$FFFF
            BEQ   EndLigne
            CMP   #1
            BNE   Nooo
            LDA   #$FFFF
            STA   SEP20
Nooo        BRL   MAINLOOP_Col

*--- End of row ---
EndLigne
            LDA   SEP20
            BEQ   NNPP
            LDA   #$20C2            ; $C2=REP, $20=#$20
            JSR   _STA16
NNPP        = *
            STZ   SEP20
            INC   _BufLgn
            INC   _PosLgn
            DEC   _BufNbLgn
            BEQ   NoMoreLgn

* Emit row-advance code if dynamic position
            SEP   #$30
            LDA   _Lgn
            CMP   #$FF
            BNE   No_Advance
            LDX   #Advance
            JSR   Insert_Rout
No_Advance  REP   #$30
            BRL   MAINLOOP_Lgn

*--- All rows done: emit epilogue ---
NoMoreLgn
            SEP   #$30
            LDX   #End_Rout
            JSR   Insert_Rout
            REP   #$30

* Handle Pixel_Shape (half-pixel shifted variant)
            LDA   _Pixel
            BEQ   EndOfCreate
            LDA   _Pix
            EOR   #$01
            STA   _Pix
            BEQ   EndOfCreate

* Restore shape addresses and compile shifted variant
            LDX   #0
]loop       LDA   SaveShp,X
            STA   _ShapeAdr,X
            INX
            INX
            CPX   #4*2
            BNE   ]loop
            BRL   MAINLOOP_Pix

EndOfCreate PLD                     ; restore caller's direct page
            REP   #$30
            RTS

*-------------------------------------------------
* Helper: Get_Screen — emit LDA dp (read screen byte)
*-------------------------------------------------
            MX    %11

Get_Screen  = *
            LDA   _Pos
            LDX   _Lgn
            BMI   NoFix
            JSR   TestZPage
NoFix       SEP   #$20
            PHA
            LDA   #$A5              ; LDA dp opcode
            JSR   _STA
            PLA
            JSR   _STA
            REP   #$20
            RTS

*-------------------------------------------------
* Helper: TestZPage — emit PEA/PLD if crossing page boundary
*-------------------------------------------------
            MX    %00

TestZPage   LDA   _PosAdr
            CLC
            ADC   _Pos
            PHA
            AND   #$FF00
            CMP   _ZPage
            BEQ   SameZPage
            STA   _ZPage
            PHA
            SEP   #$20
            LDA   #$F4              ; PEA opcode
            JSR   _STA
            REP   #$20
            PLA
            JSR   _STA16            ; emit page address
            SEP   #$20
            LDA   #$2B              ; PLD opcode
            JSR   _STA
            REP   #$20
SameZPage   PLA
            RTS

*-------------------------------------------------
* Create_Sprite internal variables
*-------------------------------------------------
SEP20       DS    2
_Cor        DS    2
_CorMsk     DS    2
_CorShp     DS    2
_Msk        DS    2
_Shp        DS    2
_Pos        DS    2
_PosLgn     DS    2
_PosAdr     DS    2
_BufNbCol   DS    2
_ZPage      DS    2
_Acc        DS    2
_Pix        DS    2
_BufLgn     DS    2
_BufNbLgn   DS    2
SaveShp     DS    8

*-------------------------------------------------
* _STA — emit one byte to compiled output
*-------------------------------------------------
            MX    %11
_STA        STA   [_RoutAdr]
            INC   _RoutAdr
            BNE   End_Sta
            INC   _RoutAdr+1
End_Sta     RTS

*-------------------------------------------------
* _STA16 — emit two bytes (word) to compiled output
*-------------------------------------------------
            MX    %00
_STA16      STA   [_RoutAdr]
            INC   _RoutAdr
            INC   _RoutAdr
            RTS

*-------------------------------------------------
* Insert_Rout — copy template bytes until $FE sentinel
*-------------------------------------------------
            MX    %11
Insert_Rout = *
]loop       LDA   Routinaga,X
            CMP   #$FE
            BEQ   End_Routaga
            JSR   _STA
            INX
            BNE   ]loop
End_Routaga RTS

*-------------------------------------------------
* Routinaga — template code copied into compiled sprites
*
* These are raw 65816 instructions. Insert_Rout copies
* them byte-by-byte into the compiled output. $FE = end sentinel.
*-------------------------------------------------
Routinaga   = *

* Prologue: enable RAMRD+RAMWRT for aux memory access, CLC for ADC
            MX    %00
Deb_Routine = *
            LDAL  $E1C068           ; State Register
            ORA   #$30              ; set bits 4+5: RAMRD + RAMWRT
            STAL  $E1C068
            CLC                     ; for Advance_Lgn's ADC
            HEX   FE                ; sentinel

* Epilogue: reset DP to 0, disable RAMRD+RAMWRT, RTL
            MX    %00
End_Routine = *
            LDA   #0
            TCD                     ; DP back to page 0
            LDAL  $E1C068
            AND   #$FFCF            ; clear bits 4+5
            STAL  $E1C068
            RTL                     ; return to caller
            HEX   FE                ; sentinel

* Row advance: DP += $A0 (next screen row = 160 bytes)
            MX    %00
Advance_Lgn = *
            TDC                     ; A = current DP (screen row addr)
            ADC   #$A0              ; CLC done in prologue; no carry possible
            TCD                     ; DP = next row
            HEX   FE                ; sentinel

* Template offset equates (byte offsets from Routinaga)
Deb_Rout    equ   0
End_Rout    equ   End_Routine-Deb_Routine
Advance     equ   Advance_Lgn-Deb_Routine
