############################################################
# Wiener Filter in MARS MIPS, Asignment CA - HCMUT - 2025
# Student(s):
#	Trần Mãnh Tài 2152950
#	Lê Quang Thành 2252749 
#	Nguyễn Anh Hào 2052971
############################################################
.include "macros.asm"

.data
N: .word 10
M: .word 10
N_float: .float 10.0
zero_float: .float 0.0

desired_signal: .space 40
input_signal: .space 40       		# input x[n] = s(n) + w(n)
optimize_coefficient: .space 40	# oefficient h[k]
mmse: .float 0.0
output_signal: .space 40		# output y[n]

# Correlation arrays
rxx: .space 40       			# autocorrelation gamma_xx(k)
rdx: .space 40       			# cross-correlation gamma_dx(k)

# Toeplitz autocorrelation matrix R_M (10x10)
Rxx: .space 400      		# 10*10 floats


# used for read/write real number
ten_float: .float 10.0          # chia cho 10 để lấy 1 chữ số thập phân
factor10000: .float 10000.0      # in 4 chữ số thập phân

# file name
file_input_name: .asciiz "input.txt"
file_desired_name: .asciiz "desired.txt"
file_output_name: .asciiz "output.txt"

# buffer to read/write file (ASCII)
buffer_input: .space 256       
buffer_desired: .space 256       
buffer_out: .space 1024      # buffer để ghép kết quả rồi ghi ra output.txt
digit_buf: .space 16        # buffer tạm cho phần nguyên khi convert float sang chuỗi

newline: .asciiz "\n"
space: .asciiz " "
err_msg: .asciiz "Error: size not match\n"
filtered_label: .asciiz "Filtered output: "
mmse_label: .asciiz "MMSE: "

.text
.globl main

main:
    ########################################################
    # 0) read desired text from desired.txt
    ########################################################
	open_file(file_desired_name, 0)       # mode 0 = read
	read_file(buffer_desired, 255)        # số byte có thể đọc là 256

	la $a0, buffer_desired              # buffer
	move $a1, $s7                         # length
	la $a2, desired_signal                     # mảng float output
	li $a3, 10                          # tối đa 10 số
	jal parse_buffer_to_floats
	move $s0, $v0                         # count_desired
	close_file

    ########################################################
    # 1) read input text from input.txt
    ########################################################
	open_file(file_input_name, 0)
	read_file(buffer_input, 255)

	la $a0, buffer_input
	move $a1, $s7                         # length
	la $a2, input_signal
	li $a3, 10
	jal parse_buffer_to_floats
	move $s1, $v0                         # count_input
	close_file

    ########################################################
    # 2) check if size is 10 or not 
    ########################################################
	li $t0, 10
	bne $s0, $t0, size_error              # if desired less or more than 10, then go to size_error
	bne $s1, $t0, size_error              # same for input


    ########################################################
    # 3) calculate rxx, rdx, Rxx, hopt, output, mmse
    ########################################################

    # 3.1) Compute autocorrelation rxx (x to x)
	la $a0, input_signal       	# base_x
 	la $a1, rxx         		# base_rxx
 	li $a2, 10          		# N
 	li $a3, 10          		# M
	jal compute_rxx

    # 3.2) Compute cross-correlation rdx (d với x)
    	la $a0, desired_signal     	# base_d
    	la $a1, input_signal       	# base_x
    	la $a2, rdx         		# base_rdx
    	li $a3, 10          		# N
    	jal compute_rdx

    # 3.3) Build Toeplitz matrix Rxx from rxx
    	la $a0, rxx         		# base_rxx
    	la $a1, Rxx         		# base_Rxx
    	li $a2, 10          		# M
    	jal build_R

    # 3.4) solve for Rxx * coeff = rdx
    	la $a0, Rxx         		# base_A
    	la $a1, rdx         		# base_b
    	la $a2, optimize_coefficient 	# base_x (solution)
    	li $a3, 10          		# n = M
    	jal gauss_solve

    # 3.5) filter: output = filter(input, coeff)
    	la $a0, input_signal       	# base_x
    	la $a1, optimize_coefficient	# base_h
    	la $a2, output_signal      	# base_y
    	li $a3, 10          		# N
    	jal filter_signal

    # 3.6) calculate MMSE between desired and output
    	la $a0, desired_signal     	# base_d
    	la $a1, output_signal      	# base_y
    	li $a2, 10          		# N
    	la $a3, mmse        		# &mmse
    	jal compute_mmse


    ########################################################
    # 4) write file output.txt
    ########################################################
    	la $a0, output_signal      	# base_y
    	la $a1, mmse        		# &mmse
    	la $a2, buffer_out  		# buffer out
    	jal write_output_file

    	end_program          	



