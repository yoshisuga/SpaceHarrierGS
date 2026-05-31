# Space Harrier GS — Engine Technical Reference

All code in `App.Main.s` unless noted. Line numbers are approximate.

---

## 1. Memory Map

### Expansion RAM Banks

| Bank(s) | Address      | Contents |
|---------|-------------|----------|
| $09     | $090000     | `Decor_Mountain` — mountain bitmap (2 frames) |
| $0A     | $0A0004+    | Shape data: Tree, Explo, Tir, Pierre, Chiffre, Ombre, Buisson, Ship, Trident, Divers |
| $0C-$0D | $0C5004+   | Shape data: Dragon (Face, Der, Mid, Back) |
| $0F     | $0F00       | `NEWPAGE0` — Direct Page for sprite compiler |
| $10     | $10F100     | `TABLE_ROUT` — compiled sprite dispatch table (4 bytes per entry) |
| $11     | $110000     | `Damier_Rout` / `TSB_Rout` — compiled checkerboard blit |
| $12     | $120000     | `Clear_Rout` — compiled screen clear |
| $13     | $130000     | `Man_Rout` — compiled Harrier sprites |
| $14     | $140000     | `Mountain_Rout` — compiled mountain blit |
| $15     | $150000     | `ROUT0` — compiled object sprites: Tree, Explo, Tir, Pierre, Ombre |
| $16     | $160000     | `ROUT1` — compiled object sprites: Buisson, Ship, Trident |
| $17     | $170000     | `ROUT2` — compiled object sprites: Dragon parts |
| $18     | $180000     | `Chiffre_Rout` — compiled digit/text sprites |
| $19     | $190000     | `IMAGE` — 8 pre-computed checkerboard frames ($1E00 each) |

### SHR Screen ($E1/2000)

```
Row layout: 160 bytes per row, 200 rows
  Bytes 0-127:   Play area (256 pixels, 4bpp packed)
  Bytes 128-159: Sidebar (filled with color $1, palette sets it to black in sky)

SCB ($E1/9D00): Per-scanline palette select
  Sky rows:      Palettes 4-15 (gradient colors)
  Ground rows:   Palettes 0-1 alternating (checkerboard banding)

Palettes ($E1/9E00): 16 palettes × 16 colors × 2 bytes
  Palette 0/1:   Ground (checker colors $4 and $E swap between palettes)
  Palettes 4-15: Sky gradient (color 0 varies per palette)
```

---

## 2. Startup Sequence (~line 80)

1. `SHR_Init` — enable SHR graphics mode
2. `SetupLoadPalette` — set initial palette
3. `LoadAssets` — load shape files from disk into expansion RAM
4. `ENTER` (Checkerboard.s) — pre-compute 8 checkerboard frames into IMAGE buffer
5. `CompileSprites` — compile all shape data into executable sprite routines
6. `SetupPalettes` — configure all 16 palettes
7. Initialize Harrier state, clear screen, fill sidebar
8. Enter game loop

---

## 3. Game Loop (~line 165)

Each frame, in order:

| Step | Routine | What it does |
|------|---------|-------------|
| 1 | `WaitVBL` | Spin until VBL ($E0C019 bit 7) |
| 2 | `HandleInput` | Poll keyboard, update HarrierRow/HarrierCol/Coordonnee_X |
| 3 | `UpdateHorizon` | Map HarrierRow to Ligne_Damier (130-140) |
| 4 | `Shape_Action` | Advance object depths, spawn new objects |
| 5 | Lateral scroll | Read Table_Vitesse[HarrierCol/2] → update Coordonnee_X |
| 6 | Forward scroll | Decrement Coordonnee_Y (wraps 0→29) |
| 7 | `ClearScreen` | Zero 128 bytes/row × 200 rows via DP trick (aux mem) |
| 8 | `SetupDamierSCB` | Perspective-correct palette banding on ground rows |
| 9 | `SetupSkySCB` | Sky gradient palette assignment |
| 10 | Damier blit | JSL to compiled checkerboard, selected by Coordonnee_X&7 |
| 11 | Mountain blit | JSL to compiled mountain, parallax at half Coordonnee_X |
| 12 | `Print_Shape` | Depth-sorted object rendering (back to front) |
| 13 | Harrier draw | JSL to compiled Man sprite at HarrierRow/HarrierCol |
| 14 | Animate | Cycle Shape_Man frames 0-7 every 8 VBLs |

