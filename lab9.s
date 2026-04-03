TTL Exercise Nine: Serial I/O Driver
;****************************************************************
; This program implements an interrupt-based serial I/O driver
; for the KL05Z using UART0 with circular FIFO receive and
; transmit queues. It adapts the queue command-menu application
; from Lab Exercise Seven to use interrupt-driven I/O.
;
; Name:  Arnav Gwas
;---------------------------------------------------------------
; Keil Template for KL05
; R. W. Melton
; Spring 2026
;****************************************************************
;Assembler directives
            THUMB
            OPT    64  ;Turn on listing macro expansions
;****************************************************************
;Include files
            GET  MKL05Z4.s     ;Included by start.s
            OPT  1             ;Turn on listing
;****************************************************************
;EQUates

;---------------------------------------------------------------
;Characters
CR          EQU  0x0D
LF          EQU  0x0A
NULL        EQU  0x00

;---------------------------------------------------------------
;Queue record structure field offsets
IN_PTR      EQU  0    ;(word)  pointer to next enqueue location
OUT_PTR     EQU  4    ;(word)  pointer to next dequeue location
BUF_STRT    EQU  8    ;(word)  pointer to start of buffer
BUF_PAST    EQU  12   ;(word)  pointer to one past end of buffer
BUF_SIZE    EQU  16   ;(byte)  capacity of buffer in characters
NUM_ENQD    EQU  17   ;(byte)  number of characters enqueued
Q_REC_SIZE  EQU  18   ;total size of queue record in bytes

;---------------------------------------------------------------
;Queue buffer capacities
RX_BUF_SIZE EQU  80
TX_BUF_SIZE EQU  80
Q_BUF_SIZE  EQU  4

;---------------------------------------------------------------
;Port B pin control register values for UART0 RX/TX
PORT_PCR_SET_PTB2_UART0_RX  EQU  (PORT_PCR_ISF_MASK :OR: \
                                   PORT_PCR_MUX_SELECT_2_MASK)
PORT_PCR_SET_PTB1_UART0_TX  EQU  (PORT_PCR_ISF_MASK :OR: \
                                   PORT_PCR_MUX_SELECT_2_MASK)

;---------------------------------------------------------------
;SIM_SOPT2: select MCGFLLCLK as UART0 clock source
SIM_SOPT2_UART0SRC_MCGFLLCLK  EQU  \
                                 (1 << SIM_SOPT2_UART0SRC_SHIFT)

;---------------------------------------------------------------
;SIM_SOPT5: clear UART0 external connection fields
SIM_SOPT5_UART0_EXTERN_MASK_CLEAR  EQU  \
                               (SIM_SOPT5_UART0ODE_MASK :OR: \
                                SIM_SOPT5_UART0RXSRC_MASK :OR: \
                                SIM_SOPT5_UART0TXSRC_MASK)

;---------------------------------------------------------------
;UART0 baud rate for 9600 baud
;UART0CLK = MCGFLLCLK = 48 MHz
;SBR = 48,000,000 / (9600 * 16) = 312.5 -> 312 = 0x138
UART0_BDH_9600  EQU  0x01
UART0_BDL_9600  EQU  0x38

;---------------------------------------------------------------
;UART0_C1: 8 data bits, no parity, 1 stop bit
UART0_C1_8N1  EQU  0x00

;---------------------------------------------------------------
;UART0_C2 combinations
;TE+RE only (used to disable before config, and as base)
UART0_C2_T_R      EQU  (UART0_C2_TE_MASK :OR: UART0_C2_RE_MASK)
;TE+RE+RIE: receiver interrupt enabled; TIE left off until PutChar
UART0_C2_T_R_RI   EQU  (UART0_C2_TE_MASK :OR: \
                         UART0_C2_RE_MASK :OR: \
                         UART0_C2_RIE_MASK)

;---------------------------------------------------------------
;UART0_C3: no TX inversion
UART0_C3_NO_TXINV  EQU  0x00

;---------------------------------------------------------------
;UART0_C4: OSR = 16
UART0_C4_OSR_16           EQU  0x0F
UART0_C4_NO_MATCH_OSR_16  EQU  UART0_C4_OSR_16

;---------------------------------------------------------------
;UART0_C5: no DMA, synchronous resample
UART0_C5_NO_DMA_SSR_SYNC  EQU  0x00

;---------------------------------------------------------------
;UART0_S1: clear error flags on init
UART0_S1_CLEAR_FLAGS  EQU  (UART0_S1_IDLE_MASK :OR: \
                             UART0_S1_OR_MASK   :OR: \
                             UART0_S1_NF_MASK   :OR: \
                             UART0_S1_FE_MASK   :OR: \
                             UART0_S1_PF_MASK)