############################################################
# size_error: print if size_error + write error to output.txt 
############################################################
size_error:
    # print error message to terminal
    	la $a0, err_msg
    	li $v0, 4
    	syscall

    # write file output.txt
    	open_file(file_output_name, 1)        # mode 1 = write
    	li $v0, 15
    	move $a0, $s6                       
    	la $a1, err_msg
    	li $a2, 22                       
   	syscall
    	close_file

    	end_program

############################################################
# parse_buffer_to_floats(buffer, len, out_array, max_count)
#   a0 = địa chỉ buffer (ASCII, vd: "0.0 3.6 ...")
#   a1 = số byte thực tế đọc từ file
#   a2 = base mảng float để lưu kết quả
#   a3 = số phần tử tối đa cần đọc (10)
# Trả về:
#   v0 = số float đã parse được
#
# Định dạng số: dấu - (optional), phần nguyên, optional ".d"
# ví dụ: -2.3 , 4.0 , 99.5
############################################################
parse_buffer_to_floats:
    	addi $sp, $sp, -32
   	sw $ra, 28($sp)
    	sw $s0, 24($sp)
    	sw $s1, 20($sp)
    	sw $s2, 16($sp)
    	sw $s3, 12($sp)
    	sw $s4, 8($sp)
    	sw $s5, 4($sp)

    	move $s0, $a0       	# base buffer
    	move $s1, $a1       	# length
    	move $s2, $a2       	# base out_array
    	move $s3, $a3       	# max_count
    	li $s4, 0         	# i (index in buffer)
    	li $s5, 0         	# count float parsed

parse_loop:
    # while (i < len && count < max_count)
    	bge $s4, $s1, parse_done
    	bge $s5, $s3, parse_done

skip_ws:
    	bge $s4, $s1, parse_done
    	add $t0, $s0, $s4
    	lbu $t1, 0($t0)
    	li $t2, ' '
    	beq $t1, $t2, skip_ws_inc
    	li $t2, '\n'
    	beq $t1, $t2, skip_ws_inc
    	li $t2, '\r'
    	beq $t1, $t2, skip_ws_inc
    	li $t2, '\t'
    	beq $t1, $t2, skip_ws_inc
    	j after_skip_ws

skip_ws_inc:
    	addi $s4, $s4, 1
    	j skip_ws

after_skip_ws:
    	bge $s4, $s1, parse_done

    # --- read sign if + of - ---
    	li $s6, 1            		# sign = +
    	add $t0, $s0, $s4
    	lbu $t1, 0($t0)
    	li $t2, '-'
    	bne $t1, $t2, sign_done
    	li $s6, -1           		# sign = -
    	addi $s4, $s4, 1
sign_done:

    # --- read number ---
    	li   $t4, 0            	# intPart = 0

int_digits:
    	bge $s4, $s1, int_done
    	add $t0, $s0, $s4
    	lbu $t1, 0($t0)
    	li $t2, '0'
    	blt $t1, $t2, int_done
    	li $t2, '9'
    	bgt $t1, $t2, int_done

    	addi $t1, $t1, -48     	# digit = ch - '0'
    	mul $t4, $t4, 10
    	add $t4, $t4, $t1
    	addi $s4, $s4, 1
    	j int_digits

int_done:
    # --- read real number --
    	li $t5, 0            		# decimalDigit = 0

    	bge $s4, $s1, dec_done
    	add $t0, $s0, $s4
    	lbu $t1, 0($t0)
    	li $t2, '.'
    	bne $t1, $t2, dec_done

    # skip '.'
    	addi $s4, $s4, 1
    	bge $s4, $s1, dec_done
    	add $t0, $s0, $s4
    	lbu $t1, 0($t0)
    	li $t2, '0'
    	blt $t1, $t2, dec_tail_loop
    	li $t2, '9'
    	bgt $t1, $t2, dec_tail_loop
    	addi $t1, $t1, -48     	# digit after '.'
    	move $t5, $t1
    	addi $s4, $s4, 1