---

## 4. Compiled Sprite Engine (`Create.Sprite.s`)

FTA's sprite compiler converts bitmap shape data into native 65816 code at startup. Each compiled sprite is a subroutine that directly writes pixels to the SHR screen.

### How it works:

1. **Input**: Shape bitmap data (from .SHP files), dimensions (rows × cols), mask
2. **Output**: Executable 65816 code stored in expansion RAM (ROUT0/ROUT1/ROUT2)
3. **Dispatch**: `TABLE_ROUT` holds 4-byte entries (one JML per shape). Index × 4 = address.

### Calling convention:

- **Y register** = SHR destination address (`TBA[row] + column_byte_offset`)
- Compiled sprite prologue: enables RAMRD+RAMWRT, does `TYA; TCD` (Y becomes DP)
- Pixel writes use `STA dp` ($85 opcode) — writes to aux memory SHR page
- Row advance: `TDC; ADC #$A0; TCD` (next scanline = +160 bytes)
- Epilogue: `LDA #0; TCD`, clears RAMRD/RAMWRT, `RTL`

### Dynamic vs static sprites:

- **Dynamic** (`_Lgn = $FFFF`): dimensions determined at compile time from shape data. Used for objects (trees, bushes, etc.)
- **Static** (`_Lgn` set): fixed dimensions. Used for damier, mountain, clear routine.

### TABLE_ROUT entry numbering:

| Entries | Type | Count | Shape offset formula |
|---------|------|-------|---------------------|
| 0 | Damier (checker blit) | 1 | — |
| 1-19 | Man (Harrier frames) | 19 | `(Shape_Man+1) * 4` |
| 20-23 | Mountain + Clear | 4 | — |
| 24-39 | Tree | 16 | `depth + 24` |
| 40-50 | Explosion | 11 | `depth + 40` |
| 51-61 | Tir (shots) | 11 | `depth + 51` |
| 62-69 | Pierre (rocks) | 8 | `depth + 62` |
| 70-77 | Ombre (shadows) | 8 | `depth + 70` |
| 78-91 | Buisson (bushes) | 14 | `depth + 78` |
| 92-106 | Ship | 15 | `depth + 92` |
| 107-115 | Trident | 9 | `depth + 107` |

---

## 5. Object System

### Data Structure (~line 637)

```
OBJ_SIZE     = 8 bytes per slot
MAX_OBJECTS  = 16 slots
Storage:       ObjArray (initialized to $FFFF = inactive)

Offset  Field           Size  Description
------  --------------  ----  -----------
0       S_Coor_Hori     16b   Horizontal world coordinate (signed)
2       S_Profondeur    16b   Depth: 0 (closest) to 15 (farthest), $FFFF = inactive
4       S_Nature        16b   Object type (see table below)
6       S_Altitude      16b   Vertical offset (0 = ground)
```

### Nature types (FTA's full set):

| Value | Type | Status | TABLE_ROUT entries | Max depth |
|-------|------|--------|-------------------|-----------|
| 0 | Tree (arbre) | Implemented | 24-39 | 15 |
| 1 | Rock (pierre) | Not yet | 62-69 | 7 |
| 2 | Bush (buisson) | Implemented | 78-91 | 13 |
| $80 | Explosion | Not yet | 40-50 | 10 |
| $81 | Shot (tir) | Not yet | 51-61 | 10 |
| $82 | Trident | Not yet | 107-115 | — |
| $83 | Ship | Not yet | 92-106 | 14 |
| $84-$87 | Dragon parts | Not yet | — | — |

### Spawning — `Shape_Action` (~line 663)

Called once per frame. Iterates all 16 object slots.

**Per-slot logic:**
- **Active** (depth >= 0): decrement depth by 1. If depth < 0, deactivate ($FFFF).
- **Inactive** ($FFFF): roll random chance to spawn.

