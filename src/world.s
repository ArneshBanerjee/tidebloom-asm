// Six connected regions, route gates and world interaction lookup. AArch64 only.
.macro WP reg,sym
 adrp \reg,\sym@PAGE
 add \reg,\reg,\sym@PAGEOFF
.endmacro
.macro WG reg,sym
 adrp x16,\sym@PAGE
 ldr \reg,[x16,\sym@PAGEOFF]
.endmacro
.macro WS reg,sym
 adrp x16,\sym@PAGE
 str \reg,[x16,\sym@PAGEOFF]
.endmacro
.text
.p2align 2
.globl _world_load, _world_try_exit, _world_find_interaction, _world_trainer_at
_world_load:
 cmp w0,#5
 b.hi Lworld_bad
 WS w0,_map_id
 mov w9,#345
 mul w10,w0,w9
 WP x11,_world_maps
 add x11,x11,x10
 WP x12,_map_data
Lworld_copy:
 ldrb w13,[x11],#1
 strb w13,[x12],#1
 subs w9,w9,#1
 b.ne Lworld_copy
 WP x11,_world_objectives
 ldr x12,[x11,w0,uxtw #3]
 WS x12,_world_objective
 WP x11,_world_arrivals
 ldr x12,[x11,w0,uxtw #3]
 WS x12,_message
 cmp w0,#0
 b.eq Lworld_home
 cmp w0,#2
 b.ne Lworld_ok
Lworld_home:
 WS w0,_home_map
Lworld_ok:
 mov w0,#0
 ret
Lworld_bad:
 mov w0,#1
 ret

// Candidate x,y in w0,w1. Return1 after transition,2 locked,0 not an exit.
_world_try_exit:
 stp x29,x30,[sp,#-32]!
 stp x19,x20,[sp,#16]
 cmp w1,#7
 b.ne Lexit_none
 cmp w0,#0
 b.eq Lexit_west
 cmp w0,#22
 b.ne Lexit_none
 WG w19,_map_id
 cmp w19,#5
 b.eq Lexit_blocked
 cmp w19,#1
 b.eq Lexit_reed
 cmp w19,#3
 b.eq Lexit_cinder
 cmp w19,#4
 b.eq Lexit_moon
 b Lexit_east_go
Lexit_reed:
 mov w9,#1
 mov w10,#3
 b Lexit_check
Lexit_cinder:
 mov w9,#2
 mov w10,#12
 b Lexit_check
Lexit_moon:
 mov w9,#4
 mov w10,#48
Lexit_check:
 WG w11,_beacons
 tst w11,w9
 b.eq Lexit_locked
 WG w11,_trainer_flags
 and w11,w11,w10
 cmp w11,w10
 b.ne Lexit_locked
Lexit_east_go:
 add w0,w19,#1
 mov w20,#1
 b Lexit_load
Lexit_west:
 WG w19,_map_id
 cbz w19,Lexit_blocked
 sub w0,w19,#1
 mov w20,#21
Lexit_load:
 bl _world_load
 WS w20,_player_x
 mov w9,#7
 WS w9,_player_y
 mov w9,#12
 WS w9,_last_event
 mov w0,#1
 b Lexit_done
Lexit_locked:
 WP x9,Lroute_locked
 WS x9,_message
 b Lexit_blocked
Lexit_none:
 mov w0,#0
 b Lexit_done
Lexit_blocked:
 mov w0,#2
Lexit_done:
 ldp x19,x20,[sp,#16]
 ldp x29,x30,[sp],#32
 ret

// Returns interactive tile inw0, its x/y inw1/w2. Prioritize facing, then own tile.
_world_find_interaction:
 WG w9,_player_x
 WG w10,_player_y
 WG w11,_facing
 mov w12,#0
 cmp w11,#0
 b.ne Lfind_left
 add w10,w10,#1
 b Lfind_scan
Lfind_left:
 cmp w11,#1
 b.ne Lfind_right
 sub w9,w9,#1
 b Lfind_scan
Lfind_right:
 cmp w11,#2
 b.ne Lfind_up
 add w9,w9,#1
 b Lfind_scan
Lfind_up:
 sub w10,w10,#1
Lfind_scan:
 cmp w9,#0
 b.lt Lfind_next
 cmp w9,#22
 b.gt Lfind_next
 cmp w10,#0
 b.lt Lfind_next
 cmp w10,#14
 b.gt Lfind_next
 mov w13,#23
 madd w13,w10,w13,w9
 WP x14,_map_data
 ldrb w0,[x14,w13,uxtw]
 cmp w0,#5
 b.lt Lfind_next
 cmp w0,#12
 b.le Lfind_found
 cmp w0,#14
 b.lt Lfind_next
 cmp w0,#16
 b.le Lfind_found
Lfind_next:
 add w12,w12,#1
 cmp w12,#5
 b.gt Lfind_none
 WG w9,_player_x
 WG w10,_player_y
 cmp w12,#1
 b.eq Lfind_scan
 cmp w12,#2
 b.ne Lfind_test3
 add w10,w10,#1
 b Lfind_scan
Lfind_test3:
 cmp w12,#3
 b.ne Lfind_test4
 sub w10,w10,#1
 b Lfind_scan
Lfind_test4:
 cmp w12,#4
 b.ne Lfind_test5
 sub w9,w9,#1
 b Lfind_scan
Lfind_test5:
 add w9,w9,#1
 b Lfind_scan
Lfind_found:
 mov w1,w9
 mov w2,w10
 ret
Lfind_none:
 mov w0,#0
 ret

_world_trainer_at:
 WG w9,_map_id
 WP x10,Ltrainer_base
 ldr w9,[x10,w9,uxtw #2]
 cmp w9,#0
 b.lt Ltrainer_none
 cmp w0,#14
 cinc w9,w9,gt
Ltrainer_none:
 mov w0,w9
 ret

.data
.p2align 3
.globl _map_names, _map_subtitles, _world_objective
_map_names: .quad Lmap0,Lmap1,Lmap2,Lmap3,Lmap4,Lmap5
_map_subtitles: .quad Lsub0,Lsub1,Lsub2,Lsub3,Lsub4,Lsub5
_world_objectives: .quad Lgoal0,Lgoal1,Lgoal2,Lgoal3,Lgoal4,Lgoal5
_world_arrivals: .quad Larrive0,Larrive1,Larrive2,Larrive3,Larrive4,Larrive5
_world_objective: .quad Lgoal0
.p2align 2
.globl _map_id, _home_map, _map_data
_map_id: .long 0
_home_map: .long 0
_map_data: .space 345
.section __TEXT,__const
.p2align 2
Ltrainer_base: .long -1,0,-1,2,4,-1
.globl _world_maps
_world_maps:
// Region 0
.byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
.byte 1,0,4,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,1
.byte 1,0,0,0,17,17,17,0,4,0,17,17,17,0,0,0,17,17,17,0,4,0,1
.byte 1,0,0,0,18,5,18,0,4,0,18,15,18,0,0,0,18,16,18,0,0,0,1
.byte 1,0,0,0,0,2,0,0,0,0,0,2,0,0,0,0,0,2,0,0,0,0,1
.byte 1,0,0,0,0,2,0,0,0,0,0,2,0,0,0,0,0,2,0,0,0,0,1
.byte 1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,13
.byte 1,0,0,0,0,2,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,1
.byte 1,0,0,0,17,17,17,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,1
.byte 1,0,0,0,18,16,18,0,0,0,0,2,0,0,10,0,0,4,4,4,0,0,1
.byte 1,0,4,0,0,2,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,1
.byte 1,0,0,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,0,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
.byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
// Region 1
.byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
.byte 1,0,4,3,3,3,3,3,3,0,0,0,2,0,0,3,3,3,3,3,0,0,1
.byte 1,0,4,3,3,3,3,3,3,4,4,0,6,0,0,3,3,3,3,3,0,0,1
.byte 1,0,0,3,3,3,3,3,3,0,0,0,2,0,0,3,3,3,3,3,0,0,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,4,4,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,1
.byte 13,2,2,2,2,2,2,2,14,2,2,2,2,2,2,2,2,2,2,14,2,2,13
.byte 1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,1
.byte 1,0,0,0,3,3,3,3,0,4,4,0,2,0,0,3,3,3,3,3,0,0,1
.byte 1,0,0,0,3,3,3,3,0,0,0,0,2,0,0,3,3,3,3,3,0,0,1
.byte 1,0,0,5,2,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,4,0,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,3,3,3,3,3,0,0,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
.byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
// Region 2
.byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
.byte 1,0,4,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,1
.byte 1,0,0,0,17,17,17,0,4,0,17,17,17,0,0,0,17,17,17,0,4,0,1
.byte 1,0,0,0,18,5,18,0,4,0,18,15,18,0,0,0,18,16,18,0,0,0,1
.byte 1,0,0,0,0,2,0,0,2,2,2,2,2,2,2,0,0,2,0,0,0,0,1
.byte 1,0,0,0,0,2,0,0,2,2,2,2,2,2,2,0,0,2,0,0,0,0,1
.byte 13,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,13
.byte 1,0,0,0,2,2,2,0,2,2,2,2,2,2,2,0,0,0,0,0,0,2,1
.byte 1,1,1,1,19,19,19,1,1,1,1,1,1,1,1,1,1,17,17,17,0,2,1
.byte 1,1,1,1,19,19,19,1,1,1,1,1,1,1,1,1,1,18,16,18,0,2,1
.byte 1,1,1,1,19,19,19,1,1,1,1,1,1,1,1,1,1,0,2,0,0,2,1
.byte 1,1,1,1,19,19,19,19,19,19,19,19,19,19,1,1,1,2,2,2,16,2,1
.byte 1,1,1,1,19,19,19,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,1
.byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
// Region 3
.byte 20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20
.byte 20,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,20
.byte 20,0,20,3,3,1,3,3,3,0,0,0,2,0,0,3,3,3,3,3,0,0,20
.byte 20,0,20,3,3,1,3,3,3,20,20,0,7,0,0,3,3,3,3,3,0,0,20
.byte 20,0,0,3,3,1,3,3,3,0,0,0,2,0,0,3,3,3,3,3,0,0,20
.byte 20,0,0,0,0,1,0,0,0,0,0,0,2,0,0,0,0,0,0,0,20,20,20
.byte 20,0,0,0,0,1,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,20
.byte 13,2,2,2,2,19,2,2,14,2,2,2,2,2,2,2,2,2,2,14,2,2,13
.byte 20,0,0,0,0,1,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,20
.byte 20,0,0,0,3,1,3,3,0,20,20,0,2,0,0,3,3,3,3,3,0,0,20
.byte 20,0,0,0,3,1,3,3,0,0,0,0,2,0,0,3,3,3,3,3,0,0,20
.byte 20,0,0,5,2,19,2,2,2,2,2,2,2,2,2,3,3,3,3,3,20,0,20
.byte 20,0,0,0,0,1,0,0,0,0,0,0,2,0,0,3,3,3,3,3,0,0,20
.byte 20,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,20
.byte 20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20
// Region 4
.byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,1
.byte 1,0,4,3,3,3,3,3,3,0,0,0,2,0,0,3,3,1,3,3,0,0,1
.byte 1,0,4,12,3,3,3,3,3,4,4,0,8,0,0,3,3,1,3,3,0,0,1
.byte 1,0,0,3,3,3,3,3,3,0,0,0,2,0,0,3,3,1,3,3,0,0,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,1,0,0,4,4,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,1,0,0,0,0,1
.byte 13,2,2,2,2,2,2,2,14,2,2,2,2,2,2,2,2,19,2,14,2,2,13
.byte 1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,1,0,0,0,0,1
.byte 1,0,0,0,3,3,3,3,0,4,4,0,2,0,0,3,3,1,3,3,0,0,1
.byte 1,0,0,0,3,3,3,3,0,0,0,0,2,0,0,3,3,1,3,3,0,0,1
.byte 1,0,0,11,2,2,2,2,2,2,2,2,2,2,2,3,3,19,3,3,4,0,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,3,3,1,3,3,0,0,1
.byte 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,1
.byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
// Region 5
.byte 20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20
.byte 20,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,20
.byte 20,0,0,0,0,0,0,0,0,0,0,9,0,0,0,0,0,0,0,0,0,0,20
.byte 20,0,0,0,0,0,0,20,20,0,0,2,0,0,20,20,0,0,0,0,0,0,20
.byte 20,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,20
.byte 20,0,0,0,0,20,0,0,0,0,0,2,0,0,0,0,0,20,0,0,0,0,20
.byte 20,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,20
.byte 13,2,2,2,2,2,2,2,2,2,2,2,0,0,0,0,0,0,0,0,0,0,20
.byte 20,0,0,0,3,3,3,0,0,0,0,2,0,0,0,0,0,3,3,3,0,0,20
.byte 20,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,20
.byte 20,0,0,0,0,20,0,0,16,0,0,2,0,0,0,0,0,20,0,0,0,0,20
.byte 20,0,0,5,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,0,20
.byte 20,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,20
.byte 20,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,20
.byte 20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20

.section __TEXT,__cstring,cstring_literals
Lmap0: .asciz "BRINEWICK"
Lmap1: .asciz "REEDWAY"
Lmap2: .asciz "EMBERPORT"
Lmap3: .asciz "CINDERPASS"
Lmap4: .asciz "MOONFEN"
Lmap5: .asciz "CROWNREACH"
Lsub0: .asciz "A HARBOR FULL OF FIRST BEGINNINGS"
Lsub1: .asciz "WHERE THE REEDS REMEMBER"
Lsub2: .asciz "WARM HEARTHS BENEATH AMBER SKIES"
Lsub3: .asciz "THE OLD ROAD THROUGH THE CINDERS"
Lsub4: .asciz "FOLLOW THE LIGHT UNDER THE MIST"
Lsub5: .asciz "THE LAST NOTE OF THE ISLAND'S SONG"
Lgoal0: .asciz "YOUR JOURNEY BEGINS\nHEAD EAST TO REEDWAY"
Lgoal1: .asciz "REEDWAY TRIALS\n2 TRAINERS + BEACON"
Lgoal2: .asciz "REST IN EMBERPORT\nTHEN SEEK CINDERPASS"
Lgoal3: .asciz "CINDERPASS TRIALS\n2 TRAINERS + BEACON"
Lgoal4: .asciz "MOONFEN TRIALS\n2 TRAINERS + BEACON"
Lgoal5: .asciz "THE FINAL ASCENT\nAWAKEN AURALITH"
Larrive0: .asciz "BRINEWICK: Visit the clinic, shop and Professor Moss.\nYour first trail lies east, beyond the harbor road."
Larrive1: .asciz "REEDWAY: Scout Ina and your rival Rowan await.\nWin both challenges and restore the beacon to travel east."
Larrive2: .asciz "EMBERPORT: A safe haven between the island's trials.\nRest at the clinic and stock up before crossing Cinderpass."
Larrive3: .asciz "CINDERPASS: Old stone bridges cross the cooling streams.\nTwo trainers guard the road to the second beacon."
Larrive4: .asciz "MOONFEN: Wild lights drift beyond the mist.\nFind the last beacon and settle Rowan's final challenge."
Larrive5: .asciz "CROWNREACH: The three restored lights meet above you.\nRest, prepare your companions, then climb to Auralith."
Lroute_locked: .asciz "The eastern road is sealed by this region's trial.\nDefeat both trainers and light the local beacon first."
