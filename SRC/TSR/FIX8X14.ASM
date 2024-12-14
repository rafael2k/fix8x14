; ****************************************************************************
; "FIX8X14" - 8x14 font fixer (TSR)
;             Part of the 8x14 font fixing package "FIX8X14"
;
; Written by Haye van den Oever <hvdo@bttr-software.de>
; for BTTR Software
;
; Copyright (C) 1997-2002 BTTR Software
; [Under GNU GENERAL PUBLIC LICENSE]
; Published by BTTR Software
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 2 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program; if not, write to the Free Software
; Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
; ****************************************************************************

  section .text

  org 100h  ; it is a COM program

  ; memory required for transient program including stack space
  mov ax, top  ; AX = program size in bytes

  ; set stack pointer to top of memory of transient program,
  ; calculate number of paragraphs used, release unused memory
  mov sp, ax          ; set initial stack pointer
  mov cl, 4           ; divide AX by 16
  shr ax, cl          ; AX paragraphs required

  mov bx, ax          ; 16 byte paragraph count in BX
  mov ah, 4ah         ; DOS func AH = 4ah resize memory block
  int 21h             ; returns with CF set on error
  jnc short resizeok  ; continue if resize block ok
  int 20h             ; else end program

resizeok:
  mov ah, 9         ; display name and license of program
  mov dx, intromsg
  int 21h

  ; get header of NUL device from the DOS list of lists
  mov ah, 52h       ; DOS func AH = 52h "SYSVARS"
  int 21h           ; ES:BX = pointer to list of lists
  add bx, byte 22h  ; offset 22h = pointer to NUL device header

nextdevdrvr:
  ; walk chain of device drivers to search for FIX8X14.SYS
  cmp word [es:bx], byte -1  ; is this the last device driver?
  je short devdrvrok         ; if so, FIX8X14.SYS not found

  les bx, [es:bx]            ; ES:BX = pointer to next device driver
  test byte [bx + 5], 80h    ; test for block driver
  jz short nextdevdrvr       ; if block driver, skip check

  lea di, [bx + 10]          ; DI = offset of name field in header
  mov si, progname           ; SI = offset of our program name
  mov cx, 7                  ; length of strings to compare
  repe cmpsb                 ; compare string at DS:SI against ES:DI
  jne short nextdevdrvr      ; if no match, check next

  mov dx, foundmsg           ; match, found device driver
  jmp exitwithmsg            ; end program with message

devdrvrok:
  ; link chain of upper memory blocks to chain of conventional
  ; DOS memory blocks
  mov ax, 5803h  ; DOS func AX = 5803h set UMB link state
  mov bx, 1      ; BX = 1 add UMBs to DOS memory chain
  int 21h

  ; get address of first MCB from the DOS list of lists
  mov ah, 52h          ; DOS func AH = 52h "SYSVARS"
  int 21h              ; ES:BX pointer to list of lists
  mov dx, [es:bx - 2]  ; offset -2 segment of first MCB

nextmcb:
  ; walk MCB chain to search for a copy of our TSR in memory
  mov es, dx            ; put segment of MCB into ES
  inc dx                ; add 1 + mem block paragraphs
  add dx, word [es:3]   ; to get segment of next MCB to DX

  mov al, byte [es:0]   ; save MCB signature byte

  mov es, word [es:1]   ; ES = segment of memory block
  xor di, di            ; offset of memory block = 0
  mov si, font8x14      ; SI = offset where to start compare
  mov cx, oldint10hofs  ; CX = length of TSR's fixed part
  cld                   ; clear direction flag
  rep cmpsb             ; compare string at DS:SI against ES:DI
  je short uninstall    ; if match, uninstall TSR

  cmp al, 'Z'           ; did we just check last MCB?

  jne short nextmcb     ; if not, check next MCB
  jmp short install     ; all checked, so install TSR