;---------------------------------------------------------------
;UART0_S2: clear LIN and edge flags
UART0_S2_NO_RXINV_BRK10_NO_LBKDETECT_CLEAR_FLAGS  EQU  \
        (UART0_S2_LBKDIF_MASK :OR: UART0_S2_RXEDGIF_MASK)

;---------------------------------------------------------------
;NVIC: UART0 is IRQ 12 -> bit 12 in ISER/ICPR
UART0_IRQ_MASK  EQU  UART0_IRQ_MASK   ;defined in MKL05Z4.s

;****************************************************************
;Program
            AREA    MyCode,CODE,READONLY
            ENTRY
            EXPORT  Reset_Handler
            IMPORT  Startup

            EXPORT  PutChar
            EXPORT  GetChar

Reset_Handler  PROC  {}
main
;---------------------------------------------------------------
;Mask interrupts during startup
            CPSID   I
;KL05 system startup with 48-MHz system clock
            BL      Startup
;---------------------------------------------------------------
;>>>>> begin main program code <<<<<

            ; Step 1: Initialize UART0 for interrupt-based serial I/O
            BL      Init_UART0_IRQ

            ; Step 2: Initialize 4-character application queue
            LDR     R0, =QBuffer        ;R0 = buffer address
            LDR     R1, =QRecord        ;R1 = record address
            MOVS    R2, #Q_BUF_SIZE     ;R2 = capacity (4)
            BL      InitQueue

            ; Unmask interrupts now that UART0 ISR is installed
            CPSIE   I

;---------------------------------------------------------------
;Main command loop
;---------------------------------------------------------------
MainLoop
            ; Step 3: Print command prompt
            LDR     R0, =PromptStr
            BL      PutStringSB

GetCmdChar
            ; Step 4: Read a character from the terminal
            BL      GetChar
            MOVS    R4, R0              ;R4 = original character typed

            ; Step 5: If lowercase alpha, make uppercase copy in R0
            CMP     R0, #'a'
            BLO     CheckValid
            CMP     R0, #'z'
            BHI     CheckValid
            SUBS    R0, R0, #('a'-'A')  ;convert copy to uppercase

            ; Step 6: Validate command (D E H P S only)
CheckValid
            CMP     R0, #'D'
            BEQ     ValidCmd
            CMP     R0, #'E'
            BEQ     ValidCmd
            CMP     R0, #'H'
            BEQ     ValidCmd
            CMP     R0, #'P'
            BEQ     ValidCmd
            CMP     R0, #'S'
            BEQ     ValidCmd
            B       GetCmdChar          ;not valid: ignore and retry

ValidCmd
            ; Step 7: Echo original character then CR LF
            MOVS    R5, R0              ;R5 = uppercase command
            MOVS    R0, R4             ;R0 = original char typed
            BL      PutChar
            MOVS    R0, #CR
            BL      PutChar
            MOVS    R0, #LF
            BL      PutChar

            ;Dispatch to command handler
            CMP     R5, #'D'
            BEQ     CmdDequeue
            CMP     R5, #'E'
            BEQ     CmdEnqueue
            CMP     R5, #'H'
            BEQ     CmdHelp
            CMP     R5, #'P'
            BEQ     CmdPrint
            B       CmdStatus           ;must be 'S'

;---------------------------------------------------------------
;Command D: Dequeue a character from the application queue
;---------------------------------------------------------------
CmdDequeue
            LDR     R1, =QRecord
            BL      Dequeue
            BCS     DequeueFail         ;C=1: queue was empty
            ;Success: print "Dequeued: X\r\n"
            PUSH    {R0}
            LDR     R0, =DequeuedStr
            BL      PutStringSB
            POP     {R0}
            BL      PutChar
            MOVS    R0, #CR
            BL      PutChar
            MOVS    R0, #LF
            BL      PutChar
            B       MainLoop
DequeueFail
            LDR     R0, =QueueEmptyStr
            BL      PutStringSB
            B       MainLoop

;---------------------------------------------------------------
;Command E: Enqueue a character to the application queue
;---------------------------------------------------------------
CmdEnqueue
            LDR     R0, =EnqueuePromptStr
            BL      PutStringSB
            BL      GetChar             ;get character to enqueue
            MOVS    R4, R0              ;save it
            BL      PutChar             ;echo it
            MOVS    R0, #CR
            BL      PutChar
            MOVS    R0, #LF
            BL      PutChar
            MOVS    R0, R4              ;restore character
            LDR     R1, =QRecord
            BL      Enqueue
            BCS     EnqueueFail         ;C=1: queue was full
            LDR     R0, =EnqueuedStr
            BL      PutStringSB
            B       MainLoop
