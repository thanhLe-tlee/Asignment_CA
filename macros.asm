# macro cho kết thúc program
.macro end_program
	li $v0, 10
	syscall
.end_macro

#macro mở file
.macro open_file(%str_file, %mode) # mode 0 for read, 1 for write
	li $v0, 13
	la $a0, %str_file
	li $a1, %mode
	li $a2, 0
	syscall 
	move $s6, $v0
.end_macro 

# macro cho đọc file input 
.macro read_file (%buffer, %nbytes)
	li $v0, 14
	move $a0, $s6
	la $a1, %buffer
	li $a2, %nbytes
	syscall
	move $s7, $v0
.end_macro

# macro cho ghi file output
.macro write_file (%buffer, %nbytes)
	li $v0, 15
	move $a0, $s6
	la $a1, %buffer
	li $a2, %nbytes
	syscall
.end_macro

# macro cho đóng file
.macro close_file
	li $v0, 16
	move $a0, $s6
	syscall 
.end_macro