dec_tail_loop:
    	bge $s4, $s1, dec_done
    	add $t0, $s0, $s4
    	lbu $t1, 0($t0)
    	li $t2, '0'
    	blt $t1, $t2, dec_done
    	li $t2, '9'
    	bgt $t1, $t2, dec_done
    	addi $s4, $s4, 1
    	j dec_tail_loop

dec_done:
    # scaled = (intPart * 10 + decimalDigit) * sign
    	mul $t6, $t4, 10
    	add $t6, $t6, $t5
    	bltz $s6, scaled_neg
    	j scaled_ok
scaled_neg:
    	sub $t6, $zero, $t6
scaled_ok:

    # float: scaled / 10.0
    	mtc1 $t6, $f0
    	cvt.s.w $f0, $f0
    	lwc1 $f1, ten_float
    	div.s $f0, $f0, $f1

    # store to out_array[count]
    	sll $t7, $s5, 2
    	add $t7, $s2, $t7
    	swc1 $f0, 0($t7)
    	addi $s5, $s5, 1

    	j parse_loop

parse_done:
    	move $v0, $s5          		# trả về số phần tử

    	lw $s5, 4($sp)
    	lw $s4, 8($sp)
    	lw $s3, 12($sp)
    	lw $s2, 16($sp)
    	lw $s1, 20($sp)
    	lw $s0, 24($sp)
    	lw $ra, 28($sp)
    	addi $sp, $sp, 32
    	jr $ra


############################################################
# append_float_4dp(f, buf, index)
#   $f12 = số thực cần in
#   a0   = base buffer (buffer_out)
#   a1   = index hiện tại trong buffer
# Trả về:
#   v0   = index mới sau khi ghi xong (không thêm space/newline)
# Định dạng: dấu (nếu âm) + phần nguyên + "." + 4 chữ số thập phân
############################################################
append_float_4dp:
    	addi $sp, $sp, -40
    	sw $ra, 36($sp)
    	sw $s0, 32($sp)
    	sw $s1, 28($sp)
    	sw $s2, 24($sp)
    	sw $s3, 20($sp)
    	sw $s4, 16($sp)
    	sw $s5, 12($sp)
    	sw $s6, 8($sp)
    	sw $s7, 4($sp)

    	move $s0, $a0       # buf base
    	move $s1, $a1       # index

    # scale f * 10000
    	lwc1 $f0, factor10000
    	mul.s $f2, $f12, $f0
    	cvt.w.s $f2, $f2
    	mfc1 $t0, $f2       # scaled int

    # sign
    	li $s2, 0         # signFlag
    	bgez $t0, af4_sign_ok
    	sub $t0, $zero, $t0
    	li $s2, 1         # negative
af4_sign_ok:

    # integerPart = scaled / 10000 ; fracPart = scaled % 10000
    	li $t1, 10000
    	div $t0, $t1
    	mflo $s3            # integerPart
    	mfhi $s4            # fracPart

    # write '.' if needed
    	beqz $s2, af4_no_sign
    	add $t2, $s0, $s1
    	li $t3, '-'
    	sb $t3, 0($t2)
    	addi $s1, $s1, 1
af4_no_sign:

    # ---- convert integerPart thành chuỗi ----
    	li $s5, 0         # numDigits

    	bne $s3, $zero, af4_int_loop
    # integerPart == 0
    	la $t4, digit_buf
    	li $t5, '0'
    	sb $t5, 0($t4)
    	li $s5, 1
    	j af4_int_done

af4_int_loop:
    	beqz $s3, af4_int_done
    	li $t6, 10
    	div $s3, $t6
    	mfhi $t7
    	mflo $s3
    	addi $t7, $t7, 48       	# '0' + remainder
    	la $t4, digit_buf
    	add $t4, $t4, $s5
    	sb $t7, 0($t4)
    	addi $s5, $s5, 1
    	j af4_int_loop

