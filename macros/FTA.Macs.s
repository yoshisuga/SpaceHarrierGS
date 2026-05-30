* FTA Space Harrier macros
* Ported from SPACE.MAC.S (FTA, 1989) for Merlin32
*
* Original macros used by the Space Harrier game engine.

* INK — 16-bit increment of a memory location
*   Increments ]1 as a 16-bit value (low byte + high byte).
INK         MAC
            INC   ]1
            BNE   EndINK
            INC   ]1+1
EndINK      <<<

* Inverse — make accumulator positive (absolute value)
*   If A is negative, negate it (EOR #$FFFF + INC).
Inverse     MAC
            BPL   InvPos
            EOR   #$FFFF
            INC
InvPos      <<<

* Call_ALEA — generate a pseudo-random number from VBL counters
*   Reads the IIgs VBL/scan counters at $C02E/$C02F,
*   mixes them with shifts and adds.  Result in A (8-bit).
Call_ALEA   MAC
            SEP   #$30
            LDA   $C02E
            ROL
            ROL
            CLC
            ADC   $C02F
            ASL
            EOR   $C02E
            CLC
            EOR   $C02F
            REP   #$30
            <<<

* CONVERT — divide A by 128 (shift right 7 times)
*   Used by the checkerboard to convert pixel coords to byte offsets.
CONVERT     MAC
            LSR
            LSR
            LSR
            LSR
            LSR
            LSR
            LSR
            <<<

* Branch-long macros — work around the 65816's 8-bit branch range.
* Each expands to a short branch over a BRL (16-bit branch).

BPLL        MAC
            BMI   NoBPLL
            BRL   ]1
NoBPLL      <<<

BMIL        MAC
            BPL   NoBMIL
            BRL   ]1
NoBMIL      <<<

BEQL        MAC
            BNE   NoBEQL
            BRL   ]1
NoBEQL      <<<

BCCL        MAC
            BCS   NoBCCL
            BRL   ]1
NoBCCL      <<<

BCSL        MAC
            BCC   NoBCSL
            BRL   ]1
NoBCSL      <<<

BNEL        MAC
            BEQ   NoBNEL
            BRL   ]1
NoBNEL      <<<
