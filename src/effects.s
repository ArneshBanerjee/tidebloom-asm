// Pure AArch64 visual effects: choreography, particles, transitions, ambient life.
.macro FP reg, sym
    adrp \reg, \sym@PAGE
    add \reg, \reg, \sym@PAGEOFF
.endmacro
.macro FG reg, sym
    adrp x16, \sym@PAGE
    ldr \reg, [x16, \sym@PAGEOFF]
.endmacro
.macro FC reg, rgb
    mov \reg,#(\rgb & 65535)
    movk \reg,#((\rgb >> 16) & 65535),lsl #16
.endmacro
.macro FR x,y,w,h,c
    mov w0,#\x
    mov w1,#\y
    mov w2,#\w
    mov w3,#\h
    FC w4,\c
    bl _draw_rect
.endmacro
.macro FT x,y,s,label,c
    mov w0,#\x
    mov w1,#\y
    mov w2,#\s
    FP x3,\label
    FC w4,\c
    bl _draw_text
.endmacro
.text
.p2align 2
.globl _battle_pose
_battle_pose:
    mov w8,w0
    mov w0,#0
    mov w1,#0
    mov w2,#1
    FG w9,_anim_kind
    cmp w9,#1
    b.ne Lpose_done
    FG w9,_anim_time
    cbnz w8,Lpose_enemy
    cmp w9,#18
    b.ge Lpose_hero_hit
    FG w10,_anim_action_id
    cmp w10,#1
    b.gt Lpose_done
    mov w10,#18
    sub w10,w10,w9
    cmp w9,#9
    csel w9,w9,w10,lt
    add w0,w9,w9,lsl #1
    lsr w1,w9,#1
    neg w1,w1
    ret
Lpose_hero_hit:
    cmp w9,#48
    b.lt Lpose_done
    cmp w9,#60
    b.ge Lpose_done
    FG w10,_last_enemy_damage
    cbz w10,Lpose_done
    and w9,w9,#1
    mov w0,#6
    cmp w9,#0
    cneg w0,w0,eq
    FG w9,_anim_time
    and w9,w9,#3
    cmp w9,#2
    cset w2,ne
    ret
Lpose_enemy:
    FG w10,_anim_action_id
    cmp w10,#2
    b.ne Lpose_enemy_damage
    FG w10,_mode
    cmp w10,#2
    b.ne Lpose_enemy_damage
    cmp w9,#34
    b.lt Lpose_enemy_damage
    mov w2,#0
    ret
Lpose_enemy_damage:
    cmp w9,#18
    b.lt Lpose_done
    cmp w9,#31
    b.ge Lpose_enemy_attack
    FG w10,_last_player_damage
    cbz w10,Lpose_done
    and w9,w9,#1
    mov w0,#7
    cmp w9,#0
    cneg w0,w0,eq
    FG w9,_anim_time
    and w9,w9,#3
    cmp w9,#2
    cset w2,ne
    ret
Lpose_enemy_attack:
    cmp w9,#36
    b.lt Lpose_done
    cmp w9,#48
    b.ge Lpose_done
    FG w10,_last_enemy_damage
    cbz w10,Lpose_done
    sub w9,w9,#36
    mov w10,#12
    sub w10,w10,w9
    cmp w9,#6
    csel w9,w9,w10,lt
    neg w0,w9,lsl #3
    mov w1,w9
Lpose_done:
    ret