af4_int_done:
    	addi $s5, $s5, -1       	# index cuối trong digit_buf

af4_write_int:
    	bltz $s5, af4_after_int
    	la $t4, digit_buf
    	add $t4, $t4, $s5
    	lbu $t7, 0($t4)

    	add $t2, $s0, $s1
    	sb $t7, 0($t2)
    	addi $s1, $s1, 1

    	addi $s5, $s5, -1
    	j af4_write_int

af4_after_int:
    # write '.'
    	add $t2, $s0, $s1
    	li $t3, '.'
    	sb $t3, 0($t2)
    	addi $s1, $s1, 1

    # ---- ghi 4 chữ số thập phân ----
    	move $t8, $s4       	# fracPart

    # hàng nghìn
    	li $t6, 1000
    	div $t8, $t6
    	mflo $t7
    	mfhi $t8
    	addi $t7, $t7, 48
    	add $t2, $s0, $s1
    	sb $t7, 0($t2)
    	addi $s1, $s1, 1

    # hàng trăm
    	li $t6, 100
    	div $t8, $t6
    	mflo $t7
    	mfhi $t8
    	addi $t7, $t7, 48
    	add $t2, $s0, $s1
    	sb $t7, 0($t2)
    	addi $s1, $s1, 1

    # hàng chục
    	li $t6, 10
    	div $t8, $t6
    	mflo $t7
    	mfhi $t8
    	addi $t7, $t7, 48
    	add $t2, $s0, $s1
    	sb $t7, 0($t2)
    	addi $s1, $s1, 1

    # hàng đơn vị
    	addi $t7, $t8, 48
    	add $t2, $s0, $s1
    	sb $t7, 0($t2)
    	addi $s1, $s1, 1

    	move $v0, $s1        # trả về index mới

    	lw $s7, 4($sp)
    	lw $s6, 8($sp)
    	lw $s5, 12($sp)
    	lw $s4, 16($sp)
    	lw $s3, 20($sp)
    	lw $s2, 24($sp)
    	lw $s1, 28($sp)
    	lw $s0, 32($sp)
    	lw $ra, 36($sp)
    	addi $sp, $sp, 40
    	jr $ra



############################################################
# compute_rxx(x, rxx, N, M)
#   a0 = base_x
#   a1 = base_rxx
#   a2 = N
#   a3 = M
# rxx[k] = (1/N) * sum_{n=k}^{N-1} x[n] * x[n-k]
############################################################
compute_rxx:
    	addi $sp, $sp, -24
    	sw $ra, 20($sp)
    	sw $s0, 16($sp)
    	sw $s1, 12($sp)
    	sw $s2, 8($sp)
    	sw $s3, 4($sp)

    	move $s0, $a0       	# base_x
    	move $s1, $a1       	# base_rxx
    	move $s2, $a2       	# N
    	move $s3, $a3       	# M

    	li $t0, 0         	# k = 0

crxx_outer_k:
    	bge $t0, $s3, crxx_done  # if k >= M, finish

    # sum = 0.0
    	lwc1 $f0, zero_float

    	move $t1, $t0       # n = k

crxx_inner_n:
    	bge $t1, $s2, crxx_after_inner  # n >= N?

    # x[n]
    	sll $t2, $t1, 2
    	add $t3, $s0, $t2
    	lwc1 $f1, 0($t3)

    # x[n-k]
    	sub $t4, $t1, $t0
    	sll $t5, $t4, 2
    	add $t6, $s0, $t5
    	lwc1 $f2, 0($t6)

    	mul.s $f3, $f1, $f2
    	add.s $f0, $f0, $f3     # sum += product

    	addi $t1, $t1, 1
    	j crxx_inner_n

crxx_after_inner:
    # rxx[k] = sum / N
    	lwc1 $f4, N_float
    	div.s $f0, $f0, $f4

    	sll $t7, $t0, 2
    	add $t8, $s1, $t7
    	swc1 $f0, 0($t8)

    	addi $t0, $t0, 1
    	j crxx_outer_k

crxx_done:
    lw   $s3, 4($sp)
    lw   $s2, 8($sp)
    lw   $s1, 12($sp)
    lw   $s0, 16($sp)
    lw   $ra, 20($sp)
    addi $sp, $sp, 24
    jr   $ra


