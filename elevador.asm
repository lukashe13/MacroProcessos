.data
    # Cabin struct (56 bytes):
    # 0: id | 4: current_floor | 8: state (0:IDLE, 1:UP, 2:DOWN, 3:DOOR) | 12: timer
    # 16..32: active_requests[5] | 36..52: deferred_requests[5]
    cabin1: .word 1, 0, 0, 0,  0,0,0,0,0,  0,0,0,0,0
    cabin2: .word 2, 0, 0, 0,  0,0,0,0,0,  0,0,0,0,0

    last_read_analog: .word 0

    str_C: .asciiz "C"
    str_F: .asciiz "F"
    str_newline: .asciiz "\n"

.text
.globl main

main:
    jal setup
loop_infinito:
    jal loop
    j loop_infinito

setup:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    li $a0, 1
    li $a1, 0
    jal send_update_to_visor

    li $a0, 2
    li $a1, 0
    jal send_update_to_visor

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

loop:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    jal scan_keypads
    jal scan_analog_buttons

    la $a0, cabin1
    jal update_cabin

    la $a0, cabin2
    jal update_cabin

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# bool has_requests(int req_array[5]) -> $v0 = 1 | 0
has_requests:
    li $t0, 0
    li $v0, 0
hr_loop:
    bge $t0, 5, hr_end
    sll $t1, $t0, 2
    add $t2, $a0, $t1
    lw $t3, 0($t2)
    bnez $t3, hr_true
    addi $t0, $t0, 1
    j hr_loop
hr_true:
    li $v0, 1
hr_end:
    jr $ra

# void send_update_to_visor(int cabin_id, int floor)
send_update_to_visor:
    addi $sp, $sp, -12
    sw $ra, 0($sp)
    sw $a0, 4($sp)
    sw $a1, 8($sp)

    li $v0, 4
    la $a0, str_C
    syscall

    li $v0, 1
    lw $a0, 4($sp)
    syscall

    li $v0, 4
    la $a0, str_F
    syscall

    li $v0, 1
    lw $a0, 8($sp)
    syscall

    li $v0, 4
    la $a0, str_newline
    syscall

    lw $ra, 0($sp)
    addi $sp, $sp, 12
    jr $ra

# void add_request(Cabin *cabin, int floor)
add_request:
    bltz $a1, ar_early_ret
    bge $a1, 5, ar_early_ret

    addi $sp, $sp, -16
    sw $ra, 0($sp)
    sw $a0, 4($sp)
    sw $a1, 8($sp)

    lw $t0, 4($a0)          # current_floor
    lw $t1, 8($a0)          # state

    bne $a1, $t0, ar_check_state
    beq $t1, 0, ar_set_door
    beq $t1, 3, ar_set_door
    j ar_check_state

ar_set_door:
    li $t2, 3
    sw $t2, 8($a0)          # state = DOOR
    jal get_millis
    lw $a0, 4($sp)
    sw $v0, 12($a0)         # timer = millis()
    j ar_end

ar_check_state:
    sll $t2, $a1, 2
    beq $t1, 0, ar_set_active
    beq $t1, 3, ar_set_active
    beq $t1, 1, ar_check_up

    # state == 2 (DOWN): atende se floor < current_floor
    bge $a1, $t0, ar_set_deferred
    j ar_set_active

ar_check_up:
    # state == 1 (UP): atende se floor > current_floor
    ble $a1, $t0, ar_set_deferred
    j ar_set_active

ar_set_active:
    addi $t3, $a0, 16
    add $t4, $t3, $t2
    li $t5, 1
    sw $t5, 0($t4)
    j ar_end

ar_set_deferred:
    addi $t3, $a0, 36
    add $t4, $t3, $t2
    li $t5, 1
    sw $t5, 0($t4)

ar_end:
    lw $ra, 0($sp)
    addi $sp, $sp, 16
ar_early_ret:
    jr $ra

# int calc_effective_dist(Cabin *c) -> $v0
calc_effective_dist:
    lw $t0, 8($a0)          # state
    lw $t1, 4($a0)          # current_floor

    # IDLE (0), DOWN (2) ou DOOR (3) retornam current_floor
    bne $t0, 1, ced_ret_current

    move $t2, $t1           # highest_target = current_floor
    li $t3, 0               # i = 0
ced_loop:
    bge $t3, 5, ced_calc
    addi $t4, $a0, 16
    sll $t5, $t3, 2
    add $t4, $t4, $t5
    lw $t6, 0($t4)
    beqz $t6, ced_next
    ble $t3, $t2, ced_next  # atualiza apenas se i > highest_target
    move $t2, $t3
