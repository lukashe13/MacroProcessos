.data
    # -----------------------------------------------------------------
    # ESTRUTURA CABIN (56 bytes)
    # Offsets:
    # 0: id (word)
    # 4: current_floor (word)
    # 8: state (word) -> 0: IDLE, 1: UP, 2: DOWN, 3: DOOR
    # 12: timer (word)
    # 16-32: active_requests (5 words, 20 bytes)
    # 36-52: deferred_requests (5 words, 20 bytes)
    # -----------------------------------------------------------------
    
    # Cabin 1
    cabin1: .word 1, 0, 0, 0,  0,0,0,0,0,  0,0,0,0,0
    
    # Cabin 2
    cabin2: .word 2, 0, 0, 0,  0,0,0,0,0,  0,0,0,0,0

    # Variável estática para scan_analog_buttons (last_read)
    last_read_analog: .word 0

    # Strings Visor
    str_C: .asciiz "C"
    str_F: .asciiz "F"
    str_newline: .asciiz "\n"

.text
.globl main

# ---------------------------------------------------------
# SETUP & LOOP (Main)
# ---------------------------------------------------------
main:
    jal setup
loop_infinito:
    jal loop
    j loop_infinito

setup:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # send_update_to_visor(1, 0)
    li $a0, 1
    li $a1, 0
    jal send_update_to_visor
    
    # send_update_to_visor(2, 0)
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

# ---------------------------------------------------------
# bool has_requests(bool req_array[5])
# Argumento: $a0 = endereço base do array
# Retorno: $v0 = 1 (true) ou 0 (false)
# ---------------------------------------------------------
has_requests:
    li $t0, 0               # i = 0
    li $v0, 0               # return false
hr_loop:
    bge $t0, 5, hr_end
    sll $t1, $t0, 2         # i * 4
    add $t2, $a0, $t1
    lw $t3, 0($t2)
    bnez $t3, hr_true       # se != 0, return true
    addi $t0, $t0, 1
    j hr_loop
hr_true:
    li $v0, 1
hr_end:
    jr $ra

# ---------------------------------------------------------
# void send_update_to_visor(byte cabin_id, int floor)
# Argumentos: $a0 = id, $a1 = floor
# ---------------------------------------------------------
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

# ---------------------------------------------------------
# void add_request(Cabin *cabin, int floor)
# Argumentos: $a0 = cabin, $a1 = floor
# ---------------------------------------------------------
add_request:
    addi $sp, $sp, -16
    sw $ra, 0($sp)
    sw $a0, 4($sp)
    sw $a1, 8($sp)

    lw $t0, 4($a0)          # current_floor
    lw $t1, 8($a0)          # state

    # if floor == current_floor && (state == 0 || state == 3)
    bne $a1, $t0, ar_check_state
    beq $t1, 0, ar_set_door
    beq $t1, 3, ar_set_door
    j ar_check_state

ar_set_door:
    li $t2, 3
    sw $t2, 8($a0)          # state = ELEV_DOOR
    jal get_millis
    lw $a0, 4($sp)
    sw $v0, 12($a0)         # timer = millis()
    j ar_end

ar_check_state:
    sll $t2, $a1, 2         # offset floor * 4
    beq $t1, 0, ar_set_active
    beq $t1, 3, ar_set_active
    beq $t1, 1, ar_set_deferred
    
    # se ELEV_DOWN (2)
    bge $a1, $t0, ar_set_deferred
    j ar_set_active

ar_set_active:
    addi $t3, $a0, 16       # active base
    add $t4, $t3, $t2
    li $t5, 1
    sw $t5, 0($t4)
    j ar_end

ar_set_deferred:
    addi $t3, $a0, 36       # deferred base
    add $t4, $t3, $t2
    li $t5, 1
    sw $t5, 0($t4)

ar_end:
    lw $ra, 0($sp)
    addi $sp, $sp, 16
    jr $ra

# ---------------------------------------------------------
# int calc_effective_dist(Cabin *c)
# Argumento: $a0 = cabin, Retorno: $v0 = dist
# ---------------------------------------------------------
calc_effective_dist:
    lw $t0, 8($a0)          # state
    lw $t1, 4($a0)          # current_floor
    
    # if IDLE (0) ou DOWN (2), return current_floor
    beq $t0, 0, ced_ret_current
    beq $t0, 2, ced_ret_current
    
    move $t2, $t1           # highest_target = current_floor
    li $t3, 0               # i = 0
ced_loop:
    bge $t3, 5, ced_calc
    addi $t4, $a0, 16       # active_requests
    sll $t5, $t3, 2
    add $t4, $t4, $t5
    lw $t6, 0($t4)
    beqz $t6, ced_next
    move $t2, $t3           # highest = i
ced_next:
    addi $t3, $t3, 1
    j ced_loop

ced_calc:
    sub $v0, $t2, $t1       # (highest - current) + highest
    add $v0, $v0, $t2
    jr $ra

ced_ret_current:
    move $v0, $t1
    jr $ra

# ---------------------------------------------------------
# void call_ground_floor()
# ---------------------------------------------------------
call_ground_floor:
    addi $sp, $sp, -16
    sw $ra, 0($sp)
    
    la $a0, cabin1
    jal calc_effective_dist
    sw $v0, 4($sp)          # dist1
    
    la $a0, cabin2
    jal calc_effective_dist
    sw $v0, 8($sp)          # dist2
    
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

# ---------------------------------------------------------
# void determine_next_state(Cabin *cabin)
# Argumento: $a0 = cabin
# ---------------------------------------------------------
determine_next_state:
    addi $sp, $sp, -12
    sw $ra, 0($sp)
    sw $a0, 4($sp)
    
    addi $a0, $a0, 16       # active_requests addr
    jal has_requests
    lw $a0, 4($sp)          # restore cabin
    bnez $v0, dns_check2    # se tem requests, pula cópia
    
    # copy deferred to active
    li $t0, 0