.globl _draw_effects
_draw_effects:
    stp x29,x30,[sp,#-64]!
    stp x19,x20,[sp,#16]
    stp x21,x22,[sp,#32]
    stp x23,x24,[sp,#48]
    FG w9,_screen
    cbz w9,Lfx_title
    FG w9,_visual_mode
    cbz w9,Lfx_world
    cmp w9,#3
    b.eq Lfx_victory
    FG w9,_anim_kind
    cmp w9,#1
    b.ne Lfx_transitions
    FG w19,_anim_time
    FG w20,_anim_action_id
    cmp w19,#40
    b.ge Lfx_enemy_label
    FT 490,124,2,Lyour_move,0xffefd2
    b Lfx_move
Lfx_enemy_label:
    FG w9,_last_enemy_damage
    cbz w9,Lfx_move
    FT 490,124,2,Ltheir_move,0xffefd2
Lfx_move:
    cmp w20,#0
    b.eq Lfx_strike
    cmp w20,#1
    b.eq Lfx_signature
    cmp w20,#2
    b.eq Lfx_bond
    cmp w20,#3
    b.eq Lfx_heal
    cmp w20,#4
    b.eq Lfx_switch
    cmp w20,#5
    b.eq Lfx_flee
    cmp w20,#6
    b.eq Lfx_guard
    b Lfx_damage_numbers
Lfx_strike:
    cmp w19,#12
    b.lt Lfx_damage_numbers
    cmp w19,#28
    b.ge Lfx_damage_numbers
    mov w21,#0
Lfx_slash_loop:
    mov w9,#13
    madd w0,w21,w9,wzr
    add w0,w0,#780
    mov w9,#12
    msub w1,w21,w9,wzr
    add w1,w1,#278
    mov w2,#22
    mov w3,#7
    FC w4,0xffefd2
    bl _draw_rect
    add w21,w21,#1
    cmp w21,#7
    b.lt Lfx_slash_loop
    b Lfx_hitburst
Lfx_signature:
    FG w9,_active_slot
    FP x10,_team_species
    ldr w9,[x10,w9,uxtw #2]
    cmp w9,#7
    sub w11,w9,#7
    csel w9,w11,w9,ge
    FP x10,Lfx_colors
    ldr w24,[x10,w9,uxtw #2]
    cmp w19,#6
    b.lt Lfx_damage_numbers
    cmp w19,#18
    b.ge Lfx_element_burst
    mov w21,#0
Lfx_trail:
    sub w22,w19,#6
    sub w22,w22,w21
    cmp w22,#0
    b.lt Lfx_trail_next
    mov w9,#39
    madd w0,w22,w9,wzr
    add w0,w0,#350
    mov w9,#10
    msub w1,w22,w9,wzr
    add w1,w1,#350
    mov w2,#20
    sub w2,w2,w21,lsl #2
    mov w3,w2
    mov w4,w24
    bl _draw_rect
Lfx_trail_next:
    add w21,w21,#1
    cmp w21,#4
    b.lt Lfx_trail
    b Lfx_damage_numbers
Lfx_element_burst:
    cmp w19,#38
    b.ge Lfx_damage_numbers
    mov w0,#826
    mov w1,#242
    sub w2,w19,#18
    mov w3,w24
    bl Lburst
    b Lfx_damage_numbers
Lfx_hitburst:
    cmp w19,#18
    b.lt Lfx_damage_numbers
    mov w0,#826
    mov w1,#240
    sub w2,w19,#18
    FC w3,0xf5c96a
    bl Lburst
    b Lfx_damage_numbers
Lfx_bond:
    cmp w19,#8
    b.lt Lfx_damage_numbers
    cmp w19,#30
    b.ge Lfx_bond_shake
    sub w22,w19,#8
    mov w9,#22
    madd w21,w22,w9,wzr
    add w21,w21,#330
    mov w9,#5
    msub w22,w22,w9,wzr
    add w22,w22,#346
    b Lfx_bond_draw
Lfx_bond_shake:
    mov w21,#814
    mov w22,#294
    and w9,w19,#7
    sub w9,w9,#4
    add w21,w21,w9
    cmp w19,#58
    b.lt Lfx_bond_draw
    FG w9,_mode
    cmp w9,#2
    b.ne Lfx_damage_numbers
    FT 756,198,3,Lbonded,0xf5c96a
Lfx_bond_draw:
    mov w0,w21
    mov w1,w22
    mov w2,#22
    mov w3,#22
    FC w4,0x142c35
    bl _draw_rect
    add w0,w21,#3
    add w1,w22,#3
    mov w2,#16
    mov w3,#16
    FC w4,0xf5c96a
    bl _draw_rect
    add w0,w21,#8
    add w1,w22,#8
    mov w2,#6
    mov w3,#6
    FC w4,0xffefd2
    bl _draw_rect
    cmp w19,#30
    b.lt Lfx_damage_numbers
    mov w0,#826
    mov w1,#248
    sub w2,w19,#30
    FC w3,0xf5c96a
    bl Lburst
    b Lfx_damage_numbers
Lfx_heal:
    cmp w19,#10
    b.lt Lfx_damage_numbers
    cmp w19,#40
    b.ge Lfx_damage_numbers
    mov w0,#310
    mov w1,#334
    sub w2,w19,#10
    FC w3,0xb6e891
    bl Lburst
    FT 246,450,3,Lrecover,0xb6e891
    b Lfx_damage_numbers
Lfx_switch:
    cmp w19,#32
    b.ge Lfx_damage_numbers
    mov w0,#310
    mov w1,#334
    mov w2,w19
    FC w3,0xb3dbd1
    bl Lburst
    b Lfx_damage_numbers
Lfx_flee:
    cmp w19,#40
    b.ge Lfx_damage_numbers
    mov w21,#0
Lfx_smoke_loop:
    mov w9,#27
    madd w0,w21,w9,wzr
    add w0,w0,#190
    add w0,w0,w19,lsl #1
    mov w1,#370
    sub w1,w1,w21,lsl #2
    mov w2,#28
    mov w3,#22
    FC w4,0xc0d3bd
    bl _draw_rect
    add w21,w21,#1
    cmp w21,#6
    b.lt Lfx_smoke_loop
    b Lfx_damage_numbers
Lfx_guard:
    cmp w19,#44
    b.ge Lfx_damage_numbers
    FR 222,246,4,152,0x8fd9cc
    FR 390,246,4,152,0x8fd9cc
    FR 236,230,144,4,0x8fd9cc
    FR 236,410,144,4,0x8fd9cc
    FT 244,450,3,Lguard,0xb6e891
Lfx_damage_numbers:
    cmp w19,#18
    b.lt Lfx_enemy_damage
    cmp w19,#42
    b.ge Lfx_enemy_damage
    FG w5,_last_player_damage
    cbz w5,Lfx_enemy_damage
    mov w0,#826
    mov w1,#224
    sub w1,w1,w19
    mov w2,#4
    FC w4,0xffefd2
    bl Ldamage_number
    FG w9,_last_effect
    cmp w9,#1
    b.ne Lfx_enemy_damage
    FT 724,166,2,Lstrong,0xf5c96a
Lfx_enemy_damage:
    cmp w19,#48
    b.lt Lfx_transitions
    cmp w19,#74
    b.ge Lfx_transitions
    FG w5,_last_enemy_damage
    cbz w5,Lfx_enemy_recover
    mov w0,#306
    mov w1,#316
    sub w1,w1,w19
    mov w2,#4
    FC w4,0xffb090
    bl Ldamage_number
    mov w0,#312
    mov w1,#324
    sub w2,w19,#48
    FC w3,0xef8972
    bl Lburst
    b Lfx_transitions
Lfx_enemy_recover:
    FG w9,_last_enemy_heal
    cbz w9,Lfx_transitions
    mov w0,#826
    mov w1,#242
    sub w2,w19,#48
    FC w3,0xb6e891
    bl Lburst
    b Lfx_transitions

Lfx_world:
    // Tiny drifting seeds travel over the marsh, never obscuring the HUD.
    mov w19,#0
Lfx_seed_loop:
    FG w9,_frame
    lsr w9,w9,#1
    mov w10,#101
    madd w9,w19,w10,w9
    mov w10,#680
    udiv w11,w9,w10
    msub w0,w11,w10,w9
    add w0,w0,#62
    mov w10,#53
    mul w9,w19,w10
    FG w10,_frame
    lsr w10,w10,#4
    and w10,w10,#7
    add w1,w9,w10
    add w1,w1,#188
    mov w2,#3
    mov w3,#2
    FC w4,0xb4c997
    bl _draw_rect
    add w19,w19,#1
    cmp w19,#7
    b.lt Lfx_seed_loop
    FG w9,_world_flash
    cbz w9,Lfx_transitions
    mov w2,#45
    sub w2,w2,w9
    lsr w2,w2,#2
    FG w0,_walk_x
    FG w1,_walk_y
    add w0,w0,#16
    add w1,w1,#18
    FC w3,0xf5c96a
    bl Lburst
    b Lfx_transitions

Lfx_title:
    mov w19,#0
Lfx_title_spark:
    FG w9,_frame
    add w9,w9,w19,lsl #4
    lsr w9,w9,#3
    and w20,w9,#31
    mov w9,#107
    mul w21,w19,w9
    add w21,w21,#126
    mov w22,#258
    sub w22,w22,w20
    cmp w20,#16
    b.ge Lfx_title_spark_next
    mov w0,w21
    mov w1,w22
    mov w2,#3
    mov w3,#7
    FC w4,0xc2d49c
    bl _draw_rect
    sub w0,w21,#2
    add w1,w22,#2
    mov w2,#7
    mov w3,#3
    FC w4,0xc2d49c
    bl _draw_rect
Lfx_title_spark_next:
    add w19,w19,#1
    cmp w19,#9
    b.lt Lfx_title_spark
    b Lfx_done
Lfx_victory:
    mov w19,#0
Lfx_confetti:
    mov w9,#71
    mul w0,w19,w9
    add w0,w0,#68
    mov w9,#19
    mul w9,w19,w9
    FG w10,_frame
    add w9,w9,w10
    mov w10,#560
    udiv w11,w9,w10
    msub w1,w11,w10,w9
    add w1,w1,#130
    mov w2,#5
    mov w3,#8
    FC w4,0xf5c96a
    tst w19,#1
    b.eq Lfx_confetti_draw
    FC w4,0x94c78a
Lfx_confetti_draw:
    bl _draw_rect
    add w19,w19,#1
    cmp w19,#14
    b.lt Lfx_confetti
    b Lfx_done

Lfx_transitions:
    FG w9,_anim_kind
    cmp w9,#2
    b.lt Lfx_done
    FG w19,_anim_time
    cmp w19,#18
    b.le Lfx_wipe_close
    mov w9,#36
    sub w19,w9,w19
Lfx_wipe_close:
    mov w9,#1120
    mul w19,w19,w9
    mov w9,#18
    udiv w19,w19,w9
    mov w20,#0
Lfx_wipe_band:
    mov w0,#0
    tst w20,#1
    b.eq Lfx_wipe_draw
    mov w0,#1120
    sub w0,w0,w19
Lfx_wipe_draw:
    lsl w1,w20,#6
    mov w2,w19
    mov w3,#64
    FC w4,0x102b35
    bl _draw_rect
    add w20,w20,#1
    cmp w20,#12
    b.lt Lfx_wipe_band
Lfx_done:
    ldp x19,x20,[sp,#16]
    ldp x21,x22,[sp,#32]
    ldp x23,x24,[sp,#48]
    ldp x29,x30,[sp],#64
    ret

// A two-pixel shadow keeps numbers readable across pale creature sprites.
Ldamage_number:
    stp x29,x30,[sp,#-64]!
    stp x0,x1,[sp,#16]
    stp x2,x4,[sp,#32]
    str x5,[sp,#48]
    add w0,w0,#2
    add w1,w1,#2
    FC w4,0x102b35
    bl _draw_number
    ldp x0,x1,[sp,#16]
    ldp x2,x4,[sp,#32]
    ldr x5,[sp,#48]
    bl _draw_number
    ldp x29,x30,[sp],#64
    ret

// Radial eight-particle burst. w0 centerX,w1 centerY,w2 age,w3 RGB.
Lburst:
    stp x29,x30,[sp,#-64]!
    stp x19,x20,[sp,#16]
    stp x21,x22,[sp,#32]
    stp x23,x24,[sp,#48]
    mov w19,w0
    mov w20,w1
    mov w21,w2
    mov w22,w3
    mov w23,#0
    FP x24,Ldirections
Lburst_loop:
    ldrsb w9,[x24],#1
    ldrsb w10,[x24],#1
    add w11,w21,w21,lsl #1
    add w11,w11,#32
    madd w0,w9,w11,w19
    madd w1,w10,w11,w20
    mov w2,#7
    cmp w21,#15
    mov w9,#3
    csel w2,w9,w2,gt
    mov w3,w2
    mov w4,w22
    bl _draw_rect
    add w23,w23,#1
    cmp w23,#8
    b.lt Lburst_loop
    ldp x19,x20,[sp,#16]
    ldp x21,x22,[sp,#32]
    ldp x23,x24,[sp,#48]
    ldp x29,x30,[sp],#64
    ret

.section __TEXT,__const
.p2align 2
Lfx_colors: .long 0xb6e891,0xffb270,0x8fdde0,0xe8cf91,0xc5a5e8,0xe1eed7,0xf5c96a
Ldirections: .byte 1,0,1,1,0,1,-1,1,-1,0,-1,-1,0,-1,1,-1
.section __TEXT,__cstring,cstring_literals
Lyour_move: .asciz "YOUR MOVE"
Ltheir_move: .asciz "FOE RESPONSE"
Lbonded: .asciz "BONDED!"
Lrecover: .asciz "RESTORE"
Lguard: .asciz "BRACE"
Lstrong: .asciz "SUPER EFFECTIVE"