############################################################
# compute_rdx(d, x, rdx, N)
#   a0 = base_d
#   a1 = base_x
#   a2 = base_rdx
#   a3 = N
# Uses global M
# rdx[k] = (1/N) * sum_{n=k}^{N-1} d[n] * x[n-k]
############################################################
compute_rdx:
    addi $sp, $sp, -28
    sw   $ra, 24($sp)
    sw   $s0, 20($sp)
    sw   $s1, 16($sp)
    sw   $s2, 12($sp)
    sw   $s3, 8($sp)
    sw   $s4, 4($sp)

    move $s0, $a0       # base_d
    move $s1, $a1       # base_x
    move $s2, $a2       # base_rdx
    move $s3, $a3       # N
    lw   $s4, M         # M

    li   $t0, 0         # k = 0

crdx_outer_k:
    bge  $t0, $s4, crdx_done

    lwc1 $f0, zero_float    # sum = 0.0
    move $t1, $t0           # n = k

crdx_inner_n:
    bge  $t1, $s3, crdx_after_inner

    # d[n]
    sll  $t2, $t1, 2
    add  $t3, $s0, $t2
    lwc1 $f1, 0($t3)

    # x[n-k]
    sub  $t4, $t1, $t0
    sll  $t5, $t4, 2
    add  $t6, $s1, $t5
    lwc1 $f2, 0($t6)

    mul.s $f3, $f1, $f2
    add.s $f0, $f0, $f3

    addi $t1, $t1, 1
    j    crdx_inner_n

crdx_after_inner:
    lwc1 $f4, N_float
    div.s $f0, $f0, $f4

    sll  $t7, $t0, 2
    add  $t8, $s2, $t7
    swc1 $f0, 0($t8)

    addi $t0, $t0, 1
    j    crdx_outer_k

crdx_done:
    lw   $s4, 4($sp)
    lw   $s3, 8($sp)
    lw   $s2, 12($sp)
    lw   $s1, 16($sp)
    lw   $s0, 20($sp)
    lw   $ra, 24($sp)
    addi $sp, $sp, 28
    jr   $ra


############################################################
# build_R(rxx, Rxx, M)
#   a0 = base_rxx
#   a1 = base_Rxx
#   a2 = M
# R[i,j] = rxx[|i-j|]
############################################################
build_R:
    addi $sp, $sp, -24
    sw   $ra, 20($sp)
    sw   $s0, 16($sp)
    sw   $s1, 12($sp)
    sw   $s2, 8($sp)
    sw   $s3, 4($sp)

    move $s0, $a0       # base_rxx
    move $s1, $a1       # base_Rxx
    move $s2, $a2       # M

    li   $t0, 0         # i = 0

build_R_outer_i:
    bge  $t0, $s2, build_R_done

    li   $t1, 0         # j = 0

build_R_inner_j:
    bge  $t1, $s2, build_R_next_i

    # diff = |i - j|
    sub  $t2, $t0, $t1
    bgez $t2, build_R_diff_ok
    sub  $t2, $zero, $t2
build_R_diff_ok:
    # rxx[diff]
    sll  $t3, $t2, 2
    add  $t3, $s0, $t3
    lwc1 $f0, 0($t3)

    # index = i*M + j
    mul  $t4, $t0, $s2
    add  $t4, $t4, $t1
    sll  $t4, $t4, 2
    add  $t4, $s1, $t4
    swc1 $f0, 0($t4)

    addi $t1, $t1, 1
    j    build_R_inner_j

build_R_next_i:
    addi $t0, $t0, 1
    j    build_R_outer_i

build_R_done:
    lw   $s3, 4($sp)
    lw   $s2, 8($sp)
    lw   $s1, 12($sp)
    lw   $s0, 16($sp)
    lw   $ra, 20($sp)
    addi $sp, $sp, 24
    jr   $ra


