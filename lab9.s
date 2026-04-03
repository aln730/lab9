            TTL Lab 9 UART Queue
;****************************************************************
; This program implements a UART interrupt-driven command system
; with a circular queue.
;
; Name: <Your Name>
; Date: <Date>
; Class: CMPE-250
; Section: <Section>
;****************************************************************

            THUMB
            OPT 64
            GET MKL05Z4.s
            OPT 1

;****************************************************************
; EQUATES
;****************************************************************
QUEUE_SIZE EQU 16

;****************************************************************
; CODE
;****************************************************************
            AREA MyCode,CODE,READONLY
            ENTRY
            EXPORT Reset_Handler
            IMPORT Startup

Reset_Handler PROC {}

main
            CPSID I
            BL Startup

;---------------------------------------------------------------
; Enable PORTB + UART0 clocks
;---------------------------------------------------------------
            LDR R0, =SIM_BASE

            ; PORTB clock
            LDR R1, [R0, #SIM_SCGC5_OFFSET]
            LDR R2, =SIM_SCGC5_PORTB_MASK
            ORRS R1, R1, R2
            STR R1, [R0, #SIM_SCGC5_OFFSET]

            ; UART0 clock
            LDR R1, [R0, #SIM_SCGC4_OFFSET]
            LDR R2, =SIM_SCGC4_UART0_MASK
            ORRS R1, R1, R2
            STR R1, [R0, #SIM_SCGC4_OFFSET]

;---------------------------------------------------------------
; UART clock source
;---------------------------------------------------------------
            LDR R1, [R0, #SIM_SOPT2_OFFSET]
            LDR R2, =SIM_SOPT2_UART0SRC_MCGFLLCLK
            ORRS R1, R1, R2
            STR R1, [R0, #SIM_SOPT2_OFFSET]

;---------------------------------------------------------------
; UART pins (PTB1 TX, PTB2 RX)
;---------------------------------------------------------------
            LDR R0, =PORTB_BASE

            LDR R1, =PORT_PCR_SET_PTB1_UART0_TX
            STR R1, [R0, #PORT_PCR1_OFFSET]

            LDR R1, =PORT_PCR_SET_PTB2_UART0_RX
            STR R1, [R0, #PORT_PCR2_OFFSET]

;---------------------------------------------------------------
; UART init
;---------------------------------------------------------------
            LDR R0, =UART0_BASE

            MOVS R1, #0
            STRB R1, [R0, #UART0_C2_OFFSET]

            MOVS R1, #UART0_BDH_9600
            STRB R1, [R0, #UART0_BDH_OFFSET]

            MOVS R1, #UART0_BDL_9600
            STRB R1, [R0, #UART0_BDL_OFFSET]

            MOVS R1, #UART0_C1_8N1
            STRB R1, [R0, #UART0_C1_OFFSET]

; Enable RX interrupt
            MOVS R1, #(UART0_C2_RIE_MASK :OR: UART0_C2_T_R)
            STRB R1, [R0, #UART0_C2_OFFSET]

; Enable NVIC
            LDR R0, =NVIC_ISER
            LDR R1, =UART0_IRQ_MASK
            STR R1, [R0]

            CPSIE I

;---------------------------------------------------------------
; Initialize queue indices
;---------------------------------------------------------------
            LDR R0, =QHead
            MOVS R1, #0
            STR R1, [R0]

            LDR R0, =QTail
            STR R1, [R0]

            LDR R0, =QCount
            STR R1, [R0]

;---------------------------------------------------------------
; Print prompt once
;---------------------------------------------------------------
            BL PrintPrompt

Loop
            B Loop

            ENDP

;****************************************************************
; DATA
;****************************************************************
            AREA MyData,DATA,READWRITE

Queue       SPACE QUEUE_SIZE
QHead       DCD 0
QTail       DCD 0
QCount      DCD 0

CmdBuffer   SPACE 8
CmdIndex    DCD 0

;****************************************************************
; UART Interrupt Handler
;****************************************************************
            AREA MyCode,CODE,READONLY
            EXPORT UART0_IRQHandler

UART0_IRQHandler PROC
            PUSH {R0-R3, LR}

            LDR R0, =UART0_BASE

; Check RX flag
            LDRB R1, [R0, #UART0_S1_OFFSET]
            TST R1, #UART0_S1_RDRF_MASK
            BEQ DoneISR

; Read char
            LDRB R2, [R0, #UART0_D_OFFSET]

; Echo
WaitTX
            LDRB R1, [R0, #UART0_S1_OFFSET]
            TST R1, #UART0_S1_TDRE_MASK
            BEQ WaitTX
            STRB R2, [R0, #UART0_D_OFFSET]

; Store command
            CMP R2, #10
            BEQ HandleCommand

            LDR R3, =CmdBuffer
            LDR R1, =CmdIndex
            LDR R0, [R1]

            STRB R2, [R3, R0]
            ADDS R0, R0, #1
            STR R0, [R1]
            B DoneISR

HandleCommand
            BL ProcessCommand

DoneISR
            POP {R0-R3, LR}
            BX LR
            ENDP

;****************************************************************
; Print Prompt
;****************************************************************
PrintPrompt PROC
            PUSH {R0-R2, LR}

            LDR R0, =UART0_BASE
            LDR R1, =Prompt

PrintLoop
            LDRB R2, [R1], #1
            CMP R2, #0
            BEQ DonePrint

WaitTX2
            LDRB R3, [R0, #UART0_S1_OFFSET]
            TST R3, #UART0_S1_TDRE_MASK
            BEQ WaitTX2

            STRB R2, [R0, #UART0_D_OFFSET]
            B PrintLoop

DonePrint
            POP {R0-R2, LR}
            BX LR
            ENDP

Prompt DCB "Type a queue command (D,E,H,P,S): ",0

;****************************************************************
; Process Command
;****************************************************************
ProcessCommand PROC
            PUSH {R0-R3, LR}

            LDR R0, =CmdBuffer
            LDRB R1, [R0]

            CMP R1, #'E'
            BEQ EnqCmd
            CMP R1, #'D'
            BEQ DeqCmd
            CMP R1, #'P'
            BEQ PrintCmd
            CMP R1, #'H'
            BEQ HelpCmd
            CMP R1, #'S'
            BEQ StatusCmd

            B DoneCmd

EnqCmd
            BL Enqueue
            B DoneCmd

DeqCmd
            BL Dequeue
            B DoneCmd

PrintCmd
            B DoneCmd

HelpCmd
            B DoneCmd

StatusCmd
            B DoneCmd

DoneCmd
            LDR R0, =CmdIndex
            MOVS R1, #0
            STR R1, [R0]

            POP {R0-R3, LR}
            BX LR
            ENDP

;****************************************************************
; Enqueue
;****************************************************************
Enqueue PROC
            PUSH {R0-R3, LR}

            LDR R0, =QCount
            LDR R1, [R0]
            CMP R1, #QUEUE_SIZE
            BGE DoneEnq

            LDR R0, =Queue
            LDR R2, =QTail
            LDR R3, [R2]

            MOVS R4, #'A'
            STRB R4, [R0, R3]

            ADDS R3, R3, #1
            CMP R3, #QUEUE_SIZE
            BLT SkipWrap
            MOVS R3, #0
SkipWrap
            STR R3, [R2]

            ADDS R1, R1, #1
            LDR R0, =QCount
            STR R1, [R0]

DoneEnq
            POP {R0-R3, LR}
            BX LR
            ENDP

;****************************************************************
; Dequeue
;****************************************************************
Dequeue PROC
            PUSH {R0-R3, LR}

            LDR R0, =QCount
            LDR R1, [R0]
            CMP R1, #0
            BEQ DoneDeq

            LDR R0, =Queue
            LDR R2, =QHead
            LDR R3, [R2]

            LDRB R4, [R0, R3]

; transmit char
WaitTX3
            LDR R0, =UART0_BASE
            LDRB R1, [R0, #UART0_S1_OFFSET]
            TST R1, #UART0_S1_TDRE_MASK
            BEQ WaitTX3

            STRB R4, [R0, #UART0_D_OFFSET]

            ADDS R3, R3, #1
            CMP R3, #QUEUE_SIZE
            BLT SkipWrap2
            MOVS R3, #0
SkipWrap2
            STR R3, [R2]

            SUBS R1, R1, #1
            LDR R0, =QCount
            STR R1, [R0]

DoneDeq
            POP {R0-R3, LR}
            BX LR
            ENDP

;****************************************************************
; VECTOR TABLE (UNCHANGED)
;****************************************************************
            AREA RESET, DATA, READONLY
            EXPORT __Vectors

__Vectors
            DCD __initial_sp
            DCD Reset_Handler
            DCD Dummy_Handler
            DCD HardFault_Handler
            ; rest unchanged...
            DCD Dummy_Handler
            DCD UART0_IRQHandler

            ALIGN
            END