**Spawn parameters you can tweak:**

| What | Line | Current | Effect |
|------|------|---------|--------|
| Spawn probability | ~677 | `cmp #$FC` (~1.5%) | Lower = more objects. Try `$F8` (~3%) or `$F0` (~6%) |
| Spawn depth | ~680 | `lda #15` | Always at horizon. Could randomize 12-15 |
| Nature selection | ~682 | 50/50 tree/bush | Randomize with ALEA; currently `and #$01; asl` |
| H-position range | ~688 | `and #$FF; sbc #$80` | +-128 around camera. Widen: use larger mask/offset |
| H-position center | ~691 | `adc Coordonnee_X` | Relative to camera X. Add constant to bias |

**Spawn horizontal position formula:**
```
world_x = random(0..255) - 128 + Coordonnee_X
```

---

## 6. Projection — `Print_Shape` (~line 706)

Depth-sorted rendering: iterates depths 15 (far) down to 0 (near). For each depth, draws all objects at that depth.

### Nature dispatch (~line 722):

```
Nature 0 (tree):  shape = depth + 24,  all depths 0-15
Nature 2 (bush):  shape = depth + 78,  depths 0-13 only
Other:            skipped
```

### Horizontal Projection (~line 741)

Converts world X to screen column (byte offset in the 128-byte play area).

**Formula:**
```
delta       = object_world_x - Coordonnee_X        (signed)
abs_delta   = |delta|, clamped to 255
projected   = abs_delta * Decalage_Y[depth] / 16
screen_col  = (delta < 0 ? -projected : projected) + $40
```

**Tweakable parameters:**

| What | Line | Current | Effect |
|------|------|---------|--------|
| Screen center | ~755 | `adc #$40` | $40 = byte 64 = pixel 128 (play area center). Decrease to shift objects left |
| Division | ~746-749 | 4x LSR (÷16) | More LSRs = tighter clustering. Fewer = wider spread |
| Left clip | ~758 | `cmp #$FFE0` | Accepts columns -32 to -1 (partial left-edge sprites) |
| Right clip | ~760 | `cmp #$80` | Rejects columns >= $80 (sidebar boundary) |
| Abs clamp | ~736 | `cmp #$FF` | Max pre-multiply distance. Lower = less spread |

### Vertical Projection (~line 765)

```
screen_row = Ligne_Damier + Decalage_Y[depth] - Shape_Hauteur[shape_num]
```

| What | Line | Current | Effect |
|------|------|---------|--------|
| Row clip | ~776 | `cmp #200` | Rejects rows >= 200 |
| Horizon | variable | `Ligne_Damier` | Moves with Harrier altitude (130-140) |

### Perspective table — `Decalage_Y` (~line 1944):
```
Depth:  0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15
Scale: 40  32  26  22  18  15  13  11   9   7   6   5   4   3   2   1
```
- Controls both horizontal spread AND vertical placement
- Depth 15 (horizon): scale=1, objects cluster at center
- Depth 0 (closest): scale=40, objects spread wide

### Sprite height table — `Shape_Hauteur` (~line 1950):
```
Tree (entries 24-39):    $79 $50 $3C $30 $28 $21 $1D $19 $17 $14 $13 $11 $11 $10 $0F $0E
Bush (entries 78-91):    $1D $12 $0E $0B $09 $08 $07 $06 $05 $05 $04 $04 $04 $02
Explosion (40-50):       $24 $1D $17 $13 $12 $0F $0E $0C $0A $09 $08
Tir (51-61):             $0E $0E $0A $08 $07 $06 $05 $04 $04 $04 $03
Pierre (62-69):          $1D $14 $0E $0B $0A $09 $07 $06
Ombre (70-77):           $0C $09 $06 $05 $04 $03 $02 $01
```

---

## 7. Rendering — `Draw_Shape` (~line 819)

Patches a `JSL` instruction to jump to the compiled sprite for a given shape number.

**Input:**
- A = shape number (TABLE_ROUT entry index)
- X = screen row (0-199)
- Y = column byte offset (0-127)

