// Native deterministic gameplay capture. This is assembly, including direction,
// simulation, pixels, captions, and synthesized PCM. An external video encoder
// consumes video.bgra (which can be a FIFO) and audio.pcm. No game scripting VM.
// A showcase uses explicit checkpoints between scenes; battle/evolution outcomes
// within scenes always come from the actual game rules and animation timeline.
.macro RP reg,sym
    adrp \reg,\sym@PAGE
    add \reg,\reg,\sym@PAGEOFF
.endmacro
.macro RG reg,sym
    adrp x16,\sym@PAGE
    ldr \reg,[x16,\sym@PAGEOFF]
.endmacro
.macro RS reg,sym
    adrp x16,\sym@PAGE
    str \reg,[x16,\sym@PAGEOFF]
.endmacro
.macro RC reg,rgb
    mov \reg,#(\rgb & 65535)
    movk \reg,#((\rgb >> 16) & 65535),lsl #16
.endmacro
.text
.p2align 2
.globl _record_demo
_record_demo:
    stp x29,x30,[sp,#-96]!
    stp x19,x20,[sp,#16]
    stp x21,x22,[sp,#32]
    stp x23,x24,[sp,#48]
    stp x25,x26,[sp,#64]
    stp x27,x28,[sp,#80]
    mov x28,x0
    mov x21,#0
    mov x22,#0
    mov x23,#0
    mov w27,#1
    mov w9,#1
    RS w9,_recording
    RS wzr,_audio_muted
    bl _audio_reset_for_recording
    mov x0,x28
    RP x1,Lvideo_name
    bl Lrecord_open
    cbz x0,Lrecord_cleanup
    mov x21,x0
    mov x0,x28
    RP x1,Laudio_name
    bl Lrecord_open
    cbz x0,Lrecord_cleanup
    mov x22,x0
    // The isolated demo save never touches the user's adventure save.
    mov x0,x28
    RP x1,Lsave_name
    bl Lrecord_path
    bl _save_set_path
    cbnz w0,Lrecord_cleanup
    mov w0,#0
    mov w1,#1120
    mov w2,#768
    mov w3,#32
    mov w4,#0x2004
    movk w4,#0x1636,lsl #16
    bl _SDL_CreateRGBSurfaceWithFormat
    cbz x0,Lrecord_cleanup
    mov x23,x0
    ldr x24,[x23,#32]
    RP x26,Lpcm_buffer
    mov w19,#0
    mov w20,#1800
    RS wzr,Ldemo_scene
    RS wzr,Ldemo_auto
    RS wzr,Ldemo_action_wait
    RS wzr,Lrecord_errors
    bl _game_init
    bl _anim_init
    RS wzr,_screen
    RS wzr,_frame
Lrecord_frame:
    mov w0,w19
    bl Ldemo_director
    bl _anim_tick
    bl _anim_tick
    RG w9,_frame
    add w9,w9,#2
    RS w9,_frame
    bl _render_frame
    bl Lrecord_caption
    RG x0,_renderer
    mov x1,#0
    mov w2,#0x2004
    movk w2,#0x1636,lsl #16
    mov x3,x24
    ldr w4,[x23,#24]
    bl _SDL_RenderReadPixels
    cbnz w0,Lrecord_cleanup
    mov x0,x24
    mov x1,#1
    mov x2,#0x8000
    movk x2,#0x34,lsl #16      // 1120*768*4 = 0x348000
    mov x3,x21
    bl _fwrite
    mov x9,#0x8000
    movk x9,#0x34,lsl #16
    cmp x0,x9
    b.ne Lrecord_cleanup
    mov x0,#0
    mov x1,x26
    mov w2,#1470              // 735 mono samples per 30fps video frame.
    bl _audio_callback
    mov x0,x26
    mov x1,#1
    mov x2,#1470
    mov x3,x22
    bl _fwrite
    cmp x0,#1470
    b.ne Lrecord_cleanup
    add w19,w19,#1
    cmp w19,w20
    b.lt Lrecord_frame
    RG w27,Lrecord_errors
Lrecord_cleanup:
    cbz x23,Lrecord_close_video
    mov x0,x23
    bl _SDL_FreeSurface
Lrecord_close_video:
    cbz x21,Lrecord_close_audio
    mov x0,x21
    bl _fclose
    cmp w0,#0
    mov w9,#1
    csel w27,w9,w27,ne
Lrecord_close_audio:
    cbz x22,Lrecord_done
    mov x0,x22
    bl _fclose
    cmp w0,#0
    mov w9,#1
    csel w27,w9,w27,ne
Lrecord_done:
    RS wzr,_recording
    mov w0,w27
    ldp x19,x20,[sp,#16]
    ldp x21,x22,[sp,#32]
    ldp x23,x24,[sp,#48]
    ldp x25,x26,[sp,#64]
    ldp x27,x28,[sp,#80]
    ldp x29,x30,[sp],#96
    ret

// Safely join a known output directory with one of the fixed filenames.
Lrecord_path:
    RP x9,Lpath_buffer
    mov x10,x9
    mov w11,#0
Lpath_dir:
    ldrb w12,[x0],#1
    cbz w12,Lpath_separator
    cmp w11,#900
    b.ge Lpath_separator
    strb w12,[x10],#1
    add w11,w11,#1
    b Lpath_dir
Lpath_separator:
    mov w12,#47
    strb w12,[x10],#1
Lpath_suffix:
    ldrb w12,[x1],#1
    strb w12,[x10],#1
    cbnz w12,Lpath_suffix
    mov x0,x9
    ret
Lrecord_open:
    stp x29,x30,[sp,#-16]!
    bl Lrecord_path
    RP x1,Lwrite_mode
    bl _fopen
    ldp x29,x30,[sp],#16
    ret

// Sixty-second edited showcase. Each scene uses the same gameplay APIs as input.
Ldemo_director:
    stp x29,x30,[sp,#-32]!
    stp x19,x20,[sp,#16]
    mov w19,w0
    cmp w19,#75
    b.eq Ldemo_town
    cmp w19,#270
    b.eq Ldemo_map
    cmp w19,#330
    b.eq Ldemo_port
    cmp w19,#480
    b.eq Ldemo_trainer
    cmp w19,#1200
    b.eq Ldemo_marsh
    cmp w19,#1350
    b.eq Ldemo_save
    cmp w19,#1395
    b.eq Ldemo_reset
    cmp w19,#1440
    b.eq Ldemo_load
    cmp w19,#1500
    b.eq Ldemo_guardian
    cmp w19,#1710
    b.eq Ldemo_end
    b Ldemo_continuous
Ldemo_town:
    bl _game_init
    mov w9,#1
    RS w9,_screen
    RS w9,Ldemo_scene
    bl _anim_init
    b Ldemo_done
Ldemo_map:
    mov w9,#1
    RS w9,_show_world_map
    mov w9,#2
    RS w9,Ldemo_scene
    b Ldemo_done
Ldemo_port:
    RS wzr,_show_world_map
    mov w0,#2
    bl _world_load
    mov w9,#1
    RS w9,_player_x
    mov w9,#7
    RS w9,_player_y
    mov w9,#3
    RS w9,Ldemo_scene
    bl _anim_init
    b Ldemo_done
Ldemo_trainer:
    // A legitimate mid-journey checkpoint, one win away from evolution.
    bl _game_init
    mov w0,#1
    bl _world_load
    mov w9,#7
    RS w9,_player_x
    RS w9,_player_y
    RP x9,_team_level
    mov w10,#7
    str w10,[x9]
    RP x9,_team_xp
    mov w10,#9
    str w10,[x9]
    RP x9,_team_maxhp
    mov w10,#64
    str w10,[x9]
    RP x9,_team_hp
    str w10,[x9]
    mov w9,#4
    RS w9,Ldemo_scene
    mov w9,#1
    RS w9,Ldemo_auto
    RS wzr,Ldemo_action_wait
    bl _anim_init
    bl _anim_interact
    b Ldemo_done
Ldemo_marsh:
    RG w9,_trainer_flags
    tst w9,#1
    b.ne Ldemo_check_evolution
    RG w9,Lrecord_errors
    orr w9,w9,#2
    RS w9,Lrecord_errors
    RP x0,Lerror_trainer
    bl _puts
Ldemo_check_evolution:
    RP x9,_team_species
    ldr w9,[x9]
    cmp w9,#7
    b.ge Ldemo_marsh_ready
    RG w9,Lrecord_errors
    orr w9,w9,#4
    RS w9,Lrecord_errors
    RP x0,Lerror_evolution
    bl _puts
Ldemo_marsh_ready:
    RS wzr,Ldemo_auto
    // Later-route checkpoint: preserve the evolved party from the prior scene.
    mov w9,#15
    RS w9,_trainer_flags
    mov w9,#3
    RS w9,_beacons
    mov w9,#0
    RS w9,_mode
    mov w0,#4
    bl _world_load
    mov w9,#1
    RS w9,_player_x
    mov w9,#7
    RS w9,_player_y
    mov w9,#5
    RS w9,Ldemo_scene
    bl _anim_init
    b Ldemo_done
Ldemo_save:
    mov w9,#6
    RS w9,Ldemo_scene
    bl _save_write
    cbz w0,Ldemo_done
    RG w9,Lrecord_errors
    orr w9,w9,#8
    RS w9,Lrecord_errors
    RP x0,Lerror_save
    bl _puts
    b Ldemo_done
Ldemo_reset:
    bl _game_init
    bl _anim_init
    RS wzr,_screen
    b Ldemo_done
Ldemo_load:
    bl _save_load
    cbz w0,Ldemo_load_ok
    RG w9,Lrecord_errors
    orr w9,w9,#16
    RS w9,Lrecord_errors
    RP x0,Lerror_load
    bl _puts
Ldemo_load_ok:
    bl _anim_init
    mov w9,#1
    RS w9,_screen
    b Ldemo_done
Ldemo_guardian:
    // Late-game checkpoint, showcasing the real final battle rather than a mockup.
    mov w0,#5
    bl _world_load
    mov w9,#7
    RS w9,_beacons
    mov w9,#63
    RS w9,_trainer_flags
    mov w9,#11
    RS w9,_player_x
    mov w9,#3
    RS w9,_player_y
    mov w9,#3
    RS w9,_facing
    RP x9,_team_species
    mov w10,#7
    str w10,[x9]
    RP x9,_team_level
    mov w10,#12
    str w10,[x9]
    RP x9,_team_hp
    mov w10,#107
    str w10,[x9]
    RP x9,_team_maxhp
    str w10,[x9]
    RP x9,_team_energy
    mov w10,#3
    str w10,[x9]
    mov w9,#7
    RS w9,Ldemo_scene
    mov w9,#1
    RS w9,Ldemo_auto
    bl _anim_init
    bl _anim_interact
    b Ldemo_done
Ldemo_end:
    RG w9,_battle_kind
    cmp w9,#2
    b.eq Ldemo_end_ready
    RG w9,Lrecord_errors
    orr w9,w9,#32
    RS w9,Lrecord_errors
    RP x0,Lerror_boss
    bl _puts
Ldemo_end_ready:
    RS wzr,_screen
    RS wzr,Ldemo_auto
    mov w9,#8
    RS w9,Ldemo_scene
    b Ldemo_done
Ldemo_continuous:
    RG w9,Ldemo_scene
    cmp w9,#1
    b.eq Ldemo_walk_town
    cmp w9,#3
    b.eq Ldemo_walk_port
    cmp w9,#5
    b.eq Ldemo_walk_marsh
    RG w9,Ldemo_auto
    cbz w9,Ldemo_done
    RG w9,_anim_busy
    cbnz w9,Ldemo_done
    RG w9,Ldemo_action_wait
    cbz w9,Ldemo_auto_ready
    sub w9,w9,#1
    RS w9,Ldemo_action_wait
    b Ldemo_done
Ldemo_auto_ready:
    RG w9,_mode
    cbz w9,Ldemo_after_trainer
    cmp w9,#4
    b.eq Ldemo_evolution
    cmp w9,#2
    b.eq Ldemo_dismiss
    cmp w9,#1
    b.ne Ldemo_done
    // Legally choose a tonic when hurt, otherwise use available signature/strike.
    RG w20,_active_slot
    RP x9,_team_hp
    ldr w10,[x9,w20,uxtw #2]
    cmp w10,#30
    b.ge Ldemo_attack
    RG w9,_tonics
    cbz w9,Ldemo_attack
    mov w0,#3
    b Ldemo_do_action
Ldemo_attack:
    RG w9,_enemy_intent
    cmp w9,#1
    b.ne Ldemo_choose_attack
    mov w0,#6                 // Demonstrate guarding a telegraphed charge.
    b Ldemo_do_action
Ldemo_choose_attack:
    RP x9,_team_species
    ldr w9,[x9,w20,uxtw #2]
    cmp w9,#7
    sub w11,w9,#7
    csel w9,w11,w9,ge
    RG w10,_enemy_species
    cmp w10,#7
    sub w11,w10,#7
    csel w10,w11,w10,ge
    mov w11,#7
    madd w9,w9,w11,w10
    RP x10,_effectiveness
    ldrb w9,[x10,w9,uxtw]
    cmp w9,#2
    b.eq Ldemo_neutral_strike
    RP x9,_team_energy
    ldr w10,[x9,w20,uxtw #2]
    cmp w10,#2
    cset w0,ge
    b Ldemo_do_action
Ldemo_neutral_strike:
    mov w0,#0
Ldemo_do_action:
    bl _anim_action
    mov w9,#16
    RS w9,Ldemo_action_wait
    b Ldemo_done
Ldemo_evolution:
    RG w9,_evolution_clock
    cmp w9,#180
    b.lt Ldemo_done
Ldemo_dismiss:
    bl _anim_dismiss
    mov w9,#18
    RS w9,Ldemo_action_wait
    b Ldemo_done
Ldemo_after_trainer:
    RG w9,Ldemo_scene
    cmp w9,#4
    b.ne Ldemo_done
    RG w9,_player_x
    cmp w9,#14
    b.lt Ldemo_walk_right
    b Ldemo_done
Ldemo_walk_town:
    cmp w19,#150
    b.lt Ldemo_town_east
    cmp w19,#210
    b.lt Ldemo_town_north
    RG w9,_player_x
    cmp w9,#18
    b.lt Ldemo_walk_right
    b Ldemo_done
Ldemo_town_east:
    RG w9,_player_x
    cmp w9,#12
    b.lt Ldemo_walk_right
    b Ldemo_done
Ldemo_town_north:
    RG w9,_player_y
    cmp w9,#8
    b.gt Ldemo_walk_up
    b Ldemo_done
Ldemo_walk_port:
    cmp w19,#420
    b.lt Ldemo_port_east
    cmp w19,#450
    b.lt Ldemo_port_north
    cmp w19,#450
    b.eq Ldemo_interact
    b Ldemo_done
Ldemo_port_east:
    RG w9,_player_x
    cmp w9,#11
    b.lt Ldemo_walk_right
    b Ldemo_done
Ldemo_port_north:
    RG w9,_player_y
    cmp w9,#5
    b.gt Ldemo_walk_up
    b Ldemo_done
Ldemo_walk_marsh:
    cmp w19,#1320
    b.ge Ldemo_done
    RG w9,_player_x
    cmp w9,#10
    b.lt Ldemo_walk_right
    b Ldemo_done
Ldemo_walk_right:
    mov w0,#1
    mov w1,#0
    bl _anim_move
    b Ldemo_done
Ldemo_walk_up:
    mov w0,#0
    mov w1,#-1
    bl _anim_move
    b Ldemo_done
Ldemo_interact:
    bl _anim_interact
Ldemo_done:
    ldp x19,x20,[sp,#16]
    ldp x29,x30,[sp],#32
    ret

Lrecord_caption:
    stp x29,x30,[sp,#-16]!
    mov w0,#270
    mov w1,#23
    mov w2,#550
    mov w3,#55
    RC w4,0x112b35
    bl _draw_rect
    RG w9,Ldemo_scene
    RP x10,Lcaption_table
    ldr x3,[x10,w9,uxtw #3]
    mov w0,#282
    mov w1,#34
    mov w2,#2
    RC w4,0xf5c96a
    bl _draw_text
    mov w0,#282
    mov w1,#61
    mov w2,#1
    RP x3,Lcaption_sub
    RC w4,0x92b8ae
    bl _draw_text
    ldp x29,x30,[sp],#16
    ret

.data
.p2align 2
.globl _recording
_recording: .long 0
Ldemo_scene: .long 0
Ldemo_auto: .long 0
Ldemo_action_wait: .long 0
Lrecord_errors: .long 0
.p2align 3
Lpath_buffer: .space 1024
Lpcm_buffer: .space 1472
.section __DATA,__const
.p2align 3
Lcaption_table: .quad Lcap0,Lcap1,Lcap2,Lcap3,Lcap4,Lcap5,Lcap6,Lcap7,Lcap8
.section __TEXT,__cstring,cstring_literals
Lvideo_name: .asciz "video.bgra"
Laudio_name: .asciz "audio.pcm"
Lsave_name: .asciz "demo-save.dat"
Lwrite_mode: .asciz "wb"
Lcaption_sub: .asciz "TIDEBLOOM JOURNEYS / NATIVE ARM64 / ORIGINAL PIXEL RPG"
Lcap0: .asciz "A CREATURE RPG. IN PURE ASSEMBLY."
Lcap1: .asciz "TOWNS TO CALL HOME."
Lcap2: .asciz "SIX CONNECTED REGIONS."
Lcap3: .asciz "EXPLORE. REST. RESUPPLY."
Lcap4: .asciz "TRAINER TEAMS. REAL EVOLUTION."
Lcap5: .asciz "A BIGGER WORLD TO GET LOST IN."
Lcap6: .asciz "SAVE YOUR PROGRESS. COME BACK."
Lcap7: .asciz "ONE ANCIENT FINAL CHALLENGE."
Lcap8: .asciz "GAMEPLAY. GRAPHICS. MUSIC. ASSEMBLY."
Lerror_trainer: .asciz "DEMO CHECK: trainer team not defeated before scene cut."
Lerror_evolution: .asciz "DEMO CHECK: evolution did not complete before scene cut."
Lerror_save: .asciz "DEMO CHECK: isolated progress save failed."
Lerror_load: .asciz "DEMO CHECK: isolated progress load failed."
Lerror_boss: .asciz "DEMO CHECK: final guardian encounter did not start."
