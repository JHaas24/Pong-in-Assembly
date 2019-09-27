
%include "/usr/local/share/csc314/asm_io.inc"


; the file that stores the initial state
%define BOARD_FILE 'board.txt'

; how to represent everything
%define WALL_CHAR '#'
%define BALL_CHAR 'O'
%define PADDLE_CHAR '|'
%define EMPTY_CHAR ' '

; the size of the game screen in characters
%define HEIGHT 23
%define WIDTH 84

%define PADDLELEN 5
%define PADY 11
%define PADY2 9

; the ball starting position.
; top left is considered (0,0)
%define STARTX 42
%define STARTY 6

%define INITIAL_GOLD 10000

; these keys do things
%define EXITCHAR 'x'
%define UPCHAR 'w'
%define DOWNCHAR 's'
%define UPCHAR2 'i'
%define DOWNCHAR2 'k'


%define TICK 60000

segment .data

        ; used to fopen() the board file defined above
        board_file                      db BOARD_FILE,0

        ; used to change the terminal mode
        mode_r                          db "r",0
        raw_mode_on_cmd         db "stty raw -echo",0
        raw_mode_off_cmd        db "stty -raw echo",0

        ; called by system() to clear/refresh the screen
        clear_screen_cmd        db "clear",0

; things the program will print
        help_str                        db 13,10,"Controls: ", \
                                                        UPCHAR,"=P1UP / ", \
                                                        DOWNCHAR,"=P1DOWN / ", \
                                                        DOWNCHAR,"=P2UP / ", \
                                                        DOWNCHAR,"=P2DOWN / ", \
                                                        EXITCHAR,"=EXIT", \
                                                        13,10,10,0

        scr1_fmt                        db "Player 1: %d", 10,10,13,0
        scr2_fmt                        db "Player 2: %d", 10,10,13,0

segment .bss

        ;speed of the game
        Tick    resb    1

        ; this array stores the current rendered gameboard (HxW)
        board   resb    (HEIGHT * WIDTH)

        ; these variables store the current ball position
        xpos    resd    1
        ypos    resd    1

        ;direction of the ball
        x_dir   resd    1
        y_dir   resd    1

        ;keep track of score
        p1_scr          resd    1
        p2_scr          resd    1

        ;paddle length
        pad_len         resd    1
        top_pady        resd    1
        top_pady2       resd    1
segment .text

        global  asm_main
        global  raw_mode_on
        global  raw_mode_off
        global  init_board
        global  render

        extern  system
        extern  putchar
        extern  getchar
        extern  printf
        extern  fopen
        extern  fread
        extern  fgetc
        extern  fclose
        extern  usleep          ; used to slow down the read loop
        extern  fcntl           ; used to change the blocking mode
        extern  getchar         ; used to get a single character
        extern  putchar         ; used to print a single character

asm_main:
        enter   0,0
        pusha
        ;***************CODE STARTS HERE***************************

        ; put the terminal in raw mode so the game works nicely
        call    raw_mode_on

        ; read the game board file into the global variable
        call    init_board

        ; set the player at the proper start position
;       mov             DWORD [Tick], TICK

        mov             DWORD [xpos], STARTX
        mov             DWORD [ypos], STARTY
        mov             DWORD [x_dir], 1
        mov             DWORD [y_dir], -1

        mov             DWORD [p1_scr], 0
        mov             DWORD [p2_scr], 0

        mov             DWORD[pad_len], PADDLELEN
        mov             DWORD[top_pady], PADY
        mov             DWORD[top_pady2], PADY2
; the game happens in this loop
        ; the steps are...
        ;   1. render (draw) the current board
        ;   2. get a character from the user
        ;       3. store current xpos,ypos in esi,edi
        ;       4. update xpos,ypos based on character from user
        ;       5. check what's in the buffer (board) at new xpos,ypos
        ;       6. if it's a wall, reset xpos,ypos to saved esi,edi
        ;       7. otherwise, just continue! (xpos,ypos are ok)
        game_loop:

                ; draw the game board
                call    render
                push    TICK
                call    usleep
                add             esp, 4


        ;boundery check
                cmp     DWORD[ypos], 1
                jne             not_top
                add             DWORD[y_dir], 2
                not_top:
                mov             eax, HEIGHT
                sub             eax, 2
                cmp     DWORD[ypos], eax
                jne             not_bot
                sub             DWORD[y_dir], 2
                not_bot:

        ; (W * y) + x = pos
        ;       mov             eax, BYTE[board*2 + 2]
                ;paddle check
                mov             eax, WIDTH
                mul             DWORD [ypos]
                add             eax, [xpos]
                inc             eax
                lea             eax, [board + eax]
                cmp             BYTE [eax], WALL_CHAR
                jne             noScorer
                inc             DWORD[p1_scr]
                mov             DWORD[xpos], STARTX
                mov             DWORD[ypos], STARTY
