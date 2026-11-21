// Presentation timeline, movement interpolation, and turn choreography.
// All state advances in fixed simulation frames; game rules remain in game.s.
// Battle rendering must use visual_mode, visual_active_slot and visual_*_hp.
// The rules resolve immediately; presentation holds the player impact until18f,
// enemy response/burn until48f, automatic replacement until60f, and results78f.
// Movement spans8f. Encounter/return wipes span36f and change scenes at18f.
// anim_selftest returns0 on success or the failed scenario index1..15.
.macro AP reg, sym
    adrp \reg, \sym@PAGE
    add \reg, \reg, \sym@PAGEOFF
.endmacro
.macro AG reg, sym
    adrp x16, \sym@PAGE
    ldr \reg, [x16, \sym@PAGEOFF]
.endmacro
.macro AS reg, sym
    adrp x16, \sym@PAGE
    str \reg, [x16, \sym@PAGEOFF]
.endmacro
.text
.p2align 2
.globl _anim_init, _anim_tick, _anim_action, _anim_move, _anim_interact, _anim_dismiss
_anim_init:
    stp x29,x30,[sp,#-16]!
    mov w9,#0
    AS w9,_anim_busy
    AS w9,_anim_kind
    AS w9,_anim_time
    AS w9,_walk_remaining
    AS w9,_world_flash
    AS w9,_walk_dx
    AS w9,_walk_dy
    AS w9,_auto_faint
    AS w9,_evolution_clock
    mov w9,#-1
    AS w9,_anim_action_id
    AG w9,_mode
    AS w9,_visual_mode
    AG w9,_player_x
    lsl w9,w9,#5
    add w9,w9,#32
    AS w9,_walk_x
    AG w9,_player_y
    lsl w9,w9,#5
    add w9,w9,#114
    AS w9,_walk_y
    bl Lsync_hp
    ldp x29,x30,[sp],#16
    ret

Lsync_hp:
    AG w9,_enemy_hp
    AS w9,_visual_enemy_hp
    AG w10,_active_slot
    AS w10,_visual_active_slot
    AP x9,_team_species
    ldr w9,[x9,w10,uxtw #2]
    AS w9,_visual_player_species
    AP x9,_team_hp
    ldr w9,[x9,w10,uxtw #2]
    AS w9,_visual_player_hp
    ret

_anim_tick:
    stp x29,x30,[sp,#-16]!
    AG w9,_world_flash
    cbz w9,Ltick_walk
    sub w9,w9,#1
    AS w9,_world_flash
Ltick_walk:
    AG w9,_walk_remaining
    cbz w9,Ltick_timeline
    sub w9,w9,#1
    AS w9,_walk_remaining
    AG w9,_walk_x
    AG w10,_walk_dx
    add w9,w9,w10,lsl #2
    AS w9,_walk_x
    AG w9,_walk_y
    AG w10,_walk_dy
    add w9,w9,w10,lsl #2
    AS w9,_walk_y
Ltick_timeline:
    AG w9,_anim_busy
    cbz w9,Ltick_idle
    AG w9,_anim_time
    add w9,w9,#1
    AS w9,_anim_time
    AG w10,_anim_kind
    cmp w10,#1
    b.eq Ltick_turn
    cmp w9,#18
    b.ne Ltick_transition_end
    AG w10,_mode
    AS w10,_visual_mode
    bl Lsync_hp
Ltick_transition_end:
    AG w9,_anim_time
    cmp w9,#36
    b.ge Ltick_end
    b Ltick_done
Ltick_turn:
    // First impact at 18f, opponent responds at 48f.
    cmp w9,#18
    b.lt Ltick_done
    cmp w9,#48
    b.ge Ltick_response
    AG w10,_enemy_mid_hp
    AS w10,_visual_enemy_hp
    AG w10,_player_mid_hp
    AS w10,_visual_player_hp
    cmp w9,#18
    b.ne Ltick_done
    AG w10,_anim_action_id
    cmp w10,#2
    mov w0,#1
    mov w11,#3
    csel w0,w11,w0,eq
    bl _audio_sfx
    b Ltick_done
Ltick_response:
    // Burn/recovery resolve with the enemy response, after the first impact.
    AG w10,_enemy_response_hp
    AS w10,_visual_enemy_hp
    AG w10,_player_response_hp
    AS w10,_visual_player_hp
    // Let the outgoing companion visibly faint before revealing its replacement.
    cmp w9,#60
    b.lt Ltick_response_sound
    AG w10,_auto_faint
    cbz w10,Ltick_response_sound
    AG w10,_mode
    cmp w10,#1
    b.ne Ltick_response_sound
    bl Lsync_hp
Ltick_response_sound:
    AG w9,_anim_time
    cmp w9,#48
    b.ne Ltick_finish_check
    AG w10,_last_enemy_damage
    cbz w10,Ltick_finish_check
    mov w0,#5
    bl _audio_sfx
Ltick_finish_check:
    AG w9,_anim_time
    cmp w9,#78
    b.lt Ltick_done
    AG w9,_mode
    cmp w9,#2
    b.lt Ltick_end
    mov w0,#4
    bl _audio_sfx
Ltick_end:
    mov w9,#0
    AS w9,_anim_busy
    AS w9,_anim_kind
    AS w9,_anim_time
    AG w9,_mode
    AS w9,_visual_mode
    cmp w9,#4
    b.ne Ltick_end_sync
    AS wzr,_evolution_clock
Ltick_end_sync:
    bl Lsync_hp
    b Ltick_done
Ltick_idle:
    AG w9,_mode
    AS w9,_visual_mode
    cmp w9,#4
    b.ne Ltick_idle_sync
    AG w10,_evolution_clock
    cmp w10,#180
    b.ge Ltick_idle_sync
    add w10,w10,#1
    AS w10,_evolution_clock
    cmp w10,#90
    b.ne Ltick_idle_sync
    mov w0,#4
    bl _audio_sfx
Ltick_idle_sync:
    bl Lsync_hp
Ltick_done:
    ldp x29,x30,[sp],#16
    ret

_anim_move:
    stp x29,x30,[sp,#-64]!
    stp x19,x20,[sp,#16]
    stp x21,x22,[sp,#32]
    stp x23,x24,[sp,#48]
    mov w19,w0
    mov w20,w1
    AG w9,_anim_busy
    cbnz w9,Lamove_done
    AG w9,_walk_remaining
    cbnz w9,Lamove_done
    AG w21,_player_x
    AG w22,_player_y
    AG w23,_map_id
    bl _game_move
    AG w9,_map_id
    cmp w9,w23
    b.ne Lamove_region
    AG w9,_player_x
    AG w10,_player_y
    cmp w21,w9
    ccmp w22,w10,#0,eq
    b.eq Lamove_done
    AS w19,_walk_dx
    AS w20,_walk_dy
    mov w9,#8
    AS w9,_walk_remaining
    mov w0,#0
    bl _audio_sfx
    AG w9,_mode
    cmp w9,#1
    b.ne Lamove_done
    bl Lencounter_transition
    b Lamove_done
Lamove_region:
    AG w9,_player_x
    lsl w9,w9,#5
    add w9,w9,#32
    AS w9,_walk_x
    AG w9,_player_y
    lsl w9,w9,#5
    add w9,w9,#114
    AS w9,_walk_y
    AS wzr,_walk_remaining
    AS wzr,_anim_time
    mov w9,#1
    AS w9,_anim_busy
    mov w9,#4
    AS w9,_anim_kind
    mov w0,#2
    bl _audio_sfx
Lamove_done:
    ldp x19,x20,[sp,#16]
    ldp x21,x22,[sp,#32]
    ldp x23,x24,[sp,#48]
    ldp x29,x30,[sp],#64
    ret

Lencounter_transition:
    mov w9,#1
    AS w9,_anim_busy
    mov w9,#2
    AS w9,_anim_kind
    mov w9,#0
    AS w9,_anim_time
    AS w9,_visual_mode
    mov w0,#2
    b _audio_sfx

_anim_interact:
    stp x29,x30,[sp,#-16]!
    AG w9,_anim_busy
    cbnz w9,Linteract_done
    AG w9,_walk_remaining
    cbnz w9,Linteract_done
    AG w9,_mode
    cmp w9,#2
    b.eq Linteract_dismiss
    cmp w9,#4
    b.eq Linteract_dismiss
    cbnz w9,Linteract_done
    bl _game_interact
    AG w9,_mode
    cmp w9,#1
    b.ne Linteract_rest
    bl Lencounter_transition
    b Linteract_done
Linteract_rest:
    AG w9,_last_event
    cmp w9,#8
    b.lt Linteract_done
    mov w9,#45
    AS w9,_world_flash
    mov w0,#4
    bl _audio_sfx
    b Linteract_done
Linteract_dismiss:
    bl _anim_dismiss
Linteract_done:
    ldp x29,x30,[sp],#16
    ret

_anim_dismiss:
    stp x29,x30,[sp,#-16]!
    AG w9,_anim_busy
    cbnz w9,Ldismiss_return
    AG w9,_mode
    cmp w9,#4
    b.eq Ldismiss_evolution
    cmp w9,#2
    b.ne Ldismiss_return
    b Ldismiss_execute
Ldismiss_evolution:
    AG w9,_evolution_clock
    cmp w9,#150
    b.lt Ldismiss_return
Ldismiss_execute:
    bl _game_dismiss
    AG w9,_mode
    cmp w9,#1
    b.eq Ldismiss_next_foe
    cmp w9,#0
    b.ne Ldismiss_same_scene
    mov w9,#1
    AS w9,_anim_busy
    mov w9,#3
    AS w9,_anim_kind
    mov w9,#0
    AS w9,_anim_time
    AG w9,_player_x
    lsl w9,w9,#5
    add w9,w9,#32
    AS w9,_walk_x
    AG w9,_player_y
    lsl w9,w9,#5
    add w9,w9,#114
    AS w9,_walk_y
    b Ldismiss_return
Ldismiss_next_foe:
    mov w9,#1
    AS w9,_anim_busy
    mov w9,#5
    AS w9,_anim_kind
    AS wzr,_anim_time
    b Ldismiss_return
Ldismiss_same_scene:
    AS w9,_visual_mode
    bl Lsync_hp
Ldismiss_return:
    ldp x29,x30,[sp],#16
    ret

_anim_action:
    stp x29,x30,[sp,#-64]!
    stp x19,x20,[sp,#16]
    stp x21,x22,[sp,#32]
    stp x23,x24,[sp,#48]
    mov w19,w0
    AG w9,_anim_busy
    cbnz w9,Laaction_done
    AG w9,_mode
    cmp w9,#1
    b.ne Laaction_done
    AG w20,_enemy_hp
    AG w22,_active_slot
    AP x9,_team_hp
    ldr w21,[x9,w22,uxtw #2]
    mov w23,w22
    mov w24,w21
    // Snapshot the chosen switch target before retaliation can faint it.
    cmp w19,#4
    b.ne Laaction_execute
    mov w10,#1
Laaction_switch_target:
    add w11,w22,w10
    cmp w11,#3
    sub w12,w11,#3
    csel w11,w12,w11,ge
    ldr w12,[x9,w11,uxtw #2]
    cbnz w12,Laaction_switch_found
    add w10,w10,#1
    cmp w10,#3
    b.lt Laaction_switch_target
    b Laaction_execute
Laaction_switch_found:
    mov w23,w11
    mov w24,w12
Laaction_execute:
    AP x9,_team_species
    ldr w9,[x9,w23,uxtw #2]
    AS w9,_visual_player_species
    mov w0,w19
    bl _game_action
    AG w9,_last_event
    cbz w9,Laaction_done
    AS w19,_anim_action_id
    AS w20,_visual_enemy_hp
    AS w23,_visual_active_slot
    AS w24,_visual_player_hp
    AG w9,_last_player_damage
    sub w10,w20,w9
    cmp w10,#0
    csel w10,w10,wzr,gt
    AS w10,_enemy_mid_hp
    AG w10,_enemy_hp
    AS w10,_enemy_response_hp
    AG w9,_last_heal
    add w24,w24,w9
    AP x9,_team_maxhp
    ldr w10,[x9,w23,uxtw #2]
    cmp w24,w10
    csel w24,w24,w10,lt
    AS w24,_player_mid_hp
    AG w9,_last_enemy_damage
    sub w10,w24,w9
    cmp w10,#0
    csel w10,w10,wzr,gt
    AS w10,_player_response_hp
    // Death detection uses damage, not post-turn HP (camp recovery may heal it).
    cmp w10,#0
    cset w11,eq
    cmp w9,#0
    csel w11,w11,wzr,gt
    AS w11,_auto_faint
    mov w9,#1
    AS w9,_anim_busy
    AS w9,_anim_kind
    AS w9,_visual_mode
    mov w9,#0
    AS w9,_anim_time
    mov w0,#2
    bl _audio_sfx
Laaction_done:
    ldp x19,x20,[sp,#16]
    ldp x21,x22,[sp,#32]
    ldp x23,x24,[sp,#48]
    ldp x29,x30,[sp],#64
    ret

// Headless regression suite. All inputs drive the same assembly game/timeline
// APIs as the live application. Only fixture state is set directly.
.globl _anim_selftest
_anim_selftest:
    stp x29,x30,[sp,#-48]!
    stp x19,x20,[sp,#16]
    stp x21,x22,[sp,#32]
    mov w19,#1
    bl _game_init
    bl _anim_init
    mov w0,#1
    mov w1,#0
    bl _anim_move
    AG w9,_player_x
    cmp w9,#5
    b.ne Latest_fail
    AG w9,_walk_x
    cmp w9,#160
    b.ne Latest_fail
    mov w0,#1
    mov w1,#0
    bl _anim_move
    AG w9,_player_x
    cmp w9,#5
    b.ne Latest_fail
    mov w0,#7
    bl Latest_ticks
    AG w9,_walk_x
    cmp w9,#188
    b.ne Latest_fail
    AG w9,_walk_remaining
    cmp w9,#1
    b.ne Latest_fail
    bl _anim_tick
    AG w9,_walk_x
    cmp w9,#192
    b.ne Latest_fail
    AG w9,_walk_remaining
    cbnz w9,Latest_fail
    // Walk five reed steps directly, then animate the sixth encounter step.
    mov w19,#2
    bl _game_init
    mov w0,#1
    bl _world_load
    mov w9,#6
    AS w9,_player_x
    mov w9,#2
    AS w9,_player_y
    mov w20,#0
Latest_reeds:
    and w9,w20,#1
    mov w0,#1
    mov w10,#-1
    cmp w9,#0
    csel w0,w0,w10,eq
    mov w1,#0
    bl _game_move
    add w20,w20,#1
    cmp w20,#5
    b.lt Latest_reeds
    bl _anim_init
    mov w0,#-1
    mov w1,#0
    bl _anim_move
    AG w9,_mode
    cmp w9,#1
    b.ne Latest_fail
    AG w9,_visual_mode
    cbnz w9,Latest_fail
    AG w9,_anim_kind
    cmp w9,#2
    b.ne Latest_fail
    mov w0,#17
    bl Latest_ticks
    AG w9,_visual_mode
    cbnz w9,Latest_fail
    bl _anim_tick
    AG w9,_visual_mode
    cmp w9,#1
    b.ne Latest_fail
    mov w0,#17
    bl Latest_ticks
    AG w9,_anim_busy
    cmp w9,#1
    b.ne Latest_fail
    bl _anim_tick
    AG w9,_anim_busy
    cbnz w9,Latest_fail
    // An invalid energy action does not start a presentation or consume a turn.
    mov w19,#3
    bl _game_preview_battle
    AP x9,_team_energy
    str wzr,[x9]
    bl _anim_init
    mov w0,#1
    bl _anim_action
    AG w9,_anim_busy
    cbnz w9,Latest_fail
    AG w9,_battle_turn
    cbnz w9,Latest_fail
    AG w9,_last_event
    cbnz w9,Latest_fail
    // Enemy HP moves at18f, player HP at48f, controls unlock at78f.
    mov w19,#4
    bl _game_preview_battle
    bl _anim_init
    mov w0,#0
    bl _anim_action
    AG w20,_enemy_hp
    AP x9,_team_hp
    ldr w21,[x9]
    AG w9,_visual_enemy_hp
    cmp w9,#56
    b.ne Latest_fail
    AG w9,_visual_player_hp
    cmp w9,#54
    b.ne Latest_fail
    mov w0,#17
    bl Latest_ticks
    AG w9,_visual_enemy_hp
    cmp w9,#56
    b.ne Latest_fail
    bl _anim_tick
    AG w9,_visual_enemy_hp
    cmp w9,w20
    b.ne Latest_fail
    AG w9,_visual_player_hp
    cmp w9,#54
    b.ne Latest_fail
    mov w0,#29
    bl Latest_ticks
    AG w9,_visual_player_hp
    cmp w9,#54
    b.ne Latest_fail
    bl _anim_tick
    AG w9,_visual_player_hp
    cmp w9,w21
    b.ne Latest_fail
    mov w0,#0
    bl _anim_action
    AG w9,_battle_turn
    cmp w9,#1
    b.ne Latest_fail
    mov w0,#29
    bl Latest_ticks
    AG w9,_anim_busy
    cmp w9,#1
    b.ne Latest_fail
    bl _anim_tick
    AG w9,_anim_busy
    cbnz w9,Latest_fail
    // Rewards and result panels wait until78f; dismissal is a36f transition.
    mov w19,#5
    bl _game_preview_battle
    mov w9,#1
    AS w9,_enemy_hp
    AP x9,_team_hp
    mov w10,#20
    str w10,[x9]
    bl _anim_init
    mov w0,#0
    bl _anim_action
    AG w9,_mode
    cmp w9,#2
    b.ne Latest_fail
    AG w9,_visual_mode
    cmp w9,#1
    b.ne Latest_fail
    mov w0,#48
    bl Latest_ticks
    AG w9,_visual_player_hp
    cmp w9,#20
    b.ne Latest_fail
    mov w0,#30
    bl Latest_ticks
    AG w9,_visual_mode
    cmp w9,#2
    b.ne Latest_fail
    AG w9,_visual_player_hp
    cmp w9,#34
    b.ne Latest_fail
    bl _anim_dismiss
    AG w9,_mode
    cbnz w9,Latest_fail
    AG w9,_visual_mode
    cmp w9,#2
    b.ne Latest_fail
    mov w0,#17
    bl Latest_ticks
    AG w9,_visual_mode
    cmp w9,#2
    b.ne Latest_fail
    bl _anim_tick
    AG w9,_visual_mode
    cbnz w9,Latest_fail
    mov w0,#18
    bl Latest_ticks
    AG w9,_anim_busy
    cbnz w9,Latest_fail
    // Guard healing appears before the reduced incoming hit.
    mov w19,#6
    bl _game_preview_battle
    AP x9,_team_hp
    mov w10,#20
    str w10,[x9]
    mov w9,#1
    AS w9,_enemy_intent
    bl _anim_init
    mov w0,#6
    bl _anim_action
    AP x9,_team_hp
    ldr w20,[x9]
    AG w9,_visual_player_hp
    cmp w9,#20
    b.ne Latest_fail
    mov w0,#18
    bl Latest_ticks
    AG w9,_visual_player_hp
    cmp w9,#25
    b.ne Latest_fail
    mov w0,#30
    bl Latest_ticks
    AG w9,_visual_player_hp
    cmp w9,w20
    b.ne Latest_fail
    // Explicit switching immediately shows the selected incoming creature.
    mov w19,#7
    bl _game_preview_battle
    bl Latest_add_party
    bl _anim_init
    mov w0,#4
    bl _anim_action
    AG w9,_visual_active_slot
    cmp w9,#1
    b.ne Latest_fail
    AG w9,_visual_player_hp
    cmp w9,#50
    b.ne Latest_fail
    AP x9,_team_hp
    ldr w20,[x9,#4]
    mov w0,#48
    bl Latest_ticks
    AG w9,_visual_player_hp
    cmp w9,w20
    b.ne Latest_fail
    // Capture result is delayed; Enter uses the animated world return.
    mov w19,#8
    bl _game_preview_battle
    mov w9,#1
    AS w9,_enemy_hp
    bl _anim_init
    mov w0,#2
    bl _anim_action
    AG w9,_last_event
    cmp w9,#3
    b.ne Latest_fail
    AG w9,_mode
    cmp w9,#2
    b.ne Latest_fail
    AG w9,_visual_mode
    cmp w9,#1
    b.ne Latest_fail
    mov w0,#78
    bl Latest_ticks
    AG w9,_visual_mode
    cmp w9,#2
    b.ne Latest_fail
    bl _anim_interact
    AG w9,_anim_kind
    cmp w9,#3
    b.ne Latest_fail
    mov w0,#36
    bl Latest_ticks
    AG w9,_visual_mode
    cbnz w9,Latest_fail
    // Burn ticks during the response, not at the player's initial impact.
    mov w19,#9
    bl _game_preview_battle
    AP x9,_team_species
    mov w10,#1
    str w10,[x9]
    mov w9,#100
    AS w9,_enemy_hp
    AS w9,_enemy_maxhp
    bl _anim_init
    mov w0,#1
    bl _anim_action
    AG w20,_enemy_hp
    AG w21,_last_burn_damage
    cmp w21,#5
    b.ne Latest_fail
    mov w0,#18
    bl Latest_ticks
    AG w9,_visual_enemy_hp
    add w10,w20,w21
    cmp w9,w10
    b.ne Latest_fail
    mov w0,#30
    bl Latest_ticks
    AG w9,_visual_enemy_hp
    cmp w9,w20
    b.ne Latest_fail
    // Automatic replacement reveals the faint at48f and new companion at60f.
    mov w19,#10
    bl _game_preview_battle
    bl Latest_add_party
    AP x9,_team_hp
    mov w10,#1
    str w10,[x9]
    bl _anim_init
    mov w0,#0
    bl _anim_action
    AG w9,_active_slot
    cmp w9,#1
    b.ne Latest_fail
    AG w9,_visual_active_slot
    cbnz w9,Latest_fail
    mov w0,#48
    bl Latest_ticks
    AG w9,_visual_active_slot
    cbnz w9,Latest_fail
    AG w9,_visual_player_hp
    cbnz w9,Latest_fail
    mov w0,#11
    bl Latest_ticks
    AG w9,_visual_active_slot
    cbnz w9,Latest_fail
    bl _anim_tick
    AG w9,_visual_active_slot
    cmp w9,#1
    b.ne Latest_fail
    AG w9,_visual_player_hp
    cmp w9,#50
    b.ne Latest_fail
    // A manually selected fragile target can itself faint during the switch.
    mov w19,#11
    bl _game_preview_battle
    bl Latest_add_party
    AP x9,_team_hp
    mov w10,#1
    str w10,[x9,#4]
    bl _anim_init
    mov w0,#4
    bl _anim_action
    AG w9,_visual_active_slot
    cmp w9,#1
    b.ne Latest_fail
    AG w9,_visual_player_hp
    cmp w9,#1
    b.ne Latest_fail
    mov w0,#48
    bl Latest_ticks
    AG w9,_visual_player_hp
    cbnz w9,Latest_fail
    mov w0,#12
    bl Latest_ticks
    AG w9,_visual_active_slot
    cbnz w9,Latest_fail
    AG w9,_visual_player_hp
    cmp w9,#54
    b.ne Latest_fail
    // Camp recovery must not conceal the whole-party faint before results.
    mov w19,#12
    bl _game_preview_battle
    AP x9,_team_hp
    mov w10,#1
    str w10,[x9]
    bl _anim_init
    mov w0,#0
    bl _anim_action
    mov w0,#48
    bl Latest_ticks
    AG w9,_visual_player_hp
    cbnz w9,Latest_fail
    mov w0,#12
    bl Latest_ticks
    AG w9,_visual_player_hp
    cbnz w9,Latest_fail
    mov w0,#18
    bl Latest_ticks
    AG w9,_visual_mode
    cmp w9,#2
    b.ne Latest_fail
    AG w9,_visual_player_hp
    cmp w9,#54
    b.ne Latest_fail
    // Mode guards prevent fake dismissals and restarted encounter wipes.
    mov w19,#13
    bl _game_init
    bl _anim_init
    bl _anim_dismiss
    AG w9,_anim_busy
    cbnz w9,Latest_fail
    bl _game_preview_battle
    bl _anim_init
    bl _anim_interact
    AG w9,_anim_busy
    cbnz w9,Latest_fail
    // Enemy recovery remains hidden until the enemy response frame.
    mov w19,#14
    bl _game_preview_battle
    mov w9,#2
    AS w9,_enemy_intent
    mov w9,#40
    AS w9,_enemy_hp
    bl _anim_init
    mov w0,#6
    bl _anim_action
    mov w0,#18
    bl Latest_ticks
    AG w9,_visual_enemy_hp
    cmp w9,#40
    b.ne Latest_fail
    mov w0,#30
    bl Latest_ticks
    AG w9,_visual_enemy_hp
    cmp w9,#47
    b.ne Latest_fail
    // Rest feedback lasts exactly45 simulation frames.
    mov w19,#15
    bl _game_init
    mov w9,#5
    AS w9,_player_x
    AS w9,_player_y
    mov w9,#3
    AS w9,_facing
    bl _anim_init
    bl _anim_interact
    AG w9,_world_flash
    cmp w9,#45
    b.ne Latest_fail
    mov w0,#44
    bl Latest_ticks
    AG w9,_world_flash
    cmp w9,#1
    b.ne Latest_fail
    bl _anim_tick
    AG w9,_world_flash
    cbnz w9,Latest_fail
    // Region exits snap interpolation to the new entry and perform one wipe.
    mov w19,#16
    bl _game_init
    mov w9,#21
    AS w9,_player_x
    mov w9,#7
    AS w9,_player_y
    bl _anim_init
    mov w0,#1
    mov w1,#0
    bl _anim_move
    AG w9,_map_id
    cmp w9,#1
    b.ne Latest_fail
    AG w9,_walk_x
    cmp w9,#64
    b.ne Latest_fail
    AG w9,_walk_remaining
    cbnz w9,Latest_fail
    AG w9,_anim_kind
    cmp w9,#4
    b.ne Latest_fail
    mov w0,#36
    bl Latest_ticks
    AG w9,_anim_busy
    cbnz w9,Latest_fail
    // Trainer intermissions return to the next foe instead of the overworld.
    mov w19,#17
    bl Latest_trainer_fixture
    bl _anim_init
    mov w9,#1
    AS w9,_enemy_hp
    mov w0,#0
    bl _anim_action
    mov w0,#78
    bl Latest_ticks
    AG w9,_trainer_flags
    cbnz w9,Latest_fail
    bl _anim_dismiss
    AG w9,_mode
    cmp w9,#1
    b.ne Latest_fail
    AG w9,_trainer_round
    cmp w9,#1
    b.ne Latest_fail
    mov w0,#36
    bl Latest_ticks
    AG w9,_visual_mode
    cmp w9,#1
    b.ne Latest_fail
    // Evolution cannot spoil the outgoing battle sprite or be skipped early.
    mov w19,#18
    bl Latest_trainer_fixture
    AP x9,_team_level
    mov w10,#7
    str w10,[x9]
    AP x9,_team_xp
    mov w10,#9
    str w10,[x9]
    mov w9,#1
    AS w9,_enemy_hp
    bl _anim_init
    mov w0,#0
    bl _anim_action
    AG w9,_mode
    cmp w9,#4
    b.ne Latest_fail
    AG w9,_visual_player_species
    cbnz w9,Latest_fail
    mov w0,#77
    bl Latest_ticks
    AG w9,_visual_mode
    cmp w9,#1
    b.ne Latest_fail
    AG w9,_visual_player_species
    cbnz w9,Latest_fail
    bl _anim_tick
    AG w9,_visual_mode
    cmp w9,#4
    b.ne Latest_fail
    bl _anim_dismiss
    AG w9,_mode
    cmp w9,#4
    b.ne Latest_fail
    mov w0,#149
    bl Latest_ticks
    bl _anim_dismiss
    AG w9,_mode
    cmp w9,#4
    b.ne Latest_fail
    bl _anim_tick
    bl _anim_dismiss
    AG w9,_mode
    cmp w9,#2
    b.ne Latest_fail
    mov w19,#0
Latest_fail:
    bl _game_init
    bl _anim_init
    mov w0,w19
    ldp x19,x20,[sp,#16]
    ldp x21,x22,[sp,#32]
    ldp x29,x30,[sp],#48
    ret

Latest_ticks:
    stp x29,x30,[sp,#-32]!
    str x19,[sp,#16]
    mov w19,w0
Latest_tick_loop:
    cbz w19,Latest_tick_done
    bl _anim_tick
    sub w19,w19,#1
    b Latest_tick_loop
Latest_tick_done:
    ldr x19,[sp,#16]
    ldp x29,x30,[sp],#32
    ret

Latest_trainer_fixture:
    stp x29,x30,[sp,#-16]!
    bl _game_init
    mov w0,#1
    bl _world_load
    mov w9,#7
    AS w9,_player_x
    AS w9,_player_y
    mov w9,#2
    AS w9,_facing
    bl _game_interact
    ldp x29,x30,[sp],#16
    ret

Latest_add_party:
    AP x9,_team_species
    mov w10,#2
    str w10,[x9,#4]
    AP x9,_team_hp
    mov w10,#50
    str w10,[x9,#4]
    AP x9,_team_maxhp
    str w10,[x9,#4]
    AP x9,_team_level
    mov w10,#5
    str w10,[x9,#4]
    ret

.data
.p2align 2
.globl _anim_busy,_anim_kind,_anim_time,_anim_action_id,_visual_mode
.globl _visual_enemy_hp,_visual_player_hp,_visual_active_slot,_walk_x,_walk_y,_walk_remaining,_world_flash
_anim_busy: .long 0
_anim_kind: .long 0
_anim_time: .long 0
_anim_action_id: .long 0
_visual_mode: .long 0
_visual_enemy_hp: .long 0
_visual_player_hp: .long 54
_visual_active_slot: .long 0
.globl _visual_player_species, _evolution_clock
_visual_player_species: .long 0
_evolution_clock: .long 0
_enemy_response_hp: .long 0
_player_response_hp: .long 54
_auto_faint: .long 0
_enemy_mid_hp: .long 0
_player_mid_hp: .long 54
_walk_x: .long 160
_walk_y: .long 498
_walk_dx: .long 0
_walk_dy: .long 0
_walk_remaining: .long 0
_world_flash: .long 0