**Process:**
1. Compute TABLE_ROUT address: `TABLE_ROUT + shape_num * 4`
2. Patch the JSL operand at `_dsJSL`
3. Compute SHR address: `Y = TBA[row] + column`
4. Execute `JSL` → compiled sprite runs, writes pixels, returns via `RTL`

---

## 8. Screen Clear — `ClearScreen` (~line 335)

Clears only the 128-byte play area (not the sidebar) using a DP trick:

1. Enable RAMRD+RAMWRT (write to aux memory)
2. Set DP = $2000 (SHR base)
3. 64 × `STZ dp` instructions = 128 bytes zeroed per row
4. `DP += $A0` (160 bytes) for next row, repeat 200 times
5. Restore DP=0, disable RAMRD/RAMWRT

---

## 9. Checkerboard Ground (`Checkerboard.s`)

Pre-computes 8 frames of perspective-correct checkerboard at startup into the IMAGE buffer ($190000). Each frame is $1E00 bytes (128 × 60 rows). Frames differ by horizontal scroll offset.

At runtime, `Coordonnee_X & 7` selects which frame to blit via `Table_Damier`:
```
Table_Damier: da 0, $1E00, $3C00, $5A00, $7800, $9600, $B400, $D200
```

The compiled `Damier_Rout` blits 60 rows from IMAGE[frame_offset] to SHR starting at the horizon row. The checkerboard effect comes from alternating palette 0/1 per scanline band via SCB manipulation in `SetupDamierSCB`.

---

## 10. Mountain Background (~line 242)

14 rows of mountain scenery drawn above the horizon. Uses parallax scrolling at half the ground scroll speed (`Coordonnee_X / 2`). Two mountain frames stored in `Decor_Mountain` ($090000), selected by odd/even bit of the parallax offset.

---

## 11. Harrier (Man) Sprite (~line 274)

Drawn last (on top of everything). 19 compiled frames (TABLE_ROUT entries 1-19):
- Frames 0-7: running animation (cycled every 8 VBLs)
- Frames 8-18: banking/leaning poses (not yet used)

Position: `TBA[HarrierRow] + HarrierCol` → Y register for compiled sprite.

---

## 12. Input — `HandleInput` (~line 565ish)

Keyboard-driven movement:
- Arrow keys move HarrierRow (0-184) and HarrierCol (0-143)
- Left/right also updates `Coordonnee_X` (world scroll position)
- ESC sets QuitFlag

`Table_Vitesse` maps HarrierCol/2 to lateral scroll speed (-3 to +3):
- Center column: speed 0 (no scroll)
- Edge columns: speed ±3 (fast scroll)

---

## 13. Key Variables

| Variable | Location | Description |
|----------|----------|-------------|
| `HarrierRow` | ~line 1905 | Harrier Y position (0-184) |
| `HarrierCol` | ~line 1906 | Harrier X position (0-143, byte offset) |
| `Shape_Man` | ~line 1907 | Current Harrier animation frame (0-7) |
| `Coordonnee_X` | ~line 1928 | World horizontal scroll (16-bit signed) |
| `Coordonnee_Y` | ~line 563 | Ground vertical scroll (0-29, wraps) |
| `Ligne_Damier` | ~line 1927 | Horizon screen row (130-140) |
| `QuitFlag` | ~line 1910 | Non-zero = exit game loop |
| `MyDirectPage` | ~line 1903 | OS-assigned DP address |

---

## 14. Quick Recipes

**Shift objects left on screen**: Change `adc #$40` to `adc #$38` (~line 755)

**Shift objects right on screen**: Change `adc #$40` to `adc #$48` (~line 755)

**More objects**: Change `cmp #$FC` to `cmp #$F0` (~line 677)

**Wider spawn spread**: Increase the `sbc #$80` offset and `and #$FF` mask (~line 688-689)

**Add rocks**: In spawn (~line 682), add nature=1 to random selection. In Print_Shape (~line 722), add `:psRock` handler: `shape = depth + 62`, max depth 7 (only 8 rock sizes).

**Change object mix**: Modify the ALEA-based nature selection at ~line 682. Current: 50% tree, 50% bush.