############################################################
# gauss_solve(A, b, x, n)
#   a0 = base_A (n x n matrix, row-major)
#   a1 = base_b (vector length n)
#   a2 = base_x (solution)
#   a3 = n
# Solves A x = b (in-place Gaussian elimination)
############################################################
gauss_solve:
    addi $sp, $sp, -32
    sw   $ra, 28($sp)
    sw   $s0, 24($sp)
    sw   $s1, 20($sp)
    sw   $s2, 16($sp)
    sw   $s3, 12($sp)
    sw   $s4, 8($sp)
    sw   $s5, 4($sp)

    move $s0, $a0       # base_A
    move $s1, $a1       # base_b
    move $s2, $a2       # base_x
    move $s3, $a3       # n

    lwc1 $f7, zero_float    # constant 0.0

    ########################################################
    # Forward elimination
    ########################################################
    li   $t0, 0         # k = 0

gs_FE_outer_k:
    addi $t7, $s3, -1
    bge  $t0, $t7, gs_FE_done

    # pivot = A[k][k]
    mul  $t1, $t0, $s3
    add  $t1, $t1, $t0
    sll  $t1, $t1, 2
    add  $t1, $s0, $t1
    lwc1 $f0, 0($t1)        # pivot

    # for i = k+1 .. n-1
    addi $t2, $t0, 1        # i = k+1

gs_FE_inner_i:
    bge  $t2, $s3, gs_FE_next_k

    # factor = A[i][k] / pivot
    mul  $t3, $t2, $s3
    add  $t3, $t3, $t0
    sll  $t3, $t3, 2
    add  $t3, $s0, $t3
    lwc1 $f1, 0($t3)        # A[i][k]
    div.s $f1, $f1, $f0     # factor

    # A[i][k] = 0
    swc1 $f7, 0($t3)

    # for j = k+1 .. n-1
    addi $t4, $t0, 1        # j = k+1

gs_FE_inner_j:
    bge  $t4, $s3, gs_FE_after_j

    # A[k][j]
    mul  $t5, $t0, $s3
    add  $t5, $t5, $t4
    sll  $t5, $t5, 2
    add  $t5, $s0, $t5
    lwc1 $f2, 0($t5)

    # factor * A[k][j]
    mul.s $f3, $f1, $f2

    # A[i][j]
    mul  $t6, $t2, $s3
    add  $t6, $t6, $t4
    sll  $t6, $t6, 2
    add  $t6, $s0, $t6
    lwc1 $f4, 0($t6)

    sub.s $f4, $f4, $f3
    swc1 $f4, 0($t6)

    addi $t4, $t4, 1
    j    gs_FE_inner_j

gs_FE_after_j:
    # b[i] -= factor * b[k]
    sll  $t8, $t0, 2
    add  $t8, $s1, $t8
    lwc1 $f5, 0($t8)        # b[k]

    mul.s $f6, $f1, $f5

    sll  $t9, $t2, 2
    add  $t9, $s1, $t9
    lwc1 $f8, 0($t9)        # b[i]

    sub.s $f8, $f8, $f6
    swc1 $f8, 0($t9)

    addi $t2, $t2, 1
    j    gs_FE_inner_i

gs_FE_next_k:
    addi $t0, $t0, 1
    j    gs_FE_outer_k

gs_FE_done:
    ########################################################
    # Back substitution
    ########################################################
    addi $t0, $s3, -1      # i = n-1

gs_BS_outer_i:
    bltz $t0, gs_done      # i < 0 ?

    lwc1 $f9, zero_float   # sum = 0.0

    # for j = i+1 .. n-1
    addi $t1, $t0, 1       # j = i+1

gs_BS_inner_j:
    bge  $t1, $s3, gs_BS_after_j

    # A[i][j]
    mul  $t2, $t0, $s3
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2
    add  $t2, $s0, $t2
    lwc1 $f10, 0($t2)

    # x[j]
    sll  $t3, $t1, 2
    add  $t3, $s2, $t3
    lwc1 $f11, 0($t3)

    mul.s $f12, $f10, $f11
    add.s $f9,  $f9, $f12

    addi $t1, $t1, 1
    j    gs_BS_inner_j