EnqueueFail
            LDR     R0, =QueueFullStr
            BL      PutStringSB
            B       MainLoop

;---------------------------------------------------------------
;Command H: Help - list all commands
;---------------------------------------------------------------
CmdHelp
            LDR     R0, =HelpStr
            BL      PutStringSB
            B       MainLoop

;---------------------------------------------------------------
;Command P: Print all queued characters in FIFO order
;           Reads directly from the buffer without dequeuing
;---------------------------------------------------------------
CmdPrint
            LDR     R0, =PrintHeaderStr
            BL      PutStringSB
            LDR     R1, =QRecord
            LDRB    R2, [R1, #NUM_ENQD] ;R2 = number enqueued
            CMP     R2, #0
            BEQ     PrintDone
            LDR     R3, [R1, #OUT_PTR]  ;R3 = read cursor (OutPointer)
            LDR     R6, [R1, #BUF_PAST] ;R6 = one past end of buffer
            LDR     R7, [R1, #BUF_STRT] ;R7 = start of buffer
PrintLoop
            CMP     R2, #0
            BEQ     PrintDone
            LDRB    R0, [R3]            ;load character at cursor
            BL      PutChar
            ADDS    R3, R3, #1          ;advance cursor
            CMP     R3, R6              ;check for wrap
            BNE     PrintNoWrap
            MOVS    R3, R7              ;wrap to buffer start
PrintNoWrap
            SUBS    R2, R2, #1
            B       PrintLoop
PrintDone
            MOVS    R0, #CR
            BL      PutChar
            MOVS    R0, #LF
            BL      PutChar
            B       MainLoop

;---------------------------------------------------------------
;Command S: Status - print InPointer, OutPointer, NumberEnqueued
;---------------------------------------------------------------
CmdStatus
            LDR     R1, =QRecord
            ;Print InPointer
            LDR     R0, =InPtrStr
            BL      PutStringSB
            LDR     R0, [R1, #IN_PTR]
            BL      PutNumHex
            MOVS    R0, #CR
            BL      PutChar
            MOVS    R0, #LF
            BL      PutChar
            ;Print OutPointer
            LDR     R0, =OutPtrStr
            BL      PutStringSB
            LDR     R0, [R1, #OUT_PTR]
            BL      PutNumHex
            MOVS    R0, #CR
            BL      PutChar
            MOVS    R0, #LF
            BL      PutChar
            ;Print NumberEnqueued
            LDR     R0, =NumEnqdStr
            BL      PutStringSB
            LDRB    R0, [R1, #NUM_ENQD]
            BL      PutNumUB
            MOVS    R0, #CR
            BL      PutChar
            MOVS    R0, #LF
            BL      PutChar
            B       MainLoop

;>>>>>   end main program code <<<<<
;Stay here
            B       .
            ENDP    ;main

;>>>>> begin subroutine code <<<<<

;==============================================================
;Init_UART0_IRQ
;  Initializes UART0 for interrupt-based serial I/O at 9600
;  baud, 8N1. Enables RDRF receive interrupt (RIE). TIE is left
;  off here and is enabled dynamically by PutChar when there is
;  data to transmit. Also initializes RxQRecord and TxQRecord
;  via InitQueue for 80-character buffers.
;  Preserves all registers.
;==============================================================
Init_UART0_IRQ  PROC  {R0-R14}
            PUSH    {R0, R1, R2}

            ;Select MCGFLLCLK as UART0 clock source
            LDR     R0, =SIM_SOPT2
            LDR     R1, =SIM_SOPT2_UART0SRC_MASK
            LDR     R2, [R0, #0]
            BICS    R2, R2, R1
            LDR     R1, =SIM_SOPT2_UART0SRC_MCGFLLCLK
            ORRS    R2, R2, R1
            STR     R2, [R0, #0]

            ;Set UART0 for external connection
            LDR     R0, =SIM_SOPT5
            LDR     R1, =SIM_SOPT5_UART0_EXTERN_MASK_CLEAR
            LDR     R2, [R0, #0]
            BICS    R2, R2, R1
            STR     R2, [R0, #0]

            ;Enable UART0 module clock
            LDR     R0, =SIM_SCGC4
            LDR     R1, =SIM_SCGC4_UART0_MASK
            LDR     R2, [R0, #0]
            ORRS    R2, R2, R1
            STR     R2, [R0, #0]

            ;Enable Port B module clock
            LDR     R0, =SIM_SCGC5
            LDR     R1, =SIM_SCGC5_PORTB_MASK
            LDR     R2, [R0, #0]
            ORRS    R2, R2, R1
            STR     R2, [R0, #0]

            ;Select PTB2 for UART0 RX (ALT2)
            LDR     R0, =PORTB_PCR2
            LDR     R1, =PORT_PCR_SET_PTB2_UART0_RX
            STR     R1, [R0, #0]

            ;Select PTB1 for UART0 TX (ALT2)
            LDR     R0, =PORTB_PCR1
            LDR     R1, =PORT_PCR_SET_PTB1_UART0_TX
            STR     R1, [R0, #0]

            ;Disable UART0 TX and RX before configuring
            LDR     R0, =UART0_BASE
            MOVS    R1, #UART0_C2_T_R
            LDRB    R2, [R0, #UART0_C2_OFFSET]
            BICS    R2, R2, R1
            STRB    R2, [R0, #UART0_C2_OFFSET]

            ;Set baud rate 9600
            MOVS    R1, #UART0_BDH_9600
            STRB    R1, [R0, #UART0_BDH_OFFSET]
            MOVS    R1, #UART0_BDL_9600
            STRB    R1, [R0, #UART0_BDL_OFFSET]

            ;Configure framing: 8N1
            MOVS    R1, #UART0_C1_8N1
            STRB    R1, [R0, #UART0_C1_OFFSET]
            MOVS    R1, #UART0_C3_NO_TXINV
            STRB    R1, [R0, #UART0_C3_OFFSET]
            MOVS    R1, #UART0_C4_NO_MATCH_OSR_16
            STRB    R1, [R0, #UART0_C4_OFFSET]
            MOVS    R1, #UART0_C5_NO_DMA_SSR_SYNC
            STRB    R1, [R0, #UART0_C5_OFFSET]

            ;Clear status flags
            MOVS    R1, #UART0_S1_CLEAR_FLAGS
            STRB    R1, [R0, #UART0_S1_OFFSET]
            MOVS    R1, #UART0_S2_NO_RXINV_BRK10_NO_LBKDETECT_CLEAR_FLAGS
            STRB    R1, [R0, #UART0_S2_OFFSET]

            ;Enable TX, RX, and Receive Interrupt (RIE)
            ;TIE is NOT set here; PutChar enables it when needed
            MOVS    R1, #UART0_C2_T_R_RI
            STRB    R1, [R0, #UART0_C2_OFFSET]

            ;Clear any pending UART0 interrupt in NVIC
            LDR     R0, =NVIC_ICPR
            LDR     R1, =UART0_IRQ_MASK
            STR     R1, [R0]

            ;Enable UART0 interrupt in NVIC (IRQ 12)
            LDR     R0, =NVIC_ISER
            LDR     R1, =UART0_IRQ_MASK
            STR     R1, [R0]

            ;Initialize Receive Queue (80 chars)
            LDR     R0, =RxQBuffer
            LDR     R1, =RxQRecord
            MOVS    R2, #RX_BUF_SIZE
            BL      InitQueue

            ;Initialize Transmit Queue (80 chars)
            LDR     R0, =TxQBuffer
            LDR     R1, =TxQRecord
            MOVS    R2, #TX_BUF_SIZE
            BL      InitQueue

            POP     {R0, R1, R2}
            BX      LR
            ENDP

;==============================================================
;UART0_ISR
;  UART0 interrupt service routine.
;
;  Receive (RDRF set):
;    Reads UART0_D (clears RDRF) and enqueues byte to RxQueue.
;    If RxQueue is full the received byte is silently dropped.
;
;  Transmit (TDRE set):
;    Attempts to dequeue one byte from TxQueue and writes it to
;    UART0_D (clears TDRE). If TxQueue is empty, clears TIE so
;    the ISR will not be re-entered for transmit until PutChar
;    re-enables TIE.
;
;  The Cortex-M0+ hardware automatically preserves R0-R3, R12,
;  LR, PC, and PSR on ISR entry/exit. This ISR additionally
;  saves and restores R4-R7 since it uses them.
;  No registers are changed on return.
;==============================================================
UART0_ISR   PROC  {}
            PUSH    {R4, R5, R6, R7, LR}

            LDR     R6, =UART0_BASE     ;R6 -> UART0 base

            ;--- Check RDRF: Receive Data Register Full ---
            LDRB    R0, [R6, #UART0_S1_OFFSET]
            MOVS    R1, #UART0_S1_RDRF_MASK
            TST     R0, R1
            BEQ     CheckTDRE           ;RDRF not set, skip receive

            ;Read received byte from UART0_D (clears RDRF)
            LDRB    R0, [R6, #UART0_D_OFFSET]
            LDR     R1, =RxQRecord
            BL      Enqueue             ;enqueue to receive queue
            ;If queue was full (C=1), byte is silently dropped

            ;--- Check TDRE: Transmit Data Register Empty ---
CheckTDRE
            LDRB    R0, [R6, #UART0_S1_OFFSET]
            MOVS    R1, #UART0_S1_TDRE_MASK
            TST     R0, R1
            BEQ     ISR_Done            ;TDRE not set, skip transmit

            ;Attempt to dequeue from transmit queue
            LDR     R1, =TxQRecord
            BL      Dequeue
            BCS     DisableTIE          ;C=1: TxQueue empty, disable TIE

            ;Write dequeued character to UART0_D (clears TDRE)
            STRB    R0, [R6, #UART0_D_OFFSET]
            B       ISR_Done

DisableTIE
            ;Clear TIE bit in UART0_C2 to stop transmit interrupts
            LDRB    R1, [R6, #UART0_C2_OFFSET]
            MOVS    R2, #UART0_C2_TIE_MASK
            BICS    R1, R1, R2
            STRB    R1, [R6, #UART0_C2_OFFSET]

ISR_Done
            POP     {R4, R5, R6, R7, PC}
            ENDP

;==============================================================
;GetChar
;  Dequeues and returns one character from the receive queue.
;  Blocks (busy-waits with interrupts enabled) until a character
;  is available in RxQRecord.
;  Input:  (none)
;  Output: R0 = received character
;  Preserves all registers except R0 and PSR.
;==============================================================
GetChar     PROC  {R1-R14}
            PUSH    {R1, LR}
GetCharLoop
            LDR     R1, =RxQRecord
            BL      Dequeue
            BCS     GetCharLoop         ;C=1: queue empty, keep trying
            POP     {R1, PC}
            ENDP

;==============================================================
;PutChar
;  Enqueues the character in R0 to the transmit queue and
;  ensures TIE is set so the ISR will send it.
;  Blocks (busy-waits) until space is available in TxQRecord.
;  Input:  R0 = character to transmit
;  Output: (none)
;  Preserves all registers except PSR.
;==============================================================
PutChar     PROC  {R0-R14}
            PUSH    {R0, R1, R2, LR}
PutCharLoop
            LDR     R1, =TxQRecord
            BL      Enqueue
            BCS     PutCharLoop         ;C=1: queue full, keep trying

            ;Enable TIE in UART0_C2 so the ISR transmits the byte
            LDR     R0, =UART0_BASE
            LDRB    R1, [R0, #UART0_C2_OFFSET]
            MOVS    R2, #UART0_C2_TIE_MASK
            ORRS    R1, R1, R2
            STRB    R1, [R0, #UART0_C2_OFFSET]

            POP     {R0, R1, R2, PC}
            ENDP

;==============================================================
;InitQueue
;  Initializes a queue record structure for an empty queue.
;  Input:  R0 = address of queue buffer
;          R1 = address of queue record structure
;          R2 = buffer capacity in characters (bytes)
;  Output: (none)
;  Preserves all registers except PSR.
;==============================================================
InitQueue   PROC  {R0-R14}
            PUSH    {R0, R1, R2, R3}
            STR     R0, [R1, #IN_PTR]   ;InPointer  = buffer start
            STR     R0, [R1, #OUT_PTR]  ;OutPointer = buffer start
            STR     R0, [R1, #BUF_STRT] ;BufStart   = buffer start
            ADDS    R3, R0, R2          ;BufPast = start + capacity
            STR     R3, [R1, #BUF_PAST]
            STRB    R2, [R1, #BUF_SIZE] ;BufSize    = capacity
            MOVS    R3, #0
            STRB    R3, [R1, #NUM_ENQD] ;NumEnqueued = 0
            POP     {R0, R1, R2, R3}
            BX      LR
            ENDP

;==============================================================
;Enqueue
;  Enqueues a single character to a queue.
;  Input:  R0 = character to enqueue
;          R1 = address of queue record structure
;  Output: PSR C = 0 (success) or 1 (failure: queue full)
;  Preserves all registers except PSR.
;==============================================================
Enqueue     PROC  {R0-R14}
            PUSH    {R0, R1, R2, R3, R4}

            ;Check if queue is full: NUM_ENQD >= BUF_SIZE
            LDRB    R2, [R1, #NUM_ENQD]
            LDRB    R3, [R1, #BUF_SIZE]
            CMP     R2, R3
            BHS     EnqueueFull         ;unsigned >=: full

            ;Store character at InPointer
            LDR     R4, [R1, #IN_PTR]
            STRB    R0, [R4, #0]

            ;Advance InPointer; wrap if past BufPast
            ADDS    R4, R4, #1
            LDR     R3, [R1, #BUF_PAST]
            CMP     R4, R3
            BNE     EnqueueNoWrap
            LDR     R4, [R1, #BUF_STRT] ;wrap to start
EnqueueNoWrap
            STR     R4, [R1, #IN_PTR]

            ;Increment NumEnqueued
            ADDS    R2, R2, #1
            STRB    R2, [R1, #NUM_ENQD]

            ;Clear carry to report success
            MRS     R2, APSR
            LDR     R3, =0xDFFFFFFF     ;mask to clear C bit (bit 29)
            ANDS    R2, R2, R3
            MSR     APSR_nzcvq, R2

            POP     {R0, R1, R2, R3, R4}
            BX      LR

EnqueueFull
            ;Set carry to report failure
            MRS     R2, APSR
            LDR     R3, =APSR_C_MASK    ;0x20000000
            ORRS    R2, R2, R3
            MSR     APSR_nzcvq, R2

            POP     {R0, R1, R2, R3, R4}
            BX      LR
            ENDP

;==============================================================
;Dequeue
;  Dequeues a single character from a queue.
;  Input:  R1 = address of queue record structure
;  Output: R0 = dequeued character (valid only if C=0)
;          PSR C = 0 (success) or 1 (failure: queue empty)
;  Preserves all registers except R0 and PSR.
;==============================================================
Dequeue     PROC  {R1-R14}
            PUSH    {R1, R2, R3, R4}

            ;Check if queue is empty: NUM_ENQD == 0
            LDRB    R2, [R1, #NUM_ENQD]
            CMP     R2, #0
            BEQ     DequeueEmpty

            ;Load character from OutPointer
            LDR     R3, [R1, #OUT_PTR]
            LDRB    R0, [R3, #0]

            ;Advance OutPointer; wrap if past BufPast
            ADDS    R3, R3, #1
            LDR     R4, [R1, #BUF_PAST]
            CMP     R3, R4
            BNE     DequeueNoWrap
            LDR     R3, [R1, #BUF_STRT] ;wrap to start
DequeueNoWrap
            STR     R3, [R1, #OUT_PTR]

            ;Decrement NumEnqueued
            SUBS    R2, R2, #1
            STRB    R2, [R1, #NUM_ENQD]

            ;Clear carry to report success
            MRS     R2, APSR
            LDR     R3, =0xDFFFFFFF
            ANDS    R2, R2, R3
            MSR     APSR_nzcvq, R2

            POP     {R1, R2, R3, R4}
            BX      LR

DequeueEmpty
            ;Set carry to report failure
            MRS     R2, APSR
            LDR     R3, =APSR_C_MASK
            ORRS    R2, R2, R3
            MSR     APSR_nzcvq, R2

            POP     {R1, R2, R3, R4}
            BX      LR
            ENDP

;==============================================================
;PutStringSB
;  Outputs a null-terminated string to the terminal via PutChar.
;  Input:  R0 = address of null-terminated string
;  Preserves all registers except PSR.
;==============================================================
PutStringSB PROC  {R0-R14}
            PUSH    {R0, R1, LR}
            MOVS    R1, R0              ;R1 = string pointer
PutStringLoop
            LDRB    R0, [R1, #0]
            CMP     R0, #NULL
            BEQ     PutStringDone
            BL      PutChar
            ADDS    R1, R1, #1
            B       PutStringLoop
PutStringDone
            POP     {R0, R1, PC}
            ENDP

;==============================================================
;PutNumHex
;  Prints the 32-bit value in R0 as exactly 8 uppercase hex
;  digits (e.g. 0x000012FF prints as 000012FF).
;  Uses bit masks and shifts only (no division).
;  Input:  R0 = unsigned 32-bit value
;  Preserves all registers except PSR.
;==============================================================
PutNumHex   PROC  {R0-R14}
            PUSH    {R0, R1, R2, R3, LR}
            MOVS    R1, R0              ;R1 = value to print
            MOVS    R2, #28             ;R2 = current shift (start at bits 31:28)
PutHexLoop
            MOVS    R0, R1
            LSRS    R0, R0, R2          ;shift nibble to bits 3:0
            MOVS    R3, #0x0F
            ANDS    R0, R0, R3          ;mask to lower nibble
            CMP     R0, #10
            BLO     PutHexIsDigit
            ADDS    R0, R0, #('A'-10)   ;A-F
            B       PutHexOut
PutHexIsDigit
            ADDS    R0, R0, #'0'        ;0-9
PutHexOut
            BL      PutChar
            CMP     R2, #0
            BEQ     PutHexDone
            SUBS    R2, R2, #4
            B       PutHexLoop
PutHexDone
            POP     {R0, R1, R2, R3, PC}
            ENDP

;==============================================================
;PutNumUB
;  Prints the unsigned byte value in R0 as decimal text.
;  Only the low byte of R0 is used.
;  Input:  R0 = unsigned byte value (low byte used)
;  Preserves all registers except PSR.
;==============================================================
PutNumUB    PROC  {R0-R14}
            PUSH    {R0, LR}
            MOVS    R1, #0xFF
            ANDS    R0, R0, R1          ;mask to byte
            BL      PutNumU
            POP     {R0, PC}
            ENDP

;==============================================================
;PutNumU
;  Prints an unsigned 32-bit word in R0 as decimal text.
;  Suppresses leading zeros (always prints at least one digit).
;  Input:  R0 = unsigned value
;  Preserves all registers except PSR.
;  Uses repeated subtraction by powers of 10 (no division).
;==============================================================
PutNumU     PROC  {R0-R14}
            PUSH    {R0, R1, R2, R3, R4, R5, LR}
            MOVS    R5, R0              ;R5 = value to print
            LDR     R1, =Divisors       ;R1 -> power-of-10 table
            MOVS    R4, #0              ;R4 = leading-zero suppress flag
            MOVS    R3, #10             ;R3 = remaining divisors

PutNumULoop
            LDR     R2, [R1]            ;R2 = current divisor
            MOVS    R0, #0              ;R0 = digit count
PutNumUDiv
            CMP     R5, R2
            BLO     PutNumUEmit
            SUBS    R5, R5, R2
            ADDS    R0, R0, #1
            B       PutNumUDiv
PutNumUEmit
            ;Print digit if non-zero, OR if we have seen a non-zero
            ;digit already, OR if this is the last (ones) digit
            CMP     R0, #0
            BNE     PutNumUPrint
            CMP     R4, #1
            BEQ     PutNumUPrint        ;already saw non-zero: print zero
            CMP     R3, #1
            BEQ     PutNumUPrint        ;last digit: always print
            B       PutNumUNext         ;suppress leading zero
PutNumUPrint
            MOVS    R4, #1              ;mark: non-zero digit seen
            ADDS    R0, R0, #'0'
            BL      PutChar
PutNumUNext
            ADDS    R1, R1, #4          ;advance to next divisor
            SUBS    R3, R3, #1
            CMP     R3, #0
            BNE     PutNumULoop

            POP     {R0, R1, R2, R3, R4, R5, PC}
            ENDP

;>>>>>   end subroutine code <<<<<
            ALIGN

;****************************************************************
;Vector Table Mapped to Address 0 at Reset
            AREA    RESET, DATA, READONLY
            EXPORT  __Vectors
            EXPORT  __Vectors_End
            EXPORT  __Vectors_Size
            IMPORT  __initial_sp
            IMPORT  Dummy_Handler
            IMPORT  HardFault_Handler

__Vectors
                                        ;ARM core vectors
            DCD    __initial_sp         ;00: end of stack
            DCD    Reset_Handler        ;01: reset vector
            DCD    Dummy_Handler        ;02: NMI
            DCD    HardFault_Handler    ;03: hard fault
            DCD    Dummy_Handler        ;04: (reserved)
            DCD    Dummy_Handler        ;05: (reserved)
            DCD    Dummy_Handler        ;06: (reserved)
            DCD    Dummy_Handler        ;07: (reserved)
            DCD    Dummy_Handler        ;08: (reserved)
            DCD    Dummy_Handler        ;09: (reserved)
            DCD    Dummy_Handler        ;10: (reserved)
            DCD    Dummy_Handler        ;11: SVCall
            DCD    Dummy_Handler        ;12: (reserved)
            DCD    Dummy_Handler        ;13: (reserved)
            DCD    Dummy_Handler        ;14: PendSV
            DCD    Dummy_Handler        ;15: SysTick
            DCD    Dummy_Handler        ;16: IRQ0  DMA ch 0
            DCD    Dummy_Handler        ;17: IRQ1  DMA ch 1
            DCD    Dummy_Handler        ;18: IRQ2  DMA ch 2
            DCD    Dummy_Handler        ;19: IRQ3  DMA ch 3
            DCD    Dummy_Handler        ;20: IRQ4  (reserved)
            DCD    Dummy_Handler        ;21: IRQ5  FTFA
            DCD    Dummy_Handler        ;22: IRQ6  LVD/LVW
            DCD    Dummy_Handler        ;23: IRQ7  LLW
            DCD    Dummy_Handler        ;24: IRQ8  I2C0
            DCD    Dummy_Handler        ;25: IRQ9  (reserved)
            DCD    Dummy_Handler        ;26: IRQ10 SPI0
            DCD    Dummy_Handler        ;27: IRQ11 (reserved)
            DCD    UART0_ISR            ;28: IRQ12 UART0 <-- installed
            DCD    Dummy_Handler        ;29: IRQ13 (reserved)
            DCD    Dummy_Handler        ;30: IRQ14 (reserved)
            DCD    Dummy_Handler        ;31: IRQ15 ADC0
            DCD    Dummy_Handler        ;32: IRQ16 CMP0
            DCD    Dummy_Handler        ;33: IRQ17 TPM0
            DCD    Dummy_Handler        ;34: IRQ18 TPM1
            DCD    Dummy_Handler        ;35: IRQ19 (reserved)
            DCD    Dummy_Handler        ;36: IRQ20 RTC alarm
            DCD    Dummy_Handler        ;37: IRQ21 RTC seconds
            DCD    Dummy_Handler        ;38: IRQ22 PIT
            DCD    Dummy_Handler        ;39: IRQ23 (reserved)
            DCD    Dummy_Handler        ;40: IRQ24 (reserved)
            DCD    Dummy_Handler        ;41: IRQ25 DAC0
            DCD    Dummy_Handler        ;42: IRQ26 TSI0
            DCD    Dummy_Handler        ;43: IRQ27 MCG
            DCD    Dummy_Handler        ;44: IRQ28 LPTMR0
            DCD    Dummy_Handler        ;45: IRQ29 (reserved)
            DCD    Dummy_Handler        ;46: IRQ30 PORTA
            DCD    Dummy_Handler        ;47: IRQ31 PORTB
__Vectors_End
__Vectors_Size  EQU  __Vectors_End - __Vectors
            ALIGN

;****************************************************************
;Constants
            AREA    MyConst,DATA,READONLY
;>>>>> begin constants here <<<<<

;Powers of 10 table for PutNumU (largest to smallest)
Divisors
            DCD    1000000000
            DCD    100000000
            DCD    10000000
            DCD    1000000
            DCD    100000
            DCD    10000
            DCD    1000
            DCD    100
            DCD    10
            DCD    1

;Strings
PromptStr
            DCB    CR, LF
            DCB    "Type a queue command (D,E,H,P,S): ", NULL
            ALIGN

DequeuedStr
            DCB    "Dequeued: ", NULL
            ALIGN

EnqueuePromptStr
            DCB    "Enter a character to enqueue: ", NULL
            ALIGN

EnqueuedStr
            DCB    "Character enqueued.", CR, LF, NULL
            ALIGN

QueueEmptyStr
            DCB    "Queue is empty.", CR, LF, NULL
            ALIGN

QueueFullStr
            DCB    "Queue is full.", CR, LF, NULL
            ALIGN

HelpStr
            DCB    CR, LF
            DCB    "Commands:", CR, LF
            DCB    "  D - Dequeue a character", CR, LF
            DCB    "  E - Enqueue a character", CR, LF
            DCB    "  H - Help (this list)", CR, LF
            DCB    "  P - Print all queued characters", CR, LF
            DCB    "  S - Status (InPtr, OutPtr, NumEnqueued)", CR, LF
            DCB    NULL
            ALIGN

PrintHeaderStr
            DCB    "Queued characters: ", NULL
            ALIGN

InPtrStr
            DCB    "InPointer:      ", NULL
            ALIGN

OutPtrStr
            DCB    "OutPointer:     ", NULL
            ALIGN

NumEnqdStr
            DCB    "NumberEnqueued: ", NULL
            ALIGN

;>>>>>   end constants here <<<<<
            ALIGN

;****************************************************************
;Variables
            AREA    MyData,DATA,READWRITE
;>>>>> begin variables here <<<<<

;Receive queue management record and buffer
            ALIGN
RxQRecord   SPACE  Q_REC_SIZE
RxQBuffer   SPACE  RX_BUF_SIZE

;Transmit queue management record and buffer
            ALIGN
TxQRecord   SPACE  Q_REC_SIZE
TxQBuffer   SPACE  TX_BUF_SIZE

;Application queue management record and buffer (4 chars)
            ALIGN
QRecord     SPACE  Q_REC_SIZE
QBuffer     SPACE  Q_BUF_SIZE

;>>>>>   end variables here <<<<<
            ALIGN
            END