;               mov             DWORD[Tick], TICK
;               jmp             norightpaddle
                noScorer:
                cmp             BYTE [eax], PADDLE_CHAR
                jne             norightpaddle
                sub             DWORD[x_dir], 2
                ;increase ball speed


                norightpaddle:
                mov             eax, WIDTH
                mul             DWORD [ypos]
                add             eax, [xpos]
                dec             eax
                lea             eax, [board + eax]
                cmp             BYTE [eax], WALL_CHAR
                jne             noScorel
                inc             DWORD[p2_scr]
                mov             DWORD[xpos], STARTX
                mov             DWORD[ypos], STARTY
;               mov             DWORD[Tick], TICK
;               jmp             noleftpaddle
                noScorel:
                cmp             BYTE [eax], PADDLE_CHAR
                jne             noleftpaddle
                add             DWORD[x_dir], 2
                noleftpaddle:

                ;move the ball
        mov             eax, DWORD[x_dir]
        add             DWORD[xpos], eax
        mov             eax, DWORD[y_dir]
        add             DWORD[ypos], eax

                mov             eax, DWORD[top_pady]
                ; get an action from the user
                call    nonblocking_getchar

                cmp             al, -1
                je              game_loop

                ; store the current position
                ; we will test if the new position is legal
                ; if not, we will restore these
                mov             esi, [xpos]
                mov             edi, [ypos]

                ; choose what to do
                cmp             eax, EXITCHAR
                je              game_loop_end
                cmp             eax, UPCHAR
                je              move_up
                cmp             eax, UPCHAR2
                je              move_up2
                cmp             eax, DOWNCHAR
                je              move_down
                cmp             eax, DOWNCHAR2
                je              move_down2
                jmp             input_end                       ; or just do nothing


                ; move the player according to the input character
                move_up:

                ;put each paddle character into spot above
                mov             eax, WIDTH
                mov             ebx, DWORD[top_pady]
                sub             ebx, 1
                mul             ebx
                add             eax, 1

                ;if valid
                cmp             BYTE[board + eax], WALL_CHAR
                je              tremendous
                mov             BYTE[board + eax], '|'
                mov             eax, WIDTH
                mov             ebx, DWORD[top_pady]
                add             ebx, DWORD[pad_len]
                dec     ebx
                mul             ebx
                add             eax, 1
                mov             BYTE[board + eax], ' '

                dec             DWORD[top_pady]
                tremendous:
                        jmp             input_end


                move_up2:

                ;put each paddle character into spot above
                mov             eax, WIDTH
                mov             ebx, DWORD[top_pady2]
                sub             ebx, 1
                mul             ebx
                add             eax, WIDTH-2

                ;if valid
                cmp             BYTE[board + eax], WALL_CHAR
                je              tremendousup
                mov             BYTE[board + eax], '|'
                mov             eax, WIDTH
                mov             ebx, DWORD[top_pady2]
                add             ebx, DWORD[pad_len]
                dec     ebx
                mul             ebx
                add             eax, WIDTH-2
                mov             BYTE[board + eax], ' '

                dec             DWORD[top_pady2]
                tremendousup:
                        jmp             input_end

                move_down:

                ;put each paddle character into spot above
                mov             eax, WIDTH
                mov             ebx, DWORD[top_pady]
                mul             ebx
                add             eax, 1


                ;if valid
                mov             ecx, eax
                mov             eax, WIDTH
                mov             ebx, DWORD[top_pady]
                add             ebx, DWORD[pad_len]
                mul             ebx
                add             eax, 1

                cmp             BYTE[board + eax], WALL_CHAR
                je              tremendous2
                mov         BYTE[board + ecx], ' '
                mov             BYTE[board + eax], '|'

                inc             DWORD[top_pady]
                tremendous2:
            jmp     input_end


                move_down2:

                ;put each paddle character into spot above
                mov             eax, WIDTH
                mov             ebx, DWORD[top_pady2]
                mul             ebx
                add             eax, WIDTH-2

                ;if valid
                mov             ecx, eax
                mov             eax, WIDTH
                mov             ebx, DWORD[top_pady2]
                add             ebx, DWORD[pad_len]
                mul             ebx
                add             eax, WIDTH-2

                cmp             BYTE[board + eax], WALL_CHAR
                je              tremendous22
                mov         BYTE[board + ecx], ' '
                mov             BYTE[board + eax], '|'

                inc             DWORD[top_pady2]
                tremendous22:
            jmp     input_end

                input_end:

        jmp             game_loop
        game_loop_end:

        ; restore old terminal functionality
        call raw_mode_off

        ;***************CODE ENDS HERE*****************************
        popa
        mov             eax, 0
        leave
        ret

; === FUNCTION ===
raw_mode_on:

        push    ebp
        mov             ebp, esp

        push    raw_mode_on_cmd
        call    system
        add             esp, 4

        mov             esp, ebp
        pop             ebp
        ret

