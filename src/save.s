// JOURNEYS — versioned, pointer-free saves and atomic commits in ARM64 assembly.
// Format: 32-byte header followed by engine-described32-bit state fields.
// Header: magic8, version3, headerSize32, payloadBytes, FNV1a32, reserved0.
// Every load checks exact length, checksum and engine invariants BEFORE commit.
// Every write uses an exclusive same-directory temporary file, write-all,
// fsync, checked close, then atomic rename. Errors preserve the previous save.
// No file is written by init/probe/load. Demo callers must set an isolated path.

.macro SPTR reg,sym
 adrp \reg,\sym@PAGE
 add \reg,\reg,\sym@PAGEOFF
.endmacro
.macro SGET reg,sym
 adrp x16,\sym@PAGE
 ldr \reg,[x16,\sym@PAGEOFF]
.endmacro
.macro SSET reg,sym
 adrp x16,\sym@PAGE
 str \reg,[x16,\sym@PAGEOFF]
.endmacro
.text
.p2align 2
.globl _save_init,_save_set_path,_save_write,_save_load,_save_selftest
_save_init:
 stp x29,x30,[sp,#-48]!
 stp x19,x20,[sp,#16]
 stp x21,x22,[sp,#32]
 SPTR x0,Lsave_env
 bl _getenv
 cbz x0,Lsave_base
 ldrb w9,[x0]
 cbnz w9,Lsave_init_path
Lsave_base:
 bl _SDL_GetBasePath
 cbz x0,Lsave_init_error
 mov x19,x0
 bl _strlen
 mov x20,x0
 SPTR x21,Lsave_filename
 cmp x20,#24
 b.lt Lsave_check_macos
 sub x0,x20,#24
 add x0,x19,x0
 mov x22,x0
 SPTR x1,Lresources_suffix
 bl _strcmp
 cbz w0,Lsave_bundle_relative
Lsave_check_macos:
 cmp x20,#20
 b.lt Lsave_base_copy
 sub x0,x20,#20
 add x0,x19,x0
 mov x22,x0
 SPTR x1,Lapp_suffix
 bl _strcmp
 cbnz w0,Lsave_base_copy
Lsave_bundle_relative:
 // Strip the complete bundle basename, rather than leaving ../../../ in the
 // path. Both SDL MacOS/ and Resources/ conventions resolve beside the app.
 mov x9,x22
Lsave_bundle_parent:
 cmp x9,x19
 b.ls Lsave_base_error
 sub x9,x9,#1
 ldrb w10,[x9]
 cmp w10,#47
 b.ne Lsave_bundle_parent
 sub x20,x9,x19
 add x20,x20,#1
Lsave_base_copy:
 cmp x20,#3900
 b.hi Lsave_base_error
 SPTR x0,Lsave_candidate
 mov x1,x19
 mov w2,w20
 bl Lcopy_bytes
 SPTR x0,Lsave_candidate
 add x0,x0,x20
 mov x1,x21
 bl Lcopy_string
 mov x0,x19
 bl _SDL_free
 SPTR x0,Lsave_candidate
Lsave_init_path:
 bl _save_set_path
 b Lsave_init_return
Lsave_base_error:
 mov x0,x19
 bl _SDL_free
Lsave_init_error:
 mov w9,#0
 SSET w9,Lsave_initialized
 SSET w9,_save_available
 mov w9,#3
 SSET w9,_save_status
 mov w0,#1
Lsave_init_return:
 ldp x21,x22,[sp,#32]
 ldp x19,x20,[sp,#16]
 ldp x29,x30,[sp],#48
 ret

// Explicit path selection, also used by the demo recorder. Only probes the path.
_save_set_path:
 stp x29,x30,[sp,#-32]!
 stp x19,x20,[sp,#16]
 mov x19,x0
 cbz x19,Lset_path_error
 bl _strlen
 cbz x0,Lset_path_error
 cmp x0,#4000
 b.hi Lset_path_error
 SPTR x0,Lsave_path
 mov x1,x19
 bl Lcopy_string
 mov w9,#1
 SSET w9,Lsave_initialized
 mov w9,#0
 SSET w9,_save_available
 SSET w9,_save_status
 bl Lread_staging
 cbnz w0,Lset_path_probe
 mov w9,#1
 SSET w9,_save_available
 b Lset_path_ok
Lset_path_probe:
 cmp w0,#1                  // Missing save is normal on first launch.
 b.eq Lset_path_ok
 mov w9,#3
 SSET w9,_save_status
Lset_path_ok:
 mov w0,#0
 b Lset_path_return
Lset_path_error:
 // Fail closed: a rejected demo/test path must never leave an earlier
 // interactive destination active for a subsequent write.
 mov w9,#0
 SSET w9,Lsave_initialized
 SSET w9,_save_available
 SPTR x9,Lsave_path
 strb wzr,[x9]
 mov w9,#3
 SSET w9,_save_status
 mov w0,#1
Lset_path_return:
 ldp x19,x20,[sp,#16]
 ldp x29,x30,[sp],#32
 ret

// Private copy of a known-bounded, NUL-terminated string. x0dest,x1source.
Lcopy_string:
 ldrb w9,[x1],#1
 strb w9,[x0],#1
 cbnz w9,Lcopy_string
 ret

// Pack/unpack only the descriptor fields. No pointers or transient UI state.
Lpack_payload:
 SPTR x9,_save_fields
 SGET w10,_save_field_count
Lpack_field:
 ldp x11,x12,[x9],#16
Lpack_word:
 ldr w13,[x11],#4
 str w13,[x0],#4
 subs x12,x12,#4
 b.ne Lpack_word
 subs w10,w10,#1
 b.ne Lpack_field
 ret
Lunpack_payload:
 SPTR x9,_save_fields
 SGET w10,_save_field_count
Lunpack_field:
 ldp x11,x12,[x9],#16
Lunpack_word:
 ldr w13,[x0],#4
 str w13,[x11],#4
 subs x12,x12,#4
 b.ne Lunpack_word
 subs w10,w10,#1
 b.ne Lunpack_field
 ret

// FNV1a32 over x0buffer,w1length; returns w0checksum.
Lsave_hash:
 movz w9,#0x9dc5
 movk w9,#0x811c,lsl#16
 movz w10,#0x0193
 movk w10,#0x0100,lsl#16
 cbz w1,Lhash_done
Lhash_byte:
 ldrb w11,[x0],#1
 eor w9,w9,w11
 mul w9,w9,w10
 subs w1,w1,#1
 b.ne Lhash_byte
Lhash_done:
 mov w0,w9
 ret

_save_write:
 stp x29,x30,[sp,#-64]!
 stp x19,x20,[sp,#16]
 stp x21,x22,[sp,#32]
 stp x23,x24,[sp,#48]
 mov w19,#-1
 SGET w9,Lsave_initialized
 cbz w9,Lwrite_error
 SGET w9,_mode
 cbnz w9,Lwrite_error
 SGET w20,_save_payload_size
 cbz w20,Lwrite_error
 cmp w20,#4096
 b.hi Lwrite_error
 SPTR x0,Lsave_image
 add x0,x0,#32
 bl Lpack_payload
 SPTR x0,Lsave_image
 add x0,x0,#32
 mov w1,w20
 bl _game_validate_save
 cbnz w0,Lwrite_error
 SPTR x0,Lsave_image
 add x0,x0,#32
 mov w1,w20
 bl Lsave_hash
 SPTR x21,Lsave_image
 SPTR x9,Lsave_magic
 ldr x9,[x9]
 str x9,[x21]
 mov w9,#3
 str w9,[x21,#8]
 mov w9,#32
 str w9,[x21,#12]
 str w20,[x21,#16]
 str w0,[x21,#20]
 str xzr,[x21,#24]
 SPTR x0,Lsave_path
 bl _strlen
 mov x22,x0
 SPTR x0,Lsave_temp
 SPTR x1,Lsave_path
 bl Lcopy_string
 SPTR x0,Lsave_temp
 add x0,x0,x22
 SPTR x1,Ltemp_suffix
 bl Lcopy_string
 SPTR x0,Lsave_temp
 bl _mkstemp
 cmp w0,#0
 b.lt Lwrite_error
 mov w19,w0
 mov x1,x21
 add w2,w20,#32
 bl Lwrite_all
 cbnz w0,Lwrite_close_error
 mov w0,w19
 bl _fsync
 cbnz w0,Lwrite_close_error
 mov w0,w19
 bl _close
 mov w19,#-1
 cbnz w0,Lwrite_temp_error
 SGET w9,Lsave_test_fail_before_rename
 cbnz w9,Lwrite_temp_error
 SPTR x0,Lsave_temp
 SPTR x1,Lsave_path
 bl _rename
 cbnz w0,Lwrite_temp_error
 mov w9,#1
 SSET w9,_save_available
 SSET w9,_save_status
 mov w0,#0
 b Lwrite_return
Lwrite_close_error:
 mov w0,w19
 bl _close
 mov w19,#-1
Lwrite_temp_error:
 SPTR x0,Lsave_temp
 bl _unlink
Lwrite_error:
 mov w9,#3
 SSET w9,_save_status
 mov w0,#1
Lwrite_return:
 ldp x23,x24,[sp,#48]
 ldp x21,x22,[sp,#32]
 ldp x19,x20,[sp,#16]
 ldp x29,x30,[sp],#64
 ret

_save_load:
 stp x29,x30,[sp,#-32]!
 stp x19,x20,[sp,#16]
 SGET w9,Lsave_initialized
 cbz w9,Lload_error
 bl Lread_staging
 cbz w0,Lload_commit
 cmp w0,#1
 b.ne Lload_error
 mov w9,#0
 SSET w9,_save_available
 mov w9,#4
 SSET w9,_save_status
 mov w0,#1
 b Lload_return
Lload_commit:
 // A rollback copy additionally protects against an unexpected after-load error.
 SPTR x0,Lsave_backup
 bl Lpack_payload
 SPTR x0,Lsave_image
 add x0,x0,#32
 bl Lunpack_payload
 bl _game_after_load
 cbz w0,Lload_success
 SPTR x0,Lsave_backup
 bl Lunpack_payload
 bl _game_after_load
 b Lload_error
Lload_success:
 mov w9,#1
 SSET w9,_save_available
 mov w9,#2
 SSET w9,_save_status
 mov w0,#0
 b Lload_return
Lload_error:
 mov w9,#3
 SSET w9,_save_status
 mov w0,#1
Lload_return:
 ldp x19,x20,[sp,#16]
 ldp x29,x30,[sp],#32
 ret

// Read into staging, check full header/EOF/hash/invariants. No live state changes.
// Return0 valid,1 not found,2 malformed or I/O error.
Lread_staging:
 stp x29,x30,[sp,#-64]!
 stp x19,x20,[sp,#16]
 stp x21,x22,[sp,#32]
 stp x23,x24,[sp,#48]
 SPTR x0,Lsave_path
 mov w1,#0
 bl _open
 cmp w0,#0
 b.ge Lread_opened
 bl ___error
 ldr w9,[x0]
 cmp w9,#2
 mov w0,#2
 mov w9,#1
 csel w0,w9,w0,eq
 b Lread_return
Lread_opened:
 mov w19,w0
 SPTR x1,Lsave_image
 mov w2,#32
 bl Lread_exact
 cbnz w0,Lread_close_error
 SPTR x21,Lsave_image
 SPTR x9,Lsave_magic
 ldr x9,[x9]
 ldr x10,[x21]
 cmp x9,x10
 b.ne Lread_close_error
 ldr w9,[x21,#8]
 cmp w9,#3
 b.ne Lread_close_error
 ldr w9,[x21,#12]
 cmp w9,#32
 b.ne Lread_close_error
 ldr w20,[x21,#16]
 SGET w9,_save_payload_size
 cmp w20,w9
 b.ne Lread_close_error
 cbz w20,Lread_close_error
 cmp w20,#4096
 b.hi Lread_close_error
 ldr x9,[x21,#24]
 cbnz x9,Lread_close_error
 ldr w22,[x21,#20]
 mov w0,w19
 add x1,x21,#32
 mov w2,w20
 bl Lread_exact
 cbnz w0,Lread_close_error
Lread_eof:
 mov w0,w19
 SPTR x1,Lsave_extra
 mov w2,#1
 bl _read
 cbz x0,Lread_close
 cmp x0,#0
 b.gt Lread_close_error
 bl ___error
 ldr w9,[x0]
 cmp w9,#4
 b.eq Lread_eof
 b Lread_close_error
Lread_close:
 mov w0,w19
 bl _close
 cbnz w0,Lread_error
 add x0,x21,#32
 mov w1,w20
 bl Lsave_hash
 cmp w0,w22
 b.ne Lread_error
 add x0,x21,#32
 mov w1,w20
 bl _game_validate_save
 cbnz w0,Lread_error
 mov w0,#0
 b Lread_return
Lread_close_error:
 mov w0,w19
 bl _close
Lread_error:
 mov w0,#2
Lread_return:
 ldp x23,x24,[sp,#48]
 ldp x21,x22,[sp,#32]
 ldp x19,x20,[sp,#16]
 ldp x29,x30,[sp],#64
 ret

// Short reads/writes and EINTR are handled; zero-progress is failure.
Lwrite_all:
 stp x29,x30,[sp,#-48]!
 stp x19,x20,[sp,#16]
 stp x21,x22,[sp,#32]
 mov w19,w0
 mov x20,x1
 mov w21,w2
Lwrite_all_loop:
 mov w0,w19
 mov x1,x20
 mov w2,w21
 bl _write
 cmp x0,#0
 b.gt Lwrite_all_progress
 b.eq Lwrite_all_error
 bl ___error
 ldr w9,[x0]
 cmp w9,#4
 b.eq Lwrite_all_loop
 b Lwrite_all_error
Lwrite_all_progress:
 add x20,x20,x0
 subs w21,w21,w0
 b.ne Lwrite_all_loop
 mov w0,#0
 b Lwrite_all_done
Lwrite_all_error:
 mov w0,#1
Lwrite_all_done:
 ldp x21,x22,[sp,#32]
 ldp x19,x20,[sp,#16]
 ldp x29,x30,[sp],#48
 ret
Lread_exact:
 stp x29,x30,[sp,#-48]!
 stp x19,x20,[sp,#16]
 stp x21,x22,[sp,#32]
 mov w19,w0
 mov x20,x1
 mov w21,w2
Lread_exact_loop:
 mov w0,w19
 mov x1,x20
 mov w2,w21
 bl _read
 cmp x0,#0
 b.gt Lread_exact_progress
 b.eq Lread_exact_error
 bl ___error
 ldr w9,[x0]
 cmp w9,#4
 b.eq Lread_exact_loop
 b Lread_exact_error
Lread_exact_progress:
 add x20,x20,x0
 subs w21,w21,w0
 b.ne Lread_exact_loop
 mov w0,#0
 b Lread_exact_done
Lread_exact_error:
 mov w0,#1
Lread_exact_done:
 ldp x21,x22,[sp,#32]
 ldp x19,x20,[sp,#16]
 ldp x29,x30,[sp],#48
 ret

// Test suite requires TIDEBLOOM_SAVE_PATH. It appends.selftest, so a real save
// at the configured path is never touched. Tests operate only on that fixture.
_save_selftest:
 stp x29,x30,[sp,#-64]!
 stp x19,x20,[sp,#16]
 stp x21,x22,[sp,#32]
 stp x23,x24,[sp,#48]
 mov w19,#90
 SPTR x0,Lsave_env
 bl _getenv
 cbz x0,Ltest_return
 mov x20,x0
 bl _strlen
 cbz x0,Ltest_return
 cmp x0,#3900
 b.hi Ltest_return
 mov x21,x0
 SPTR x0,Lsave_candidate
 mov x1,x20
 bl Lcopy_string
 SPTR x0,Lsave_candidate
 add x0,x0,x21
 SPTR x1,Lselftest_suffix
 bl Lcopy_string
 SPTR x0,Lsave_candidate
 bl _save_set_path
 cbnz w0,Ltest_return
 SPTR x0,Lsave_path
 bl _unlink
 bl _game_save_test_fixture
 SPTR x0,Lsave_expected
 bl Lpack_payload
 mov w19,#1
 bl _save_write
 cbnz w0,Ltest_return
 // Preserve the valid serialized image for corruption cases.
 SPTR x0,Lsave_good_image
 SPTR x1,Lsave_image
 SGET w2,_save_payload_size
 add w2,w2,#32
 bl Lcopy_bytes
 bl _game_init
 mov w19,#2
 bl _save_load
 cbnz w0,Ltest_return
 bl Ltest_compare_state
 cbnz w0,Ltest_return
 // A forced pre-rename failure must leave the previous save byte-for-byte valid.
 mov w19,#3
 mov w9,#0
 SSET w9,_coins
 mov w9,#1
 SSET w9,Lsave_test_fail_before_rename
 bl _save_write
 mov w20,w0
 mov w9,#0
 SSET w9,Lsave_test_fail_before_rename
 cbz w20,Ltest_return
 bl _game_init
 bl _save_load
 cbnz w0,Ltest_return
 bl Ltest_compare_state
 cbnz w0,Ltest_return
 mov w20,#0
Ltest_corruption:
 SPTR x0,Lsave_image
 SPTR x1,Lsave_good_image
 SGET w2,_save_payload_size
 add w2,w2,#32
 bl Lcopy_bytes
 SGET w21,_save_payload_size
 add w21,w21,#32
 SPTR x22,Lsave_image
 cmp w20,#0
 b.eq Ltest_truncated
 cmp w20,#1
 b.eq Ltest_checksum
 cmp w20,#2
 b.eq Ltest_version
 cmp w20,#3
 b.eq Ltest_magic
 cmp w20,#4
 b.eq Ltest_trailing
 cmp w20,#5
 b.eq Ltest_length
 // Cases6..10 have a correct checksum but invalid engine state.
 mov w9,#99
 cmp w20,#6
 b.eq Ltest_bad_map
 cmp w20,#7
 b.eq Ltest_bad_active
 cmp w20,#8
 b.eq Ltest_bad_hp
 cmp w20,#9
 b.eq Ltest_bad_species
 str wzr,[x22,#108]           // Payloadword19: level of populated lead.
 b Ltest_rehash
Ltest_bad_map:
 str w9,[x22,#32]
 b Ltest_rehash
Ltest_bad_active:
 str w9,[x22,#68]
 b Ltest_rehash
Ltest_bad_hp:
 mov w9,#30000
 str w9,[x22,#84]
 b Ltest_rehash
Ltest_bad_species:
 str w9,[x22,#72]
Ltest_rehash:
 add x0,x22,#32
 SGET w1,_save_payload_size
 bl Lsave_hash
 str w0,[x22,#20]
 b Ltest_write_bad
Ltest_truncated:
 sub w21,w21,#1
 b Ltest_write_bad
Ltest_checksum:
 ldrb w9,[x22,#40]
 eor w9,w9,#1
 strb w9,[x22,#40]
 b Ltest_write_bad
Ltest_version:
 mov w9,#99
 str w9,[x22,#8]
 b Ltest_write_bad
Ltest_magic:
 strb wzr,[x22]
 b Ltest_write_bad
Ltest_trailing:
 strb wzr,[x22,w21,uxtw]
 add w21,w21,#1
 b Ltest_write_bad
Ltest_length:
 mov w9,#4097
 str w9,[x22,#16]
Ltest_write_bad:
 add w19,w20,#10
 mov w0,w21
 bl Ltest_write_image
 cbnz w0,Ltest_return
 bl _save_load
 cbz w0,Ltest_return
 bl Ltest_compare_state
 cbnz w0,Ltest_return
 add w20,w20,#1
 cmp w20,#11
 b.lt Ltest_corruption
 mov w19,#30
 SPTR x0,Lsave_path
 bl _unlink
 bl _save_load
 cbz w0,Ltest_return
 SGET w9,_save_status
 cmp w9,#4
 b.ne Ltest_return
 mov w19,#0
Ltest_return:
 mov w9,#0
 SSET w9,Lsave_test_fail_before_rename
 mov w0,w19
 ldp x23,x24,[sp,#48]
 ldp x21,x22,[sp,#32]
 ldp x19,x20,[sp,#16]
 ldp x29,x30,[sp],#64
 ret

Lcopy_bytes:
 cbz w2,Lcopy_bytes_done
Lcopy_bytes_loop:
 ldrb w9,[x1],#1
 strb w9,[x0],#1
 subs w2,w2,#1
 b.ne Lcopy_bytes_loop
Lcopy_bytes_done:
 ret
Ltest_compare_state:
 stp x29,x30,[sp,#-16]!
 SPTR x0,Lsave_backup
 bl Lpack_payload
 SPTR x9,Lsave_backup
 SPTR x10,Lsave_expected
 SGET w11,_save_payload_size
Ltest_compare_byte:
 ldrb w12,[x9],#1
 ldrb w13,[x10],#1
 cmp w12,w13
 b.ne Ltest_compare_bad
 subs w11,w11,#1
 b.ne Ltest_compare_byte
 mov w0,#0
 b Ltest_compare_done
Ltest_compare_bad:
 mov w0,#1
Ltest_compare_done:
 ldp x29,x30,[sp],#16
 ret
Ltest_write_image:
 stp x29,x30,[sp,#-32]!
 stp x19,x20,[sp,#16]
 mov w19,w0
 SPTR x0,Lsave_path
 SPTR x1,Lbinary_write
 bl _fopen
 cbz x0,Ltest_write_failed
 mov x20,x0
 SPTR x0,Lsave_image
 mov x1,#1
 mov w2,w19
 mov x3,x20
 bl _fwrite
 cmp w0,w19
 cset w19,ne
 mov x0,x20
 bl _fclose
 cmp w0,#0
 cset w0,ne
 orr w0,w0,w19
 b Ltest_write_done
Ltest_write_failed:
 mov w0,#1
Ltest_write_done:
 ldp x19,x20,[sp,#16]
 ldp x29,x30,[sp],#32
 ret

.section __TEXT,__cstring,cstring_literals
Lsave_env: .asciz "TIDEBLOOM_SAVE_PATH"
Lsave_filename: .asciz "tidebloom-save.dat"
Lsave_app_relative: .asciz "../../../tidebloom-save.dat"
Lapp_suffix: .asciz ".app/Contents/MacOS/"
Lresources_suffix: .asciz ".app/Contents/Resources/"
Ltemp_suffix: .asciz ".tmp.XXXXXX"
Lselftest_suffix: .asciz ".selftest"
Lbinary_write: .asciz "wb"
.section __DATA,__data
.p2align 3
.globl _save_available,_save_status,_save_path
_save_available: .long 0
_save_status: .long 0
Lsave_initialized: .long 0
Lsave_test_fail_before_rename: .long 0
Lsave_magic: .ascii "TDBLOOM3"
Lsave_extra: .space 8,0
_save_path:
Lsave_path: .space 4096,0
Lsave_temp: .space 4096,0
Lsave_candidate: .space 4096,0
Lsave_image: .space 4136,0
Lsave_good_image: .space 4136,0
Lsave_backup: .space 4096,0
Lsave_expected: .space 4096,0
