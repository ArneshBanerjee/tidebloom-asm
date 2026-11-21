// TIDEBLOOM — all game rules, world state, and combat in AArch64 assembly.
// Apple arm64 ABI; compile with clang. No C or other gameplay source.
// Public API: game_init, game_move(dx,dy), game_interact, game_action(action),
// game_dismiss, game_cycle_lead, game_preview_battle, game_selftest (0=pass).
// Actions: 0 strike,1 elemental pulse,2 bond,3 tonic,4 switch,5 flee,6 guard.
// State integers are signed 32-bit; message and species_names are pointers.
// mode:0 world,1 combat,2 result (Enter dismisses),3 final victory.
// Map 23x15:0 grass,1 water,2 path,3 reeds,4 tree,5 camp,6..8 beacon,9 gate.
// Tiles10 researcher,11 ranger,12 supply cache. NPC tiles are walkable.
// Energy 0..3: strike/guard +1, signatures cost2. Enemy intent0 hit,1 charge,2 mend.
// last_event:0 rejected,1 strike,2 signature,3 bond,4 tonic,5 switch,6 flee,
// 7 guard,8 rest,9 NPC dialog,10 quest reward,11 cache. Outcomes use mode/HP.
// Party arrays have 3 elements; species=-1 means empty. Seven species ids0..6.
// effectiveness[player*7+enemy]:0 normal,1 strong,2 resisted.

.macro ADDR reg, symbol
    adrp \reg, \symbol@PAGE
    add \reg, \reg, \symbol@PAGEOFF
.endmacro
.macro GET reg, symbol
    adrp x16, \symbol@PAGE
    ldr \reg, [x16, \symbol@PAGEOFF]
.endmacro
.macro PUT reg, symbol
    adrp x16, \symbol@PAGE
    str \reg, [x16, \symbol@PAGEOFF]
.endmacro
.macro MESSAGE symbol
    ADDR x9, \symbol
    PUT x9, _message