gs_BS_after_j:
    # x[i] = (b[i] - sum) / A[i][i]
    sll  $t4, $t0, 2
    add  $t4, $s1, $t4
    lwc1 $f13, 0($t4)      # b[i]

    sub.s $f13, $f13, $f9   # numerator

    mul  $t5, $t0, $s3
    add  $t5, $t5, $t0
    sll  $t5, $t5, 2
    add  $t5, $s0, $t5
    lwc1 $f14, 0($t5)      # A[i][i]

    div.s $f15, $f13, $f14

    sll  $t6, $t0, 2
    add  $t6, $s2, $t6
    swc1 $f15, 0($t6)

    addi $t0, $t0, -1
    j    gs_BS_outer_i

gs_done:
    lw   $s5, 4($sp)
    lw   $s4, 8($sp)
    lw   $s3, 12($sp)
    lw   $s2, 16($sp)
    lw   $s1, 20($sp)
    lw   $s0, 24($sp)
    lw   $ra, 28($sp)
    addi $sp, $sp, 32
    jr   $ra


############################################################
# filter_signal(x, h, y, N)
#   a0 = base_x
#   a1 = base_h
#   a2 = base_y
#   a3 = N
# Uses global M
# y[n] = sum_{k=0}^{M-1} h[k] * x[n-k], with zero-padding
############################################################
filter_signal:
    addi $sp, $sp, -28
    sw   $ra, 24($sp)
    sw   $s0, 20($sp)
    sw   $s1, 16($sp)
    sw   $s2, 12($sp)
    sw   $s3, 8($sp)
    sw   $s4, 4($sp)

    move $s0, $a0       # base_x
    move $s1, $a1       # base_h
    move $s2, $a2       # base_y
    move $s3, $a3       # N
    lw   $s4, M         # M

    li   $t0, 0         # n = 0

fs_outer_n:
    bge  $t0, $s3, fs_done

    lwc1 $f0, zero_float    # sum = 0.0
    li   $t1, 0             # k = 0

fs_inner_k:
    bge  $t1, $s4, fs_after_k

    # n_minus_k = n - k
    sub  $t2, $t0, $t1
    bltz $t2, fs_skip_term   # if n-k < 0, skip

    # h[k]
    sll  $t3, $t1, 2
    add  $t3, $s1, $t3
    lwc1 $f1, 0($t3)

    # x[n-k]
    sll  $t4, $t2, 2
    add  $t4, $s0, $t4
    lwc1 $f2, 0($t4)

    mul.s $f3, $f1, $f2
    add.s $f0, $f0, $f3

fs_skip_term:
    addi $t1, $t1, 1
    j    fs_inner_k

fs_after_k:
    # y[n] = sum
    sll  $t5, $t0, 2
    add  $t5, $s2, $t5
    swc1 $f0, 0($t5)

    addi $t0, $t0, 1
    j    fs_outer_n

fs_done:
    lw   $s4, 4($sp)
    lw   $s3, 8($sp)
    lw   $s2, 12($sp)
    lw   $s1, 16($sp)
    lw   $s0, 20($sp)
    lw   $ra, 24($sp)
    addi $sp, $sp, 28
    jr   $ra


############################################################
# compute_mmse(d, y, N, &mmse)
#   a0 = base_d
#   a1 = base_y
#   a2 = N
#   a3 = &mmse
# MMSE = (1/N) * sum (d[n] - y[n])^2
############################################################
compute_mmse:
    addi $sp, $sp, -24
    sw   $ra, 20($sp)
    sw   $s0, 16($sp)
    sw   $s1, 12($sp)
    sw   $s2, 8($sp)
    sw   $s3, 4($sp)

    move $s0, $a0       # base_d
    move $s1, $a1       # base_y
    move $s2, $a2       # N
    move $s3, $a3       # &mmse

    lwc1 $f0, zero_float    # sum = 0.0
    li   $t0, 0             # n = 0

mmse_loop:
    bge  $t0, $s2, mmse_done

    sll  $t1, $t0, 2

    # d[n]
    add  $t2, $s0, $t1
    lwc1 $f1, 0($t2)

    # y[n]
    add  $t3, $s1, $t1
    lwc1 $f2, 0($t3)

    sub.s $f3, $f1, $f2     # e = d - y
    mul.s $f4, $f3, $f3     # e^2
    add.s $f0, $f0, $f4     # sum += e^2

    addi $t0, $t0, 1
    j    mmse_loop

