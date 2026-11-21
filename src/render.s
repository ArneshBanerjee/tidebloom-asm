// Tidebloom — hand-written AArch64 renderer. No engine, textures, or shaders.
// All artwork is drawn from assembly data using SDL's rectangle primitive.
.section __TEXT,__text,regular,pure_instructions
.p2align 2

.macro COLOR reg, value
    mov \reg, #(\value & 0xffff)
    movk \reg, #((\value >> 16) & 0xffff), lsl #16
.endmacro
.macro PTR reg, symbol
    adrp \reg, \symbol@PAGE
    add \reg, \reg, \symbol@PAGEOFF
.endmacro
.macro RECT x, y, width, height, color
    mov w0, #\x
    mov w1, #\y
    mov w2, #\width
    mov w3, #\height
    COLOR w4, \color
    bl _draw_rect
.endmacro
.macro TEXT x, y, scale, string, color
    mov w0, #\x
    mov w1, #\y
    mov w2, #\scale
    PTR x3, \string
    COLOR w4, \color
    bl _draw_text
.endmacro
.macro CREATURE x, y, scale, species
    mov w0, #\x
    mov w1, #\y
    mov w2, #\scale
    mov w3, #\species
    bl _draw_creature
.endmacro
.macro LOAD reg, symbol
    adrp x16, \symbol@PAGE
    ldr \reg, [x16, \symbol@PAGEOFF]
.endmacro