.endmacro
.macro ENTER
    stp x29, x30, [sp, #-16]!
    mov x29, sp
.endmacro
.macro LEAVE
    ldp x29, x30, [sp], #16
    ret
.endmacro

.text
.p2align 2
.globl _game_init
_game_init:
    ENTER
    mov w9, #0
    PUT w9, _mode
    PUT w9, _steps
    PUT w9, _beacons
    PUT w9, _captures
    PUT w9, _active_slot
    PUT w9, _facing
    PUT w9, _encounter_steps
    PUT w9, _battle_turn
    PUT w9, _last_player_damage
    PUT w9, _last_enemy_damage
    PUT w9, _last_effect
    PUT w9, _guard_charge
    PUT w9, _battle_kind
    PUT w9, _battle_beacon
    PUT w9, _enemy_species
    PUT w9, _enemy_hp
    PUT w9, _enemy_maxhp
    PUT w9, _enemy_level
    PUT w9, _enemy_intent
    PUT w9, _enemy_burn
    PUT w9, _enemy_hex
    PUT w9, _last_event
    PUT w9, _last_heal
    PUT w9, _last_enemy_heal
    PUT w9, _last_burn_damage
    PUT w9, _capture_chance
    PUT w9, _quest_flags
    PUT w9, _lore_page
    ADDR x10, _team_armor
    stp wzr, wzr, [x10]
    str wzr, [x10, #8]
    ADDR x10, _team_energy
    mov w11, #3
    stp w11, w11, [x10]
    str w11, [x10, #8]
    mov w9, #-1
    PUT w9, _caught_species
    mov w9, #4
    PUT w9, _player_x
    mov w9, #12
    PUT w9, _player_y
    mov w9, #3
    PUT w9, _tonics
    mov w9, #8
    PUT w9, _orbs
    movz w9, #0x79f5
    movk w9, #0x6d2b, lsl #16
    PUT w9, _rng_seed
    ADDR x9, _team_species
    mov w10, #0
    mov w11, #-1
    stp w10, w11, [x9]
    str w11, [x9, #8]
    ADDR x9, _team_hp
    mov w10, #54
    stp w10, wzr, [x9]
    str wzr, [x9, #8]
    ADDR x9, _team_maxhp
    stp w10, wzr, [x9]
    str wzr, [x9, #8]
    ADDR x9, _team_level
    mov w10, #5
    stp w10, wzr, [x9]
    str wzr, [x9, #8]
    PUT wzr, _trainer_flags
    PUT wzr, _trainer_pending
    PUT wzr, _trainer_round
    PUT wzr, _home_map
    mov w9, #-1
    PUT w9, _trainer_id
    PUT w9, _evolution_from
    PUT w9, _evolution_to
    PUT w9, _evolution_slot
    PUT wzr, _evolution_return_mode
    mov w9, #60
    PUT w9, _coins
    ADDR x9, _team_xp
    stp wzr, wzr, [x9]
    str wzr, [x9, #8]
    mov w0, #0
    bl _world_load
    MESSAGE _msg_welcome
    LEAVE

// Local deterministic xorshift generator, returns nonnegative w0.
_game_rng:
    GET w9, _rng_seed
    eor w9, w9, w9, lsl #13
    eor w9, w9, w9, lsr #17
    eor w9, w9, w9, lsl #5
    PUT w9, _rng_seed
    and w0, w9, #0x7fffffff
    ret

_game_beacon_count:
    GET w9, _beacons
    and w0, w9, #1
    ubfx w10, w9, #1, #1
    add w0, w0, w10
    ubfx w10, w9, #2, #1
    add w0, w0, w10
    ret

_game_heal_party:
    ADDR x9, _team_hp
    ADDR x10, _team_maxhp
    ldp w11, w12, [x10]
    stp w11, w12, [x9]
    ldr w11, [x10, #8]
    str w11, [x9, #8]
    ADDR x9, _team_energy
    mov w10, #3
    stp w10, w10, [x9]
    str w10, [x9, #8]
    ADDR x9, _team_armor
    stp wzr, wzr, [x9]
    str wzr, [x9, #8]
    ret

// Restore w0 HP to the active companion, exposing the actual amount restored.
_game_heal_active:
    GET w9, _active_slot
    ADDR x10, _team_hp
    ADDR x11, _team_maxhp
    ldr w12, [x10, w9, uxtw #2]
    ldr w13, [x11, w9, uxtw #2]
    add w14, w12, w0
    cmp w14, w13
    csel w14, w14, w13, lt
    str w14, [x10, w9, uxtw #2]
    sub w0, w14, w12
    PUT w0, _last_heal
    ret

_game_charge_energy:
    GET w9, _active_slot
    ADDR x10, _team_energy
    ldr w11, [x10, w9, uxtw #2]
    add w11, w11, #1
    cmp w11, #3
    mov w12, #3
    csel w11, w11, w12, lt
    str w11, [x10, w9, uxtw #2]
    ret

_game_plan_intent:
    GET w9, _enemy_species
    ADDR x10, _species_base
    ldr w9, [x10, w9, uxtw #2]
    GET w10, _battle_turn
    and w10, w10, #3
    lsl w9, w9, #2
    add w9, w9, w10
    ADDR x10, _intent_patterns
    ldrb w11, [x10, w9, uxtw]
    PUT w11, _enemy_intent
    ret

_game_update_capturechance:
    mov w12, #0
    GET w9, _battle_kind
    cbnz w9, Lchance_done
    GET w10, _enemy_hp
    GET w11, _enemy_maxhp
    cbz w11, Lchance_done
    lsl w9, w10, #1
    cmp w9, w11
    b.gt Lchance_done
    sub w10, w11, w10
    mov w9, #60
    mul w10, w10, w9
    udiv w12, w10, w11
    add w12, w12, #40
    cmp w12, #99
    mov w9, #99
    csel w12, w12, w9, lt
Lchance_done:
    PUT w12, _capture_chance
    ret

.globl _game_move
_game_move:
    ENTER
    stp x19, x20, [sp, #-16]!
    GET w9, _mode
    cbnz w9, Lmove_done
    // Direction is updated even if a tree or shoreline blocks the step.
    mov w10, #0
    cmp w1, #0
    mov w11, #3
    csel w10, w11, w10, lt
    cmp w0, #0
    mov w11, #1
    csel w10, w11, w10, lt
    mov w11, #2
    csel w10, w11, w10, gt
    PUT w10, _facing
    GET w9, _player_x
    GET w10, _player_y
    add w19, w9, w0
    add w20, w10, w1
    mov w0, w19
    mov w1, w20
    bl _world_try_exit
    cbnz w0, Lmove_done
    cmp w19, #1
    b.lt Lmove_done
    cmp w19, #21
    b.gt Lmove_done
    cmp w20, #1
    b.lt Lmove_done
    cmp w20, #13
    b.gt Lmove_done
    mov w11, #23
    madd w11, w20, w11, w19
    ADDR x9, _map_data
    ldrb w10, [x9, w11, uxtw]
    cmp w10, #1
    b.eq Lmove_done
    cmp w10, #4
    b.eq Lmove_done
    cmp w10, #17
    b.eq Lmove_done
    cmp w10, #18
    b.eq Lmove_done
    cmp w10, #20
    b.eq Lmove_done
    PUT w19, _player_x
    PUT w20, _player_y
    GET w9, _steps
    add w9, w9, #1
    PUT w9, _steps
    cmp w10, #3
    b.ne Lmove_hint
    GET w9, _encounter_steps
    add w9, w9, #1
    PUT w9, _encounter_steps
    mov w11, #6
    udiv w12, w9, w11
    msub w12, w12, w11, w9
    cbnz w12, Lmove_reeds
    bl _game_rng
    mov w9, #6
    udiv w10, w0, w9
    msub w10, w10, w9, w0
    GET w11, _map_id
    madd w10, w11, w9, w10
    ADDR x9, _wild_tables
    ldrb w0, [x9, w10, uxtw]
    ADDR x9, _wild_levels
    ldr w1, [x9, w11, uxtw #2]
    mov w2, #0
    mov w3, #0
    bl _game_begin
    b Lmove_done
Lmove_reeds:
    MESSAGE _msg_reeds
    b Lmove_done
Lmove_hint:
    cmp w10, #10
    b.ge Lmove_npc
    cmp w10, #5
    b.eq Lmove_camp
    cmp w10, #6
    b.ge Lmove_beacon
    MESSAGE _msg_explore
    b Lmove_done
Lmove_npc:
    MESSAGE _msg_npc_hint
    b Lmove_done
Lmove_camp:
    MESSAGE _msg_camp_hint
    b Lmove_done
Lmove_beacon:
    MESSAGE _msg_beacon_hint
Lmove_done:
    ldp x19, x20, [sp], #16
    LEAVE

// w0,w1 target tile; true if adjacent or standing on it.
_game_near:
    GET w9, _player_x
    GET w10, _player_y
    sub w9, w9, w0
    sub w10, w10, w1
    cmp w9, #0
    cneg w9, w9, lt
    cmp w10, #0
    cneg w10, w10, lt
    add w9, w9, w10
    cmp w9, #1
    cset w0, le
    ret

.globl _game_interact
_game_interact:
    ENTER
    PUT wzr, _last_event
    stp x19, x20, [sp, #-16]!
    GET w9, _mode
    cmp w9, #2
    b.eq Linteract_dismiss
    cmp w9, #4
    b.eq Linteract_dismiss
    cbnz w9, Linteract_done
    bl _world_find_interaction
    cmp w0, #5
    b.eq Linteract_rest
    cmp w0, #10
    b.eq Linteract_researcher
    cmp w0, #11
    b.eq Linteract_ranger
    cmp w0, #12
    b.eq Linteract_cache
    cmp w0, #14
    b.eq Linteract_trainer
    cmp w0, #15
    b.eq Linteract_shop
    cmp w0, #16
    b.eq Linteract_citizen
    cmp w0, #9
    b.eq Linteract_gate
    cmp w0, #6
    b.lt Linteract_nothing
    cmp w0, #8
    b.gt Linteract_nothing
    sub w19, w0, #6
    mov w9, #1
    lsl w9, w9, w19
    GET w10, _beacons
    tst w9, w10
    b.ne Linteract_lit
    ADDR x9, _warden_species
    ldr w0, [x9, w19, uxtw #2]
    mov w9, #3
    mul w1, w19, w9
    add w1, w1, #7
    mov w2, #1
    mov w3, w19
    bl _game_begin
    b Linteract_done
Linteract_rest:
    bl _game_heal_party
    GET w9, _tonics
    cmp w9, #3
    mov w10, #3
    csel w9, w9, w10, gt
    PUT w9, _tonics
    GET w9, _orbs
    cmp w9, #8
    mov w10, #8
    csel w9, w9, w10, gt
    PUT w9, _orbs
    MESSAGE _msg_rested
    mov w9, #8
    PUT w9, _last_event
    b Linteract_done
Linteract_trainer:
    mov w0, w1
    bl _world_trainer_at
    cmp w0, #0
    b.lt Linteract_nothing
    bl _game_start_trainer
    b Linteract_done
Linteract_shop:
    GET w9, _coins
    cmp w9, #25
    b.lt Lshop_poor
    GET w10, _tonics
    cmp w10, #99
    b.ge Lshop_full
    sub w9, w9, #25
    PUT w9, _coins
    add w10, w10, #1
    PUT w10, _tonics
    mov w9, #11
    PUT w9, _last_event
    MESSAGE _msg_shop_bought
    b Linteract_done
Lshop_poor:
    MESSAGE _msg_shop_poor
    b Linteract_done
Lshop_full:
    MESSAGE _msg_shop_full
    b Linteract_done
Linteract_citizen:
    mov w9, #9
    PUT w9, _last_event
    GET w9, _map_id
    cmp w9, #2
    b.eq Lcitizen_port
    cmp w9, #5
    b.eq Lcitizen_peak
    MESSAGE _msg_citizen_home
    b Linteract_done
Lcitizen_port:
    MESSAGE _msg_citizen_port
    b Linteract_done
Lcitizen_peak:
    MESSAGE _msg_citizen_peak
    b Linteract_done
Linteract_lit:
    MESSAGE _msg_lit
    b Linteract_done
Linteract_gate:
    GET w9, _beacons
    cmp w9, #7
    b.ne Linteract_locked
    GET w9, _trainer_flags
    cmp w9, #63
    b.ne Linteract_locked
    mov w0, #6
    mov w1, #16
    mov w2, #2
    mov w3, #0
    bl _game_begin
    b Linteract_done
Linteract_locked:
    MESSAGE _msg_locked
    b Linteract_done
Linteract_nothing:
    MESSAGE _msg_nothing
    b Linteract_done
Linteract_researcher:
    mov w9, #9
    PUT w9, _last_event
    GET w9, _lore_page
    ADDR x10, _lore_messages
    ldr x10, [x10, w9, uxtw #3]
    PUT x10, _message
    add w9, w9, #1
    cmp w9, #3
    csel w9, wzr, w9, ge
    PUT w9, _lore_page
    b Linteract_done
Linteract_ranger:
    mov w9, #9
    PUT w9, _last_event
    GET w9, _quest_flags
    tbnz w9, #0, Lranger_complete
    GET w10, _captures
    cmp w10, #2
    b.lt Lranger_request
    orr w9, w9, #1
    PUT w9, _quest_flags
    ADDR x9, _team_species
    ADDR x10, _team_maxhp
    mov w11, #0
Lranger_buff:
    ldr w12, [x9, w11, uxtw #2]
    cmp w12, #-1
    b.eq Lranger_skip
    ldr w12, [x10, w11, uxtw #2]
    add w12, w12, #8
    str w12, [x10, w11, uxtw #2]
Lranger_skip:
    add w11, w11, #1
    cmp w11, #3
    b.lt Lranger_buff
    bl _game_heal_party
    mov w9, #10
    PUT w9, _last_event
    MESSAGE _msg_ranger_reward
    b Linteract_done
Lranger_request:
    MESSAGE _msg_ranger_quest
    b Linteract_done
Lranger_complete:
    MESSAGE _msg_ranger_complete
    b Linteract_done
Linteract_cache:
    GET w9, _quest_flags
    tbnz w9, #1, Lcache_empty
    orr w9, w9, #2
    PUT w9, _quest_flags
    GET w9, _tonics
    add w9, w9, #2
    PUT w9, _tonics
    GET w9, _orbs
    add w9, w9, #4
    PUT w9, _orbs
    mov w9, #11
    PUT w9, _last_event
    MESSAGE _msg_cache
    b Linteract_done
Lcache_empty:
    mov w9, #9
    PUT w9, _last_event
    MESSAGE _msg_cache_empty
    b Linteract_done
Linteract_dismiss:
    bl _game_dismiss
Linteract_done:
    ldp x19, x20, [sp], #16
    LEAVE

.globl _game_start_trainer
_game_start_trainer:
    ENTER
    cmp w0, #5
    b.hi Ltrainer_start_done
    mov w9, #1
    lsl w9, w9, w0
    GET w10, _trainer_flags
    tst w9, w10
    b.ne Ltrainer_already
    PUT w0, _trainer_id
    PUT wzr, _trainer_round
    PUT wzr, _trainer_pending
    bl _game_next_trainer
    b Ltrainer_start_done
Ltrainer_already:
    MESSAGE _msg_trainer_done
Ltrainer_start_done:
    LEAVE

_game_next_trainer:
    ENTER
    GET w9, _trainer_id
    GET w10, _trainer_round
    lsl w9, w9, #1
    add w9, w9, w10
    ADDR x10, _trainer_species
    ldr w0, [x10, w9, uxtw #2]
    ADDR x10, _trainer_levels
    ldr w1, [x10, w9, uxtw #2]
    mov w2, #3
    mov w3, #0
    bl _game_begin
    MESSAGE _msg_trainer_start
    LEAVE

// Start battle: w0 species,w1 level,w2 kind,w3 beacon index.
.globl _game_begin
_game_begin:
    ENTER
    PUT w0, _enemy_species
    PUT w1, _enemy_level
    PUT w2, _battle_kind
    PUT w3, _battle_beacon
    mov w9, #6
    mul w9, w1, w9
    add w9, w9, #32
    cmp w2, #1
    add w10, w9, #12
    csel w9, w10, w9, eq
    cmp w2, #3
    add w10, w9, #18
    csel w9, w10, w9, eq
    cmp w0, #7
    add w10, w9, #18
    csel w9, w10, w9, ge
    cmp w2, #2
    mov w10, #220
    csel w9, w10, w9, eq
    PUT w9, _enemy_hp
    PUT w9, _enemy_maxhp
    mov w9, #1
    PUT w9, _mode
    mov w9, #0
    PUT w9, _battle_turn
    PUT w9, _last_player_damage
    PUT w9, _last_enemy_damage
    PUT w9, _last_effect
    PUT w9, _guard_charge
    PUT w9, _enemy_burn
    PUT w9, _enemy_hex
    PUT w9, _last_heal
    PUT w9, _last_enemy_heal
    PUT w9, _last_burn_damage
    PUT w9, _last_event
    ADDR x10, _team_armor
    stp wzr, wzr, [x10]
    str wzr, [x10, #8]
    mov w9, #-1
    PUT w9, _caught_species
    MESSAGE _msg_wild
    cmp w2, #1
    b.ne Lbegin_boss
    MESSAGE _msg_warden
Lbegin_boss:
    cmp w2, #2
    b.ne Lbegin_done
    MESSAGE _msg_boss
Lbegin_done:
    bl _game_plan_intent
    bl _game_update_capturechance
    LEAVE

.globl _game_preview_battle
_game_preview_battle:
    ENTER
    bl _game_init
    mov w0, #1
    mov w1, #4
    mov w2, #0
    mov w3, #0
    bl _game_begin
    LEAVE

.globl _game_dismiss
_game_dismiss:
    ENTER
    GET w9, _mode
    cmp w9, #4
    b.eq Ldismiss_evolution
    cmp w9, #2
    b.ne Ldismiss_done
    GET w9, _trainer_pending
    cbnz w9, Ldismiss_trainer
    PUT wzr, _mode
    MESSAGE _msg_explore
    b Ldismiss_done
Ldismiss_evolution:
    GET w9, _evolution_return_mode
    PUT w9, _mode
    MESSAGE _msg_evolution_done
    b Ldismiss_done
Ldismiss_trainer:
    PUT wzr, _trainer_pending
    mov w9, #1
    PUT w9, _trainer_round
    bl _game_next_trainer
Ldismiss_done:
    LEAVE

// World-only party cycling, no retaliation and no time cost.
.globl _game_cycle_lead
_game_cycle_lead:
    GET w9, _mode
    cbnz w9, Lcycle_done
    GET w10, _active_slot
    mov w11, #1
    ADDR x12, _team_hp
Lcycle_loop:
    add w13, w10, w11
    cmp w13, #3
    sub w14, w13, #3
    csel w13, w14, w13, ge
    ldr w14, [x12, w13, uxtw #2]
    cbnz w14, Lcycle_found
    add w11, w11, #1
    cmp w11, #3
    b.lt Lcycle_loop
    MESSAGE _msg_no_switch
    b Lcycle_done
Lcycle_found:
    PUT w13, _active_slot
    MESSAGE _msg_world_switch
Lcycle_done:
    ret

.globl _game_action
_game_action:
    ENTER
    PUT wzr, _last_event
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    GET w9, _mode
    cmp w9, #1
    b.ne Laction_done
    mov w19, w0
    GET w20, _active_slot
    mov w9, #0
    PUT w9, _last_player_damage
    PUT w9, _last_enemy_damage
    PUT w9, _last_effect
    PUT w9, _last_event
    PUT w9, _last_heal
    PUT w9, _last_enemy_heal
    PUT w9, _last_burn_damage
    cmp w19, #0
    b.eq Laction_strike
    cmp w19, #1
    b.eq Laction_pulse
    cmp w19, #2
    b.eq Laction_bond
    cmp w19, #3
    b.eq Laction_tonic
    cmp w19, #4
    b.eq Laction_switch
    cmp w19, #5
    b.eq Laction_flee
    cmp w19, #6
    b.eq Laction_guard
    b Laction_done
Laction_strike:
    mov w9, #1
    PUT w9, _last_event
    bl _game_charge_energy
    ADDR x9, _team_level
    ldr w21, [x9, w20, uxtw #2]
    lsl w21, w21, #1
    add w21, w21, #7
    ADDR x9, _team_species
    ldr w10, [x9, w20, uxtw #2]
    cmp w10, #7
    add w11, w21, #6
    csel w21, w11, w21, ge
    MESSAGE _msg_strike
    b Laction_damage
Laction_pulse:
    ADDR x9, _team_energy
    ldr w10, [x9, w20, uxtw #2]
    cmp w10, #2
    b.lt Lsignature_empty
    sub w10, w10, #2
    str w10, [x9, w20, uxtw #2]
    mov w9, #2
    PUT w9, _last_event
    ADDR x9, _team_level
    ldr w21, [x9, w20, uxtw #2]
    lsl w21, w21, #1
    add w21, w21, #13
    ADDR x9, _team_species
    ldr w22, [x9, w20, uxtw #2]
    cmp w22, #7
    add w10, w21, #6
    csel w21, w10, w21, ge
    ADDR x9, _species_base
    ldr w22, [x9, w22, uxtw #2]
    GET w11, _enemy_species
    ldr w11, [x9, w11, uxtw #2]
    mov w12, #7
    madd w10, w22, w12, w11
    ADDR x9, _effectiveness
    ldrb w10, [x9, w10, uxtw]
    PUT w10, _last_effect
    ADDR x9, _signature_messages
    ldr x9, [x9, w22, uxtw #3]
    PUT x9, _message
    cmp w10, #1
    b.eq Laction_strong
    cmp w10, #2
    b.ne Lsignature_apply
    lsr w21, w21, #1
    b Lsignature_apply
Laction_strong:
    add w21, w21, #10
Lsignature_apply:
    cmp w22, #0
    b.eq Lsignature_sprig
    cmp w22, #1
    b.eq Lsignature_cinder
    cmp w22, #2
    b.eq Lsignature_rill
    cmp w22, #3
    b.eq Lsignature_crag
    cmp w22, #4
    b.eq Lsignature_glim
    cmp w22, #5
    b.eq Lsignature_zeph
    b Laction_damage
Lsignature_sprig:
    mov w0, #10
    bl _game_heal_active
    b Laction_damage
Lsignature_cinder:
    mov w9, #3
    PUT w9, _enemy_burn
    b Laction_damage
Lsignature_rill:
    mov w0, #18
    bl _game_heal_active
    b Laction_damage
Lsignature_crag:
    ADDR x9, _team_armor
    mov w10, #2
    str w10, [x9, w20, uxtw #2]
    b Laction_damage
Lsignature_glim:
    mov w9, #2
    PUT w9, _enemy_hex
    mov w0, #8
    bl _game_heal_active
    b Laction_damage
Lsignature_zeph:
    bl _game_charge_energy
    GET w9, _enemy_intent
    cmp w9, #1
    add w10, w21, #12
    csel w21, w10, w21, eq
    b Laction_damage
Lsignature_empty:
    MESSAGE _msg_no_energy
    b Laction_done
Laction_damage:
    bl _game_rng
    and w0, w0, #3
    add w21, w21, w0
    GET w9, _guard_charge
    add w21, w21, w9
    PUT wzr, _guard_charge
    PUT w21, _last_player_damage
    GET w9, _enemy_hp
    sub w9, w9, w21
    cmp w9, #0
    csel w9, wzr, w9, le
    PUT w9, _enemy_hp
    cbz w9, Laction_win
    mov w0, #0
    bl _game_enemy_turn
    b Laction_done
Laction_win:
    bl _game_victory
    b Laction_done
Laction_bond:
    GET w9, _battle_kind
    cbnz w9, Lbond_warden
    ADDR x9, _team_species
    mov w21, #0
Lbond_slot:
    ldr w10, [x9, w21, uxtw #2]
    cmp w10, #-1
    b.eq Lbond_check
    add w21, w21, #1
    cmp w21, #3
    b.lt Lbond_slot
    MESSAGE _msg_party_full
    b Laction_done
Lbond_check:
    GET w9, _orbs
    cbz w9, Lbond_empty
    GET w10, _enemy_hp
    GET w11, _enemy_maxhp
    lsl w12, w10, #1
    cmp w12, w11
    b.gt Lbond_weaken
    sub w9, w9, #1
    PUT w9, _orbs
    mov w9, #3
    PUT w9, _last_event
    sub w10, w11, w10
    mov w12, #60
    mul w10, w10, w12
    udiv w22, w10, w11
    add w22, w22, #40
    bl _game_rng
    mov w9, #100
    udiv w10, w0, w9
    msub w10, w10, w9, w0
    cmp w10, w22
    b.ge Lbond_failed
    ADDR x9, _team_species
    GET w10, _enemy_species
    str w10, [x9, w21, uxtw #2]
    PUT w10, _caught_species
    GET w10, _enemy_level
    ADDR x9, _team_level
    str w10, [x9, w21, uxtw #2]
    GET w10, _enemy_maxhp
    ADDR x9, _team_maxhp
    str w10, [x9, w21, uxtw #2]
    ADDR x9, _team_hp
    str w10, [x9, w21, uxtw #2]
    ADDR x9, _team_energy
    mov w10, #3
    str w10, [x9, w21, uxtw #2]
    GET w9, _captures
    add w9, w9, #1
    PUT w9, _captures
    mov w9, #2
    PUT w9, _mode
    mov w9, #3
    PUT w9, _last_effect
    MESSAGE _msg_bonded
    b Laction_done
Lbond_failed:
    MESSAGE _msg_bond_failed
    mov w0, #0
    bl _game_enemy_turn
    b Laction_done
Lbond_warden:
    MESSAGE _msg_no_warden_bond
    b Laction_done
Lbond_empty:
    MESSAGE _msg_no_orbs
    b Laction_done
Lbond_weaken:
    MESSAGE _msg_weaken
    b Laction_done
Laction_tonic:
    GET w9, _tonics
    cbz w9, Ltonic_empty
    ADDR x10, _team_hp
    ADDR x11, _team_maxhp
    ldr w12, [x10, w20, uxtw #2]
    mov w14, w12
    ldr w13, [x11, w20, uxtw #2]
    cmp w12, w13
    b.ge Ltonic_full
    sub w9, w9, #1
    PUT w9, _tonics
    add w12, w12, #32
    cmp w12, w13
    csel w12, w12, w13, lt
    str w12, [x10, w20, uxtw #2]
    sub w14, w12, w14
    PUT w14, _last_heal
    mov w9, #4
    PUT w9, _last_event
    MESSAGE _msg_tonic
    mov w0, #0
    bl _game_enemy_turn
    b Laction_done
Ltonic_empty:
    MESSAGE _msg_no_tonics
    b Laction_done
Ltonic_full:
    MESSAGE _msg_hp_full
    b Laction_done
Laction_switch:
    mov w21, #1
Lswitch_loop:
    add w10, w20, w21
    cmp w10, #3
    sub w11, w10, #3
    csel w10, w11, w10, ge
    ADDR x9, _team_hp
    ldr w11, [x9, w10, uxtw #2]
    cbnz w11, Lswitch_found
    add w21, w21, #1
    cmp w21, #3
    b.lt Lswitch_loop
    MESSAGE _msg_no_switch
    b Laction_done
Lswitch_found:
    PUT w10, _active_slot
    mov w9, #5
    PUT w9, _last_event
    MESSAGE _msg_switch
    mov w0, #2
    bl _game_enemy_turn
    b Laction_done
Laction_flee:
    GET w9, _battle_kind
    cbnz w9, Lflee_denied
    mov w9, #2
    PUT w9, _mode
    mov w9, #6
    PUT w9, _last_event
    MESSAGE _msg_fled
    b Laction_done
Lflee_denied:
    MESSAGE _msg_no_flee
    b Laction_done
Laction_guard:
    mov w9, #7
    PUT w9, _last_event
    bl _game_charge_energy
    mov w0, #5
    bl _game_heal_active
    mov w9, #4
    PUT w9, _last_effect
    mov w9, #12
    PUT w9, _guard_charge
    MESSAGE _msg_guard
    mov w0, #1
    bl _game_enemy_turn
Laction_done:
    bl _game_update_capturechance
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    LEAVE

// Resolve the telegraphed enemy action. w0:0 normal,1 guard,2 safe switch.
_game_enemy_turn:
    ENTER
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    mov w19, w0
    GET w9, _battle_turn
    add w9, w9, #1
    PUT w9, _battle_turn
    // Burning ticks before the enemy acts and can end the encounter.
    GET w9, _enemy_burn
    cbz w9, Lenemy_intent
    sub w9, w9, #1
    PUT w9, _enemy_burn
    GET w10, _enemy_hp
    sub w10, w10, #5
    cmp w10, #0
    csel w10, wzr, w10, le
    PUT w10, _enemy_hp
    mov w9, #5
    PUT w9, _last_burn_damage
    cbnz w10, Lenemy_intent
    bl _game_victory
    b Lenemy_done
Lenemy_intent:
    GET w21, _enemy_intent
    cmp w21, #2
    b.eq Lenemy_recover
    bl _game_rng
    and w20, w0, #3
    GET w9, _enemy_level
    add w20, w20, w9
    add w20, w20, #5
    cmp w21, #1
    b.ne Lenemy_hex
    lsr w9, w20, #1
    add w20, w20, w9
    add w20, w20, #3
Lenemy_hex:
    GET w9, _enemy_hex
    cbz w9, Lenemy_guard
    sub w9, w9, #1
    PUT w9, _enemy_hex
    sub w20, w20, #5
    cmp w20, #2
    mov w10, #2
    csel w20, w20, w10, gt
Lenemy_guard:
    cbz w19, Lenemy_armor
    lsr w20, w20, #1
    cmp w19, #1
    b.ne Lenemy_armor
    cmp w21, #1
    b.ne Lenemy_armor
    lsr w20, w20, #1
Lenemy_armor:
    GET w22, _active_slot
    ADDR x9, _team_armor
    ldr w10, [x9, w22, uxtw #2]
    cbz w10, Lenemy_apply
    sub w10, w10, #1
    str w10, [x9, w22, uxtw #2]
    lsr w20, w20, #1
Lenemy_apply:
    cmp w20, #1
    mov w9, #1
    csel w20, w20, w9, gt
    PUT w20, _last_enemy_damage
    ADDR x9, _team_hp
    ldr w10, [x9, w22, uxtw #2]
    sub w10, w10, w20
    cmp w10, #0
    csel w10, wzr, w10, le
    str w10, [x9, w22, uxtw #2]
    cbnz w10, Lenemy_next
    mov w11, #0
Lenemy_party:
    ldr w10, [x9, w11, uxtw #2]
    cbnz w10, Lenemy_replacement
    add w11, w11, #1
    cmp w11, #3
    b.lt Lenemy_party
    bl _game_heal_party
    GET w0, _home_map
    bl _world_load
    mov w9, #5
    PUT w9, _player_x
    PUT w9, _player_y
    PUT wzr, _trainer_pending
    mov w9, #0
    PUT w9, _active_slot
    mov w9, #2
    PUT w9, _mode
    mov w9, #3
    PUT w9, _tonics
    mov w9, #8
    PUT w9, _orbs
    MESSAGE _msg_blackout
    b Lenemy_done
Lenemy_replacement:
    PUT w11, _active_slot
    MESSAGE _msg_fainted
    b Lenemy_next
Lenemy_recover:
    GET w9, _enemy_maxhp
    lsr w10, w9, #3
    GET w11, _enemy_hp
    add w12, w11, w10
    cmp w12, w9
    csel w12, w12, w9, lt
    PUT w12, _enemy_hp
    sub w12, w12, w11
    PUT w12, _last_enemy_heal
Lenemy_next:
    bl _game_plan_intent
Lenemy_done:
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    LEAVE

_game_victory:
    ENTER
    stp x19, x20, [sp, #-16]!
    GET w19, _active_slot
    GET w20, _battle_kind
    mov w9, #2
    PUT w9, _mode
    mov w0, #3
    cmp w20, #1
    mov w9, #7
    csel w0, w9, w0, eq
    cmp w20, #3
    mov w9, #5
    csel w0, w9, w0, eq
    bl _game_award_xp
    // Every win patches up the active companion; rest restores the whole party.
    GET w19, _last_heal
    mov w0, #14
    bl _game_heal_active
    PUT w19, _last_heal // Preserve signature healing; reward healing waits for results.
    cmp w20, #3
    b.eq Lvictory_trainer
    cbz w20, Lvictory_wild
    cmp w20, #2
    b.eq Lvictory_final
    GET w9, _battle_beacon
    mov w10, #1
    lsl w10, w10, w9
    GET w9, _beacons
    orr w9, w9, w10
    PUT w9, _beacons
    GET w9, _coins
    add w9, w9, #60
    PUT w9, _coins
    bl _game_heal_party
    GET w9, _tonics
    cmp w9, #3
    mov w10, #3
    csel w9, w9, w10, gt
    PUT w9, _tonics
    GET w9, _orbs
    cmp w9, #8
    mov w10, #8
    csel w9, w9, w10, gt
    PUT w9, _orbs
    MESSAGE _msg_beacon_won
    b Lvictory_evolve
Lvictory_trainer:
    GET w9, _trainer_round
    cbnz w9, Ltrainer_final_foe
    mov w9, #1
    PUT w9, _trainer_pending
    MESSAGE _msg_trainer_next
    b Lvictory_evolve
Ltrainer_final_foe:
    GET w9, _trainer_id
    mov w10, #1
    lsl w10, w10, w9
    GET w11, _trainer_flags
    orr w11, w11, w10
    PUT w11, _trainer_flags
    mov w10, #10
    mul w9, w9, w10
    add w9, w9, #45
    GET w10, _coins
    add w10, w10, w9
    PUT w10, _coins
    PUT wzr, _trainer_pending
    MESSAGE _msg_trainer_won
    b Lvictory_evolve
Lvictory_wild:
    GET w9, _coins
    add w9, w9, #8
    PUT w9, _coins
    MESSAGE _msg_wild_won
    b Lvictory_evolve
Lvictory_final:
    bl _game_heal_party
    mov w9, #3
    PUT w9, _mode
    MESSAGE _msg_final
Lvictory_evolve:
    bl _game_check_evolution
    ldp x19, x20, [sp], #16
    LEAVE

// XP threshold is current level+3. The active companion gains5 maxHP per level.
_game_award_xp:
    GET w9, _active_slot
    ADDR x10, _team_xp
    ldr w11, [x10, w9, uxtw #2]
    add w11, w11, w0
    ADDR x12, _team_level
    ldr w13, [x12, w9, uxtw #2]
Lxp_loop:
    add w14, w13, #3
    cmp w11, w14
    b.lt Lxp_done
    cmp w13, #99
    b.ge Lxp_done
    sub w11, w11, w14
    add w13, w13, #1
    str w13, [x12, w9, uxtw #2]
    ADDR x14, _team_maxhp
    ldr w15, [x14, w9, uxtw #2]
    add w15, w15, #5
    str w15, [x14, w9, uxtw #2]
    ADDR x14, _team_hp
    ldr w15, [x14, w9, uxtw #2]
    add w15, w15, #5
    str w15, [x14, w9, uxtw #2]
    b Lxp_loop
Lxp_done:
    str w11, [x10, w9, uxtw #2]
    ret

_game_check_evolution:
    GET w9, _active_slot
    ADDR x10, _team_species
    ldr w11, [x10, w9, uxtw #2]
    cmp w11, #5
    b.hi Levolve_done
    ADDR x12, _team_level
    ldr w13, [x12, w9, uxtw #2]
    cmp w13, #8
    b.lt Levolve_done
    PUT w11, _evolution_from
    PUT w9, _evolution_slot
    add w11, w11, #7
    PUT w11, _evolution_to
    str w11, [x10, w9, uxtw #2]
    ADDR x10, _team_maxhp
    ldr w11, [x10, w9, uxtw #2]
    add w11, w11, #18
    str w11, [x10, w9, uxtw #2]
    ADDR x10, _team_hp
    ldr w11, [x10, w9, uxtw #2]
    add w11, w11, #18
    str w11, [x10, w9, uxtw #2]
    GET w9, _mode
    PUT w9, _evolution_return_mode
    mov w9, #4
    PUT w9, _mode
    MESSAGE _msg_evolution
Levolve_done:
    ret


.data
.p2align 3
.globl _signature_names, _enemy_intent_names
_signature_names: .quad _sig_sprig, _sig_cinder, _sig_rill, _sig_crag, _sig_glim, _sig_zeph, _sig_auralith, _sig_sprig, _sig_cinder, _sig_rill, _sig_crag, _sig_glim, _sig_zeph
_signature_messages: .quad _msg_sig_sprig, _msg_sig_cinder, _msg_sig_rill, _msg_sig_crag, _msg_sig_glim, _msg_sig_zeph, _msg_pulse
_enemy_intent_names:
.quad _intent_leaf_hit, _intent_leaf_charge, _intent_leaf_mend
.quad _intent_fire_hit, _intent_fire_charge, _intent_fire_mend
.quad _intent_tide_hit, _intent_tide_charge, _intent_tide_mend
.quad _intent_stone_hit, _intent_stone_charge, _intent_stone_mend
.quad _intent_spirit_hit, _intent_spirit_charge, _intent_spirit_mend
.quad _intent_sky_hit, _intent_sky_charge, _intent_sky_mend
.quad _intent_ancient_hit, _intent_ancient_charge, _intent_ancient_mend
.quad _intent_leaf_hit, _intent_leaf_charge, _intent_leaf_mend
.quad _intent_fire_hit, _intent_fire_charge, _intent_fire_mend
.quad _intent_tide_hit, _intent_tide_charge, _intent_tide_mend
.quad _intent_stone_hit, _intent_stone_charge, _intent_stone_mend
.quad _intent_spirit_hit, _intent_spirit_charge, _intent_spirit_mend
.quad _intent_sky_hit, _intent_sky_charge, _intent_sky_mend
_lore_messages: .quad _msg_lore_energy, _msg_lore_elements, _msg_lore_intent
.globl _message
_message: .quad _msg_welcome
.globl _species_names
_species_names: .quad _name_sprig, _name_cinder, _name_rill, _name_crag, _name_glim, _name_zeph, _name_auralith, _name_verdant, _name_pyrelume, _name_tiderune, _name_bastion, _name_noctilume, _name_zephyrion
.globl _element_names
_element_names: .quad _name_leaf, _name_flame, _name_tide, _name_stone, _name_spirit, _name_sky, _name_ancient
.p2align 2
.globl _mode, _player_x, _player_y, _facing, _steps, _beacons, _captures
.globl _tonics, _orbs, _active_slot, _team_species, _team_hp, _team_maxhp, _team_level
.globl _enemy_species, _enemy_hp, _enemy_maxhp, _enemy_level, _battle_kind, _battle_beacon
.globl _battle_turn, _caught_species, _last_player_damage, _last_enemy_damage, _last_effect
.globl _species_elements
_mode: .long 0
_player_x: .long 4
_player_y: .long 12
_facing: .long 0
_steps: .long 0
_beacons: .long 0
_captures: .long 0
_tonics: .long 3
_orbs: .long 8
_active_slot: .long 0
_team_species: .long 0,-1,-1
_team_hp: .long 54,0,0
_team_maxhp: .long 54,0,0
_team_level: .long 5,0,0
_enemy_species: .long 1
_enemy_hp: .long 56
_enemy_maxhp: .long 56
_enemy_level: .long 4
_battle_kind: .long 0
_battle_beacon: .long 0
_battle_turn: .long 0
_caught_species: .long -1
_last_player_damage: .long 0
_last_enemy_damage: .long 0
_last_effect: .long 0
_species_elements: .long 0,1,2,3,4,5,6,0,1,2,3,4,5
.globl _species_base
_species_base: .long 0,1,2,3,4,5,6,0,1,2,3,4,5
_warden_species: .long 2,3,5
.globl _team_energy, _team_armor, _enemy_intent, _enemy_burn, _enemy_hex
.globl _last_event, _last_heal, _last_enemy_heal, _last_burn_damage, _capture_chance, _quest_flags
_team_energy: .long 3,3,3
_team_armor: .long 0,0,0
_enemy_intent: .long 0
_enemy_burn: .long 0
_enemy_hex: .long 0
_last_event: .long 0
_last_heal: .long 0
_last_enemy_heal: .long 0
_last_burn_damage: .long 0
_capture_chance: .long 0
_quest_flags: .long 0
_lore_page: .long 0
.globl _coins, _trainer_flags, _trainer_id, _trainer_round, _trainer_pending
.globl _evolution_from, _evolution_to, _evolution_slot, _evolution_return_mode, _team_xp
_coins: .long 60
_trainer_flags: .long 0
_trainer_id: .long -1
_trainer_round: .long 0
_trainer_pending: .long 0
_evolution_from: .long -1
_evolution_to: .long -1
_evolution_slot: .long -1
_evolution_return_mode: .long 0
_team_xp: .long 0,0,0
_guard_charge: .long 0
_encounter_steps: .long 0
_rng_seed: .long 0x6d2b79f5

.section __TEXT,__const
_intent_patterns:
.byte 0,1,0,2 // Sprig: lash, surge, lash, roots
.byte 0,1,0,2 // Cinder: claw, firestorm, claw, stoke
.byte 0,2,1,0 // Rill: ripple, renew, crash, ripple
.byte 1,0,2,1 // Crag: avalanche, tap, reforge, avalanche
.byte 0,1,2,0 // Glim: spark, flare, dream, spark
.byte 0,0,1,2 // Zeph: gust, gust, dive, wind
.byte 0,1,0,2 // Auralith: shard, eclipse, shard, mend
.p2align 2
_wild_tables:
.byte 0,1,2,0,1,2
.byte 0,1,2,5,1,2
.byte 1,2,3,1,2,3
.byte 1,3,5,3,1,5
.byte 4,2,5,4,2,0
.byte 4,5,3,4,5,3
.p2align 2
_wild_levels: .long 3,4,7,8,10,12
.globl _trainer_species, _trainer_levels
_trainer_species: .long 1,2,4,5,3,1,5,2,4,3,8,12
_trainer_levels: .long 5,6,6,7,8,9,9,10,11,12,12,13
_test_signature_heals: .long 10,0,18,0,8,0
_test_coords: .long 5,3,17,4,17,11,11,2
_test_masks: .long 1,3,7,7
.globl _effectiveness
_effectiveness:
// Enemy: leaf flame tide stone spirit sky ancient
.byte 0,2,1,1,0,2,0  // leaf
.byte 1,0,2,2,1,0,0  // flame
.byte 2,1,0,1,0,0,1  // tide
.byte 2,1,2,0,2,1,0  // stone
.byte 0,2,0,1,0,1,1  // spirit
.byte 1,0,0,2,2,0,0  // sky
.byte 0,0,2,0,2,0,0  // ancient

.section __TEXT,__cstring,cstring_literals
_name_sprig: .asciz "SPRIG"
_name_cinder: .asciz "CINDER"
_name_rill: .asciz "RILL"
_name_crag: .asciz "CRAG"
_name_glim: .asciz "GLIM"
_name_zeph: .asciz "ZEPH"
_name_auralith: .asciz "AURALITH"
_name_leaf: .asciz "LEAF"
_name_flame: .asciz "FLAME"
_name_tide: .asciz "TIDE"
_name_stone: .asciz "STONE"
_name_spirit: .asciz "SPIRIT"
_name_sky: .asciz "SKY"
_name_ancient: .asciz "ANCIENT"
_msg_welcome: .asciz "Your journey begins in Brinewick with your companion Sprig.\nExplore east: six trainers, three beacons, and a lost song."
_msg_explore: .asciz "Follow the road east. Town clinics restore your party.\nMeet wild companions, challenge trainers, and seek the beacons."
_msg_reeds: .asciz "Something stirs in the reeds...\nKeep exploring to meet a wild companion."
_msg_camp_hint: .asciz "A warm light and a safe place to rest.\nPress ENTER to heal and replenish tonics and bond orbs."
_msg_beacon_hint: .asciz "A quiet monument hums beneath your feet.\nPress ENTER to awaken its guardian."
_msg_rested: .asciz "Your companions are rested and ready.\nHealth and energy restored. Tonics and orbs replenished."
_msg_lit: .asciz "This beacon sings again. Its light guides the island.\nSeek the other beacons, then visit the northern gate."
_msg_locked: .asciz "The northern gate sleeps beneath three silent stars.\nRelight all three beacons to awaken Auralith."
_msg_nothing: .asciz "Stand beside a trainer, doorway or beacon and press ENTER.\nEast and west road signs connect the island's six regions."
_msg_wild: .asciz "A wild creature emerges from the reeds!\nWeaken it below half health, then use a bond orb."
_msg_warden: .asciz "The beacon's warden answers your call.\nWin this battle to restore a piece of the island's song."
_msg_boss: .asciz "Auralith rises where the three lights meet.\nOne final battle will bring the island's song home."
_msg_strike: .asciz "A quick strike builds +1 energy for your signature.\nRead the next enemy intent before choosing your move."
_msg_pulse: .asciz "Elemental energy ripples across the clearing.\nYour opponent answers. Choose your next move."
_msg_strong: .asciz "A perfect match! Your elemental pulse strikes hard.\nYour opponent answers. Keep the advantage."
_msg_resisted: .asciz "Your opponent resists that element.\nTry a strike or switch to another companion."
_msg_party_full: .asciz "Your three-companion party is full.\nWin this battle or retreat to keep exploring."
_msg_no_warden_bond: .asciz "This guardian is bound to the island.\nDefeat it in battle to restore its ancient light."
_msg_no_orbs: .asciz "No bond orbs remain.\nVisit the camp to replenish your supplies."
_msg_weaken: .asciz "Its spirit is too strong to form a bond yet.\nLower its health to half or less, then try again."
_msg_bonded: .asciz "A new friendship blooms! It joins your party.\nPress ENTER to return to the island."
_msg_bond_failed: .asciz "The bond orb flickers, but the creature breaks free.\nLower its health further for a stronger chance."
_msg_tonic: .asciz "A bright tonic restores up to 32 health.\nYour opponent takes its turn."
_msg_no_tonics: .asciz "Your tonic pouch is empty.\nRest at camp or restore a beacon to replenish it."
_msg_hp_full: .asciz "Your companion is already at full health.\nChoose a move or switch to another companion."
_msg_no_switch: .asciz "No other companion is ready to fight.\nBond with wild creatures to grow your party."
_msg_switch: .asciz "Another companion takes the field.\nA careful handoff softens the next enemy attack."
_msg_world_switch: .asciz "A new companion takes the lead.\nYour lead companion enters the next battle."
_msg_fled: .asciz "You slip safely back into the reeds.\nPress ENTER to continue your journey."
_msg_no_flee: .asciz "The guardian's challenge must be seen through.\nUse a tonic, switch companions, or hold your ground."
_msg_guard: .asciz "Brace: +1 energy, +5 HP and a stronger next attack.\nBlock HALF normal damage or THREE QUARTERS of a charge."
_msg_fainted: .asciz "Your companion needs a rest. Another steps forward!\nUse a tonic or choose your next move."
_msg_blackout: .asciz "Your weary party finds its way back to camp.\nEveryone is restored. Press ENTER to try again."
_msg_beacon_won: .asciz "The beacon awakens! Earned 7 experience and 60 coins.\nParty healed and supplies restored. Press ENTER."
_msg_gate_open: .asciz "All three beacons sing! The northern gate opens.\nYour party is restored. Seek Auralith. Press ENTER."
_msg_wild_won: .asciz "Victory! Earned 3 experience and 8 coins.\nYour companion recovers a little health. Press ENTER."
_msg_final: .asciz "The island sings again. You and your companions did it.\nTIDEBLOOM COMPLETE. Press R to begin a new journey."

_sig_sprig: .asciz "BLOOM SIP"
_sig_cinder: .asciz "WILDFIRE"
_sig_rill: .asciz "LIFE TIDE"
_sig_crag: .asciz "IRON ROOT"
_sig_glim: .asciz "SOUL THREAD"
_sig_zeph: .asciz "SKY BREAK"
_sig_auralith: .asciz "STARFALL"
_intent_leaf_hit: .asciz "VINE LASH"
_intent_leaf_charge: .asciz "THORN SURGE"
_intent_leaf_mend: .asciz "ROOT RECOVERY"
_intent_fire_hit: .asciz "EMBER CLAW"
_intent_fire_charge: .asciz "FIRESTORM"
_intent_fire_mend: .asciz "STOKE"
_intent_tide_hit: .asciz "RIPPLE"
_intent_tide_charge: .asciz "TIDAL CRASH"
_intent_tide_mend: .asciz "RENEW"
_intent_stone_hit: .asciz "STONE TAP"
_intent_stone_charge: .asciz "AVALANCHE"
_intent_stone_mend: .asciz "REFORGE"
_intent_spirit_hit: .asciz "SPARK"
_intent_spirit_charge: .asciz "SOUL FLARE"
_intent_spirit_mend: .asciz "DREAM"
_intent_sky_hit: .asciz "GUST"
_intent_sky_charge: .asciz "SKY DIVE"
_intent_sky_mend: .asciz "SECOND WIND"
_intent_ancient_hit: .asciz "STAR SHARD"
_intent_ancient_charge: .asciz "ECLIPSE"
_intent_ancient_mend: .asciz "STELLAR MEND"
_msg_no_energy: .asciz "Your signature needs 2 energy.\nSTRIKE or GUARD to gain energy, then unleash it."
_msg_sig_sprig: .asciz "BLOOM SIP draws strength from the earth.\nElemental damage and up to 10 health restored."
_msg_sig_cinder: .asciz "WILDFIRE sears the air and leaves a lingering burn.\nThe enemy takes 5 burn damage for its next 3 turns."
_msg_sig_rill: .asciz "LIFE TIDE washes over the clearing.\nElemental damage and up to 18 health restored."
_msg_sig_crag: .asciz "IRON ROOT calls up a shell of living stone.\nElemental damage; halve the next 2 incoming attacks."
_msg_sig_glim: .asciz "SOUL THREAD unravels the enemy's strength.\nRestore 8 health and weaken its next 2 attacks."
_msg_sig_zeph: .asciz "SKY BREAK cuts through the wind. Regain 1 energy.\nDeal 12 extra damage against a charging enemy."
_msg_lore_energy: .asciz "PROF. MOSS: Each companion has its own signature.\nStrike or guard for energy. Signatures cost 2 energy."
_msg_lore_elements: .asciz "PROF. MOSS: Leaf beats Tide, Tide beats Flame.\nFlame beats Leaf. A resisted hit still gives its bonus."
_msg_lore_intent: .asciz "PROF. MOSS: Watch the enemy's next move.\nGuard against charges; strike while it plans to recover."
_msg_ranger_quest: .asciz "RANGER SOL: Make two wild friends and return to me.\nI will teach your whole party a little extra resilience."
_msg_ranger_reward: .asciz "RANGER SOL: A promise kept! Your party grows stronger.\nEvery companion gains 8 max health and is fully restored."
_msg_ranger_complete: .asciz "RANGER SOL: Good friends make brave explorers.\nYour party carries my blessing. Seek the northern gate."
_msg_cache: .asciz "A forgotten trail cache! You find useful supplies.\nCollected 2 tonics and 4 bond orbs."
_msg_cache_empty: .asciz "The trail cache is empty.\nSomeone left a note: LISTEN TO THE ISLAND'S SONG."

_msg_npc_hint: .asciz "Someone left a story along this trail.\nPress ENTER to talk or investigate."

_name_verdant: .asciz "VERDANT"
_name_pyrelume: .asciz "PYRELUME"
_name_tiderune: .asciz "TIDERUNE"
_name_bastion: .asciz "BASTION"
_name_noctilume: .asciz "NOCTILUME"
_name_zephyrion: .asciz "ZEPHYRION"
_msg_shop_bought: .asciz "One fresh tonic for 25 coins. Added to your pouch!\nENTER buys another. Battle trainers to earn more coins."
_msg_shop_poor: .asciz "Tonics cost 25 coins. Come back after a few battles.\nThe town clinic always heals your companions for free."
_msg_shop_full: .asciz "Your tonic pouch is full.\nNo coins were spent."
_msg_trainer_start: .asciz "A fellow explorer challenges your whole party!\nEach trainer brings two companions. Plan for both rounds."
_msg_trainer_next: .asciz "First companion defeated! Earned 5 experience.\nThe trainer reaches for another friend. Press ENTER."
_msg_trainer_won: .asciz "Trainer challenge complete! Coins added to your pouch.\nYour victory opens a piece of the road ahead. Press ENTER."
_msg_trainer_done: .asciz "We have already shared our challenge, friend.\nKeep following the road. The island is counting on you."
_msg_citizen_home: .asciz "HARBOR KEEPER: Every journey begins with one good friend.\nVisit Professor Moss south of the road before heading east."
_msg_citizen_port: .asciz "EMBERPORT LOCAL: Strong bonds awaken new forms at level 8.\nYour companion keeps its signature and gains strength."
_msg_citizen_peak: .asciz "THE LAST KEEPER: Six challenges. Three lights. One song.\nRest by the shrine. Auralith waits at the end of the ascent."
_msg_evolution: .asciz "Your companion is changing! A deeper bond awakens.\nA new form, 18 more maximum health, and stronger attacks."
_msg_evolution_done: .asciz "A new form, the same loyal friend.\nPress ENTER to continue your journey."
_msg_loaded: .asciz "Your journey resumes exactly where you left it.\nThe roads, companions, and promises you made are waiting."
.section __DATA,__data
.p2align 3
.globl _trainer_names
_trainer_names: .quad _trainer_name0,_trainer_name1,_trainer_name2,_trainer_name3,_trainer_name4,_trainer_name5
.section __TEXT,__cstring,cstring_literals
_trainer_name0: .asciz "SCOUT INA"
_trainer_name1: .asciz "RIVAL ROWAN"
_trainer_name2: .asciz "SMITH ORIN"
_trainer_name3: .asciz "COURIER NYX"
_trainer_name4: .asciz "WARDEN LUMA"
_trainer_name5: .asciz "RIVAL ROWAN"

// Save contract:22 address/size descriptors,34 packed little-endian words.
// Validation reads staging memory only and never changes the live world.
.text
.p2align 2
.globl _game_validate_save, _game_after_load, _game_save_test_fixture
_game_validate_save:
    cmp w1, #136
    b.ne Lsave_invalid
    // Per-word basic ranges; RNG's unrestricted signed bitpattern is skipped.
    ADDR x9, _save_ranges
    mov w10, #0
Lsave_range_loop:
    cmp w10, #29
    b.eq Lsave_range_next
    ldr w11, [x0, w10, uxtw #2]
    lsl w12, w10, #3
    add x12, x9, x12
    ldp w13, w14, [x12]
    cmp w11, w13
    b.lt Lsave_invalid
    cmp w11, w14
    b.gt Lsave_invalid
Lsave_range_next:
    add w10, w10, #1
    cmp w10, #34
    b.lt Lsave_range_loop
    ldr w9, [x0, #116]
    cbz w9, Lsave_invalid
    ldr w9, [x0, #120]
    cmp w9, #0
    b.eq Lsave_home_ok
    cmp w9, #2
    b.ne Lsave_invalid
Lsave_home_ok:
    // Saved position must stand on a traversable tile in the specified map.
    ldr w9, [x0]
    mov w10, #345
    mul w9, w9, w10
    ldp w10, w11, [x0, #4]
    mov w12, #23
    madd w10, w11, w12, w10
    add w9, w9, w10
    ADDR x10, _world_maps
    ldrb w11, [x10, w9, uxtw]
    cmp w11, #1
    b.eq Lsave_invalid
    cmp w11, #4
    b.eq Lsave_invalid
    cmp w11, #17
    b.eq Lsave_invalid
    cmp w11, #18
    b.eq Lsave_invalid
    cmp w11, #20
    b.eq Lsave_invalid
    // A populated slot has coherent health, level, experience and evolution.
    mov w9, #0
Lsave_party_loop:
    add x10, x0, #40
    ldr w10, [x10, w9, uxtw #2]
    add x11, x0, #52
    ldr w11, [x11, w9, uxtw #2]
    add x12, x0, #64
    ldr w12, [x12, w9, uxtw #2]
    add x13, x0, #76
    ldr w13, [x13, w9, uxtw #2]
    add x14, x0, #124
    ldr w14, [x14, w9, uxtw #2]
    cmp w10, #-1
    b.eq Lsave_empty
    cmp w12, #1
    b.lt Lsave_invalid
    cmp w13, #1
    b.lt Lsave_invalid
    cmp w11, w12
    b.gt Lsave_invalid
    cmp w10, #6
    b.eq Lsave_invalid // Auralith is a guardian, never a party companion.
    cmp w10, #7
    b.lt Lsave_xp
    cmp w13, #8
    b.lt Lsave_invalid
Lsave_xp:
    add w15, w13, #3
    cmp w14, w15
    b.ge Lsave_invalid
    b Lsave_party_next
Lsave_empty:
    orr w11, w11, w12
    orr w11, w11, w13
    orr w11, w11, w14
    cbnz w11, Lsave_invalid
Lsave_party_next:
    add w9, w9, #1
    cmp w9, #3
    b.lt Lsave_party_loop
    ldr w9, [x0, #36]
    add x10, x0, #40
    ldr w10, [x10, w9, uxtw #2]
    cmp w10, #-1
    b.eq Lsave_invalid
    add x10, x0, #52
    ldr w10, [x10, w9, uxtw #2]
    cbz w10, Lsave_invalid
    // Later regions require the route gates actually completed earlier.
    ldr w9, [x0]
    ldr w10, [x0, #20]
    ldr w11, [x0, #100]
    cmp w9, #2
    b.lt Lsave_progress_ok
    tbz w10, #0, Lsave_invalid
    and w12, w11, #3
    cmp w12, #3
    b.ne Lsave_invalid
    cmp w9, #4
    b.lt Lsave_progress_ok
    tbz w10, #1, Lsave_invalid
    and w12, w11, #12
    cmp w12, #12
    b.ne Lsave_invalid
    cmp w9, #5
    b.lt Lsave_progress_ok
    tbz w10, #2, Lsave_invalid
    and w12, w11, #48
    cmp w12, #48
    b.ne Lsave_invalid
Lsave_progress_ok:
    mov w0, #0
    ret
Lsave_invalid:
    mov w0, #1
    ret

_game_after_load:
    ENTER
    PUT wzr, _mode
    PUT wzr, _trainer_pending
    PUT wzr, _trainer_round
    PUT wzr, _enemy_hp
    PUT wzr, _enemy_maxhp
    PUT wzr, _enemy_burn
    PUT wzr, _enemy_hex
    PUT wzr, _enemy_intent
    PUT wzr, _battle_turn
    PUT wzr, _last_event
    PUT wzr, _last_player_damage
    PUT wzr, _last_enemy_damage
    PUT wzr, _last_heal
    PUT wzr, _last_burn_damage
    PUT wzr, _last_enemy_heal
    PUT wzr, _guard_charge
    mov w9, #-1
    PUT w9, _trainer_id
    PUT w9, _evolution_from
    PUT w9, _evolution_to
    PUT w9, _evolution_slot
    ADDR x9, _team_armor
    stp wzr, wzr, [x9]
    str wzr, [x9, #8]
    GET w0, _map_id
    bl _world_load
    MESSAGE _msg_loaded
    mov w0, #0
    LEAVE

_game_save_test_fixture:
    ENTER
    bl _game_init
    mov w9, #7
    PUT w9, _beacons
    mov w9, #63
    PUT w9, _trainer_flags
    mov w9, #240
    PUT w9, _coins
    mov w9, #3
    PUT w9, _quest_flags
    mov w9, #2
    PUT w9, _home_map
    PUT w9, _captures
    mov w0, #5
    bl _world_load
    mov w9, #11
    PUT w9, _player_x
    PUT w9, _player_y
    ADDR x9, _team_species
    mov w10, #7
    mov w11, #8
    mov w12, #9
    stp w10, w11, [x9]
    str w12, [x9, #8]
    ADDR x9, _team_level
    mov w10, #9
    mov w11, #11
    mov w12, #10
    stp w10, w11, [x9]
    str w12, [x9, #8]
    ADDR x9, _team_maxhp
    mov w10, #110
    mov w11, #120
    mov w12, #115
    stp w10, w11, [x9]
    str w12, [x9, #8]
    ADDR x9, _team_hp
    mov w10, #73
    mov w11, #100
    mov w12, #89
    stp w10, w11, [x9]
    str w12, [x9, #8]
    ADDR x9, _team_xp
    mov w10, #3
    mov w11, #5
    mov w12, #7
    stp w10, w11, [x9]
    str w12, [x9, #8]
    ADDR x9, _team_energy
    mov w10, #1
    mov w11, #2
    mov w12, #3
    stp w10, w11, [x9]
    str w12, [x9, #8]
    mov w0, #0
    LEAVE

.section __DATA,__data
.p2align 3
.globl _save_fields, _save_field_count, _save_payload_size
_save_fields:
.quad _map_id,4, _player_x,4, _player_y,4, _facing,4, _steps,4
.quad _beacons,4, _captures,4, _tonics,4, _orbs,4, _active_slot,4
.quad _team_species,12, _team_hp,12, _team_maxhp,12, _team_level,12, _team_energy,12
.quad _trainer_flags,4, _coins,4, _quest_flags,4, _encounter_steps,4, _rng_seed,4, _home_map,4
.quad _team_xp,12
.quad 0,0
_save_field_count: .long 22
_save_payload_size: .long 136
.section __TEXT,__const
.p2align 2
_save_ranges:
.long 0,5, 1,21, 1,13, 0,3, 0,0x7fffffff
.long 0,7, 0,9999, 0,99, 0,99, 0,2
.long -1,12, -1,12, -1,12
.long 0,999, 0,999, 0,999
.long 0,999, 0,999, 0,999
.long 0,99, 0,99, 0,99
.long 0,3, 0,3, 0,3
.long 0,63, 0,999999, 0,3, 0,0x7fffffff, 0,0, 0,2
.long 0,101, 0,101, 0,101

.text
.p2align 2
// Headless engine regression tests, no SDL requirement.
// Return codes name assertions in README; resets state before returning.
.globl _game_selftest
_game_selftest:
    ENTER
    stp x19, x20, [sp, #-16]!
    mov w19, #1
    bl _game_init
    GET w9, _player_x
    cmp w9, #4
    b.ne Ltest_fail
    GET w9, _player_y
    cmp w9, #12
    b.ne Ltest_fail
    mov w19, #2
    mov w0, #-1
    mov w1, #0
    bl _game_move
    GET w9, _player_x
    cmp w9, #3
    b.ne Ltest_fail
    mov w19, #3
    mov w9, #1
    PUT w9, _player_x
    PUT w9, _player_y
    mov w0, #-1
    mov w1, #0
    bl _game_move
    GET w9, _player_x
    cmp w9, #1
    b.ne Ltest_fail
    mov w19, #4
    bl _game_preview_battle
    mov w0, #2
    bl _game_action
    GET w9, _orbs
    cmp w9, #8
    b.ne Ltest_fail
    GET w9, _mode
    cmp w9, #1
    b.ne Ltest_fail
    mov w19, #5
    mov w9, #1
    PUT w9, _enemy_hp
    PUT w9, _rng_seed
    mov w0, #2
    bl _game_action
    GET w9, _captures
    cmp w9, #1
    b.ne Ltest_fail
    ADDR x9, _team_species
    ldr w10, [x9, #4]
    cmp w10, #1
    b.ne Ltest_fail
    GET w9, _mode
    cmp w9, #2
    b.ne Ltest_fail
    mov w19, #6
    bl _game_dismiss
    GET w9, _mode
    cbnz w9, Ltest_fail
    mov w19, #7
    mov w0, #1
    bl _world_load
    mov w9, #11
    PUT w9, _player_x
    mov w9, #3
    PUT w9, _player_y
    bl _game_interact
    GET w9, _battle_kind
    cmp w9, #1
    b.ne Ltest_fail
    GET w9, _enemy_species
    cmp w9, #2
    b.ne Ltest_fail
    mov w19, #8
    mov w9, #1
    PUT w9, _enemy_hp
    mov w0, #0
    bl _game_action
    GET w9, _beacons
    cmp w9, #1
    b.ne Ltest_fail
    ADDR x9, _team_hp
    ADDR x10, _team_maxhp
    ldr w11, [x9]
    ldr w12, [x10]
    cmp w11, w12
    b.ne Ltest_fail
    mov w19, #9
    bl _game_dismiss
    mov w0, #5
    bl _world_load
    mov w9, #11
    PUT w9, _player_x
    mov w9, #3
    PUT w9, _player_y
    bl _game_interact
    GET w9, _mode
    cbnz w9, Ltest_fail
    mov w19, #10
    mov w9, #7
    PUT w9, _beacons
    mov w9, #63
    PUT w9, _trainer_flags
    bl _game_interact
    GET w9, _mode
    cmp w9, #1
    b.ne Ltest_fail
    GET w9, _battle_kind
    cmp w9, #2
    b.ne Ltest_fail
    mov w19, #11
    mov w9, #1
    PUT w9, _enemy_hp
    mov w0, #0
    bl _game_action
    GET w9, _mode
    cmp w9, #3
    b.ne Ltest_fail
    // Test a whole-party faint and camp recovery.
    mov w19, #12
    bl _game_preview_battle
    ADDR x9, _team_hp
    mov w10, #1
    str w10, [x9]
    mov w0, #0
    bl _game_action
    GET w9, _mode
    cmp w9, #2
    b.ne Ltest_fail
    GET w9, _player_y
    cmp w9, #5
    b.ne Ltest_fail
    ADDR x9, _team_hp
    ldr w10, [x9]
    cmp w10, #54
    b.ne Ltest_fail
    // World party cycling must skip empty slots and ignore combat.
    mov w19, #13
    bl _game_init
    ADDR x9, _team_species
    mov w10, #1
    str w10, [x9, #4]
    ADDR x9, _team_hp
    mov w10, #40
    str w10, [x9, #4]
    bl _game_cycle_lead
    GET w9, _active_slot
    cmp w9, #1
    b.ne Ltest_fail
    bl _game_cycle_lead
    GET w9, _active_slot
    cbnz w9, Ltest_fail
    mov w9, #1
    PUT w9, _mode
    bl _game_cycle_lead
    GET w9, _active_slot
    cbnz w9, Ltest_fail
    // Guard stores one non-stacking charge, consumed by the next attack.
    mov w19, #14
    bl _game_preview_battle
    mov w0, #6
    bl _game_action
    GET w9, _guard_charge
    cmp w9, #12
    b.ne Ltest_fail
    mov w9, #1
    PUT w9, _rng_seed
    mov w0, #0
    bl _game_action
    GET w9, _last_player_damage
    cmp w9, #30
    b.ne Ltest_fail
    GET w9, _guard_charge
    cbnz w9, Ltest_fail
    // Complete all four boss fights with genuine stats and legal actions.
    mov w19, #15
    bl _game_test_campaign
    cbnz w0, Ltest_fail
    // Energy is spent once; a rejected signature consumes no turn.
    mov w19, #16
    bl _game_preview_battle
    mov w0, #1
    bl _game_action
    ADDR x9, _team_energy
    ldr w10, [x9]
    cmp w10, #1
    b.ne Ltest_fail
    GET w20, _enemy_hp
    mov w0, #1
    bl _game_action
    GET w9, _last_event
    cbnz w9, Ltest_fail
    GET w9, _battle_turn
    cmp w9, #1
    b.ne Ltest_fail
    GET w9, _enemy_hp
    cmp w9, w20
    b.ne Ltest_fail
    mov w0, #0
    bl _game_action
    ADDR x9, _team_energy
    ldr w10, [x9]
    cmp w10, #2
    b.ne Ltest_fail
    // A charged attack is reduced to one quarter; a mend turn deals no damage.
    mov w19, #17
    bl _game_preview_battle
    mov w9, #1
    PUT w9, _enemy_intent
    PUT w9, _rng_seed
    mov w0, #6
    bl _game_action
    GET w9, _last_enemy_damage
    cmp w9, #4
    b.ne Ltest_fail
    mov w9, #2
    PUT w9, _enemy_intent
    mov w9, #20
    PUT w9, _enemy_hp
    mov w0, #6
    bl _game_action
    GET w9, _last_enemy_damage
    cbnz w9, Ltest_fail
    GET w9, _last_enemy_heal
    cmp w9, #7
    b.ne Ltest_fail
    GET w9, _enemy_hp
    cmp w9, #27
    b.ne Ltest_fail
    // Every playable species has its distinct, deterministic signature bonus.
    mov w19, #18
    mov w20, #0
Ltest_signature_loop:
    bl _game_preview_battle
    ADDR x9, _team_species
    str w20, [x9]
    ADDR x9, _team_hp
    mov w10, #20
    str w10, [x9]
    mov w9, #200
    PUT w9, _enemy_hp
    PUT w9, _enemy_maxhp
    mov w0, #1
    bl _game_action
    ADDR x9, _team_energy
    ldr w10, [x9]
    mov w11, #1
    cmp w20, #5
    mov w12, #2
    csel w11, w12, w11, eq
    cmp w10, w11
    b.ne Ltest_fail
    ADDR x9, _test_signature_heals
    ldr w10, [x9, w20, uxtw #2]
    GET w11, _last_heal
    cmp w10, w11
    b.ne Ltest_fail
    cmp w20, #1
    b.ne Ltest_signature_armor
    GET w9, _enemy_burn
    cmp w9, #2
    b.ne Ltest_fail
    GET w9, _last_burn_damage
    cmp w9, #5
    b.ne Ltest_fail
Ltest_signature_armor:
    cmp w20, #3
    b.ne Ltest_signature_hex
    ADDR x9, _team_armor
    ldr w10, [x9]
    cmp w10, #1
    b.ne Ltest_fail
Ltest_signature_hex:
    cmp w20, #4
    b.ne Ltest_signature_next
    GET w9, _enemy_hex
    cmp w9, #1
    b.ne Ltest_fail
Ltest_signature_next:
    add w20, w20, #1
    cmp w20, #6
    b.lt Ltest_signature_loop
    // Ranger upgrade and supply cache are granted once, and survive resting.
    mov w19, #19
    bl _game_init
    mov w0, #4
    bl _world_load
    mov w9, #2
    PUT w9, _captures
    mov w9, #3
    PUT w9, _player_x
    mov w9, #10
    PUT w9, _player_y
    bl _game_interact
    GET w9, _quest_flags
    cmp w9, #1
    b.ne Ltest_fail
    ADDR x9, _team_maxhp
    ldr w10, [x9]
    cmp w10, #62
    b.ne Ltest_fail
    bl _game_interact
    ADDR x9, _team_maxhp
    ldr w10, [x9]
    cmp w10, #62
    b.ne Ltest_fail
    mov w9, #3
    PUT w9, _player_x
    mov w9, #4
    PUT w9, _player_y
    bl _game_interact
    GET w9, _quest_flags
    cmp w9, #3
    b.ne Ltest_fail
    GET w9, _tonics
    cmp w9, #5
    b.ne Ltest_fail
    GET w9, _orbs
    cmp w9, #12
    b.ne Ltest_fail
    bl _game_interact
    GET w9, _tonics
    cmp w9, #5
    b.ne Ltest_fail
    mov w0, #2
    bl _world_load
    mov w9, #5
    PUT w9, _player_x
    PUT w9, _player_y
    bl _game_interact
    GET w9, _tonics
    cmp w9, #5
    b.ne Ltest_fail
    GET w9, _orbs
    cmp w9, #12
    b.ne Ltest_fail
    // The visible capture percentage matches the actual probability formula.
    mov w19, #20
    bl _game_preview_battle
    mov w9, #28
    PUT w9, _enemy_hp
    bl _game_update_capturechance
    GET w9, _capture_chance
    cmp w9, #70
    b.ne Ltest_fail
    mov w9, #1
    PUT w9, _enemy_hp
    bl _game_update_capturechance
    GET w9, _capture_chance
    cmp w9, #98
    b.ne Ltest_fail
    mov w19, #0
Ltest_fail:
    bl _game_init
    mov w0, w19
    ldp x19, x20, [sp], #16
    LEAVE


// Complete the ten campaign challenges using normal damage, XP, items and AI.
// Only travel coordinates are fixtures; clinics and shops are real interactions.
.text
.p2align 2
_game_test_campaign:
    ENTER
    stp x19, x20, [sp, #-16]!
    bl _game_init
    mov w19, #0
Lcampaign_loop:
    cmp w19, #3
    b.eq Lcampaign_restock
    cmp w19, #6
    b.eq Lcampaign_restock
    cmp w19, #9
    b.ne Lcampaign_start
Lcampaign_restock:
    mov w0, #2
    bl _world_load
    mov w9, #5
    PUT w9, _player_x
    PUT w9, _player_y
    bl _game_interact
    mov w9, #11
    PUT w9, _player_x
    mov w20, #4
Lcampaign_buy:
    bl _game_interact
    subs w20, w20, #1
    b.ne Lcampaign_buy
Lcampaign_start:
    ADDR x9, _campaign_cases
    mov w10, #12
    madd x9, x19, x10, x9
    ldr w0, [x9]
    bl _world_load
    ADDR x9, _campaign_cases
    mov w10, #12
    madd x9, x19, x10, x9
    ldp w10, w11, [x9, #4]
    PUT w10, _player_x
    PUT w11, _player_y
    bl _game_interact
    GET w9, _mode
    cmp w9, #1
    b.ne Lcampaign_fail
    bl _game_test_resolve
    cbnz w0, Lcampaign_fail
    ADDR x9, _campaign_flags
    ldr w10, [x9, w19, uxtw #2]
    GET w11, _trainer_flags
    cmp w10, w11
    b.ne Lcampaign_fail
    ADDR x9, _campaign_beacons
    ldr w10, [x9, w19, uxtw #2]
    GET w11, _beacons
    cmp w10, w11
    b.ne Lcampaign_fail
    cmp w19, #9
    b.eq Lcampaign_finish
    bl _game_dismiss
    add w19, w19, #1
    b Lcampaign_loop
Lcampaign_finish:
    GET w9, _mode
    cmp w9, #3
    b.ne Lcampaign_fail
    ADDR x9, _team_species
    ldr w10, [x9]
    cmp w10, #7
    b.ne Lcampaign_fail
    mov w0, #0
    b Lcampaign_done
Lcampaign_fail:
    add w0, w19, #1
Lcampaign_done:
    ldp x19, x20, [sp], #16
    LEAVE

_game_test_resolve:
    ENTER
    stp x19, x20, [sp, #-16]!
    mov w19, #256
Lresolve_loop:
    subs w19, w19, #1
    b.eq Lresolve_fail
    GET w9, _mode
    cmp w9, #4
    b.eq Lresolve_dismiss
    cmp w9, #2
    b.ne Lresolve_battle
    GET w9, _trainer_pending
    cbz w9, Lresolve_won
Lresolve_dismiss:
    bl _game_dismiss
    b Lresolve_loop
Lresolve_battle:
    cmp w9, #1
    b.ne Lresolve_won
    GET w10, _active_slot
    ADDR x9, _team_hp
    ldr w11, [x9, w10, uxtw #2]
    GET w9, _enemy_intent
    cmp w9, #1
    b.eq Lresolve_guard
    GET w12, _enemy_level
    add w12, w12, #12
    cmp w11, w12
    b.gt Lresolve_attack
    GET w9, _tonics
    cbz w9, Lresolve_attack
    mov w0, #3
    bl _game_action
    b Lresolve_loop
Lresolve_guard:
    mov w0, #6
    bl _game_action
    b Lresolve_loop
Lresolve_attack:
    ADDR x9, _team_energy
    ldr w11, [x9, w10, uxtw #2]
    cmp w11, #2
    b.lt Lresolve_strike
    ADDR x9, _team_species
    ldr w10, [x9, w10, uxtw #2]
    ADDR x9, _species_base
    ldr w10, [x9, w10, uxtw #2]
    GET w11, _enemy_species
    ldr w11, [x9, w11, uxtw #2]
    mov w12, #7
    madd w10, w10, w12, w11
    ADDR x9, _effectiveness
    ldrb w11, [x9, w10, uxtw]
    cmp w11, #2
    cset w0, ne
    b Lresolve_do_attack
Lresolve_strike:
    mov w0, #0
Lresolve_do_attack:
    bl _game_action
    b Lresolve_loop
Lresolve_won:
    mov w0, #0
    b Lresolve_done
Lresolve_fail:
    mov w0, #1
Lresolve_done:
    ldp x19, x20, [sp], #16
    LEAVE
.section __TEXT,__const
.p2align 2
_campaign_cases:
.long 1,7,7, 1,11,3, 1,18,7
.long 3,7,7, 3,11,3, 3,18,7
.long 4,7,7, 4,11,3, 4,18,7
.long 5,11,3
_campaign_flags: .long 1,1,3,7,7,15,31,31,63,63
_campaign_beacons: .long 0,1,1,1,3,3,3,7,7,7

.text
.p2align 2
.globl _game_world_selftest
_game_world_selftest:
    ENTER
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    // All five links connect in both directions with the earned gate flags.
    mov w19, #1
    bl _game_init
    mov w9, #7
    PUT w9, _beacons
    mov w9, #63
    PUT w9, _trainer_flags
    mov w20, #0
Lworldtest_east:
    mov w0, w20
    bl _world_load
    mov w9, #21
    PUT w9, _player_x
    mov w9, #7
    PUT w9, _player_y
    mov w0, #1
    mov w1, #0
    bl _game_move
    GET w9, _map_id
    add w10, w20, #1
    cmp w9, w10
    b.ne Lworldtest_fail
    GET w9, _player_x
    cmp w9, #1
    b.ne Lworldtest_fail
    mov w0, #-1
    mov w1, #0
    bl _game_move
    GET w9, _map_id
    cmp w9, w20
    b.ne Lworldtest_fail
    GET w9, _player_x
    cmp w9, #21
    b.ne Lworldtest_fail
    add w20, w20, #1
    cmp w20, #5
    b.lt Lworldtest_east
    // Eastern gates require BOTH the region's trainer pair and beacon.
    mov w19, #2
    mov w20, #0
Lworldtest_gate:
    bl _game_init
    ADDR x9, _gate_test_maps
    ldr w0, [x9, w20, uxtw #2]
    mov w21, w0
    bl _world_load
    mov w9, #21
    PUT w9, _player_x
    mov w9, #7
    PUT w9, _player_y
    mov w0, #1
    mov w1, #0
    bl _game_move
    GET w9, _map_id
    cmp w9, w21
    b.ne Lworldtest_fail
    mov w9, #1
    lsl w9, w9, w20
    PUT w9, _beacons
    mov w0, #1
    mov w1, #0
    bl _game_move
    GET w9, _map_id
    cmp w9, w21
    b.ne Lworldtest_fail
    mov w9, #3
    lsl w10, w20, #1
    lsl w9, w9, w10
    PUT w9, _trainer_flags
    mov w0, #1
    mov w1, #0
    bl _game_move
    GET w9, _map_id
    add w10, w21, #1
    cmp w9, w10
    b.ne Lworldtest_fail
    add w20, w20, #1
    cmp w20, #3
    b.lt Lworldtest_gate
    // House roofs and walls are real colliders, not decorative facades.
    mov w19, #3
    bl _game_init
    mov w9, #4
    PUT w9, _player_x
    mov w9, #2
    PUT w9, _player_y
    mov w0, #0
    mov w1, #1
    bl _game_move
    GET w9, _player_y
    cmp w9, #2
    b.ne Lworldtest_fail
    mov w9, #5
    PUT w9, _player_y
    mov w0, #0
    mov w1, #-1
    bl _game_move
    GET w9, _player_y
    cmp w9, #5
    b.ne Lworldtest_fail
    // A trainer is not marked defeated or paid until BOTH creatures fall.
    mov w19, #4
    bl _game_init
    mov w0, #0
    bl _game_start_trainer
    mov w9, #1
    PUT w9, _enemy_hp
    mov w0, #0
    bl _game_action
    GET w9, _trainer_flags
    cbnz w9, Lworldtest_fail
    GET w9, _coins
    cmp w9, #60
    b.ne Lworldtest_fail
    GET w9, _trainer_pending
    cmp w9, #1
    b.ne Lworldtest_fail
    bl _game_dismiss
    GET w9, _trainer_round
    cmp w9, #1
    b.ne Lworldtest_fail
    GET w9, _enemy_species
    cmp w9, #2
    b.ne Lworldtest_fail
    mov w9, #1
    PUT w9, _enemy_hp
    mov w0, #0
    bl _game_action
    GET w9, _trainer_flags
    cmp w9, #1
    b.ne Lworldtest_fail
    GET w9, _coins
    cmp w9, #105
    b.ne Lworldtest_fail
    ADDR x9, _team_level
    ldr w10, [x9]
    cmp w10, #6
    b.ne Lworldtest_fail
    ADDR x9, _team_xp
    ldr w10, [x9]
    cmp w10, #2
    b.ne Lworldtest_fail
    // Every playable species evolves from actual XP, once, at level8.
    mov w19, #5
    mov w20, #0
Lworldtest_evolution:
    bl _game_init
    ADDR x9, _team_species
    str w20, [x9]
    ADDR x9, _team_level
    mov w10, #7
    str w10, [x9]
    ADDR x9, _team_xp
    mov w10, #9
    str w10, [x9]
    mov w0, #1
    mov w1, #4
    mov w2, #0
    mov w3, #0
    bl _game_begin
    mov w9, #1
    PUT w9, _enemy_hp
    mov w0, #0
    bl _game_action
    GET w9, _mode
    cmp w9, #4
    b.ne Lworldtest_fail
    GET w9, _evolution_from
    cmp w9, w20
    b.ne Lworldtest_fail
    GET w9, _evolution_to
    add w10, w20, #7
    cmp w9, w10
    b.ne Lworldtest_fail
    ADDR x9, _team_species
    ldr w11, [x9]
    cmp w11, w10
    b.ne Lworldtest_fail
    ADDR x9, _team_maxhp
    ldr w10, [x9]
    cmp w10, #77
    b.ne Lworldtest_fail
    bl _game_dismiss
    GET w9, _mode
    cmp w9, #2
    b.ne Lworldtest_fail
    add w20, w20, #1
    cmp w20, #6
    b.lt Lworldtest_evolution
    // Loss returns to the most recent town clinic with a healthy lead.
    mov w19, #6
    bl _game_init
    mov w0, #2
    bl _world_load
    mov w0, #4
    bl _world_load
    ADDR x9, _team_hp
    mov w10, #1
    str w10, [x9]
    mov w0, #1
    mov w1, #4
    mov w2, #0
    mov w3, #0
    bl _game_begin
    mov w0, #0
    bl _game_action
    GET w9, _map_id
    cmp w9, #2
    b.ne Lworldtest_fail
    GET w9, _player_x
    cmp w9, #5
    b.ne Lworldtest_fail
    GET w9, _player_y
    cmp w9, #5
    b.ne Lworldtest_fail
    GET w9, _trainer_pending
    cbnz w9, Lworldtest_fail
    // Validate the exact packed save schema, rejecting corruption pre-commit.
    mov w19, #7
    bl _game_save_test_fixture
    bl _game_pack_test
    bl _game_validate_save
    cbnz w0, Lworldtest_fail
    ADDR x9, _world_test_save
    mov w10, #99
    str w10, [x9]
    bl _game_validate_test
    cbz w0, Lworldtest_fail
    ADDR x9, _world_test_save
    mov w10, #5
    str w10, [x9]
    mov w10, #999
    str w10, [x9, #52]
    bl _game_validate_test
    cbz w0, Lworldtest_fail
    ADDR x9, _world_test_save
    mov w10, #73
    str w10, [x9, #52]
    mov w10, #7
    str w10, [x9, #76]
    bl _game_validate_test
    cbz w0, Lworldtest_fail
    ADDR x9, _world_test_save
    mov w10, #9
    str w10, [x9, #76]
    mov w10, #3
    str w10, [x9, #36]
    bl _game_validate_test
    cbz w0, Lworldtest_fail
    ADDR x9, _world_test_save
    str wzr, [x9, #36]
    mov w10, #7
    str w10, [x9, #4]
    mov w10, #3
    str w10, [x9, #8]
    bl _game_validate_test
    cbz w0, Lworldtest_fail
    ADDR x9, _world_test_save
    mov w10, #11
    stp w10, w10, [x9, #4]
    str wzr, [x9, #100]
    bl _game_validate_test
    cbz w0, Lworldtest_fail
    ADDR x9, _world_test_save
    mov w10, #63
    str w10, [x9, #100]
    mov w10, #99
    str w10, [x9, #124]
    bl _game_validate_test
    cbz w0, Lworldtest_fail
    GET w9, _coins
    cmp w9, #240
    b.ne Lworldtest_fail
    // Resume rebuilds world presentation and keeps evolved party/progression.
    mov w19, #8
    mov w9, #4
    PUT w9, _mode
    bl _game_after_load
    GET w9, _mode
    cbnz w9, Lworldtest_fail
    GET w9, _map_id
    cmp w9, #5
    b.ne Lworldtest_fail
    ADDR x9, _team_species
    ldr w10, [x9]
    cmp w10, #7
    b.ne Lworldtest_fail
    GET w9, _trainer_flags
    cmp w9, #63
    b.ne Lworldtest_fail
    mov w19, #0
Lworldtest_fail:
    bl _game_init
    mov w0, w19
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    LEAVE

_game_pack_test:
    ADDR x9, _save_fields
    ADDR x10, _world_test_save
Lpacktest_field:
    ldp x11, x12, [x9], #16
    cbz x11, Lpacktest_done
Lpacktest_word:
    ldr w13, [x11], #4
    str w13, [x10], #4
    subs x12, x12, #4
    b.ne Lpacktest_word
    b Lpacktest_field
Lpacktest_done:
    ADDR x0, _world_test_save
    mov w1, #136
    ret
_game_validate_test:
    ADDR x0, _world_test_save
    mov w1, #136
    b _game_validate_save
.section __TEXT,__const
.p2align 2
_gate_test_maps: .long 1,3,4
.section __DATA,__data
.p2align 3
_world_test_save: .space 136