mmse_done:
    lwc1 $f5, N_float
    div.s $f0, $f0, $f5     # sum / N

    swc1 $f0, 0($s3)        # store mmse

    lw   $s3, 4($sp)
    lw   $s2, 8($sp)
    lw   $s1, 12($sp)
    lw   $s0, 16($sp)
    lw   $ra, 20($sp)
    addi $sp, $sp, 24
    jr   $ra
    
############################################################
# write_output_file(y, &mmse, buffer_out)
#   a0 = base_output (y[n])
#   a1 = &mmse
#   a2 = buffer_out
# Tạo chuỗi:
#   dòng 1: "Filtered output: " + 10 số y[0..9]
#   dòng 2: "MMSE: " + 1 số mmse
# rồi ghi ra file_output_name
############################################################
write_output_file:
    addi $sp, $sp, -24
    sw   $ra, 20($sp)
    sw   $s0, 16($sp)
    sw   $s1, 12($sp)
    sw   $s2, 8($sp)
    sw   $s3, 4($sp)

    move $s0, $a0       # base_y
    move $s1, $a1       # &mmse
    move $s2, $a2       # buffer_out
    li   $s3, 0         # index trong buffer

    ####################################################
    # Filtered output: "
    ####################################################
    la   $t0, filtered_label
wof_copy_filtered_lbl:
    lbu  $t1, 0($t0)
    beq  $t1, $zero, wof_filtered_lbl_done
    add  $t2, $s2, $s3
    sb   $t1, 0($t2)
    addi $s3, $s3, 1
    addi $t0, $t0, 1
    j    wof_copy_filtered_lbl
wof_filtered_lbl_done:

    ####################################################
    # --- dòng 1: 10 phần tử output ---
    ####################################################
    li   $t0, 0         # i = 0
wof_loop:
    li   $t1, 10
    bge  $t0, $t1, wof_after_outputs

    sll  $t2, $t0, 2
    add  $t3, $s0, $t2
    lwc1 $f12, 0($t3)

    # gọi append_float_4dp 
    move $a0, $s2       # buf
    move $a1, $s3       # index
    move $t9, $t0
    jal  append_float_4dp
    move $t0, $t9
    move $s3, $v0

    # thêm space nếu chưa phải phần tử cuối
    li   $t1, 9
    beq  $t0, $t1, wof_no_space
    add  $t4, $s2, $s3
    li   $t5, ' '
    sb   $t5, 0($t4)
    addi $s3, $s3, 1
wof_no_space:
    addi $t0, $t0, 1
    j    wof_loop

wof_after_outputs:
    # xuống dòng
    add  $t4, $s2, $s3
    li   $t5, '\n'
    sb   $t5, 0($t4)
    addi $s3, $s3, 1

    ####################################################
    # "MMSE: "
    ####################################################
    la   $t0, mmse_label
wof_copy_mmse_lbl:
    lbu  $t1, 0($t0)
    beq  $t1, $zero, wof_mmse_lbl_done
    add  $t2, $s2, $s3
    sb   $t1, 0($t2)
    addi $s3, $s3, 1
    addi $t0, $t0, 1
    j    wof_copy_mmse_lbl
wof_mmse_lbl_done:

    # --- dòng 2: giá trị mmse ---
    lwc1 $f12, 0($s1)
    move $a0, $s2
    move $a1, $s3
    jal  append_float_4dp
    move $s3, $v0

    add  $t4, $s2, $s3
    li   $t5, '\n'
    sb   $t5, 0($t4)
    addi $s3, $s3, 1

    # null-terminator
    add  $t4, $s2, $s3
    li   $t5, 0
    sb   $t5, 0($t4)
    
    move $a0, $s2          # buffer_out
    li   $v0, 4            # print_string
    syscall

    # --- ghi buffer_out ra file_output.txt ---
    open_file(file_output_name, 1)    # open for write, fd -> $s6

    li   $v0, 15
    move $a0, $s6                     # fd
    move $a1, $s2                     # buffer_out
    move $a2, $s3                     # số byte thực sự
    syscall

    close_file

    lw   $s3, 4($sp)
    lw   $s2, 8($sp)
    lw   $s1, 12($sp)
    lw   $s0, 16($sp)
    lw   $ra, 20($sp)
    addi $sp, $sp, 24
    jr   $ra