uninstall:
  mov dx, es  ; save ES = segment of memory block

  ; get address of current handler
  mov ax, 3510h  ; DOS func AH = 35h get interrupt vector
  int 21h        ; of interrupt 10h in ES:BX
  mov ax, es     ; AX = segment of int 10h address

  ; check if interrupt 10h is still owned by our TSR before
  ; restoring the old interrupt
  cmp bx, newint10hofs   ; offset of interrupt 10h changed?
  jne short vectornotok  ; if so, other program owns interrupt
  cmp ax, dx             ; segment of interrupt 10h changed?
  jne short vectornotok  ; if so, other program owns interrupt

  ; obtain address of old interrupt 10h from our TSR in memory and
  ; restore the old interrupt
  mov es, dx                     ; restore ES = segment of resident code
  mov dx, [es:oldint10hofs]      ; DX = offset of old interrupt 10h
  mov ds, [es:oldint10hofs + 2]  ; DS = segment of old interrupt 10h
  mov ax, 2510h                  ; DOS func AH = 25h set interrupt vector
  int 21h                        ; of interrupt 10h to DS:DX

  ; release memory block of TSR
  mov ah, 49h            ; DOS func AH = 49h free memory
  int 21h                ; ES = segment of block to free

  push cs                ; put current code segment
  pop ds                 ; back into DS

  mov dx, uninstallmsg   ; DX = offset of message
  jmp short exitwithmsg  ; end program with message

vectornotok:
  mov dx, vectornotokmsg  ; DX = offset of message
  jmp short exitwithmsg   ; end program with message

install:
  ; store old interrupt vector
  mov ax, 3510h            ; get interrupt 10h vector address
  int 21h                  ; in ES:BX through DOS
  mov [oldint10h], bx      ; store the address
  mov [oldint10h + 2], es

  ; change DOS memory allocation strategy to 'last fit' to get
  ; a memory block at the highest available address, this will
  ; prevent a memory hole just below the allocated block when
  ; the transient program ends
  mov ax, 5801h  ; DOS func AX = 5801h set memory allocation strategy
  mov bx, 2      ; select last fit
  int 21h        ; set allocation strategy
  jc short exit  ; exit if CF set on error

  ; calculate number of paragraphs needed for TSR and request
  ; appropriate memory block
  mov ah, 48h                  ; DOS func AH = 48h allocate memory
  mov bx, (tsrsize + 15) >> 4  ; BX paragraphs needed
  int 21h                      ; request memory block
  jc short exit                ; exit if CF set on error
  mov es, ax                   ; ES = segment of allocated block

  ; restore default DOS memory allocation strategy
  mov ax, 5801h  ; DOS func AX = 5801h set memory allocation strategy
  xor bx, bx     ; select first fit (default)
  int 21h        ; set allocation strategy
  jc short exit  ; exit if CF set on error

  ; copy font data and interrupt handler to allocated memory block
  mov si, font8x14  ; start of data and code to copy
  xor di, di        ; memory block starts at offset 0
  mov cx, tsrsize   ; size of resident data and code
  cld               ; clear direction flag
  rep movsb         ; transfer resident portion

  ; update owner's segment field in MCB of allocated block to make
  ; memory block own itself instead of being owned by the transient
  ; program, this prevents DOS from releasing the memory block when
  ; the transient program ends
  push es          ; save memory block segment

  push es          ; push memory block segment
  mov ax, es       ; AX = memory block segment
  dec ax           ; AX = segment of it's MCB
  mov es, ax       ; put MCB segment into ES
  pop word [es:1]  ; memory block now owns itself

  ; update name field in MCB of allocated block to allow DOS
  ; MEM utility to display the name of our TSR
  mov si, progname  ; offset of program name
  mov di, 8         ; offset of namespace in MCB
  mov cx, 8         ; length of string
  cld               ; clear direction flag
  rep movsb         ; transfer name into MCB

  ; set interrupt 10h to our handler
  pop ds                ; DS = memory block segment

  mov dx, newint10hofs  ; DX = offset of new interrupt 10h
  mov ax, 2510h         ; change interrupt 10h vector
  int 21h               ; to DS:DX through DOS

  push cs               ; push current code segment CS
  pop ds                ; and pop it back into DS

  mov dx, installmsg    ; DX = offset of message

