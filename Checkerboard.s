* Checkerboard pattern generator
* Ported from FTA's ESSAI2.S (1989) for Merlin32
*
* Pre-computes 8 frames of perspective-correct checkerboard
* into IMAGE buffer ($030000). Each frame is offset by a
* different horizontal scroll amount.
*
* Uses colors $4 and $E for the two stripe colors.
* At runtime, palette swapping between palette 0/2 on
* alternating scanlines creates the full checkerboard effect.

* DP variables (uses NEWPAGE0 = $0F00 as DP base)
_LIG_NB     equ   $00
_LIG_ADR    equ   $02
_CTR        equ   $04
_TR_PAS     equ   $06
_TR_LAST    equ   $08
_TR_NEW     equ   $0A
_TR_LAST2   equ   $0C
_TR_NEW2    equ   $0E
_PARITE     equ   $10
_CTR_PAS    equ   $12

* Constants
_MIN_COL    equ   $80
_MAX_COL    equ   256*$80
_MAX_COL2   equ   256
_CTR0       equ   128*$80
_CTR_PAS0   equ   0
_CTR_PAS2   equ   16
_TR_PAS0    equ   $80
_TR_PAS2    equ   $80
_LIG_ADR0   equ   0
_NB_LIG     equ   $3C           ; 60 rows
_LIG_PAS    equ   256

IMAGE       equ   $190000     ; 8 frames × $1E00 = $F000 bytes (banks $19-$19)
_LONGUEUR   equ   $80*$3C       ; 128 bytes × 60 rows = $1E00 per frame

* =====================================================================
* ENTER — generate 8 checkerboard frames
* =====================================================================
ENTER
            phd                       ; save caller's DP
            lda    MyDirectPage
            tcd                       ; DP = app's assigned direct page
            rep    #$30

            ; Clear IMAGE buffer: 8 frames × $1E00 = $F000 bytes
            lda    #0
            ldx    #0
:clrImg     stal   IMAGE,x
            inx
            inx
            cpx    #_LONGUEUR*8
            bcc    :clrImg

            lda    #_CTR_PAS0
            sta    _CTR_PAS
]BOU2       jsr    TRACE_DAMIER
            lda    _CTR_PAS
            clc
            adc    #_CTR_PAS2
            cmp    #_TR_PAS0
            bcs    ON_A_FINI
            sta    _CTR_PAS
            lda    _MOD1+1
            clc
            adc    #_LONGUEUR
            jsr    CHANGE_IMAGE
            bra    ]BOU2

ON_A_FINI
            pld                       ; restore caller's DP
            rts

* =====================================================================
* CHANGE_IMAGE — patch all self-modifying addresses to next frame
* =====================================================================
CHANGE_IMAGE
            mx     %00
            sta    _MOD1+1
            sta    _MOD2+1
            sta    _MOD3+1
            sta    _MOD4+1
            sta    _MOD5+1
            sta    _MOD6+1
            sta    _MOD7+1
            sta    _MOD8+1
            sta    _MOD9+1
            sta    _MOD10+1
            sta    _MOD11+1
            sta    _MOD12+1
            sta    _MOD13+1
            sta    _MOD14+1
            sta    _MOD15+1
            sta    _MOD16+1
            sta    _MOD17+1
            sta    _MOD18+1
            rts

* =====================================================================
* COLOR0 — draw a stripe segment using color $4
* X = byte offset in IMAGE row, Y = width in pixels
* =====================================================================
_COLOR0     mx     %00
            cpy    #0
            bne    _OK_LONG
            ldy    #1
_OK_LONG    txa
            lsr
            tax
            bcc    _NO_PIXEL
_MOD1       ldal   IMAGE,x
            and    #$FFF0
            ora    #$4
_MOD2       stal   IMAGE,x
            inx
            dey
_NO_PIXEL   lda    #$4444
_NO_PIXEL2  cpy    #4
            bcc    _F_TRACE
_MOD3       stal   IMAGE,x
            inx
            inx
            dey
            dey
            dey
            dey
            bne    _NO_PIXEL2
_OUT        rts

_F_TRACE    cpy    #2
            beq    _TRACE_2
            bcs    _TRACE_3
            cpy    #1
            bcc    _OUT
_MOD4       =      *
_TRACE_1    ldal   IMAGE,x
            and    #$FF0F
            ora    #$0040
_MOD5       stal   IMAGE,x
_OUT2       rts
_MOD6       =      *
_TRACE_2    ldal   IMAGE,x
            and    #$FF00
            ora    #$0044
_MOD7       stal   IMAGE,x
_OUT3       rts
_MOD8       =      *
_TRACE_3    ldal   IMAGE,x
            and    #$0F00
            ora    #$4044
_MOD9       stal   IMAGE,x
_OUT4       rts

* =====================================================================
* COLOR1 — draw a stripe segment using color $E
* =====================================================================
_COLOR1     mx     %00
            cpy    #0
            bne    _ZOK_LONG
            ldy    #1
_ZOK_LONG   txa
            lsr
            tax
            bcc    _ZNO_PIXEL
