// TIDEBLOOM — original procedural soundtrack and effects, entirely ARM64.
// 22050 Hz signed 16-bit mono. No sampled assets, no generated C glue.
// A triangle lead, soft pulse bass and fading noise percussion play 32-step
// island/battle/ending patterns. Event sounds use an independent swept voice.
// SDL owns the device; this assembly callback synthesizes every output sample.
// Public: audio_init(), audio_shutdown(), audio_sfx(event0..5), audio_selftest().
// _audio_muted is a 32-bit flag, safe to change from the main thread.

.macro APTR reg, sym
    adrp \reg, \sym@PAGE
    add \reg, \reg, \sym@PAGEOFF
.endmacro
.equ A_LEAD, 0
.equ A_BASS, 4
.equ A_FXPHASE, 8
.equ A_NOISE, 12
.equ A_BEAT, 16
.equ A_NOTE, 20
.equ A_THEME, 24
.equ A_LEADSTEP, 28
.equ A_BASSSTEP, 32
.equ A_FXLEFT, 36
.equ A_FXKIND, 40
.equ A_FXSTEP, 44
.equ A_DEVICE, 48
.equ A_BEATLEN, 52

.text
.p2align 2
.globl _audio_init
_audio_init:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl Laudio_reset
    mov w0, #0x10                // SDL_INIT_AUDIO
    bl _SDL_InitSubSystem
    cbnz w0, Laudio_init_done    // Sound is optional if no device is available.
    mov x0, #0
    mov w1, #0
    APTR x2, Laudio_spec
    mov x3, #0
    mov w4, #0                  // Exact format, SDL converts to hardware format.
    bl _SDL_OpenAudioDevice
    APTR x9, Laudio_state
    str w0, [x9, #A_DEVICE]
    cbz w0, Laudio_init_done
    mov w1, #0                  // Unpause only after all callback state exists.
    bl _SDL_PauseAudioDevice
Laudio_init_done:
    APTR x9, Laudio_state
    ldr w0, [x9, #A_DEVICE]
    cmp w0, #0
    cset w0, ne                 //1 device ready,0 silently unavailable.
    ldp x29, x30, [sp], #16
    ret

.globl _audio_shutdown
_audio_shutdown:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    APTR x9, Laudio_state
    ldr w0, [x9, #A_DEVICE]
    cbz w0, Laudio_shutdown_done
    str wzr, [x9, #A_DEVICE]
    bl _SDL_CloseAudioDevice    // Waits for any in-flight callback to finish.
Laudio_shutdown_done:
    ldp x29, x30, [sp], #16
    ret

.globl _audio_sfx
_audio_sfx:
    cmp w0, #5
    b.hi Laudio_sfx_done
    add w0, w0, #1
    APTR x9, Laudio_request
    stlr w0, [x9]               // Publish only a request, not mutable synth state.
Laudio_sfx_done:
    ret

.globl _audio_reset_for_recording
_audio_reset_for_recording:
Laudio_reset:
    APTR x9, Laudio_state
    stp xzr, xzr, [x9]
    stp xzr, xzr, [x9, #16]
    stp xzr, xzr, [x9, #32]
    str xzr, [x9, #48]
    mov w10, #-1
    str w10, [x9, #A_THEME]
    movz w10, #0x9bdf
    movk w10, #0x1357, lsl #16
    str w10, [x9, #A_NOISE]
    APTR x9, Laudio_request
    str wzr, [x9]
    ret

// SDL callback: userdata x0, output buffer x1, byte length w2.
// Registers x19..x28 hold persistent oscillator state within this buffer.
.p2align 2
.globl _audio_callback
_audio_callback:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]
    mov x19, x1
    lsr w20, w2, #1
    cbz w20, Laudio_callback_done
    APTR x21, Laudio_state
    APTR x9, _mode
    ldr w10, [x9]
    mov w28, #0
    cmp w10, #1
    cset w28, eq
    cmp w10, #2
    mov w11, #1
    csel w28, w11, w28, eq
    cmp w10, #3
    mov w11, #2
    csel w28, w11, w28, eq
    cmp w10, #4                // Evolution shares the celebratory theme.
    csel w28, w11, w28, eq
    APTR x9, _screen
    ldr w10, [x9]
    cmp w10, #0
    csel w28, wzr, w28, eq
    ldr w9, [x21, #A_THEME]
    cmp w9, w28
    b.eq Laudio_same_theme
    str w28, [x21, #A_THEME]
    str wzr, [x21, #A_BEAT]
    str wzr, [x21, #A_NOTE]
    str wzr, [x21, #A_LEAD]
    str wzr, [x21, #A_BASS]
    mov w9, #5512               // Island: eighth notes around120 BPM.
    cmp w28, #1
    mov w10, #3675              // Battle: brisk arpeggios around180 BPM.
    csel w9, w10, w9, eq
    cmp w28, #2
    mov w10, #7350
    csel w9, w10, w9, eq
    str w9, [x21, #A_BEATLEN]
Laudio_same_theme:
    ldr w22, [x21, #A_LEAD]
    ldr w23, [x21, #A_BASS]
    ldr w24, [x21, #A_FXPHASE]
    ldr w25, [x21, #A_BEAT]
    ldr w26, [x21, #A_NOTE]
    ldr w27, [x21, #A_FXLEFT]
    bl Laudio_select_notes
    // Atomically exchange the pending effect with zero. A concurrent request
    // either becomes this effect or remains queued for the next callback.
    APTR x9, Laudio_request
Laudio_request_retry:
    ldaxr w10, [x9]
    stlxr w11, wzr, [x9]
    cbnz w11, Laudio_request_retry
    cbz w10, Laudio_sample
    sub w10, w10, #1
    str w10, [x21, #A_FXKIND]
    APTR x9, Laudio_fx_lengths
    ldr w27, [x9, w10, uxtw #2]
    APTR x9, Laudio_fx_steps
    ldr w11, [x9, w10, uxtw #2]
    str w11, [x21, #A_FXSTEP]
    mov w24, #0
Laudio_sample:
    // Phase accumulator triangle lead. Its first128 and last512 samples are
    // softly faded so note changes remain gentle despite the retro waveform.
    ldr w9, [x21, #A_LEADSTEP]
    add w22, w22, w9
    lsr w10, w22, #16
    mov w11, #65535
    sub w11, w11, w10
    cmp w10, #32768
    csel w10, w10, w11, lo
    lsl w10, w10, #1
    sub w10, w10, #32768
    asr w10, w10, #4
    cmp w9, #0
    csel w10, wzr, w10, eq
    mov w11, #128
    cmp w25, w11
    csel w11, w25, w11, lo
    mul w10, w10, w11
    asr w10, w10, #7
    ldr w12, [x21, #A_BEATLEN]
    sub w12, w12, w25
    mov w11, #512
    cmp w12, w11
    csel w11, w12, w11, lo
    mul w10, w10, w11
    asr w0, w10, #9             // w0 = running sample mix
    // Low pulse bass, deliberately much softer than the lead.
    ldr w9, [x21, #A_BASSSTEP]
    add w23, w23, w9
    mov w10, #440
    mov w11, #-440
    cmp w23, #0
    csel w10, w11, w10, lt
    cmp w9, #0
    csel w10, wzr, w10, eq
    mov w11, #128
    cmp w25, w11
    csel w11, w25, w11, lo
    mul w10, w10, w11
    asr w10, w10, #7
    add w0, w0, w10
    // Deterministic xorshift white-noise percussion, short and quiet.
    ldr w9, [x21, #A_NOISE]
    eor w9, w9, w9, lsl #13
    eor w9, w9, w9, lsr #17
    eor w9, w9, w9, lsl #5
    str w9, [x21, #A_NOISE]
    and w8, w9, #1023
    sub w8, w8, #512
    cmp w28, #1
    b.eq Laudio_drum
    tbnz w26, #0, Laudio_effect
Laudio_drum:
    mov w11, #1100
    subs w11, w11, w25
    b.le Laudio_effect
    mul w10, w8, w11
    asr w10, w10, #11
    add w0, w0, w10
Laudio_effect:
    cbz w27, Laudio_sample_store
    ldr w12, [x21, #A_FXKIND]
    ldr w9, [x21, #A_FXSTEP]
    cmp w12, #3
    b.eq Laudio_fx_arpeggio
    cmp w12, #4
    b.eq Laudio_fx_arpeggio
    cmp w12, #2
    b.ne Laudio_fx_fall
    add w9, w9, #4096           // Elemental pulse rises in pitch.
    b Laudio_fx_phase
Laudio_fx_fall:
    cmp w12, #1
    b.eq Laudio_fx_decay
    cmp w12, #5
    b.ne Laudio_fx_phase
Laudio_fx_decay:
    sub w9, w9, w9, lsr #12     // Strike/hurt fall smoothly in pitch.
    b Laudio_fx_phase
Laudio_fx_arpeggio:
    APTR x10, Laudio_fx_lengths
    ldr w10, [x10, w12, uxtw #2]
    sub w10, w10, w27
    mov w11, #2205
    udiv w10, w10, w11
    APTR x11, Laudio_catch_notes
    cmp w12, #4
    b.ne Laudio_fx_arpeggio_note
    APTR x11, Laudio_win_notes
Laudio_fx_arpeggio_note:
    ldrb w10, [x11, w10, uxtw]
    sub w10, w10, #48
    APTR x11, Laudio_steps
    ldr w9, [x11, w10, uxtw #2]
Laudio_fx_phase:
    str w9, [x21, #A_FXSTEP]
    add w24, w24, w9
    lsr w10, w24, #16
    mov w11, #65535
    sub w11, w11, w10
    cmp w10, #32768
    csel w10, w10, w11, lo
    lsl w10, w10, #1
    sub w10, w10, #32768
    asr w10, w10, #4
    cmp w12, #0                // Steps sound like tiny soft footfalls.
    asr w11, w8, #1
    csel w10, w11, w10, eq
    cmp w12, #1
    b.ne Laudio_fx_envelope
    add w10, w10, w8           // Impacts add a percussive edge.
Laudio_fx_envelope:
    mov w11, #1024
    cmp w27, w11
    csel w11, w27, w11, lo
    mul w10, w10, w11
    asr w10, w10, #10
    add w0, w0, w10
    sub w27, w27, #1
Laudio_sample_store:
    mov w9, #12000
    cmp w0, w9
    csel w0, w9, w0, gt
    neg w9, w9
    cmp w0, w9
    csel w0, w9, w0, lt
    APTR x9, _audio_muted
    ldr w9, [x9]
    cmp w9, #0
    csel w0, wzr, w0, ne
    strh w0, [x19], #2
    add w25, w25, #1
    ldr w9, [x21, #A_BEATLEN]
    cmp w25, w9
    b.lo Laudio_next_sample
    mov w25, #0
    add w26, w26, #1
    and w26, w26, #31
    bl Laudio_select_notes
Laudio_next_sample:
    subs w20, w20, #1
    b.ne Laudio_sample
    str w22, [x21, #A_LEAD]
    str w23, [x21, #A_BASS]
    str w24, [x21, #A_FXPHASE]
    str w25, [x21, #A_BEAT]
    str w26, [x21, #A_NOTE]
    str w27, [x21, #A_FXLEFT]
Laudio_callback_done:
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

// Local helper: x21 state, w26 step, w28 theme. Clobbers only x9..x13.
Laudio_select_notes:
    APTR x9, Laudio_island_lead
    APTR x10, Laudio_island_bass
    cmp w28, #1
    b.ne Laudio_select_win
    APTR x9, Laudio_battle_lead
    APTR x10, Laudio_battle_bass
    b Laudio_note_lookup
Laudio_select_win:
    cmp w28, #2
    b.ne Laudio_note_lookup
    APTR x9, Laudio_ending_lead
Laudio_note_lookup:
    ldrb w11, [x9, w26, uxtw]
    ldrb w12, [x10, w26, uxtw]
    APTR x13, Laudio_steps
    cbz w11, Laudio_lead_rest
    sub w11, w11, #48
    ldr w11, [x13, w11, uxtw #2]
Laudio_lead_rest:
    str w11, [x21, #A_LEADSTEP]
    cbz w12, Laudio_bass_rest
    sub w12, w12, #48
    ldr w12, [x13, w12, uxtw #2]
Laudio_bass_rest:
    str w12, [x21, #A_BASSSTEP]
    ret

// Offline validation exercises all themes, all six effects, amplitude bounds,
// buffer boundaries, and mute without opening an audio or video device.
.globl _audio_selftest
_audio_selftest:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    bl Laudio_reset
    APTR x9, _audio_muted
    str wzr, [x9]
    APTR x9, _screen
    mov w10, #1
    str w10, [x9]
    mov w19, #0
    mov w24, #0
Laudio_test_theme:
    APTR x9, _mode
    str w19, [x9]
    mov w20, #0
Laudio_test_effect:
    mov w0, w20
    bl _audio_sfx
    mov w21, #80               // Covers complete phrases and every effect envelope.
Laudio_test_buffer:
    APTR x1, Laudio_test_buffer_data
    mov w9, #0x65a3
    str w9, [x1, #1024]
    mov x0, #0
    mov w2, #1024
    bl _audio_callback
    APTR x22, Laudio_test_buffer_data
    ldr w9, [x22, #1024]
    mov w10, #0x65a3
    cmp w9, w10
    b.ne Laudio_test_bad_bound
    mov w23, #512
Laudio_test_sample:
    ldrsh w9, [x22], #2
    mov w10, #12000
    cmp w9, w10
    b.gt Laudio_test_bad_range
    mov w10, #-12000
    cmp w9, w10
    b.lt Laudio_test_bad_range
    cmp w9, #0
    cinc w24, w24, ne
    subs w23, w23, #1
    b.ne Laudio_test_sample
    subs w21, w21, #1
    b.ne Laudio_test_buffer
    add w20, w20, #1
    cmp w20, #6
    b.lt Laudio_test_effect
    add w19, w19, #1
    cmp w19, #4
    b.lt Laudio_test_theme
    cbz w24, Laudio_test_bad_silence
    APTR x9, _audio_muted
    mov w10, #1
    str w10, [x9]
    APTR x1, Laudio_test_buffer_data
    mov x0, #0
    mov w2, #1024
    bl _audio_callback
    APTR x22, Laudio_test_buffer_data
    mov w23, #512
Laudio_test_mute:
    ldrsh w9, [x22], #2
    cbnz w9, Laudio_test_bad_mute
    subs w23, w23, #1
    b.ne Laudio_test_mute
    mov w0, #0
    b Laudio_test_return
Laudio_test_bad_bound:
    mov w0, #1
    b Laudio_test_return
Laudio_test_bad_range:
    mov w0, #2
    b Laudio_test_return
Laudio_test_bad_silence:
    mov w0, #3
    b Laudio_test_return
Laudio_test_bad_mute:
    mov w0, #4
Laudio_test_return:
    APTR x9, _audio_muted
    str wzr, [x9]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

.section __DATA,__data
.p2align 3
.globl _audio_muted
_audio_muted: .long 0
Laudio_request: .long 0
Laudio_state: .space 56, 0
// SDL_AudioSpec: freq, format(S16LE), channels, silence, samples, padding,
// byte size, callback pointer, userdata pointer. Offsets match SDL2 headers.
.p2align 3
Laudio_spec:
    .long 22050
    .short 0x8010
    .byte 1, 0
    .short 512, 0
    .long 0
    .quad _audio_callback, 0
Laudio_fx_lengths: .long 800, 2800, 4400, 8820, 17640, 3500
Laudio_fx_steps: .long 17530479, 58434929, 81808901, 101920450, 101920450, 42852281
Laudio_catch_notes: .byte 72, 76, 79, 84
Laudio_win_notes: .byte 72, 76, 79, 84, 79, 84, 88, 91
// Original melodies: MIDI notes,0 is a rest. Low pulse bass anchors each chord.
Laudio_island_lead:
    .byte 72,0,76,79,81,79,76,0,74,0,72,67,69,0,67,0
    .byte 72,76,79,84,81,79,76,74,72,0,69,67,64,67,72,0
Laudio_island_bass:
    .byte 48,48,48,48,48,48,48,48,53,53,53,53,53,53,53,53
    .byte 57,57,57,57,57,57,57,57,55,55,55,55,55,55,55,55
Laudio_battle_lead:
    .byte 72,75,79,84,79,75,72,67,70,74,77,82,77,74,70,65
    .byte 68,72,75,80,75,72,68,63,67,71,74,79,83,79,74,71
Laudio_battle_bass:
    .byte 48,48,48,48,48,48,48,48,58,58,58,58,58,58,58,58
    .byte 56,56,56,56,56,56,56,56,55,55,55,55,55,55,55,55
Laudio_ending_lead:
    .byte 72,0,76,0,79,0,84,0,83,81,79,0,76,0,74,0
    .byte 72,76,79,84,88,0,84,0,81,79,76,74,72,0,0,0
.p2align 2
// Phase increments = round(equal-tempered Hz * 2^32 /22050), MIDI48..96.
Laudio_steps:
    .long 25480119,26995246,28600467,30301139,32102938,34011878,36034330
    .long 38177043,40447168,42852281,45400411,48100060,50960238,53990491
    .long 57200933,60602278,64205876,68023757,72068660,76354085,80894335
    .long 85704563,90800821,96200119,101920476,107980983,114401866
    .long 121204555,128411753,136047513,144137319,152708170,161788671
    .long 171409126,181601643,192400238,203840952,215961966,228803732
    .long 242409110,256823506,272095026,288274639,305416341,323577341
    .long 342818251,363203285,384800477,407681904
.p2align 3
Laudio_test_buffer_data: .space 1032, 0