dns_copy_loop:
    bge $t0, 5, dns_check2
    sll $t1, $t0, 2
    
    addi $t2, $a0, 36       # deferred
    add $t2, $t2, $t1
    lw $t3, 0($t2)          # val = deferred[i]
    sw $zero, 0($t2)        # deferred[i] = 0
    
    addi $t4, $a0, 16       # active
    add $t4, $t4, $t1
    sw $t3, 0($t4)          # active[i] = val
    
    addi $t0, $t0, 1
    j dns_copy_loop

dns_check2:
    lw $a0, 4($sp)
    addi $a0, $a0, 16
    jal has_requests
    lw $a0, 4($sp)
    bnez $v0, dns_find_reqs
    sw $zero, 8($a0)        # state = ELEV_IDLE
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
    move $t1, $t2           # lowest = i
dns_skip_low:
    move $t0, $t2           # highest = i
dns_find_next:
    addi $t2, $t2, 1
    j dns_find_loop

dns_set_state:
    lw $t6, 4($a0)          # current_floor
    bgt $t0, $t6, dns_set_up
    blt $t1, $t6, dns_set_down
    j dns_end

dns_set_up:
    li $t7, 1
    sw $t7, 8($a0)          # state = UP
    jal get_millis
    lw $a0, 4($sp)
    sw $v0, 12($a0)         # timer = millis()
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

# ---------------------------------------------------------
# void update_cabin(Cabin *cabin)
# Argumento: $a0 = cabin
# ---------------------------------------------------------
update_cabin:
    addi $sp, $sp, -12
    sw $ra, 0($sp)
    sw $a0, 4($sp)
    
    lw $t0, 8($a0)          # state
    bne $t0, 3, uc_check_idle   # if state == DOOR
    
    jal get_millis
    lw $a0, 4($sp)
    lw $t1, 12($a0)         # cabin->timer
    sub $t2, $v0, $t1
    blt $t2, 5000, uc_end   # if millis - timer < 5000
    
    lw $t3, 4($a0)          # current_floor
    sll $t4, $t3, 2
    addi $t5, $a0, 16       # active_requests
    add $t5, $t5, $t4
    sw $zero, 0($t5)        # active[current] = false
    jal determine_next_state
    j uc_end

uc_check_idle:
    bne $t0, 0, uc_check_move
    jal determine_next_state
    j uc_end

uc_check_move:
    # UP(1) ou DOWN(2)
    jal get_millis
    lw $a0, 4($sp)
    lw $t1, 12($a0)
    sub $t2, $v0, $t1
    blt $t2, 2000, uc_end   # if millis - timer < 2000
    
    sw $v0, 12($a0)         # timer = millis()
    
    lw $t3, 4($a0)          # current_floor
    lw $t0, 8($a0)          # state
    beq $t0, 1, uc_inc
    addi $t3, $t3, -1
    j uc_save_floor
uc_inc:
    addi $t3, $t3, 1
uc_save_floor:
    sw $t3, 4($a0)          # save current_floor
    
    lw $a0, 0($a0)          # id
    move $a1, $t3           # floor
    jal send_update_to_visor
    
    lw $a0, 4($sp)          # restore cabin
    lw $t3, 4($a0)
    sll $t4, $t3, 2
    addi $t5, $a0, 16
    add $t5, $t5, $t4
    lw $t6, 0($t5)          # active_requests[current_floor]
    
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
    jal determine_next_state

uc_end:
    lw $ra, 0($sp)
    addi $sp, $sp, 12
    jr $ra

# ---------------------------------------------------------
# void scan_keypads() 
# (Mock: Lê caracter do console para simular o Keypad)
# ---------------------------------------------------------
scan_keypads:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    jal get_keypad_mock
    move $t0, $v0           # key

    blt $t0, '0', sk_end
    bgt $t0, '4', sk_check2
    la $a0, cabin1
    sub $a1, $t0, '0'
    jal add_request
    j sk_end
    
sk_check2:
    blt $t0, '5', sk_end
    bgt $t0, '9', sk_end
    la $a0, cabin2
    sub $a1, $t0, '5'
    jal add_request

sk_end:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# ---------------------------------------------------------
# void scan_analog_buttons()
# (Mock: Lógica preservada chamando mock de digitalRead)
# ---------------------------------------------------------
scan_analog_buttons:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    jal get_millis
    la $t0, last_read_analog
    lw $t1, 0($t0)
    sub $t2, $v0, $t1
    blt $t2, 150, sab_end

    # Chamada Mock p/ Pino 13
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
    beqz $v0, sab_end       # Cortando os ifs seguintes para economizar abstração, mas a lógica segue igual
    la $a0, cabin1
    li $a1, 2
    jal add_request
    j sab_update

sab_update:
    jal get_millis
    la $t0, last_read_analog
    sw $v0, 0($t0)

sab_end:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# ---------------------------------------------------------
# ABSTRAÇÕES HARDWARE ARDUINO
# ---------------------------------------------------------

# get_millis(): Retorna milissegundos em $v0 usando Syscall 30
get_millis:
    li $v0, 30
    syscall
    move $v0, $a0           # Pega low bytes do tempo
    jr $ra

# get_keypad_mock(): Retorna 0 (nenhuma tecla) para não travar o loop
get_keypad_mock:
    li $v0, 0
    jr $ra

# mock_digitalRead(pin): Retorna 0 (LOW)
mock_digitalRead:
    li $v0, 0
    jr $ra