_MOD10      ldal   IMAGE,x
            and    #$FFF0
            ora    #$E
_MOD11      stal   IMAGE,x
            inx
            dey
_ZNO_PIXEL  lda    #$EEEE
_ZNO_PIXEL2 cpy    #4
            bcc    _ZF_TRACE
_MOD12      stal   IMAGE,x
            inx
            inx
            dey
            dey
            dey
            dey
            bne    _ZNO_PIXEL2
_ZOUT       rts

_ZF_TRACE   cpy    #2
            beq    _ZTRACE_2
            bcs    _ZTRACE_3
            cpy    #1
            bcc    _ZOUT
_MOD13      =      *
_ZTRACE_1   ldal   IMAGE,x
            and    #$FF0F
            ora    #$00E0
_MOD14      stal   IMAGE,x
_ZOUT2      rts
_MOD15      =      *
_ZTRACE_2   ldal   IMAGE,x
            and    #$FF00
            ora    #$00EE
_MOD16      stal   IMAGE,x
_ZOUT3      rts
_MOD17      =      *
_ZTRACE_3   ldal   IMAGE,x
            and    #$0F00
            ora    #$E0EE
_MOD18      stal   IMAGE,x
_ZOUT4      rts

* =====================================================================
* TRACE_DAMIER — draw one complete checkerboard frame
* =====================================================================
TRACE_DAMIER
            php
            rep    #$30
            lda    #_CTR0
            sec
            sbc    _CTR_PAS
            sta    _CTR
            lda    #_NB_LIG
            sta    _LIG_NB
            lda    #_LIG_ADR0
            sta    _LIG_ADR
            lda    #_TR_PAS0
            sta    _TR_PAS
]BOU        jsr    TRACE_LIGNE
            dec    _LIG_NB
            beq    TR_DAM_OUT
            lda    _TR_PAS
            clc
            adc    #_TR_PAS2
            sta    _TR_PAS
            lda    _CTR
            sec
            sbc    _CTR_PAS
            sta    _CTR
            lda    _LIG_ADR
            clc
            adc    #_LIG_PAS
            sta    _LIG_ADR
            bra    ]BOU

TR_DAM_OUT  plp
            rts

* =====================================================================
* TRACE_LIGNE — draw one checkerboard row (left half then right half)
* =====================================================================
TRACE_LIGNE
            php
            rep    #$30
            stz    _PARITE
            lda    _TR_PAS
            lsr
            sec
            sbc    _CTR
            eor    #$FFFF
            inc
            sta    _TR_LAST
            CONVERT
            sta    _TR_LAST2

* --- Left side (center toward left edge) ---
]SUITE_L    lda    _TR_LAST
            sec
            sbc    _TR_PAS
            bcc    END_GAU
            cmp    #_MIN_COL
            bcc    END_GAU
            sta    _TR_NEW
            CONVERT
            sta    _TR_NEW2
            clc
            adc    _LIG_ADR
            tax
            lda    _TR_LAST2
            sec
            sbc    _TR_NEW2
            tay
            lda    _PARITE
            beq    COL1_A
            jsr    _COLOR0
            bra    UP1_A
COL1_A      jsr    _COLOR1
UP1_A       lda    _TR_NEW
            sta    _TR_LAST
            lda    _TR_NEW2
            sta    _TR_LAST2
            lda    _PARITE
            eor    #$FFFF
            sta    _PARITE
            bra    ]SUITE_L

END_GAU     ldx    _LIG_ADR
            ldy    _TR_LAST2
            lda    _PARITE
            beq    COL1_B
            jsr    _COLOR0
            bra    A_DROITE
COL1_B      jsr    _COLOR1

* --- Right side (center toward right edge) ---
A_DROITE    lda    #$FFFF
            sta    _PARITE
            lda    _TR_PAS
            lsr
            sec
            sbc    _CTR
            eor    #$FFFF
            inc
            sta    _TR_LAST
            CONVERT
            sta    _TR_LAST2

]SUITE_R    lda    _TR_LAST
            clc
            adc    _TR_PAS
            cmp    #_MAX_COL
            bcs    END_DRO
            sta    _TR_NEW
            CONVERT
            sta    _TR_NEW2
            lda    _TR_LAST2
            clc
            adc    _LIG_ADR
            tax
            lda    _TR_NEW2
            sec
            sbc    _TR_LAST2
            tay
            lda    _PARITE
            beq    COL1_C
            jsr    _COLOR0
            bra    UP1_C
COL1_C      jsr    _COLOR1
UP1_C       lda    _TR_NEW
            sta    _TR_LAST
            lda    _TR_NEW2
            sta    _TR_LAST2
            lda    _PARITE
            eor    #$FFFF
            sta    _PARITE
            bra    ]SUITE_R

END_DRO     lda    _TR_LAST2
            clc
            adc    _LIG_ADR
            tax
            lda    #_MAX_COL2
            sec
            sbc    _TR_LAST2
            tay
            lda    _PARITE
            beq    COL1_D
            jsr    _COLOR0
]OUT_TL     plp
            rts
COL1_D      jsr    _COLOR1
            bra    ]OUT_TL