; === FUNCTION ===
raw_mode_off:

        push    ebp
        mov             ebp, esp

        push    raw_mode_off_cmd
        call    system
        add             esp, 4

        mov             esp, ebp
        pop             ebp
        ret

; === FUNCTION ===
init_board:

        push    ebp
        mov             ebp, esp

        ; FILE* and loop counter
        ; ebp-4, ebp-8
        sub             esp, 8

        ; open the file
        push    mode_r
        push    board_file
        call    fopen
        add             esp, 8
        mov             DWORD [ebp-4], eax

        ; read the file data into the global buffer
        ; line-by-line so we can ignore the newline characters
        mov             DWORD [ebp-8], 0
        read_loop:
        cmp             DWORD [ebp-8], HEIGHT
        je              read_loop_end

                ; find the offset (WIDTH * counter)
                mov             eax, WIDTH
                mul             DWORD [ebp-8]
                lea             ebx, [board + eax]

                ; read the bytes into the buffer
                push    DWORD [ebp-4]
                push    WIDTH
                push    1
                push    ebx
                call    fread
                add             esp, 16

                ; slurp up the newline
                push    DWORD [ebp-4]
                call    fgetc
                add             esp, 4

        inc             DWORD [ebp-8]
        jmp             read_loop
        read_loop_end:

        ; close the open file handle
        push    DWORD [ebp-4]
        call    fclose
        add             esp, 4

        mov             esp, ebp
        pop             ebp
        ret

; === FUNCTION ===
render:

        push    ebp
        mov             ebp, esp

        ; two ints, for two loop counters
        ; ebp-4, ebp-8
        sub             esp, 8

        ; clear the screen
        push    clear_screen_cmd
        call    system
        add             esp, 4

        ; print the help information
        push    help_str
        call    printf
        add             esp, 4
        push    DWORD[p1_scr]
        push    scr1_fmt
        call    printf
        add             esp, 8
        push    DWORD[p2_scr]
        push    scr2_fmt
        call    printf
        add             esp, 8


        ; outside loop by height
        ; i.e. for(c=0; c<height; c++)
        mov             DWORD [ebp-4], 0
        y_loop_start:
        cmp             DWORD [ebp-4], HEIGHT
        je              y_loop_end

                ; inside loop by width
                ; i.e. for(c=0; c<width; c++)
                mov             DWORD [ebp-8], 0
                x_loop_start:
                cmp             DWORD [ebp-8], WIDTH
                je              x_loop_end

                        ; check if (xpos,ypos)=(x,y)
                        mov             eax, [xpos]
                        cmp             eax, DWORD [ebp-8]
                        jne             print_board
                        mov             eax, [ypos]
                        cmp             eax, DWORD [ebp-4]
                        jne             print_board
                                ; if both were equal, print the player
                                push    BALL_CHAR
                                jmp             print_end
                        print_board:
                                ; otherwise print whatever's in the buffer
                                mov             eax, [ebp-4]
                                mov             ebx, WIDTH
                                mul             ebx
                                add             eax, [ebp-8]
                                mov             ebx, 0
                                mov             bl, BYTE [board + eax]
                                push    ebx
                        print_end:
                        call    putchar
                        add             esp, 4

                inc             DWORD [ebp-8]
                jmp             x_loop_start
                x_loop_end:

                ; write a carriage return (necessary when in raw mode)
                push    0x0d
                call    putchar
                add             esp, 4

                ; write a newline
                push    0x0a
                call    putchar
                add             esp, 4

        inc             DWORD [ebp-4]
        jmp             y_loop_start
        y_loop_end:

        mov             esp, ebp
        pop             ebp
        ret


; === FUNCTION ===
nonblocking_getchar:

; returns -1 on no-data
; returns char on succes

; magic values
%define F_GETFL 3
%define F_SETFL 4
%define O_NONBLOCK 2048
%define STDIN 0

        push    ebp
        mov             ebp, esp

        ; single int used to hold flags
        ; single character (aligned to 4 bytes) return
        sub             esp, 8

        ; get current stdin flags
        ; flags = fcntl(stdin, F_GETFL, 0)
        push    0
        push    F_GETFL
        push    STDIN
        call    fcntl
        add             esp, 12
        mov             DWORD [ebp-4], eax

        ; set non-blocking mode on stdin
        ; fcntl(stdin, F_SETFL, flags | O_NONBLOCK)
        or              DWORD [ebp-4], O_NONBLOCK
        push    DWORD [ebp-4]
        push    F_SETFL
        push    STDIN
        call    fcntl
        add             esp, 12

        call    getchar
        mov             DWORD [ebp-8], eax

        ; restore blocking mode
        ; fcntl(stdin, F_SETFL, flags ^ O_NONBLOCK
        xor             DWORD [ebp-4], O_NONBLOCK
        push    DWORD [ebp-4]
        push    F_SETFL
        push    STDIN
        call    fcntl
        add             esp, 12

        mov             eax, DWORD [ebp-8]

        mov             esp, ebp
        pop             ebp
        ret