// x,y,width,height,RGB. Every procedure obeys Apple's ARM64 ABI.
.globl _draw_rect
_draw_rect:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp w0, w1, [sp, #16]
    stp w2, w3, [sp, #24]
    mov w3, w4
    ubfx w1, w4, #16, #8
    ubfx w2, w4, #8, #8
    and w3, w3, #255
    mov w4, #255
    LOAD x0, _renderer
    bl _SDL_SetRenderDrawColor
    LOAD x0, _renderer
    add x1, sp, #16
    bl _SDL_RenderFillRect
    ldp x29, x30, [sp], #48
    ret

// x,y,scale,string,RGB. Font is 5x7 pixels with a one-pixel advance.
.globl _draw_text
_draw_text:
    stp x29, x30, [sp, #-96]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]
    mov w19, w0
    mov w20, w1
    mov w21, w2
    mov x22, x3
    mov w23, w4
    mov w24, w0
Ltext_char:
    ldrb w9, [x22], #1
    cbz w9, Ltext_done
    cmp w9, #10
    b.eq Ltext_newline
    cmp w9, #32
    b.lt Ltext_char
    cmp w9, #127
    b.gt Ltext_char
    sub w9, w9, #32
    mov w10, #7
    mul w9, w9, w10
    PTR x28, _font
    add x28, x28, w9, uxtw
    mov w25, #0
Ltext_row:
    ldrb w27, [x28, w25, uxtw]
    mov w26, #0
Ltext_col:
    mov w10, #16
    lsr w10, w10, w26
    tst w27, w10
    b.eq Ltext_skip
    madd w0, w26, w21, w19
    madd w1, w25, w21, w20
    mov w2, w21
    mov w3, w21
    mov w4, w23
    bl _draw_rect
Ltext_skip:
    add w26, w26, #1
    cmp w26, #5
    b.lt Ltext_col
    add w25, w25, #1
    cmp w25, #7
    b.lt Ltext_row
    mov w9, #6
    madd w19, w21, w9, w19
    b Ltext_char
Ltext_newline:
    mov w9, #11
    madd w20, w21, w9, w20
    mov w19, w24
    b Ltext_char
Ltext_done:
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x25, x26, [sp, #64]
    ldp x27, x28, [sp, #80]
    ldp x29, x30, [sp], #96
    ret

// x,y,scale,sprite,width,height. ASCII pixels index a packed RGB palette.
.globl _draw_sprite
_draw_sprite:
    stp x29, x30, [sp, #-96]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]
    mov w19, w0
    mov w20, w1
    mov w21, w2
    mov x22, x3
    mov w23, w4
    mov w24, w5
    mov w25, #0
    PTR x28, Lpalette
Lsprite_row:
    mov w26, #0
Lsprite_col:
    ldrb w27, [x22], #1
    cmp w27, #46
    b.eq Lsprite_skip
    // Adjacent pixels of one colour become one SDL rectangle. This preserves
    // exact pixel artwork while keeping the animated island comfortably fast.
    mov w10, #1
Lsprite_run:
    add w11, w26, w10
    cmp w11, w23
    b.ge Lsprite_run_ready
    ldrb w11, [x22]
    cmp w11, w27
    b.ne Lsprite_run_ready
    add x22, x22, #1
    add w10, w10, #1
    b Lsprite_run
Lsprite_run_ready:
    ldr w4, [x28, w27, uxtw #2]
    LOAD w12, Lsprite_tint
    cmp w12, #0
    csel w4, w12, w4, ne
    madd w0, w26, w21, w19
    madd w1, w25, w21, w20
    mul w2, w21, w10
    mov w3, w21
    add w26, w26, w10
    bl _draw_rect
    b Lsprite_next
Lsprite_skip:
    add w26, w26, #1
Lsprite_next:
    cmp w26, w23
    b.lt Lsprite_col
    add w25, w25, #1
    cmp w25, w24
    b.lt Lsprite_row
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x25, x26, [sp, #64]
    ldp x27, x28, [sp, #80]
    ldp x29, x30, [sp], #96
    ret

_draw_creature:
    LOAD w9, _frame
    // Evolved forms inherit the animation cadence of their family.
    PTR x12, _species_base
    ldr w12, [x12, w3, uxtw #2]
    cmp w12, #0
    b.eq Lcreature_brief_pose
    cmp w12, #3
    b.eq Lcreature_brief_pose
    cmp w12, #6
    b.eq Lcreature_brief_pose
    mov w10, #20
    cmp w12, #1
    b.eq Lcreature_wingbeat
    cmp w12, #5
    b.ne Lcreature_cycle
Lcreature_wingbeat:
    mov w10, #12
Lcreature_cycle:
    udiv w9, w9, w10
    and w9, w9, #1
    b Lcreature_pose_table
Lcreature_brief_pose:
    mov w10, #120
    udiv w11, w9, w10
    msub w9, w11, w10, w9
    cmp w9, #112
    cset w9, hs
Lcreature_pose_table:
    PTR x10, Lsprites
    PTR x11, _creature_alt_sprites
    cmp w9, #0
    csel x9, x10, x11, eq
    ldr x3, [x9, w3, uxtw #3]
    mov w4, #24
    mov w5, #24
    b _draw_sprite

// x,y,scale,unused,RGB,value. Integer conversion is also assembly.
.globl _draw_number
_draw_number:
    stp x29, x30, [sp, #-64]!
    stp x0, x1, [sp, #16]
    stp x2, x4, [sp, #32]
    add x3, sp, #63
    strb wzr, [x3]
    mov w10, #10
Lnumber_digit:
    udiv w11, w5, w10
    msub w12, w11, w10, w5
    add w12, w12, #48
    strb w12, [x3, #-1]!
    mov w5, w11
    cbnz w5, Lnumber_digit
    ldp x0, x1, [sp, #16]
    ldp x2, x4, [sp, #32]
    bl _draw_text
    ldp x29, x30, [sp], #64
    ret

// x,y,width,currentHP,maxHP,RGB; 8 pixels high.
_draw_hp:
    stp x29, x30, [sp, #-64]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    mov w19, w0
    mov w20, w1
    mov w21, w2
    mov w22, w3
    mov w23, w4
    mov w24, w5
    mov w3, #8
    COLOR w4, 0x152e38
    bl _draw_rect
    cbz w23, Lhp_done
    mul w2, w21, w22
    udiv w2, w2, w23
    cbz w2, Lhp_done
    mov w0, w19
    mov w1, w20
    mov w3, #8
    mov w4, w24
    bl _draw_rect
Lhp_done:
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x29, x30, [sp], #64
    ret

.globl _render_frame
_render_frame:
    stp x29, x30, [sp, #-16]!
    RECT 0, 0, 1120, 768, 0x112b35
    LOAD w9, _screen
    cbz w9, Lframe_title
    TEXT 32, 30, 4, Ltitle, 0xffefd2
    TEXT 280, 43, 2, Lsubtitle, 0x81aba5
    LOAD w9, _map_id
    PTR x10, _map_names
    ldr x3, [x10, w9, uxtw #3]
    mov w0, #834
    mov w1, #32
    mov w2, #2
    COLOR w4, 0xf5c96a
    bl _draw_text
    LOAD w9, _map_id
    PTR x10, _map_subtitles
    ldr x3, [x10, w9, uxtw #3]
    mov w0, #834
    mov w1, #57
    mov w2, #1
    COLOR w4, 0x81aba5
    bl _draw_text
    mov w0, #1000
    mov w1, #74
    mov w2, #1
    bl Ldraw_sound_label
    RECT 32, 86, 1056, 2, 0x2c5058
    LOAD w9, _visual_mode
    cmp w9, #3
    b.eq Lframe_win
    cmp w9, #4
    b.eq Lframe_evolve
    cbnz w9, Lframe_battle
    bl Ldraw_world
    bl Ldraw_sidebar
    RECT 32, 628, 1056, 108, 0x1c3c44
    RECT 32, 628, 4, 108, 0xf5c96a
    mov w0, #52
    mov w1, #644
    mov w2, #2
    LOAD x3, _message
    COLOR w4, 0xffefd2
    bl _draw_text
    TEXT 52, 706, 2, Lworld_controls, 0x81aba5
    b Lframe_done
Lframe_title:
    bl Ldraw_title
    b Lframe_done
Lframe_battle:
    bl Ldraw_battle
    b Lframe_done
Lframe_win:
    bl Ldraw_win
    b Lframe_done
Lframe_evolve:
    bl Ldraw_evolution
Lframe_done:
    bl Ldraw_save_status
    LOAD w9, _show_world_map
    cbz w9, Lframe_effects
    bl Ldraw_world_map
    b Lframe_return
Lframe_effects:
    bl _draw_effects
Lframe_return:
    ldp x29, x30, [sp], #16
    ret

Ldraw_title:
    stp x29, x30, [sp, #-16]!
    RECT 0, 236, 1120, 330, 0x1b3c48
    RECT 0, 396, 1120, 170, 0x234c57
    RECT 0, 474, 1120, 92, 0x2b5a60
    RECT 84, 268, 56, 3, 0x3b6b70
    RECT 916, 334, 120, 3, 0x3b6b70
    RECT 36, 456, 100, 3, 0x51857f
    RECT 930, 490, 130, 3, 0x51857f
    RECT 190, 380, 44, 3, 0x51857f
    RECT 848, 270, 7, 7, 0xf5c96a
    RECT 152, 148, 5, 5, 0xf5c96a
    RECT 942, 108, 5, 5, 0xf5c96a
    RECT 880, 186, 3, 3, 0xb3d7c1
    RECT 212, 214, 3, 3, 0xb3d7c1
    TEXT 362, 54, 2, Ltitle_kicker, 0x8db9aa
    TEXT 290, 112, 10, Ltitle, 0x081d2b
    TEXT 290, 106, 10, Ltitle, 0xffefd2
    TEXT 344, 205, 2, Ltitle_tagline, 0x92b8ae
    RECT 252, 438, 616, 50, 0x102e37
    RECT 228, 420, 664, 44, 0x102e37
    RECT 252, 402, 616, 58, 0x43785e
    RECT 280, 386, 560, 72, 0x52896a
    RECT 316, 376, 488, 64, 0x74a577
    RECT 296, 432, 30, 6, 0x36634f
    RECT 780, 420, 24, 6, 0x36634f
    CREATURE 282, 296, 5, 2
    CREATURE 488, 266, 6, 0
    CREATURE 710, 294, 5, 1
    TEXT 306, 510, 2, Ltitle_desc, 0xffefd2
    RECT 424, 592, 272, 54, 0x0a202b
    RECT 424, 586, 272, 54, 0xf5c96a
    LOAD w9, _session_started
    cbnz w9, Ltitle_resume
    LOAD w9, _save_available
    cbnz w9, Ltitle_continue
    TEXT 488, 606, 3, Lstart, 0x18343c
    b Ltitle_controls
Ltitle_resume:
    TEXT 506, 606, 3, Lresume, 0x18343c
    b Ltitle_controls
Ltitle_continue:
    TEXT 488, 606, 3, Lcontinue_save, 0x18343c
Ltitle_controls:
    TEXT 368, 663, 2, Ljourney_start_hint, 0x92b8ae
    mov w0, #500
    mov w1, #696
    mov w2, #2
    bl Ldraw_sound_label
    TEXT 290, 730, 2, Lasm_note, 0x638d8b
    ldp x29, x30, [sp], #16
    ret

// Tile terrain first, then scenery. Water never gets overdrawn by land.
Ldraw_world:
    stp x29, x30, [sp, #-96]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]
    RECT 28, 108, 744, 504, 0x081e2b
    PTR x28, _map_data
    mov w19, #0
Lterrain_row:
    mov w20, #0
Lterrain_col:
    mov w9, #23
    madd w9, w19, w9, w20
    ldrb w23, [x28, w9, uxtw]
    lsl w21, w20, #5
    add w21, w21, #32
    lsl w22, w19, #5
    add w22, w22, #124
    LOAD w9, _map_id
    PTR x10, Lregion_grass
    ldr w24, [x10, w9, uxtw #2]
    add w9, w19, w20
    tst w9, #1
    b.eq Lterrain_zone_done
    add w24, w24, #0x303
Lterrain_zone_done:
    cmp w23, #1
    b.ne Lterrain_land
    COLOR w24, 0x28545f
Lterrain_land:
    cmp w23, #2
    b.eq Lterrain_ispath
    cmp w23, #13
    b.ne Lterrain_notpath
Lterrain_ispath:
    COLOR w24, 0xc4b589
Lterrain_notpath:
    cmp w23, #3
    b.ne Lterrain_base
    COLOR w24, 0x3c7159
Lterrain_base:
    mov w0, w21
    mov w1, w22
    mov w2, #32
    mov w3, #32
    mov w4, w24
    bl _draw_rect
    cmp w23, #1
    b.eq Lterrain_water
    cmp w23, #2
    b.eq Lterrain_path
    cmp w23, #3
    b.eq Lterrain_reeds
    cmp w23, #0
    b.ne Lterrain_next
    mov w0, w21
    mov w1, w22
    mov w2, w19
    mov w3, w20
    bl Lgrass_details
    // Scattered grass seed-pixels.
    add w9, w19, w20
    tst w9, #3
    b.ne Lterrain_next
    add w0, w21, #6
    add w1, w22, #14
    mov w2, #3
    mov w3, #3
    COLOR w4, 0x78a27a
    bl _draw_rect
    b Lterrain_next
Lterrain_water:
    mov w0, w21
    mov w1, w22
    mov w2, w19
    mov w3, w20
    bl Lshore_details
    add w9, w19, w20
    tst w9, #1
    b.eq Lterrain_next
    LOAD w9, _frame
    lsr w9, w9, #5
    and w9, w9, #7
    add w0, w21, w9
    add w0, w0, #5
    add w1, w22, #16
    mov w2, #13
    mov w3, #2
    COLOR w4, 0x39717a
    bl _draw_rect
    b Lterrain_next
Lterrain_path:
    add w0, w21, #19
    add w1, w22, #8
    mov w2, #5
    mov w3, #3
    COLOR w4, 0xa89c76
    bl _draw_rect
    b Lterrain_next
Lterrain_reeds:
    mov w25, #0
Lreed_loop:
    mov w9, #9
    madd w0, w25, w9, w21
    add w0, w0, #5
    add w1, w22, #11
    mov w2, #3
    mov w3, #13
    COLOR w4, 0x87b77a
    bl _draw_rect
    mov w9, #9
    madd w0, w25, w9, w21
    LOAD w9, _frame
    lsr w9, w9, #3
    and w9, w9, #1
    add w0, w0, w9
    add w0, w0, #3
    add w1, w22, #8
    mov w2, #3
    mov w3, #8
    COLOR w4, 0x679961
    bl _draw_rect
    add w25, w25, #1
    cmp w25, #3
    b.lt Lreed_loop
Lterrain_next:
    add w20, w20, #1
    cmp w20, #23
    b.lt Lterrain_col
    add w19, w19, #1
    cmp w19, #15
    b.lt Lterrain_row
    mov w19, #0
Lscenery_row:
    mov w20, #0
Lscenery_col:
    mov w9, #23
    madd w9, w19, w9, w20
    ldrb w23, [x28, w9, uxtw]
    lsl w21, w20, #5
    add w21, w21, #32
    lsl w22, w19, #5
    add w22, w22, #124
    cmp w23, #4
    b.eq Lscenery_tree
    cmp w23, #5
    b.eq Lscenery_camp
    cmp w23, #9
    b.eq Lscenery_guardian
    cmp w23, #10
    b.eq Lscenery_researcher
    cmp w23, #11
    b.eq Lscenery_ranger
    cmp w23, #12
    b.eq Lscenery_cache
    cmp w23, #13
    b.eq Lscenery_exit
    cmp w23, #14
    b.eq Lscenery_trainer
    cmp w23, #15
    b.eq Lscenery_shop
    cmp w23, #16
    b.eq Lscenery_home
    cmp w23, #17
    b.eq Lscenery_roof
    cmp w23, #18
    b.eq Lscenery_wall
    cmp w23, #19
    b.eq Lscenery_bridge
    cmp w23, #20
    b.eq Lscenery_cliff
    cmp w23, #6
    b.lt Lscenery_next
    cmp w23, #8
    b.le Lscenery_beacon
    b Lscenery_next
Lscenery_tree:
    sub w0, w21, #8
    sub w1, w22, #30
    mov w2, #2
    LOAD w9, _map_id
    PTR x10, Lregional_trees
    ldr x3, [x10, w9, uxtw #3]
    mov w4, #24
    mov w5, #32
    bl _draw_sprite
    b Lscenery_next
Lscenery_camp:
    LOAD w9, _map_id
    cbz w9, Lscenery_clinic
    cmp w9, #2
    b.eq Lscenery_clinic
    mov w0, w21
    mov w1, w22
    bl Ldraw_camp
    b Lscenery_next
Lscenery_clinic:
    mov w0, w21
    mov w1, w22
    mov w2, #0
    bl Ldraw_door
    b Lscenery_next
Lscenery_shop:
    mov w0, w21
    mov w1, w22
    mov w2, #1
    bl Ldraw_door
    b Lscenery_next
Lscenery_home:
    LOAD w9, _map_id
    cbz w9, Lscenery_home_door
    cmp w9, #2
    b.ne Lscenery_researcher
Lscenery_home_door:
    mov w0, w21
    mov w1, w22
    mov w2, #2
    bl Ldraw_door
    b Lscenery_next
Lscenery_roof:
    mov w0, w21
    mov w1, w22
    mov w2, w20
    mov w3, w19
    bl Ldraw_roof
    b Lscenery_next
Lscenery_wall:
    mov w0, w21
    mov w1, w22
    bl Ldraw_wall
    b Lscenery_next
Lscenery_bridge:
    mov w0, w21
    mov w1, w22
    bl Ldraw_bridge
    b Lscenery_next
Lscenery_cliff:
    mov w0, w21
    mov w1, w22
    bl Ldraw_cliff
    b Lscenery_next
Lscenery_exit:
    add w0, w21, #8
    add w1, w22, #5
    mov w2, #1
    PTR x3, _sprite_signpost
    mov w4, #16
    mov w5, #20
    bl _draw_sprite
    b Lscenery_next
Lscenery_trainer:
    LOAD w9, _map_id
    mov w2, #0
    cmp w9, #3
    b.ne Ltrainer_not_cinder
    mov w2, #2
Ltrainer_not_cinder:
    cmp w9, #4
    b.ne Ltrainer_route_index
    mov w2, #4
Ltrainer_route_index:
    cmp w20, #10
    cinc w2, w2, gt
    mov w0, w21
    mov w1, w22
    bl Ldraw_trainer
    b Lscenery_next
Lscenery_researcher:
    PTR x3, _sprite_npc_researcher
    b Lscenery_npc
Lscenery_ranger:
    PTR x3, _sprite_npc
Lscenery_npc:
    mov w0, w21
    sub w1, w22, #8
    mov w2, #2
    mov w4, #16
    mov w5, #20
    bl _draw_sprite
    add w0, w21, #13
    sub w1, w22, #19
    mov w2, #1
    PTR x3, Lnpc_marker
    COLOR w4, 0xffefd2
    bl _draw_text
    b Lscenery_next
Lscenery_cache:
    LOAD w9, _quest_flags
    tst w9, #2
    PTR x3, _sprite_chest
    PTR x10, _sprite_chest_open
    csel x3, x3, x10, eq
    mov w0, w21
    mov w1, w22
    mov w2, #2
    mov w4, #16
    mov w5, #16
    bl _draw_sprite
    b Lscenery_next
Lscenery_guardian:
    sub w0, w21, #8
    sub w1, w22, #15
    mov w2, #2
    mov w3, #6
    bl _draw_creature
    b Lscenery_next
Lscenery_beacon:
    mov w0, w21
    sub w1, w22, #18
    mov w2, #2
    PTR x3, _sprite_beacon
    mov w4, #16
    mov w5, #24
    bl _draw_sprite
    sub w9, w23, #6
    LOAD w10, _beacons
    lsr w10, w10, w9
    and w10, w10, #1
    cbz w10, Lscenery_next
    add w0, w21, #10
    sub w1, w22, #15
    mov w2, #12
    mov w3, #10
    COLOR w4, 0xf5c96a
    bl _draw_rect
Lscenery_next:
    add w20, w20, #1
    cmp w20, #23
    b.lt Lscenery_col
    add w19, w19, #1
    cmp w19, #15
    b.lt Lscenery_row
    LOAD w19, _walk_x
    LOAD w20, _walk_y
    add w0, w19, #2
    add w1, w20, #34
    mov w2, #28
    mov w3, #6
    COLOR w4, 0x315b4c
    bl _draw_rect
    LOAD w9, _facing
    PTR x10, Lfacing_to_walk
    ldr w9, [x10, w9, uxtw #2]
    mov w10, #3
    mul w9, w9, w10
    LOAD w10, _walk_remaining
    cbz w10, Lworld_idle_pose
    LOAD w10, _frame
    lsr w10, w10, #2
    and w10, w10, #1
    add w10, w10, #1
    add w9, w9, w10
Lworld_idle_pose:
    PTR x10, _player_walk_sprites
    ldr x3, [x10, w9, uxtw #3]
    mov w0, w19
    mov w1, w20
    mov w2, #2
    mov w4, #16
    mov w5, #20
    bl _draw_sprite
    // Small location tab sits just outside the map.
    RECT 40, 112, 202, 24, 0x173a43
    LOAD w9, _map_id
    PTR x10, _map_names
    ldr x3, [x10, w9, uxtw #3]
    mov w0, #49
    mov w1, #119
    mov w2, #1
    COLOR w4, 0xffefd2
    bl _draw_text
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x25, x26, [sp, #64]
    ldp x27, x28, [sp, #80]
    ldp x29, x30, [sp], #96
    ret

Ldraw_sidebar:
    stp x29, x30, [sp, #-64]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    RECT 792, 112, 296, 496, 0x19373f
    TEXT 812, 132, 2, Lparty, 0xffefd2
    mov w19, #0
Lparty_loop:
    mov w9, #90
    mov w10, #166
    madd w20, w19, w9, w10
    mov w0, #808
    mov w1, w20
    mov w2, #264
    mov w3, #78
    COLOR w4, 0x24464c
    bl _draw_rect
    LOAD w9, _active_slot
    cmp w9, w19
    b.ne Lparty_inactive
    mov w0, #808
    mov w1, w20
    mov w2, #3
    mov w3, #78
    COLOR w4, 0xf5c96a
    bl _draw_rect
Lparty_inactive:
    PTR x9, _team_species
    ldr w21, [x9, w19, uxtw #2]
    cmp w21, #0
    b.lt Lparty_empty
    mov w0, #818
    add w1, w20, #10
    mov w2, #2
    mov w3, w21
    bl _draw_creature
    mov w0, #880
    add w1, w20, #10
    mov w2, #2
    PTR x9, _species_names
    ldr x3, [x9, w21, uxtw #3]
    COLOR w4, 0xffefd2
    bl _draw_text
    mov w0, #880
    add w1, w20, #34
    mov w2, #1
    PTR x9, Lelements
    ldr x3, [x9, w21, uxtw #3]
    COLOR w4, 0x8fb5a9
    bl _draw_text
    PTR x9, _team_hp
    ldr w22, [x9, w19, uxtw #2]
    PTR x9, _team_maxhp
    ldr w23, [x9, w19, uxtw #2]
    mov w0, #880
    add w1, w20, #58
    mov w2, #170
    mov w3, w22
    mov w4, w23
    COLOR w5, 0x94c78a
    bl _draw_hp
    mov w0, #1012
    add w1, w20, #34
    mov w2, #8
    PTR x9, _team_energy
    ldr w3, [x9, w19, uxtw #2]
    bl Ldraw_energy
    b Lparty_next
Lparty_empty:
    mov w0, #846
    add w1, w20, #19
    mov w2, #2
    PTR x3, Lempty_slot
    COLOR w4, 0x72968e
    bl _draw_text
    mov w0, #846
    add w1, w20, #46
    mov w2, #1
    PTR x3, Lempty_hint
    COLOR w4, 0x72968e
    bl _draw_text
Lparty_next:
    add w19, w19, #1
    cmp w19, #3
    b.lt Lparty_loop
    TEXT 812, 443, 1, Lnext_step, 0xf5c96a
    mov w0, #812
    mov w1, #463
    mov w2, #2
    LOAD x3, _world_objective
    COLOR w4, 0xffefd2
    bl _draw_text
    TEXT 812, 526, 2, Lcoins, 0xf5c96a
    LOAD w5, _coins
    mov w0, #1000
    mov w1, #526
    mov w2, #2
    COLOR w4, 0xffefd2
    bl _draw_number
    TEXT 812, 554, 2, Ltrainers, 0x81aba5
    LOAD w9, _trainer_flags
    mov w5, #0
    mov w10, #6
Lsidebar_trainers_count:
    and w11, w9, #1
    add w5, w5, w11
    lsr w9, w9, #1
    subs w10, w10, #1
    b.ne Lsidebar_trainers_count
    mov w0, #1016
    mov w1, #554
    mov w2, #2
    COLOR w4, 0xffefd2
    bl _draw_number
    TEXT 1032, 554, 2, Lof6, 0x81aba5
    TEXT 812, 582, 2, Lresonators, 0x81aba5
    LOAD w9, _beacons
    and w10, w9, #1
    ubfx w11, w9, #1, #1
    add w10, w10, w11
    ubfx w11, w9, #2, #1
    add w5, w10, w11
    mov w0, #1016
    mov w1, #582
    mov w2, #2
    COLOR w4, 0xf5c96a
    bl _draw_number
    TEXT 1032, 582, 2, Lof3, 0x81aba5
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x29, x30, [sp], #64
    ret

// Input labels inherit a dim palette during the presentation timeline.
.macro BTEXT x, y, scale, string, color
    mov w0, #\x
    mov w1, #\y
    mov w2, #\scale
    PTR x3, \string
    COLOR w4, \color
    COLOR w10, 0x607f7d
    cmp w22, #0
    csel w4, w4, w10, eq
    bl _draw_text
.endmacro

Ldraw_battle:
    stp x29, x30, [sp, #-80]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    RECT 32, 112, 1056, 374, 0x447365
    RECT 32, 112, 1056, 166, 0x89aaa0
    RECT 32, 238, 1056, 62, 0x6c9580
    RECT 32, 278, 1056, 60, 0x568570
    RECT 54, 178, 76, 100, 0x648d7a
    RECT 72, 158, 40, 122, 0x648d7a
    RECT 984, 168, 70, 112, 0x648d7a
    RECT 1000, 144, 38, 136, 0x648d7a
    bl Lbattle_details
    // Stepped pixel islands anchor both creatures.
    RECT 172, 420, 288, 24, 0x2b554d
    RECT 148, 398, 336, 28, 0x346455
    RECT 172, 384, 288, 30, 0x77a279
    RECT 188, 384, 32, 3, 0x92b384
    RECT 388, 386, 46, 3, 0x92b384
    RECT 698, 320, 264, 22, 0x3a6657
    RECT 674, 302, 312, 28, 0x5b8a69
    RECT 698, 288, 264, 30, 0x90b384
    RECT 720, 290, 34, 3, 0xb0ca96
    RECT 918, 292, 28, 3, 0xb0ca96
    LOAD w19, _visual_active_slot
    LOAD w20, _visual_player_species
    mov w0, #0
    bl _battle_pose
    cbz w2, Lbattle_hide_hero
    add w0, w0, #214
    add w1, w1, #242
    mov w2, #7
    mov w3, w20
    bl _draw_creature
Lbattle_hide_hero:
    LOAD w21, _enemy_species
    mov w0, #1
    bl _battle_pose
    cbz w2, Lbattle_hide_enemy
    add w0, w0, #754
    add w1, w1, #170
    mov w2, #6
    mov w3, w21
    bl _draw_creature
Lbattle_hide_enemy:
    // Opponent identity and true animated health.
    RECT 60, 136, 350, 88, 0x19373f
    RECT 60, 136, 4, 88, 0xf5c96a
    mov w0, #80
    mov w1, #154
    mov w2, #3
    PTR x9, _species_names
    ldr x3, [x9, w21, uxtw #3]
    COLOR w4, 0xffefd2
    bl _draw_text
    mov w0, #298
    mov w1, #160
    mov w2, #2
    PTR x9, Lelements
    ldr x3, [x9, w21, uxtw #3]
    COLOR w4, 0xf5c96a
    bl _draw_text
    mov w0, #80
    mov w1, #190
    mov w2, #310
    LOAD w3, _visual_enemy_hp
    LOAD w4, _enemy_maxhp
    COLOR w5, 0xecab7b
    bl _draw_hp
    mov w0, #80
    mov w1, #208
    mov w2, #1
    LOAD w5, _visual_enemy_hp
    COLOR w4, 0xecab7b
    bl _draw_number
    TEXT 114, 208, 1, Lslash, 0x81aba5
    mov w0, #128
    mov w1, #208
    mov w2, #1
    LOAD w5, _enemy_maxhp
    COLOR w4, 0x81aba5
    bl _draw_number
    TEXT 232, 205, 2, Lbond_chance, 0x81aba5
    mov w0, #296
    mov w1, #205
    mov w2, #2
    LOAD w5, _capture_chance
    COLOR w4, 0xf5c96a
    bl _draw_number
    TEXT 326, 205, 2, Lpercent, 0xf5c96a
    LOAD w9, _enemy_burn
    cbz w9, Lbattle_no_burn
    TEXT 60, 236, 2, Lburn_status, 0xf8b184
Lbattle_no_burn:
    LOAD w9, _enemy_hex
    cbz w9, Lbattle_no_hex
    TEXT 124, 236, 2, Lhex_status, 0xbca1d2
Lbattle_no_hex:
    // Telegraph the opponent's next plan; the player can choose a real counter.
    RECT 440, 148, 276, 66, 0x315b56
    LOAD w23, _enemy_intent
    COLOR w24, 0xc8ddba
    PTR x3, Lnext_quick
    cmp w23, #1
    b.ne Lbattle_intent_mend
    PTR x3, Lnext_charge
    COLOR w24, 0xffc579
    b Lbattle_intent_label
Lbattle_intent_mend:
    cmp w23, #2
    b.ne Lbattle_intent_label
    PTR x3, Lnext_mend
    COLOR w24, 0xa8dfcb
Lbattle_intent_label:
    mov w0, #456
    mov w1, #159
    mov w2, #1
    mov w4, w24
    bl _draw_text
    mov w9, #3
    madd w9, w21, w9, w23
    PTR x10, _enemy_intent_names
    ldr x3, [x10, w9, uxtw #3]
    mov w0, #456
    mov w1, #180
    mov w2, #2
    mov w4, w24
    bl _draw_text
    // Companion identity, health, energy, and defensive status.
    RECT 660, 376, 400, 96, 0x19373f
    RECT 660, 376, 4, 96, 0x94c78a
    mov w0, #680
    mov w1, #393
    mov w2, #3
    PTR x9, _species_names
    ldr x3, [x9, w20, uxtw #3]
    COLOR w4, 0xffefd2
    bl _draw_text
    TEXT 914, 398, 2, Llvl, 0x81aba5
    PTR x9, _team_level
    ldr w5, [x9, w19, uxtw #2]
    mov w0, #954
    mov w1, #398
    mov w2, #2
    COLOR w4, 0xffefd2
    bl _draw_number
    mov w0, #680
    mov w1, #430
    mov w2, #256
    LOAD w3, _visual_player_hp
    PTR x9, _team_maxhp
    ldr w4, [x9, w19, uxtw #2]
    COLOR w5, 0x94c78a
    bl _draw_hp
    LOAD w5, _visual_player_hp
    mov w0, #952
    mov w1, #426
    mov w2, #2
    COLOR w4, 0x94c78a
    bl _draw_number
    TEXT 992, 426, 2, Lslash, 0x81aba5
    mov w0, #1008
    mov w1, #426
    mov w2, #2
    PTR x9, _team_maxhp
    ldr w5, [x9, w19, uxtw #2]
    COLOR w4, 0x81aba5
    bl _draw_number
    TEXT 680, 453, 1, Lenergy, 0x81aba5
    mov w0, #730
    mov w1, #453
    mov w2, #20
    PTR x9, _team_energy
    ldr w3, [x9, w19, uxtw #2]
    mov w25, w3
    bl Ldraw_energy
    PTR x9, _team_armor
    ldr w9, [x9, w19, uxtw #2]
    cbz w9, Lbattle_no_armor
    TEXT 848, 453, 1, Larmor_status, 0xd4b77d
Lbattle_no_armor:
    // Journal reports the rules; the timeline and effects show their consequences.
    RECT 32, 486, 1056, 128, 0x1c3c44
    LOAD w22, _anim_busy
    cbz w22, Lbattle_ready_header
    TEXT 52, 499, 2, Lresolving, 0xf5c96a
    b Lbattle_journal_stats
Lbattle_ready_header:
    TEXT 52, 502, 1, Lyour_turn, 0xf5c96a
Lbattle_journal_stats:
    TEXT 640, 502, 1, Ldamage_dealt, 0x81aba5
    mov w0, #718
    mov w1, #502
    mov w2, #1
    LOAD w5, _last_player_damage
    COLOR w4, 0xc7e2a8
    bl _draw_number
    TEXT 778, 502, 1, Ldamage_taken, 0x81aba5
    mov w0, #868
    mov w1, #502
    mov w2, #1
    LOAD w5, _last_enemy_damage
    COLOR w4, 0xecab7b
    bl _draw_number
    TEXT 960, 502, 1, Lturn_label, 0x81aba5
    mov w0, #1002
    mov w1, #502
    mov w2, #1
    LOAD w5, _battle_turn
    COLOR w4, 0xffefd2
    bl _draw_number
    mov w0, #52
    mov w1, #527
    mov w2, #2
    LOAD x3, _message
    COLOR w4, 0xffefd2
    bl _draw_text
    TEXT 52, 588, 2, Lguard_hint, 0x81aba5
    LOAD w9, _visual_mode
    cmp w9, #2
    b.eq Lbattle_result
    cbnz w22, Lbattle_dim_buttons
    RECT 32, 634, 344, 46, 0x2a5055
    RECT 388, 634, 344, 46, 0x355b52
    RECT 744, 634, 344, 46, 0x655a41
    RECT 32, 692, 344, 46, 0x1c3c44
    RECT 388, 692, 344, 46, 0x1c3c44
    RECT 744, 692, 344, 46, 0x1c3c44
    b Lbattle_action_labels
Lbattle_dim_buttons:
    RECT 32, 634, 344, 46, 0x18343b
    RECT 388, 634, 344, 46, 0x18343b
    RECT 744, 634, 344, 46, 0x18343b
    RECT 32, 692, 344, 46, 0x18343b
    RECT 388, 692, 344, 46, 0x18343b
    RECT 744, 692, 344, 46, 0x18343b
Lbattle_action_labels:
    BTEXT 52, 650, 2, Lattack, 0xffefd2
    BTEXT 302, 650, 2, Lgain_energy, 0x81aba5
    BTEXT 408, 650, 2, Lsignature_key, 0xc7e2a8
    mov w0, #432
    mov w1, #650
    mov w2, #2
    PTR x9, _signature_names
    ldr x3, [x9, w20, uxtw #3]
    COLOR w4, 0xc7e2a8
    COLOR w10, 0x607f7d
    cmp w25, #2
    csel w4, w4, w10, ge
    cmp w22, #0
    csel w4, w4, w10, eq
    bl _draw_text
    BTEXT 676, 650, 2, Lcharge_cost, 0xf5c96a
    BTEXT 764, 650, 2, Lbefriend, 0xf5c96a
    BTEXT 1004, 650, 2, Ltimes, 0x81aba5
    mov w0, #1028
    mov w1, #650
    mov w2, #2
    LOAD w5, _orbs
    COLOR w4, 0x81aba5
    bl _draw_number
    BTEXT 52, 708, 2, Ltonic, 0xa5c4b6
    BTEXT 292, 708, 2, Ltimes, 0x81aba5
    mov w0, #316
    mov w1, #708
    mov w2, #2
    LOAD w5, _tonics
    COLOR w4, 0x81aba5
    bl _draw_number
    BTEXT 408, 708, 2, Lswitch, 0xa5c4b6
    BTEXT 764, 708, 2, Lflee, 0xa5c4b6
    b Lbattle_done
Lbattle_result:
    RECT 32, 634, 1056, 104, 0x2a5055
    TEXT 332, 671, 3, Lcontinue, 0xf5c96a
Lbattle_done:
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x25, x26, [sp, #64]
    ldp x29, x30, [sp], #80
    ret

Ldraw_win:
    stp x29, x30, [sp, #-16]!
    RECT 32, 112, 1056, 610, 0x1c3c44
    TEXT 308, 150, 2, Lwin_kicker, 0xf5c96a
    CREATURE 464, 222, 8, 6
    TEXT 308, 468, 6, Lwin_title, 0xffefd2
    TEXT 266, 542, 2, Lwin_desc, 0x9dc7b4
    TEXT 356, 638, 2, Lwin_restart, 0xf5c96a
    ldp x29, x30, [sp], #16
    ret

Ldraw_sound_label:
    LOAD w9, _audio_muted
    PTR x3, Lsound_on
    PTR x10, Lsound_off
    cmp w9, #0
    csel x3, x3, x10, eq
    COLOR w4, 0x81aba5
    b _draw_text

// Three discrete energy lights; x,y,pip width,current energy.
Ldraw_energy:
    stp x29, x30, [sp, #-64]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    mov w19, w0
    mov w20, w1
    mov w21, w2
    mov w22, w3
    mov w23, #0
Lenergy_loop:
    add w9, w21, #4
    madd w0, w23, w9, w19
    mov w1, w20
    mov w2, w21
    mov w3, #6
    COLOR w4, 0x132d35
    COLOR w10, 0xf5c96a
    cmp w23, w22
    csel w4, w10, w4, lt
    bl _draw_rect
    add w23, w23, #1
    cmp w23, #3
    b.lt Lenergy_loop
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x29, x30, [sp], #64
    ret

// Deterministic flower beds, stones, and mushrooms grow off the island paths.
Lgrass_details:
    stp x29, x30, [sp, #-48]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov w19, w0
    mov w20, w1
    mov w9, #17
    mul w21, w2, w9
    mov w9, #11
    madd w21, w3, w9, w21
    mov w9, #23
    udiv w10, w21, w9
    msub w21, w10, w9, w21
    cmp w21, #3
    b.gt Lgrass_done
    PTR x3, _sprite_flowers
    cmp w21, #2
    b.ne Lgrass_notrock
    PTR x3, _sprite_rock
Lgrass_notrock:
    cmp w21, #3
    b.ne Lgrass_sprite
    PTR x3, _sprite_mushrooms
Lgrass_sprite:
    add w0, w19, #8
    add w1, w20, #9
    mov w2, #1
    mov w4, #16
    mov w5, #16
    bl _draw_sprite
Lgrass_done:
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x29, x30, [sp], #48
    ret

// Shore edges are determined from real neighbouring tiles, never a painted overlay.
Lshore_details:
    stp x29, x30, [sp, #-64]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    mov w19, w0
    mov w20, w1
    mov w21, w2
    mov w22, w3
    mov w9, #23
    madd w23, w21, w9, w22
    PTR x24, _map_data
    tst w23, #3
    b.ne Lshore_north
    LOAD w9, _frame
    lsr w9, w9, #3
    add w9, w9, w23
    and w9, w9, #7
    cmp w9, #3
    b.gt Lshore_north
    add w0, w19, #12
    add w1, w20, #8
    mov w2, #8
    mov w3, #2
    COLOR w4, 0x75a6a1
    bl _draw_rect
    add w0, w19, #15
    add w1, w20, #5
    mov w2, #2
    mov w3, #8
    COLOR w4, 0x75a6a1
    bl _draw_rect
Lshore_north:
    cbz w21, Lshore_south
    sub w9, w23, #23
    ldrb w9, [x24, w9, uxtw]
    cmp w9, #1
    b.eq Lshore_south
    mov w0, w19
    mov w1, w20
    mov w2, #32
    mov w3, #3
    COLOR w4, 0x78a58d
    bl _draw_rect
Lshore_south:
    cmp w21, #14
    b.ge Lshore_west
    add w9, w23, #23
    ldrb w9, [x24, w9, uxtw]
    cmp w9, #1
    b.eq Lshore_west
    mov w0, w19
    add w1, w20, #29
    mov w2, #32
    mov w3, #3
    COLOR w4, 0x78a58d
    bl _draw_rect
Lshore_west:
    cbz w22, Lshore_east
    sub w9, w23, #1
    ldrb w9, [x24, w9, uxtw]
    cmp w9, #1
    b.eq Lshore_east
    mov w0, w19
    mov w1, w20
    mov w2, #3
    mov w3, #32
    COLOR w4, 0x78a58d
    bl _draw_rect
Lshore_east:
    cmp w22, #22
    b.ge Lshore_done
    add w9, w23, #1
    ldrb w9, [x24, w9, uxtw]
    cmp w9, #1
    b.eq Lshore_done
    add w0, w19, #29
    mov w1, w20
    mov w2, #3
    mov w3, #32
    COLOR w4, 0x78a58d
    bl _draw_rect
Lshore_done:
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x29, x30, [sp], #64
    ret

// Canvas tent, pennant and a breathing campfire mark the safe resting place.
Ldraw_camp:
    stp x29, x30, [sp, #-48]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov w19, w0
    mov w20, w1
    sub w0, w19, #10
    add w1, w20, #27
    mov w2, #54
    mov w3, #5
    COLOR w4, 0x385a4a
    bl _draw_rect
    sub w0, w19, #6
    sub w1, w20, #7
    mov w2, #44
    mov w3, #36
    COLOR w4, 0xd8ad70
    bl _draw_rect
    sub w0, w19, #11
    sub w1, w20, #11
    mov w2, #54
    mov w3, #11
    COLOR w4, 0xf3cb80
    bl _draw_rect
    sub w0, w19, #4
    sub w1, w20, #18
    mov w2, #40
    mov w3, #11
    COLOR w4, 0xf3cb80
    bl _draw_rect
    add w0, w19, #5
    sub w1, w20, #25
    mov w2, #22
    mov w3, #11
    COLOR w4, 0xf3cb80
    bl _draw_rect
    add w0, w19, #12
    sub w1, w20, #4
    mov w2, #12
    mov w3, #33
    COLOR w4, 0x253b3a
    bl _draw_rect
    add w0, w19, #2
    add w1, w20, #1
    mov w2, #3
    mov w3, #27
    COLOR w4, 0xbc8e5e
    bl _draw_rect
    sub w0, w19, #10
    sub w1, w20, #43
    mov w2, #3
    mov w3, #38
    COLOR w4, 0x243d3d
    bl _draw_rect
    sub w0, w19, #7
    sub w1, w20, #43
    LOAD w9, _frame
    lsr w9, w9, #4
    and w9, w9, #1
    add w2, w9, #14
    mov w3, #9
    COLOR w4, 0xdc7a65
    bl _draw_rect
    // The fire sits to the west of camp, off the walkable path.
    sub w0, w19, #26
    add w1, w20, #20
    mov w2, #12
    mov w3, #5
    COLOR w4, 0x304b44
    bl _draw_rect
    sub w0, w19, #24
    add w1, w20, #11
    LOAD w9, _frame
    lsr w9, w9, #3
    and w9, w9, #3
    sub w1, w1, w9
    mov w2, #8
    add w3, w9, #12
    COLOR w4, 0xee806d
    bl _draw_rect
    sub w0, w19, #22
    add w1, w20, #15
    mov w2, #4
    mov w3, #7
    COLOR w4, 0xffd477
    bl _draw_rect
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x29, x30, [sp], #48
    ret

// Far scenery and reeds enrich the arena while leaving combatants unobstructed.
Lbattle_details:
    stp x29, x30, [sp, #-48]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    RECT 32, 298, 88, 25, 0x397785
    RECT 32, 316, 144, 14, 0x397785
    RECT 32, 328, 96, 8, 0x397785
    RECT 52, 307, 35, 2, 0x79aea5
    RECT 90, 321, 42, 2, 0x79aea5
    RECT 994, 266, 94, 42, 0x397785
    RECT 1014, 257, 74, 12, 0x397785
    RECT 1010, 282, 28, 2, 0x79aea5
    RECT 1050, 294, 22, 2, 0x79aea5
    // Distant stepped crowns with trunks behind the battle platforms.
    RECT 480, 274, 16, 40, 0x476f60
    RECT 454, 244, 68, 42, 0x5e8b72
    RECT 466, 224, 44, 24, 0x6c997b
    RECT 476, 212, 24, 20, 0x6c997b
    RECT 932, 228, 12, 54, 0x476f60
    RECT 910, 210, 56, 35, 0x5e8b72
    RECT 920, 192, 36, 28, 0x6c997b
    // Small flower beds at the edge of the clearing.
    mov w0, #70
    mov w1, #374
    mov w2, #2
    PTR x3, _sprite_flowers
    mov w4, #16
    mov w5, #16
    bl _draw_sprite
    mov w0, #988
    mov w1, #324
    mov w2, #2
    PTR x3, _sprite_flowers
    mov w4, #16
    mov w5, #16
    bl _draw_sprite
    mov w0, #560
    mov w1, #404
    mov w2, #2
    PTR x3, _sprite_mushrooms
    mov w4, #16
    mov w5, #16
    bl _draw_sprite
    // Foreground reeds use a staggered frame phase to sway.
    mov w19, #0
Lforeground_reeds:
    mov w9, #28
    mov w10, #44
    madd w21, w19, w9, w10
    cmp w19, #4
    b.lt Lforeground_left
    add w21, w21, #844
Lforeground_left:
    LOAD w9, _frame
    add w9, w9, w19, lsl #3
    lsr w9, w9, #4
    and w9, w9, #1
    add w0, w21, w9
    mov w1, #462
    mov w2, #3
    mov w3, #24
    COLOR w4, 0x274f48
    bl _draw_rect
    sub w0, w21, #4
    mov w1, #466
    mov w2, #3
    mov w3, #14
    COLOR w4, 0x315c4d
    bl _draw_rect
    add w19, w19, #1
    cmp w19, #7
    b.lt Lforeground_reeds
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x29, x30, [sp], #48
    ret

// Relative pixel rectangle inside a scene object (x19,y20 is its origin).
.macro RR x, y, width, height, color
    .if \x < 0
    sub w0, w19, #(-\x)
    .else
    add w0, w19, #\x
    .endif
    .if \y < 0
    sub w1, w20, #(-\y)
    .else
    add w1, w20, #\y
    .endif
    mov w2, #\width
    mov w3, #\height
    COLOR w4, \color
    bl _draw_rect
.endmacro
.macro RRV x, y, width, height, colorreg
    add w0, w19, #\x
    add w1, w20, #\y
    mov w2, #\width
    mov w3, #\height
    mov w4, \colorreg
    bl _draw_rect
.endmacro

Lcenter_text:
    mov x9, x3
    mov w10, #0
Lcenter_count:
    ldrb w11, [x9], #1
    cbz w11, Lcenter_ready
    add w10, w10, #1
    b Lcenter_count
Lcenter_ready:
    mov w11, #6
    mul w10, w10, w11
    mul w10, w10, w2
    lsr w10, w10, #1
    sub w0, w0, w10
    b _draw_text

Ldraw_save_status:
    LOAD w9, _save_status
    cbz w9, Lsave_status_done
    PTR x3, Lsave_ok
    cmp w9, #1
    b.eq Lsave_status_text
    PTR x3, Lload_ok
    cmp w9, #2
    b.eq Lsave_status_text
    PTR x3, Lsave_error
    cmp w9, #3
    b.eq Lsave_status_text
    PTR x3, Lno_save
Lsave_status_text:
    mov w0, #32
    mov w1, #748
    mov w2, #2
    COLOR w4, 0xf5c96a
    COLOR w10, 0xee9982
    cmp w9, #3
    csel w4, w10, w4, ge
    b _draw_text
Lsave_status_done:
    ret

// Continuous roofs make a genuine3×2 building out of collidable map cells.
Ldraw_roof:
    stp x29, x30, [sp, #-64]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    mov w19, w0
    mov w20, w1
    mov w9, #23
    madd w22, w3, w9, w2
    PTR x23, _map_data
    COLOR w21, 0xb96e6a
    LOAD w9, _map_id
    cmp w9, #2
    b.ne Lroof_palette_ready
    COLOR w21, 0x528a94
Lroof_palette_ready:
    sub w9, w22, #1
    ldrb w9, [x23, w9, uxtw]
    cmp w9, #17
    b.ne Lroof_left
    add w9, w22, #1
    ldrb w9, [x23, w9, uxtw]
    cmp w9, #17
    b.ne Lroof_right
    RRV 0, 0, 32, 32, w21
    RR 0, 2, 32, 2, 0xe3b396
    RR 0, 12, 32, 2, 0x846264
    RR 0, 23, 32, 2, 0x846264
    b Lroof_trim
Lroof_left:
    RRV 16, 0, 16, 12, w21
    RRV 8, 10, 24, 12, w21
    RRV 0, 20, 32, 12, w21
    RR 18, 2, 14, 2, 0xe3b396
    RR 10, 12, 22, 2, 0x846264
    RR 2, 23, 30, 2, 0x846264
    b Lroof_trim
Lroof_right:
    RRV 0, 0, 16, 12, w21
    RRV 0, 10, 24, 12, w21
    RRV 0, 20, 32, 12, w21
    RR 0, 2, 14, 2, 0xe3b396
    RR 0, 12, 22, 2, 0x846264
    RR 0, 23, 30, 2, 0x846264
Lroof_trim:
    RR 0, 30, 32, 3, 0x614d4b
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x29, x30, [sp], #64
    ret

Ldraw_wall:
    stp x29, x30, [sp, #-32]!
    stp x19, x20, [sp, #16]
    mov w19, w0
    mov w20, w1
    RR 0, 0, 32, 32, 0xd8c79f
    RR 0, 0, 3, 32, 0x8c7660
    RR 29, 0, 3, 32, 0x8c7660
    RR 0, 28, 32, 4, 0x8c7660
    RR 7, 7, 18, 16, 0x665f55
    RR 9, 9, 14, 12, 0x82bdc0
    RR 15, 9, 2, 12, 0xe6d9b1
    RR 9, 14, 14, 2, 0xe6d9b1
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// Door kind0 clinic,1 shop,2 resident. Every open doorway is an interactable tile.
Ldraw_door:
    stp x29, x30, [sp, #-48]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov w19, w0
    mov w20, w1
    mov w21, w2
    RR 0, 0, 32, 32, 0xd8c79f
    RR 7, 7, 18, 25, 0x735e50
    RR 10, 9, 12, 23, 0x273d40
    RR 6, 29, 20, 3, 0xe5d5ad
    cbz w21, Ldoor_clinic
    cmp w21, #1
    b.eq Ldoor_shop
    mov w0, w19
    sub w1, w20, #8
    mov w2, #2
    PTR x3, _sprite_npc
    mov w4, #16
    mov w5, #20
    bl _draw_sprite
    b Ldoor_done
Ldoor_clinic:
    RR 5, -15, 22, 14, 0xffefd2
    RR 13, -13, 6, 10, 0xd9766b
    RR 9, -10, 14, 4, 0xd9766b
    b Ldoor_done
Ldoor_shop:
    RR 0, -13, 32, 12, 0xf3c96d
    add w0, w19, #4
    sub w1, w20, #10
    mov w2, #1
    PTR x3, Lshop_sign
    COLOR w4, 0x614d4b
    bl _draw_text
    RR 3, 21, 26, 7, 0xb88856
    RR 5, 20, 22, 3, 0xe4bd79
Ldoor_done:
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x29, x30, [sp], #48
    ret

Ldraw_bridge:
    stp x29, x30, [sp, #-32]!
    stp x19, x20, [sp, #16]
    mov w19, w0
    mov w20, w1
    RR 0, 0, 32, 32, 0x28545f
    RR 0, 4, 32, 24, 0xb1946c
    RR 0, 2, 32, 3, 0xe4c78d
    RR 0, 27, 32, 3, 0xe4c78d
    RR 7, 5, 2, 22, 0x826e59
    RR 15, 5, 2, 22, 0x826e59
    RR 23, 5, 2, 22, 0x826e59
    RR 0, 0, 3, 32, 0x795e49
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

Ldraw_cliff:
    stp x29, x30, [sp, #-32]!
    stp x19, x20, [sp, #16]
    mov w19, w0
    mov w20, w1
    RR 0, 0, 32, 32, 0x776c67
    RR 0, 0, 32, 7, 0xb3a28a
    RR 2, 8, 4, 15, 0x958574
    RR 8, 13, 6, 19, 0x645d5c
    RR 23, 10, 3, 16, 0x958574
    RR 28, 20, 4, 12, 0x645d5c
    RR 0, 29, 32, 3, 0x514e50
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

Ldraw_trainer:
    stp x29, x30, [sp, #-48]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov w19, w0
    mov w20, w1
    mov w21, w2
    PTR x3, _sprite_trainer
    PTR x9, _sprite_rival
    tst w21, #1
    csel x3, x3, x9, eq
    mov w0, w19
    sub w1, w20, #8
    mov w2, #2
    mov w4, #16
    mov w5, #20
    bl _draw_sprite
    LOAD w9, _trainer_flags
    lsr w9, w9, w21
    tst w9, #1
    b.ne Ltrainer_draw_done
    add w0, w19, #13
    sub w1, w20, #19
    mov w2, #1
    PTR x3, Lnpc_marker
    COLOR w4, 0xf5c96a
    bl _draw_text
Ltrainer_draw_done:
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x29, x30, [sp], #48
    ret

Ldraw_world_map:
    stp x29, x30, [sp, #-64]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    RECT 0, 96, 1120, 672, 0x0b202d
    RECT 80, 96, 960, 624, 0x0b202d
    RECT 96, 112, 928, 592, 0x1c3c44
    TEXT 344, 144, 4, Lmap_title, 0xffefd2
    TEXT 416, 192, 2, Lmap_subtitle, 0x81aba5
    RECT 240, 286, 640, 4, 0x496d6c
    RECT 878, 288, 4, 144, 0x496d6c
    RECT 240, 430, 640, 4, 0x496d6c
    mov w19, #0
Lworld_map_node:
    PTR x9, Lnode_x
    ldr w20, [x9, w19, uxtw #2]
    PTR x9, Lnode_y
    ldr w21, [x9, w19, uxtw #2]
    COLOR w22, 0x65918b
    LOAD w9, _map_id
    cmp w9, w19
    b.ne Lworld_map_inactive
    COLOR w22, 0xf5c96a
    mov w0, w20
    sub w1, w21, #46
    mov w2, #1
    PTR x3, Lmap_here
    COLOR w4, 0xf5c96a
    bl Lcenter_text
Lworld_map_inactive:
    sub w0, w20, #20
    sub w1, w21, #14
    mov w2, #40
    mov w3, #28
    mov w4, w22
    bl _draw_rect
    sub w0, w20, #14
    sub w1, w21, #20
    mov w2, #28
    mov w3, #40
    mov w4, w22
    bl _draw_rect
    sub w0, w20, #10
    sub w1, w21, #10
    mov w2, #20
    mov w3, #20
    COLOR w4, 0x19373f
    bl _draw_rect
    mov w0, w20
    add w1, w21, #32
    mov w2, #2
    PTR x9, _map_names
    ldr x3, [x9, w19, uxtw #3]
    COLOR w4, 0xffefd2
    bl Lcenter_text
    PTR x3, Lroute_type
    cmp w19, #0
    b.eq Lworld_node_town
    cmp w19, #2
    b.eq Lworld_node_town
    cmp w19, #5
    b.ne Lworld_node_type
    PTR x3, Lfinal_type
    b Lworld_node_type
Lworld_node_town:
    PTR x3, Ltown_type
Lworld_node_type:
    mov w0, w20
    add w1, w21, #58
    mov w2, #1
    COLOR w4, 0x81aba5
    bl Lcenter_text
    add w19, w19, #1
    cmp w19, #6
    b.lt Lworld_map_node
    RECT 136, 534, 848, 80, 0x274b50
    TEXT 156, 551, 1, Lmap_next, 0xf5c96a
    mov w0, #408
    mov w1, #549
    mov w2, #2
    LOAD x3, _world_objective
    COLOR w4, 0xffefd2
    bl _draw_text
    mov w0, #560
    mov w1, #658
    mov w2, #2
    PTR x3, Lmap_controls
    COLOR w4, 0x81aba5
    bl Lcenter_text
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x29, x30, [sp], #64
    ret

Ldraw_evolution:
    stp x29, x30, [sp, #-64]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    LOAD w19, _evolution_clock
    LOAD w20, _evolution_from
    LOAD w21, _evolution_to
    RECT 32, 112, 1056, 610, 0x1c3c44
    TEXT 404, 150, 4, Levolve_header, 0xf5c96a
    TEXT 410, 202, 2, Levolve_sub, 0x81aba5
    RECT 252, 448, 240, 20, 0x315a54
    RECT 628, 448, 240, 20, 0x315a54
    mov w0, #288
    mov w1, #282
    mov w2, #7
    mov w3, w20
    bl _draw_creature
    mov w9, #0
    cmp w19, #150
    b.ge Levolve_tint_ready
    COLOR w9, 0x0e2733
    cmp w19, #75
    b.lt Levolve_tint_ready
    tst w19, #8
    b.eq Levolve_tint_ready
    COLOR w9, 0xffefd2
Levolve_tint_ready:
    PTR x10, Lsprite_tint
    str w9, [x10]
    mov w0, #664
    mov w1, #282
    mov w2, #7
    mov w3, w21
    bl _draw_creature
    PTR x10, Lsprite_tint
    str wzr, [x10]
    TEXT 524, 352, 4, Levolve_arrow, 0x81aba5
    mov w0, #372
    mov w1, #488
    mov w2, #3
    PTR x9, _species_names
    ldr x3, [x9, w20, uxtw #3]
    COLOR w4, 0xffefd2
    bl Lcenter_text
    PTR x3, Levolve_mystery
    cmp w19, #150
    b.lt Levolve_name_ready
    PTR x9, _species_names
    ldr x3, [x9, w21, uxtw #3]
Levolve_name_ready:
    mov w0, #748
    mov w1, #488
    mov w2, #3
    COLOR w4, 0xf5c96a
    bl Lcenter_text
    mov w0, #320
    mov w1, #538
    mov w2, #480
    mov w3, w19
    mov w4, #150
    cmp w3, w4
    csel w3, w3, w4, lt
    COLOR w5, 0xf5c96a
    bl _draw_hp
    PTR x3, Levolve_wait
    cmp w19, #150
    b.lt Levolve_caption
    PTR x3, Levolve_done
Levolve_caption:
    mov w0, #560
    mov w1, #584
    mov w2, #2
    COLOR w4, 0x9dc7b4
    bl Lcenter_text
    cmp w19, #150
    b.lt Levolve_done_draw
    mov w0, #560
    mov w1, #650
    mov w2, #2
    PTR x3, Levolve_continue
    COLOR w4, 0xf5c96a
    bl Lcenter_text
Levolve_done_draw:
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x29, x30, [sp], #64
    ret

.section __DATA,__const
.p2align 3
Lfacing_to_walk: .long 0, 2, 3, 1
.p2align 3
Lsprites: .quad _sprite_sprig, _sprite_cinder, _sprite_rill, _sprite_crag, _sprite_glim, _sprite_zeph, _sprite_auralith
    .quad _sprite_verdant, _sprite_pyrelume, _sprite_tiderune, _sprite_bastion, _sprite_noctilume, _sprite_zephyrion
Lelements: .quad Lleaf, Lflame, Ltide, Lstone, Lspirit, Lsky, Lancient
    .quad Lleaf, Lflame, Ltide, Lstone, Lspirit, Lsky
Lmoves: .quad Lmove0, Lmove1, Lmove2, Lmove3, Lmove4, Lmove5, Lmove6

.section __TEXT,__cstring,cstring_literals
Ltitle: .asciz "TIDEBLOOM"
Lsubtitle: .asciz "JOURNEYS / A WORLD WILD AT HEART"
Lregion: .asciz "BRINEWICK ISLE"
Lregion_sub: .asciz "THE LAST LIGHT OF SUMMER"
Ltitle_kicker: .asciz "SIX REGIONS. ONE LIVING WORLD."
Ltitle_tagline: .asciz "JOURNEYS ACROSS THE BRINEWICK COAST"
Ltitle_desc: .asciz "EXPLORE. BEFRIEND. BRING BACK THE LIGHT."
Lstart: .asciz "SET SAIL"
Lstart_hint: .asciz "PRESS ENTER OR CLICK TO BEGIN"
Lasm_note: .asciz "HANDCRAFTED PIXELS / WRITTEN IN ARM64 ASSEMBLY"
Llocation: .asciz "BRINEWICK / THE RESONANT MARSH"
Lparty: .asciz "YOUR COMPANIONS"
Lempty_slot: .asciz "+ OPEN SLOT"
Lempty_hint: .asciz "BEFRIEND A WILD CREATURE"
Lresonators: .asciz "RESONATORS"
Lof3: .asciz "/3"
Lorbs_label: .asciz "BOND ORBS"
Ltonics_label: .asciz "TONICS"
Lworld_controls: .asciz "WASD MOVE  E TALK  TAB LEAD  J MAP  F5 SAVE  F9 LOAD  ESC MENU"
Lleaf: .asciz "LEAF"
Lflame: .asciz "FLAME"
Ltide: .asciz "TIDE"
Lstone: .asciz "STONE"
Lspirit: .asciz "SPIRIT"
Lsky: .asciz "SKY"
Lancient: .asciz "ANCIENT"
Lmove0: .asciz "2  LEAF LANCE"
Lmove1: .asciz "2  EMBER WING"
Lmove2: .asciz "2  TIDE PULSE"
Lmove3: .asciz "2  STONE ROLL"
Lmove4: .asciz "2  WISP SONG"
Lmove5: .asciz "2  SKY SLICER"
Lmove6: .asciz "2  ANCIENT TIDE"
Llvl: .asciz "LV"
Lhp_label: .asciz "HP"
Lslash: .asciz "/"
Ldamage_dealt: .asciz "DAMAGE DEALT"
Ldamage_taken: .asciz "DAMAGE TAKEN"
Lturn_label: .asciz "TURN"
Lbattle_log: .asciz "FIELD JOURNAL / BATTLE"
Lbattle_hint: .asciz "7: GUARD + CHARGE   WEAKEN FOES TO BEFRIEND   CHOOSE WITH KEYS OR CLICK"
Lattack: .asciz "1  STRIKE"
Lbefriend: .asciz "3  BEFRIEND"
Ltonic: .asciz "4  USE TONIC"
Lswitch: .asciz "5  SWITCH LEAD"
Lflee: .asciz "6  RETREAT"
Lcontinue: .asciz "ENTER / CLICK TO CONTINUE"
Lwin_kicker: .asciz "THREE LIGHTS. ONE ISLAND. A NEW BEGINNING."
Lwin_title: .asciz "TIDE RESTORED"
Lwin_desc: .asciz "THE MARSH SINGS AGAIN. YOUR FRIENDS BROUGHT IT HOME."
Lwin_restart: .asciz "PRESS ENTER FOR ANOTHER SUMMER"

.section __DATA,__const
.p2align 2
// ASCII palette: unused entries intentionally dark.
Lpalette:
    .rept 67
    .long 0x172b35
    .endr
    .long 0x387e9b // C
    .rept 3
    .long 0x172b35
    .endr
    .long 0x3b8060 // G
    .rept 8
    .long 0x172b35
    .endr
    .long 0x70638e // P
    .long 0x172b35
    .long 0xbb515c // R
    .rept 15
    .long 0x172b35
    .endr
    .long 0x83b9e0 // b (98)
    .long 0x54bdc3 // c
    .rept 3
    .long 0x172b35
    .endr
    .long 0x65bd7b // g
    .rept 4
    .long 0x172b35
    .endr
    .long 0xb6e891 // l
    .long 0x172b35 // m
    .long 0x30495b // n
    .long 0x172b35 // o
    .long 0xaa94c9 // p
    .long 0x172b35 // q
    .long 0xee806d // r
    .long 0xd4b77d // s
    .rept 3
    .long 0x172b35
    .endr
    .long 0xfff1d2 // w
    .long 0x172b35 // x
    .long 0xf7cc6c // y
    .rept 6
    .long 0x172b35
    .endr

.section __TEXT,__cstring,cstring_literals
Lnpc_marker: .asciz "!"
Lenergy: .asciz "ENERGY"
Lcharge_cost: .asciz "2E"
Lgain_energy: .asciz "+1E"
Lsignature_key: .asciz "2"
Lnext_quick: .asciz "NEXT / QUICK STRIKE"
Lnext_charge: .asciz "NEXT / HEAVY CHARGE"
Lnext_mend: .asciz "NEXT / RECOVERING"
Lbond_chance: .asciz "BOND"
Lpercent: .asciz "%"
Ltimes: .asciz "X"
Lresolving: .asciz "RESOLVING TURN..."
Lyour_turn: .asciz "YOUR TURN / READ THEIR NEXT MOVE"
Lguard_hint: .asciz "7 GUARD: BLOCK + 1 ENERGY + 5 HP       M SOUND"
Lburn_status: .asciz "BURN"
Lhex_status: .asciz "HEX"
Larmor_status: .asciz "ARMOR"

.section __TEXT,__cstring,cstring_literals
Lsound_on: .asciz "M SOUND ON"
Lsound_off: .asciz "M SOUND OFF"

.section __DATA,__data
.p2align 2
.globl _show_world_map
_show_world_map: .long 0
Lsprite_tint: .long 0

.section __TEXT,__const
.p2align 2
Lregion_grass: .long 0x66896c,0x477e68,0x768b6b,0x8d7b67,0x4c7477,0x65867b
Lnode_x: .long 240,560,880,880,560,240
Lnode_y: .long 288,288,288,432,432,432
Lnode_label_x: .long 186,518,826,820,518,180

.section __TEXT,__cstring,cstring_literals
Lresume: .asciz "RESUME"
Lcontinue_save: .asciz "CONTINUE"
Ljourney_start_hint: .asciz "ENTER CONTINUE / N NEW JOURNEY"
Lnext_step: .asciz "NEXT STEP"
Lcoins: .asciz "COINS"
Ltrainers: .asciz "TRAINERS"
Lof6: .asciz "/6"
Lshop_sign: .asciz "SHOP"
Lsave_ok: .asciz "JOURNEY SAVED"
Lload_ok: .asciz "JOURNEY LOADED"
Lsave_error: .asciz "SAVE COULD NOT BE COMPLETED"
Lno_save: .asciz "NO SAVED JOURNEY YET"
Lmap_title: .asciz "THE BRINEWICK COAST"
Lmap_subtitle: .asciz "SIX PLACES. ONE JOURNEY."
Lmap_controls: .asciz "J / ESC RETURN TO YOUR JOURNEY"
Lmap_next: .asciz "YOUR NEXT CHAPTER"
Ltown_type: .asciz "TOWN / REST + SUPPLIES"
Lroute_type: .asciz "ROUTE / TRAINERS + TRIAL"
Lfinal_type: .asciz "THE ANCIENT CROWN"
Lmap_here: .asciz "YOU ARE HERE"
Levolve_header: .asciz "A NEW CHAPTER"
Levolve_sub: .asciz "YOUR COMPANION IS EVOLVING"
Levolve_arrow: .asciz ">>>"
Levolve_mystery: .asciz "???"
Levolve_wait: .asciz "A STRONGER BOND IS TAKING SHAPE..."
Levolve_done: .asciz "EVOLUTION COMPLETE. +18 MAX HEALTH."
Levolve_continue: .asciz "PRESS ENTER TO CONTINUE YOUR JOURNEY"

.section __DATA,__const
.p2align 3
Lregional_trees: .quad _sprite_tree,_sprite_tree,_sprite_tree,_sprite_tree_autumn,_sprite_tree_moon,_sprite_tree_silver