exitwithmsg:
  mov ah, 9  ; DOS func AH = 09h write string to standard output
  int 21h    ; display message at DS:DX

exit:
  ; remove UMBs from chain of memory blocks to restore
  ; default link state before ending program
  mov ax, 5803h  ; DOS func AX = 5803h set UMB link state
  xor bx, bx     ; BX = 0 remove UMBs from DOS memory chain
  int 21h

  int 20h        ; end program using int 20h

; include the 8x14 font
font8x14
  incbin  '.\share\fix8x14.fnt'

; handle 8x14 font requests
newint10h:
  or ah, ah                   ; is it "Set video mode"?
  je short .setvidmode

  cmp ah, 11h                 ; is it a character generator function?
  jne short .done

  cmp al, 22h                 ; is it "Set ROM 8x14 graphics chars"?
  je short set8x14graphchars

  cmp al, 30h                 ; is it "Get font information"?
  jne short .done

  cmp bh, 2                   ; is it "ROM 8x14 character font pointer"?
  jne short .done

  push cs                     ; return pointer to internal font
  pop es
  xor bp, bp
  iret

.setvidmode:
  push ax
  and al, 7fh          ; discard "clear screen" bit

  cmp al, 0fh          ; is it 640x350 monochrome?
  je short setvidmode

  cmp al, 10h          ; is it 640x350 color?
  je short setvidmode
  pop ax

.done:
  jmp far [cs:oldint10hofs]  ; jump to old interrupt 10h handler

; handle direct requests to set 8x14 font in graphics modes
set8x14graphchars:
  push ax
  push cx
  push es
  push bp

  dec al                      ; call "Set user graphics pattern"
  push cs                     ; with address of internal font
  pop es
  xor bp, bp
  mov cx, 14
  pushf
  call far [cs:oldint10hofs]  ; call old interrupt 10h handler

  pop bp
  pop es
  pop cx
  pop ax
  iret

; handle requests for video modes that use the 8x14 font by default
setvidmode:
  pop ax                      ; restore register left-over by newint10h()

  pushf                       ; call old interrupt 10h handler
  call far [cs:oldint10hofs]

  push ax
  push ds

  xor ax, ax                  ; modify interrupt vector table entry
  mov ds, ax                  ; for "Video data - Character table"
  mov [43h * 4], ax
  mov [43h * 4 + 2], cs

  pop ds
  pop ax

  iret

; old interrupt 10h vector
oldint10h
  dd 0

; name to search for and to patch into MCB
progname
  db 'FIX8X14', 0

; size of resident part of the TSR
tsrsize equ progname - font8x14

; offset of new interrupt 10h vector
newint10hofs equ newint10h - font8x14

; offset of old interrupt 10h vector
oldint10hofs equ oldint10h - font8x14

; name and license of program
intromsg
  db 'FIX8X14 Version 1.0.8', 13, 10
  db 'Copyright (C) 1997-2002 BTTR Software', 13, 10
  db '[Under GNU GENERAL PUBLIC LICENSE]', 13, 10
  db 'Published by BTTR Software', 13, 10
  db 13, 10, '$'

; if installed successfully
installmsg
  db 'FIX8X14 installed.', 13, 10, '$'

; if device driver present in memory
foundmsg
  db 'FIX8X14 is already installed.', 13, 10, '$'

; if another program has intercepted int10h
vectornotokmsg
  db 'FIX8X14 cannot be uninstalled.', 13, 10, '$'

; if removed successfully from memory
uninstallmsg
  db 'FIX8X14 uninstalled.', 13, 10, '$'

  ; align stack at next segment boundary
  section .bss align=16

  ; stack space
  resb 128
top:
