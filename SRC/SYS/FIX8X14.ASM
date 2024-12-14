; ****************************************************************************
; "FIX8X14" - 8x14 font fixer (device driver)
;             Part of the 8x14 font fixing package "FIX8X14"
;
; Written by Robert Riebisch <rr@bttr-software.de>
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

  org 0  ; it is a device driver

; device driver header
devdrvrhdr
  dd -1                 ; pointer to next device driver header
  dw 1000000000000000b  ; device driver attributes (character device driver)
  dw stratfunc          ; offset to device driver strategy routine
.intfuncaddr            ; ! to be patched later !
  dw main               ; offset to device driver interrupt routine
  db "FIX8X14$"         ; device driver name

; pointer to request header
reqhdraddr
  dd 0

; device driver strategy routine
stratfunc:
  mov [cs:reqhdraddr], bx      ; save pointer to data structure
  mov [cs:reqhdraddr + 2], es
  retf

; "dummy" device driver interrupt routine to keep system state clear
intfunc:
  push bx                               ; save used registers
  push ds

  lds bx, [cs:reqhdraddr]               ; point DS:BX to request header
  mov word [bx + 3], 1000000100000011b  ; return error "UNKNOWN
                                        ; COMMAND" + "DONE"

  pop ds                                ; restore used registers
  pop bx
  retf

; include the 8x14 font
font8x14
  incbin '.\share\fix8x14.fnt'

; old interrupt 10h vector
oldint10h
  dd 0

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

  pushf                       ; call old interrupt 10h handler
  call far [cs:oldint10h]

  push cs                     ; return pointer to internal font
  pop es
  mov bp, font8x14
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
  jmp far [cs:oldint10h]  ; jump to old interrupt 10h handler

; handle direct requests to set 8x14 font in graphics modes
set8x14graphchars:
  push ax
  push cx
  push es
  push bp

  dec al                   ; call "Set user graphics pattern"
  push cs                  ; with address of internal font
  pop es
  mov bp, font8x14
  mov cx, 14
  pushf
  call far [cs:oldint10h]  ; call old interrupt 10h handler

  pop bp
  pop es
  pop cx
  pop ax
  iret

; handle requests for video modes that use the 8x14 font by default
setvidmode:
  pop ax                        ; restore register left-over by newint10h()

  pushf                         ; call old interrupt 10h handler
  call far [cs:oldint10h]

  push ax
  push ds

  xor ax, ax                    ; modify interrupt vector table entry
  mov ds, ax                    ; for "Video data - Character table"
  mov word [43h * 4], font8x14
  mov [43h * 4 + 2], cs

  pop ds
  pop ax

  iret

; device driver interrupt routine (used during INIT() only)
main:
  push ax                                     ; save used registers
  push bx
  push dx
  push ds
  push es
  pushf

  push cs                                     ; point data segment
  pop ds                                      ; to code segment

  mov ah, 9                                   ; display name and
  mov dx, intromsg                            ; license of program
  int 21h

  mov ax, 3510h                               ; save interrupt 10h vector
  int 21h
  mov [oldint10h], bx
  mov [oldint10h + 2], es

  mov ah, 25h                                 ; install new
  mov dx, newint10h                           ; interrupt 10h handler
  int 21h

  mov word [devdrvrhdr.intfuncaddr], intfunc  ; patching to the new device
                                              ; driver interrupt routine

  lds bx, [reqhdraddr]                        ; point DS:BX to request header

  mov word [bx + 14], main                    ; specify end of resident code
  mov [bx + 16], cs

  mov word [bx + 3], 100000000b               ; return "NO ERROR" + "DONE"

  popf                                        ; restore used registers
  pop es
  pop ds
  pop dx
  pop bx
  pop ax
  retf

; name and license of program
intromsg
  db 'FIX8X14 Version 1.0.8', 13, 10
  db 'Copyright (C) 1997-2002 BTTR Software', 13, 10
  db '[Under GNU GENERAL PUBLIC LICENSE]', 13, 10
  db 'Published by BTTR Software', 13, 10, '$'
