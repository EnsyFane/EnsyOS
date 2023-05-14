org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A 

; FAT12 HEADER
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'       ; 8 bytes padded with space
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880             ; 1.44MB = 2880 sectors * 512 bytes
bdb_media_descriptor:       db 0F0h             ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sectors:          dd 0

; Extended boot record
ebr_drive_number:           db 0                ; 0x00 floppy, 0x80 hdd
ebr_reserved:               db 0
ebr_signature:              db 29h
ebr_volume_id:              dd 66h, 61h, 6Eh, 65h
ebr_volume_label:           db 'ENSYOS     '    ; 11 bytes padded with space
ebr_system_id:              db 'FAT12   '       ; 8 bytes padded with space

; Code starts here

start:
    jmp main

; Prints a string to the screen
; Params:
;   ds:si - pointer to string
puts:
    push si
    push ax
    push bx

.loop:
    lodsb               ; loads next character in al
    or al, al           ; verify if next character is null?
    jz .done

    mov ah, 0x0E        
    mov bh, 0           ; set page number to 0
    int 0x10            ; call bios interrupt

    jmp .loop

.done:
    pop bx
    pop ax
    pop si
    ret

main:
    ; setup data segments
    mov ax, 0
    mov ds, ax
    mov es, ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00

    ; read something from floppy
    ; dl = drive number from where bootloader was loaded
    mov [ebr_drive_number], dl

    mov ax, 1
    mov cl, 1
    mov bx, 0x7E00
    call disk_read

    mov si, msg_hello
    call puts

    cli
    hlt

floppy_error:
    mov si, msg_floppy_read_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h                     ; wait for key press
    jmp 0FFFFh:0                ; jump to beginning of BIOS, this should reboot

.halt:
    cli                         ; disable interrupts to not be able to exit out of halt
    hlt                        

; Disk routines

; Converts an LBA address to an CHS address
; LBA = Logical Block Address (block number)
; CHS = Cylinder, Head, Sector address (phisical address on disk)
; Params:
;   ax - LBA address
; Returns:
;   cx [bits 0-5] - sector number
;   cx [bits 6-15] - cylinder number
;   dh - head number
lba_to_chs:
    push ax
    push dx

    xor dx, dx                          ; dx = 0
    div word [bdb_sectors_per_track]    ; ax = LBA / sectors_per_track, dx = LBA % sectors_per_track

    inc dx                              ; dx = (LBA % sectors_per_track) + 1
    mov cx, dx                          ; cx = sector number

    xor dx, dx                          ; dx = 0
    div word [bdb_heads]                ; ax = (LBA / sectors_per_track) / heads, dx = (LBA / sectors_per_track) % heads

    mov dh, dl                          ; dh = head number
    mov ch, al                          ; ch = cylinder number
    shl ah, 6
    or cl, ah                           ; cl = sector number + (cylinder number << 6)

    pop ax
    mov dl, al
    pop ax
    ret

; Reads a sector from disk
; Params:
;   ax - sector number
;   cl - sectors to read (max 128)
;   dl - drive number
;   es:bx - memory address to store data at
disk_read:
    push ax
    push bx
    push cx
    push dx
    push di

    push cx
    call lba_to_chs
    pop ax

    mov ah, 02h
    mov di, 3

; floppy disks are unreliable, we have to retry 3 times to make sure the read is successful
.retry:
    pusha                        ; save all registers
    stc                          ; set carry flag (some BIOS'es don't do this correctly)
    int 13h                      ; call bios interrupt. if carry flag is set, the read failed
    jnc .done

    ; read failed
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Resets the floppy disk controller
; Params:
;   dl - drive number
disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret

msg_hello:                  db 'Hello, World!', ENDL, 0
msg_floppy_read_failed:     db 'Floppy read failed!', ENDL, 0

times 510-($-$$) db 0

dw 0AA55h
    