ced_next:
    addi $t3, $t3, 1
    j ced_loop

ced_calc:
    subu $v0, $t2, $t1      # (highest - current) + highest
    addu $v0, $v0, $t2
    jr $ra

ced_ret_current:
    move $v0, $t1
    jr $ra

# void call_ground_floor()
call_ground_floor:
    addi $sp, $sp, -16
    sw $ra, 0($sp)

    la $a0, cabin1
    jal calc_effective_dist
    sw $v0, 4($sp)

    la $a0, cabin2
    jal calc_effective_dist
    sw $v0, 8($sp)

    lw $t0, 4($sp)
    lw $t1, 8($sp)
    ble $t0, $t1, cgf_cab1
    la $a0, cabin2
    j cgf_call
cgf_cab1:
    la $a0, cabin1
cgf_call:
    li $a1, 0
    jal add_request

    lw $ra, 0($sp)
    addi $sp, $sp, 16
    jr $ra

# void determine_next_state(Cabin *cabin)
determine_next_state:
    addi $sp, $sp, -12
    sw $ra, 0($sp)
    sw $a0, 4($sp)

    addi $a0, $a0, 16
    jal has_requests
    lw $a0, 4($sp)
    bnez $v0, dns_find_reqs

    # Promove deferred_requests para active_requests
    li $t0, 0
dns_copy_loop:
    bge $t0, 5, dns_check2
    sll $t1, $t0, 2

    addi $t2, $a0, 36
    add $t2, $t2, $t1
    lw $t3, 0($t2)
    sw $zero, 0($t2)

    addi $t4, $a0, 16
    add $t4, $t4, $t1
    sw $t3, 0($t4)

    addi $t0, $t0, 1
    j dns_copy_loop

dns_check2:
    lw $a0, 4($sp)
    addi $a0, $a0, 16
    jal has_requests
    lw $a0, 4($sp)
    bnez $v0, dns_find_reqs
    sw $zero, 8($a0)        # state = IDLE
    j dns_end

dns_find_reqs:
    li $t0, -1              # highest_req
    li $t1, -1              # lowest_req
    li $t2, 0               # i = 0
dns_find_loop:
    bge $t2, 5, dns_set_state
    addi $t3, $a0, 16
    sll $t4, $t2, 2
    add $t3, $t3, $t4
    lw $t5, 0($t3)
    beqz $t5, dns_find_next

    bne $t1, -1, dns_skip_low
    move $t1, $t2
dns_skip_low:
    move $t0, $t2
dns_find_next:
    addi $t2, $t2, 1
    j dns_find_loop

dns_set_state:
    lw $t6, 4($a0)          # current_floor
    bgt $t0, $t6, dns_set_up
    blt $t1, $t6, dns_set_down

    # Pedido ativo no proprio andar atual -> abre a porta
    li $t7, 3
    sw $t7, 8($a0)          # state = DOOR
    jal get_millis
    lw $a0, 4($sp)
    sw $v0, 12($a0)
    j dns_end

dns_set_up:
    li $t7, 1
    sw $t7, 8($a0)          # state = UP
    jal get_millis
    lw $a0, 4($sp)
    sw $v0, 12($a0)
    j dns_end

dns_set_down:
    li $t7, 2
    sw $t7, 8($a0)          # state = DOWN
    jal get_millis
    lw $a0, 4($sp)
    sw $v0, 12($a0)

dns_end:
    lw $ra, 0($sp)
    addi $sp, $sp, 12
    jr $ra

# void update_cabin(Cabin *cabin)
update_cabin:
    addi $sp, $sp, -12
    sw $ra, 0($sp)
    sw $a0, 4($sp)

    lw $t0, 8($a0)          # state
    bne $t0, 3, uc_check_idle

    jal get_millis
    lw $a0, 4($sp)
    lw $t1, 12($a0)
    subu $t2, $v0, $t1
    bltu $t2, 5000, uc_end

    lw $t3, 4($a0)          # current_floor
    sll $t4, $t3, 2
    addi $t5, $a0, 16
    add $t5, $t5, $t4
    sw $zero, 0($t5)        # active[current_floor] = 0
    jal determine_next_state
    j uc_end

uc_check_idle:
    bne $t0, 0, uc_check_move
    jal determine_next_state
    j uc_end

