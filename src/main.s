// TIDEBLOOM — native application shell, written entirely in ARM64 assembly.
// SDL supplies windowing/input/drawing primitives; no C gameplay or glue.
// Apple AArch64 ABI: stack stays 16-byte aligned at every call boundary.

.macro ADDR reg, sym
    adrp \reg, \sym@PAGE
    add \reg, \reg, \sym@PAGEOFF
.endmacro

.section __TEXT,__text,regular,pure_instructions
.p2align 2
.globl _main
_main:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    mov w19, w0
    mov x20, x1
    mov w21, #0                 // 0 interactive;1/2/3/4/5 title/map/battle/win/impact
    mov x22, #0                 // snapshot filename
    mov w23, #0                 // exit code
    cmp w19, #2
    b.lt Lmain_initialize
    ldr x0, [x20, #8]
    ADDR x1, Lselftest_flag
    bl _strcmp
    cbz w0, Lmain_selftest
    ldr x0, [x20, #8]
    ADDR x1, Laudiotest_flag
    bl _strcmp
    cbz w0, Lmain_audiotest
    ldr x0, [x20, #8]
    ADDR x1, Lanimationtest_flag
    bl _strcmp
    cbz w0, Lmain_animationtest
    ldr x0, [x20, #8]
    ADDR x1, Lworldtest_flag
    bl _strcmp
    cbz w0, Lmain_worldtest
    ldr x0, [x20, #8]
    ADDR x1, Lsavetest_flag
    bl _strcmp
    cbz w0, Lmain_savetest
    ldr x0, [x20, #8]
    ADDR x1, Lsavepath_flag
    bl _strcmp
    cbz w0, Lmain_savepath
    cmp w19, #3
    b.lt Lmain_initialize
    ldr x0, [x20, #8]
    ADDR x1, Lsnapshot_flag
    bl _strcmp
    cbz w0, Lmain_snapshot_title
    ldr x0, [x20, #8]
    ADDR x1, Lsnapshot_map_flag
    bl _strcmp
    cbz w0, Lmain_snapshot_map
    ldr x0, [x20, #8]
    ADDR x1, Lsnapshot_battle_flag
    bl _strcmp
    cbz w0, Lmain_snapshot_battle
    ldr x0, [x20, #8]
    ADDR x1, Lsnapshot_win_flag
    bl _strcmp
    cbz w0, Lmain_snapshot_win
    ldr x0, [x20, #8]
    ADDR x1, Lsnapshot_impact_flag
    bl _strcmp
    cbz w0, Lmain_snapshot_impact
    ldr x0, [x20, #8]
    ADDR x1, Lrecord_flag
    bl _strcmp
    cbz w0, Lmain_record_flag
    ldr x0, [x20, #8]
    ADDR x1, Levolution_flag
    bl _strcmp
    cbz w0, Lmain_evolution_flag
    ldr x0, [x20, #8]
    ADDR x1, Lworldmap_snapshot_flag
    bl _strcmp
    cbnz w0, Lmain_initialize
    mov w21, #8
    b Lmain_snapshot_path
Lmain_evolution_flag:
    mov w21, #7
    b Lmain_snapshot_path
Lmain_record_flag:
    mov w21, #6
    b Lmain_snapshot_path
Lmain_snapshot_impact:
    mov w21, #5
    b Lmain_snapshot_path
Lmain_snapshot_win:
    mov w21, #4
    b Lmain_snapshot_path
Lmain_snapshot_battle:
    mov w21, #3
    b Lmain_snapshot_path
Lmain_snapshot_title:
    mov w21, #1
    b Lmain_snapshot_path
Lmain_snapshot_map:
    mov w21, #2
Lmain_snapshot_path:
    ldr x22, [x20, #16]
    cmp w21, #7
    b.ne Lmain_snapshot_region
    cmp w19, #4
    b.lt Lmain_snapshot_driver
    ldr x0, [x20, #24]
    bl _parse_evolution_ticks
    ADDR x9, _snapshot_evolution_clock
    str w0, [x9]
    b Lmain_snapshot_driver
Lmain_snapshot_region:
    cmp w21, #8
    b.eq Lmain_snapshot_map_number
    cmp w21, #2
    b.ne Lmain_snapshot_ticks
Lmain_snapshot_map_number:
    cmp w19, #4
    b.lt Lmain_snapshot_driver
    ldr x0, [x20, #24]
    bl _parse_snapshot_ticks
    cmp w0, #5
    csel w0, w0, wzr, ls
    ADDR x9, _snapshot_map_id
    str w0, [x9]
    b Lmain_snapshot_driver
Lmain_snapshot_ticks:
    cmp w21, #5
    b.ne Lmain_snapshot_driver
    cmp w19, #4
    b.lt Lmain_snapshot_driver
    ldr x0, [x20, #24]
    bl _parse_snapshot_ticks
    ADDR x9, _snapshot_frame_count
    str w0, [x9]
Lmain_snapshot_driver:
    // Screenshots use a deterministic software renderer, also under SDL_VIDEODRIVER=dummy.
    ADDR x0, Lrender_driver_hint
    ADDR x1, Lsoftware
    bl _SDL_SetHint
Lmain_initialize:
    bl _game_init
    bl _SDL_SetMainReady
    mov w0, #0x20
    bl _SDL_Init
    cbnz w0, Lmain_error
    cbnz w21, Lmain_save_ready
    bl _save_init              // Interactive startup probes; it never writes.
Lmain_save_ready:
    ADDR x0, Lwindow_title
    mov w1, #0x2fff0000          // SDL_WINDOWPOS_CENTERED
    mov w2, #0x2fff0000
    mov w3, #1120
    mov w4, #768
    mov w5, #0x24               // SHOWN | RESIZABLE
    cbz w21, Lmain_window
    mov w5, #8                  // HIDDEN for snapshots
Lmain_window:
    bl _SDL_CreateWindow
    cbz x0, Lmain_error
    ADDR x9, _window
    str x0, [x9]
    mov w1, #-1
    mov w2, #6                  // ACCELERATED | PRESENTVSYNC
    cbz w21, Lmain_renderer
    mov w2, #1                  // SOFTWARE
Lmain_renderer:
    bl _SDL_CreateRenderer
    cbnz x0, Lmain_renderer_ready
    ADDR x9, _window
    ldr x0, [x9]
    mov w1, #-1
    mov w2, #1
    bl _SDL_CreateRenderer
    cbz x0, Lmain_error
Lmain_renderer_ready:
    ADDR x9, _renderer
    str x0, [x9]
    mov w1, #1120
    mov w2, #768
    bl _SDL_RenderSetLogicalSize
    cmp w21, #6
    b.eq Lmain_record
    cbnz w21, Lmain_audio_ready
    bl _audio_init
Lmain_audio_ready:
    cmp w21, #2
    b.lt Lmain_render_start
    ADDR x9, _screen
    mov w10, #1
    str w10, [x9]
    cmp w21, #2
    b.eq Lmain_preview_map
    cmp w21, #8
    b.eq Lmain_preview_map
    cmp w21, #7
    b.eq Lmain_preview_evolution
    cmp w21, #3
    b.eq Lmain_preview_battle
    cmp w21, #5
    b.eq Lmain_preview_battle
    cmp w21, #4
    b.ne Lmain_render_start
    // Render-only fixture for reviewing the ending; interactive state is untouched.
    ADDR x9, _mode
    mov w10, #3
    str w10, [x9]
    b Lmain_render_start
Lmain_preview_map:
    ADDR x9, _snapshot_map_id
    ldr w0, [x9]
    bl _world_load
    b Lmain_render_start
Lmain_preview_evolution:
    ADDR x9, _evolution_from
    str wzr, [x9]
    ADDR x9, _evolution_to
    mov w10, #7
    str w10, [x9]
    ADDR x9, _evolution_slot
    str wzr, [x9]
    ADDR x9, _mode
    mov w10, #4
    str w10, [x9]
    b Lmain_render_start
Lmain_preview_battle:
    bl _game_preview_battle
Lmain_render_start:
    bl _anim_init
    cmp w21, #8
    b.ne Lmain_evolution_fixture
    ADDR x9, _show_world_map
    mov w10, #1
    str w10, [x9]
    b Lmain_fixture_ready
Lmain_evolution_fixture:
    cmp w21, #7
    b.ne Lmain_impact_fixture
    ADDR x9, _snapshot_evolution_clock
    ldr w10, [x9]
    ADDR x9, _evolution_clock
    str w10, [x9]
    b Lmain_fixture_ready
Lmain_impact_fixture:
    cmp w21, #5
    b.ne Lmain_fixture_ready
    mov w0, #1
    bl _anim_action
    ADDR x9, _snapshot_frame_count
    ldr w25, [x9]
    cbz w25, Lmain_impact_frame
Lmain_impact_advance:
    bl _anim_tick
    subs w25, w25, #1
    b.ne Lmain_impact_advance
Lmain_impact_frame:
    ADDR x9, _snapshot_frame_count
    ldr w10, [x9]
    ADDR x9, _frame
    str w10, [x9]
Lmain_fixture_ready:
    cbz w21, Lmain_loop
    bl _render_frame
    mov x0, x22
    bl _save_snapshot
    mov w23, w0
    b Lmain_cleanup
Lmain_record:
    mov x0, x22
    bl _record_demo
    mov w23, w0
    b Lmain_cleanup
Lmain_loop:
    ADDR x0, _event
    bl _SDL_PollEvent
    cbz w0, Lmain_draw
    ADDR x9, _event
    ldr w10, [x9]
    cmp w10, #0x100             // SDL_QUIT
    b.eq Lmain_cleanup
    cmp w10, #0x300             // SDL_KEYDOWN
    b.eq Lmain_key
    cmp w10, #0x401             // SDL_MOUSEBUTTONDOWN
    b.eq Lmain_click
    b Lmain_loop
Lmain_key:
    // Held walking is polled each frame; toggles and saves must never repeat.
    ldrb w10, [x9, #13]
    cbnz w10, Lmain_loop
Lmain_key_dispatch:
    ldr w0, [x9, #20]           // SDL_Keysym.sym at event +20
    cmp w0, #109                // M is a toggle, never a repeating action.
    b.ne Lmain_handle_key
    ldrb w10, [x9, #13]
    cbnz w10, Lmain_loop
Lmain_handle_key:
    bl _handle_key
    cbnz w0, Lmain_cleanup
    b Lmain_loop
Lmain_click:
    ldrb w10, [x9, #16]         // only primary button (button offset 16)
    cmp w10, #1
    b.ne Lmain_loop
    ldr w0, [x9, #20]
    ldr w1, [x9, #24]
    // SDL_RenderSetLogicalSize scales SDL mouse events into logical coordinates.
    bl _handle_click
    b Lmain_loop
Lmain_draw:
    bl _SDL_GetTicks
    mov w24, w0
    ADDR x9, _screen
    ldr w9, [x9]
    cbz w9, Lmain_scene_ready   // Esc freezes the gameplay presentation timeline.
    bl _anim_tick
    bl _poll_held_movement
Lmain_scene_ready:
    bl _render_frame
    ADDR x9, _renderer
    ldr x0, [x9]
    bl _SDL_RenderPresent
    ADDR x9, _frame
    ldr w10, [x9]
    add w10, w10, #1
    str w10, [x9]
    bl _SDL_GetTicks
    sub w0, w0, w24
    cmp w0, #16
    b.hs Lmain_loop
    mov w9, #16
    sub w0, w9, w0
    bl _SDL_Delay              // Vsync normally consumes the whole frame budget.
    b Lmain_loop
Lmain_error:
    ADDR x0, Lerror
    bl _puts
    bl _SDL_GetError
    bl _puts
    mov w23, #1
Lmain_cleanup:
    bl _audio_shutdown
    ADDR x9, _renderer
    ldr x0, [x9]
    cbz x0, Lmain_destroy_window
    bl _SDL_DestroyRenderer
Lmain_destroy_window:
    ADDR x9, _window
    ldr x0, [x9]
    cbz x0, Lmain_quit
    bl _SDL_DestroyWindow
Lmain_quit:
    bl _SDL_Quit
    b Lmain_exit
Lmain_selftest:
    bl _game_selftest
    mov w23, w0
    cbnz w23, Lmain_test_failed
    ADDR x0, Ltests_passed
    bl _puts
    b Lmain_exit
Lmain_test_failed:
    ADDR x0, Ltests_failed
    bl _puts
    b Lmain_exit
Lmain_audiotest:
    bl _audio_selftest
    mov w23, w0
    cbnz w23, Lmain_audio_failed
    ADDR x0, Laudio_passed
    bl _puts
    b Lmain_exit
Lmain_audio_failed:
    ADDR x0, Laudio_failed
    bl _puts
    b Lmain_exit
Lmain_animationtest:
    bl _anim_selftest
    mov w23, w0
    cbnz w23, Lmain_animation_failed
    ADDR x0, Lanimation_passed
    bl _puts
    b Lmain_exit
Lmain_animation_failed:
    ADDR x0, Lanimation_failed
    bl _puts
    b Lmain_exit
Lmain_worldtest:
    bl _game_world_selftest
    mov w23, w0
    cbnz w23, Lmain_world_failed
    ADDR x0, Lworld_passed
    bl _puts
    b Lmain_exit
Lmain_world_failed:
    ADDR x0, Lworld_failed
    bl _puts
    b Lmain_exit
Lmain_savetest:
    bl _save_selftest
    mov w23, w0
    cbnz w23, Lmain_save_failed
    ADDR x0, Lsave_passed
    bl _puts
    b Lmain_exit
Lmain_save_failed:
    ADDR x0, Lsave_failed
    bl _puts
    b Lmain_exit
Lmain_savepath:
    bl _game_init
    bl _SDL_SetMainReady
    bl _save_init
    mov w23, w0
    ADDR x0, _save_path
    bl _puts
Lmain_exit:
    mov w0, w23
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

// Parse an optional decimal snapshot tick0..90. Invalid input keeps default22.
.p2align 2
_parse_snapshot_ticks:
    mov w13, #90
    mov w14, #22
    b Lparse_ticks_common
_parse_evolution_ticks:
    mov w13, #240
    mov w14, #180
Lparse_ticks_common:
    mov w9, #0
    mov w10, #0
Lparse_tick_digit:
    ldrb w11, [x0], #1
    cbz w11, Lparse_tick_done
    sub w11, w11, #48
    cmp w11, #9
    b.hi Lparse_tick_invalid
    mov w12, #10
    madd w9, w9, w12, w11
    cmp w9, w13
    b.hi Lparse_tick_invalid
    mov w10, #1
    b Lparse_tick_digit
Lparse_tick_done:
    cbz w10, Lparse_tick_invalid
    mov w0, w9
    ret
Lparse_tick_invalid:
    mov w0, w14
    ret

// A title resume preserves unsaved in-memory progress. Only the first start
// loads a save; N always creates a new session without writing over that save.
.p2align 2
_start_or_resume:
    stp x29, x30, [sp, #-16]!
    ADDR x9, _session_started
    ldr w9, [x9]
    cbnz w9, Lresume_enter
    ADDR x9, _save_available
    ldr w9, [x9]
    cbz w9, Lresume_new
    bl _save_load
    cbnz w0, Lresume_done
    bl _anim_init
Lresume_enter:
    bl Lenter_session
    b Lresume_done
Lresume_new:
    bl _start_new_journey
Lresume_done:
    ldp x29, x30, [sp], #16
    ret
_start_new_journey:
    stp x29, x30, [sp, #-16]!
    bl _game_init
    bl _anim_init
    ADDR x9, _save_status
    str wzr, [x9]
    bl Lenter_session
    ldp x29, x30, [sp], #16
    ret
Lenter_session:
    mov w10, #1
    ADDR x9, _session_started
    str w10, [x9]
    ADDR x9, _screen
    str w10, [x9]
    ADDR x9, _show_world_map
    str wzr, [x9]
    ret

// w0 key symbol. Returns 1 for quit, 0 otherwise.
.p2align 2
_handle_key:
    stp x29, x30, [sp, #-32]!
    stp x19, x20, [sp, #16]
    mov x29, sp
    mov w19, w0
    cmp w19, #109
    b.eq Lkey_mute
    cmp w19, #27
    b.eq Lkey_escape
    ADDR x9, _screen
    ldr w10, [x9]
    cbnz w10, Lkey_game
    cmp w19, #113               // Q on title exits.
    b.eq Lkey_quit
    cmp w19, #110               // N starts fresh; the old save is preserved.
    b.eq Lkey_new
    cmp w19, #13
    b.eq Lkey_start
    cmp w19, #32
    b.eq Lkey_start
    b Lkey_done
Lkey_start:
    bl _start_or_resume
    b Lkey_done
Lkey_new:
    bl _start_new_journey
    b Lkey_done
Lkey_escape:
    ADDR x9, _show_world_map
    ldr w10, [x9]
    cbnz w10, Lkey_close_map
    ADDR x9, _screen
    ldr w10, [x9]
    cbnz w10, Lkey_pause
    ADDR x9, _session_started
    ldr w10, [x9]
    cbz w10, Lkey_done
    ADDR x9, _screen
    mov w10, #0
Lkey_pause:
    eor w10, w10, #1
    str w10, [x9]
    b Lkey_done
Lkey_mute:
    ADDR x9, _audio_muted
    ldr w10, [x9]
    eor w10, w10, #1
    str w10, [x9]
    b Lkey_done
Lkey_game:
    ADDR x9, _show_world_map
    ldr w10, [x9]
    cbz w10, Lkey_world_closed
    cmp w19, #106
    b.eq Lkey_close_map
    cmp w19, #104
    b.eq Lkey_close_map
    b Lkey_done
Lkey_close_map:
    str wzr, [x9]
    b Lkey_done
Lkey_world_closed:
    ADDR x9, _mode
    ldr w20, [x9]
    cmp w20, #4
    b.eq Lkey_evolution
    ADDR x9, _anim_busy
    ldr w10, [x9]
    cbnz w10, Lkey_done
    ADDR x9, _mode
    ldr w20, [x9]
    cmp w19, #13
    b.eq Lkey_confirm
    cmp w19, #32
    b.eq Lkey_confirm
    cmp w19, #101
    b.eq Lkey_confirm
    cmp w20, #1
    b.eq Lkey_battle
    cbnz w20, Lkey_done
    cmp w19, #106               // J world map; H is a convenient alias.
    b.eq Lkey_open_map
    cmp w19, #104
    b.eq Lkey_open_map
    mov w9, #0x3e
    movk w9, #0x4000, lsl #16
    cmp w19, w9                // F5
    b.eq Lkey_save
    add w9, w9, #4             // F9
    cmp w19, w9
    b.eq Lkey_load
    cmp w19, #9                 // Tab cycles the lead companion on the map.
    b.eq Lkey_cycle_lead
    cmp w19, #119
    b.eq Lkey_up
    cmp w19, #115
    b.eq Lkey_down
    cmp w19, #97
    b.eq Lkey_left
    cmp w19, #100
    b.eq Lkey_right
    mov w9, #0x52
    movk w9, #0x4000, lsl #16
    cmp w19, w9                 // SDLK_UP
    b.eq Lkey_up
    sub w9, w9, #1             // SDLK_DOWN
    cmp w19, w9
    b.eq Lkey_down
    sub w9, w9, #1             // SDLK_LEFT
    cmp w19, w9
    b.eq Lkey_left
    sub w9, w9, #1             // SDLK_RIGHT
    cmp w19, w9
    b.eq Lkey_right
    b Lkey_done
Lkey_confirm:
    cbz w20, Lkey_interact
    cmp w20, #2
    b.eq Lkey_dismiss
    cmp w20, #3
    b.ne Lkey_done
    bl _start_new_journey
    b Lkey_done
Lkey_evolution:
    cmp w19, #13
    b.eq Lkey_evolution_confirm
    cmp w19, #32
    b.eq Lkey_evolution_confirm
    cmp w19, #101
    b.ne Lkey_done
Lkey_evolution_confirm:
    ADDR x9, _evolution_clock
    ldr w9, [x9]
    cmp w9, #150
    b.lt Lkey_done
    bl _anim_dismiss
    b Lkey_done
Lkey_open_map:
    ADDR x9, _walk_remaining
    ldr w9, [x9]
    cbnz w9, Lkey_done
    ADDR x9, _show_world_map
    mov w10, #1
    str w10, [x9]
    b Lkey_done
Lkey_save:
    ADDR x9, _walk_remaining
    ldr w9, [x9]
    cbnz w9, Lkey_done
    bl _save_write
    b Lkey_done
Lkey_load:
    ADDR x9, _walk_remaining
    ldr w9, [x9]
    cbnz w9, Lkey_done
    bl _save_load
    cbnz w0, Lkey_done
    bl _anim_init
    b Lkey_done
Lkey_interact:
    bl _anim_interact
    b Lkey_done
Lkey_dismiss:
    bl _anim_dismiss
    b Lkey_done
Lkey_battle:
    sub w0, w19, #49
    cmp w0, #6
    b.hi Lkey_done
    bl _anim_action
    b Lkey_done
Lkey_cycle_lead:
    bl _game_cycle_lead
    b Lkey_done
Lkey_up:
    mov w0, #0
    mov w1, #-1
    bl _anim_move
    b Lkey_done
Lkey_down:
    mov w0, #0
    mov w1, #1
    bl _anim_move
    b Lkey_done
Lkey_left:
    mov w0, #-1
    mov w1, #0
    bl _anim_move
    b Lkey_done
Lkey_right:
    mov w0, #1
    mov w1, #0
    bl _anim_move
Lkey_done:
    mov w0, #0
    b Lkey_return
Lkey_quit:
    mov w0, #1
Lkey_return:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// SDL logical mouse coordinates w0=x, w1=y.
.p2align 2
_handle_click:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ADDR x9, _screen
    ldr w10, [x9]
    cbnz w10, Lclick_game
    cmp w0, #424
    b.lt Lclick_done
    cmp w0, #696
    b.gt Lclick_done
    cmp w1, #592
    b.lt Lclick_done
    cmp w1, #646
    b.gt Lclick_done
    bl _start_or_resume
    b Lclick_done
Lclick_game:
    ADDR x9, _show_world_map
    ldr w10, [x9]
    cbnz w10, Lclick_done
    ADDR x9, _mode
    ldr w10, [x9]
    cmp w10, #4
    b.eq Lclick_evolution
    ADDR x9, _anim_busy
    ldr w10, [x9]
    cbnz w10, Lclick_done
    ADDR x9, _mode
    ldr w10, [x9]
    cbz w10, Lclick_map
    cmp w10, #2
    b.eq Lclick_dismiss
    cmp w10, #3
    b.eq Lclick_restart
    cmp w1, #634
    b.lt Lclick_done
    cmp w1, #738
    b.gt Lclick_done
    mov w11, #0
    cmp w1, #680
    b.le Lclick_column
    cmp w1, #692
    b.lt Lclick_done
    mov w11, #3
Lclick_column:
    cmp w0, #32
    b.lt Lclick_done
    cmp w0, #376
    b.le Lclick_action
    cmp w0, #388
    b.lt Lclick_done
    add w11, w11, #1
    cmp w0, #732
    b.le Lclick_action
    cmp w0, #744
    b.lt Lclick_done
    cmp w0, #1088
    b.gt Lclick_done
    add w11, w11, #1
Lclick_action:
    mov w0, w11
    bl _anim_action
    b Lclick_done
Lclick_map:
    cmp w1, #632
    b.lt Lclick_done
    bl _anim_interact
    b Lclick_done
Lclick_dismiss:
    cmp w1, #608
    b.lt Lclick_done
    bl _anim_dismiss
    b Lclick_done
Lclick_restart:
    cmp w1, #608
    b.lt Lclick_done
    bl _start_new_journey
    b Lclick_done
Lclick_evolution:
    cmp w1, #608
    b.lt Lclick_done
    ADDR x9, _evolution_clock
    ldr w9, [x9]
    cmp w9, #150
    b.lt Lclick_done
    bl _anim_dismiss
Lclick_done:
    ldp x29, x30, [sp], #16
    ret

// Continuous walking follows the physical key state. Animation owns the tile
// cooldown, so holding a direction advances seamlessly without OS key repeat.
.p2align 2
_poll_held_movement:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ADDR x9, _screen
    ldr w9, [x9]
    cbz w9, Lheld_done
    ADDR x9, _show_world_map
    ldr w9, [x9]
    cbnz w9, Lheld_done
    ADDR x9, _mode
    ldr w9, [x9]
    cbnz w9, Lheld_done
    ADDR x9, _anim_busy
    ldr w9, [x9]
    cbnz w9, Lheld_done
    mov x0, #0
    bl _SDL_GetKeyboardState
    cbz x0, Lheld_done
    ldrb w9, [x0, #26]         // W
    ldrb w10, [x0, #82]        // Up
    orr w9, w9, w10
    cbnz w9, Lheld_up
    ldrb w9, [x0, #22]         // S
    ldrb w10, [x0, #81]        // Down
    orr w9, w9, w10
    cbnz w9, Lheld_down
    ldrb w9, [x0, #4]          // A
    ldrb w10, [x0, #80]        // Left
    orr w9, w9, w10
    cbnz w9, Lheld_left
    ldrb w9, [x0, #7]          // D
    ldrb w10, [x0, #79]        // Right
    orr w9, w9, w10
    cbz w9, Lheld_done
    mov w0, #1
    mov w1, #0
    b Lheld_move
Lheld_up:
    mov w0, #0
    mov w1, #-1
    b Lheld_move
Lheld_down:
    mov w0, #0
    mov w1, #1
    b Lheld_move
Lheld_left:
    mov w0, #-1
    mov w1, #0
Lheld_move:
    bl _anim_move
Lheld_done:
    ldp x29, x30, [sp], #16
    ret

// Save a complete 1120x768 BMP from the current renderer, filename in x0.
.p2align 2
_save_snapshot:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0
    mov w0, #0
    mov w1, #1120
    mov w2, #768
    mov w3, #32
    mov w4, #0x2004
    movk w4, #0x1636, lsl #16   // SDL_PIXELFORMAT_ARGB8888 = 0x16362004
    bl _SDL_CreateRGBSurfaceWithFormat
    cbz x0, Lsnapshot_error
    mov x20, x0
    ADDR x9, _renderer
    ldr x0, [x9]
    mov x1, #0
    mov w2, #0x2004
    movk w2, #0x1636, lsl #16
    ldr x3, [x20, #32]          // SDL_Surface.pixels
    ldr w4, [x20, #24]          // SDL_Surface.pitch
    bl _SDL_RenderReadPixels
    cbnz w0, Lsnapshot_surface_error
    mov x0, x19
    ADDR x1, Lwrite_mode
    bl _SDL_RWFromFile
    cbz x0, Lsnapshot_surface_error
    mov x1, x0
    mov x0, x20
    mov w2, #1                  // close the RWops when finished
    bl _SDL_SaveBMP_RW
    mov w21, w0
    mov x0, x20
    bl _SDL_FreeSurface
    cmp w21, #0
    cset w0, ne
    b Lsnapshot_return
Lsnapshot_surface_error:
    mov x0, x20
    bl _SDL_FreeSurface
Lsnapshot_error:
    bl _SDL_GetError
    bl _puts
    mov w0, #1
Lsnapshot_return:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

.section __TEXT,__cstring,cstring_literals
Lwindow_title: .asciz "Tidebloom Journeys | An assembly creature-taming adventure"
Lsnapshot_flag: .asciz "--snapshot"
Lsnapshot_map_flag: .asciz "--snapshot-map"
Lsnapshot_battle_flag: .asciz "--snapshot-battle"
Lsnapshot_win_flag: .asciz "--snapshot-win"
Lsnapshot_impact_flag: .asciz "--snapshot-impact"
Lselftest_flag: .asciz "--self-test"
Laudiotest_flag: .asciz "--audio-test"
Lanimationtest_flag: .asciz "--animation-test"
Lworldtest_flag: .asciz "--world-test"
Lsavetest_flag: .asciz "--save-test"
Lsavepath_flag: .asciz "--save-path"
Lrecord_flag: .asciz "--record-demo"
Levolution_flag: .asciz "--snapshot-evolution"
Lworldmap_snapshot_flag: .asciz "--snapshot-world-map"
Lrender_driver_hint: .asciz "SDL_RENDER_DRIVER"
Lsoftware: .asciz "software"
Lwrite_mode: .asciz "wb"
Lerror: .asciz "Tidebloom could not initialize its display:"
Ltests_passed: .asciz "TIDEBLOOM: all assembly gameplay self-tests passed."
Ltests_failed: .asciz "TIDEBLOOM: gameplay self-test failed (failure number is exit status)."
Laudio_passed: .asciz "TIDEBLOOM: synthesized audio, effect, range, buffer and mute tests passed."
Laudio_failed: .asciz "TIDEBLOOM: audio self-test failed (failure number is exit status)."
Lanimation_passed: .asciz "TIDEBLOOM: movement, battle timeline, HP and input-gating tests passed."
Lanimation_failed: .asciz "TIDEBLOOM: animation self-test failed (failure number is exit status)."
Lworld_passed: .asciz "JOURNEYS: region, progression and world tests passed."
Lworld_failed: .asciz "JOURNEYS: world self-test failed (failure number is exit status)."
Lsave_passed: .asciz "JOURNEYS: save roundtrip, validation and atomic-failure tests passed."
Lsave_failed: .asciz "JOURNEYS: save test failed. Set TIDEBLOOM_SAVE_PATH to an isolated work path; exit90 means missing path."

.section __DATA,__data
.p2align 3
.globl _renderer, _window, _frame, _screen, _session_started
_renderer: .quad 0
_window: .quad 0
_frame: .long 0
_screen: .long 0
_session_started: .long 0
_snapshot_frame_count: .long 22
_snapshot_map_id: .long 0
_snapshot_evolution_clock: .long 180
.p2align 3
_event: .space 64, 0