uc_check_move:
    jal get_millis
    lw $a0, 4($sp)
    lw $t1, 12($a0)
    subu $t2, $v0, $t1
    bltu $t2, 2000, uc_end

    sw $v0, 12($a0)

    lw $t3, 4($a0)          # current_floor
    lw $t0, 8($a0)          # state
    beq $t0, 1, uc_inc

    # state == 2 (DOWN)
    blez $t3, uc_recalc
    addi $t3, $t3, -1
    j uc_save_floor

uc_inc:
    bge $t3, 4, uc_recalc
    addi $t3, $t3, 1

uc_save_floor:
    sw $t3, 4($a0)

    lw $a0, 0($a0)
    move $a1, $t3
    jal send_update_to_visor

    lw $a0, 4($sp)
    lw $t3, 4($a0)
    sll $t4, $t3, 2
    addi $t5, $a0, 16
    add $t5, $t5, $t4
    lw $t6, 0($t5)

    beqz $t6, uc_check_empty
    li $t7, 3
    sw $t7, 8($a0)          # state = DOOR
    jal get_millis
    lw $a0, 4($sp)
    sw $v0, 12($a0)
    j uc_end

uc_check_empty:
    addi $a0, $a0, 16
    jal has_requests
    lw $a0, 4($sp)
    bnez $v0, uc_end
uc_recalc:
    jal determine_next_state

uc_end:
    lw $ra, 0($sp)
    addi $sp, $sp, 12
    jr $ra

# void scan_keypads()
scan_keypads:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    jal get_keypad_mock
    move $t0, $v0

    blt $t0, 48, sk_end     # '0'
    bgt $t0, 52, sk_check2  # '4'
    la $a0, cabin1
    addi $a1, $t0, -48
    jal add_request
    j sk_end

sk_check2:
    blt $t0, 53, sk_end     # '5'
    bgt $t0, 57, sk_end     # '9'
    la $a0, cabin2
    addi $a1, $t0, -53
    jal add_request

sk_end:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# void scan_analog_buttons()
scan_analog_buttons:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    jal get_millis
    la $t0, last_read_analog
    lw $t1, 0($t0)
    subu $t2, $v0, $t1
    bltu $t2, 150, sab_end

    li $a0, 13
    jal mock_digitalRead
    beqz $v0, sab_p12
    jal call_ground_floor
    j sab_update

sab_p12:
    li $a0, 12
    jal mock_digitalRead
    beqz $v0, sab_p11
    la $a0, cabin1
    li $a1, 1
    jal add_request
    j sab_update

sab_p11:
    li $a0, 11
    jal mock_digitalRead
    beqz $v0, sab_p10
    la $a0, cabin2
    li $a1, 1
    jal add_request
    j sab_update

sab_p10:
    li $a0, 10
    jal mock_digitalRead
    beqz $v0, sab_p9
    la $a0, cabin1
    li $a1, 2
    jal add_request
    j sab_update

sab_p9:
    li $a0, 9
    jal mock_digitalRead
    beqz $v0, sab_p8
    la $a0, cabin2
    li $a1, 2
    jal add_request
    j sab_update

sab_p8:
    li $a0, 8
    jal mock_digitalRead
    beqz $v0, sab_p7
    la $a0, cabin1
    li $a1, 3
    jal add_request
    j sab_update

sab_p7:
    li $a0, 7
    jal mock_digitalRead
    beqz $v0, sab_p6
    la $a0, cabin2
    li $a1, 3
    jal add_request
    j sab_update

sab_p6:
    li $a0, 6
    jal mock_digitalRead
    beqz $v0, sab_p5
    la $a0, cabin1
    li $a1, 4
    jal add_request
    j sab_update

sab_p5:
    li $a0, 5
    jal mock_digitalRead
    beqz $v0, sab_end
    la $a0, cabin2
    li $a1, 4
    jal add_request

sab_update:
    jal get_millis
    la $t0, last_read_analog
    sw $v0, 0($t0)

sab_end:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# ---------------------------------------------------------
# ABSTRACOES DE HARDWARE (MARS)
# ---------------------------------------------------------
get_millis:
    li $v0, 30
    syscall
    move $v0, $a0
    jr $ra

# Leitura nao-bloqueante via MMIO do MARS (Tools -> Keyboard and Display MMIO Simulator)
get_keypad_mock:
    lui $t0, 0xffff
    lw $t1, 0($t0)          # Receiver control
    andi $t1, $t1, 1
    beqz $t1, gkm_none
    lw $v0, 4($t0)          # Receiver data (ASCII)
    jr $ra
gkm_none:
    li $v0, 0
    jr $ra

mock_digitalRead:
    li $v0, 0
    jr $ra
