TTL Lab 9 - UART Queue Command Processor
;****************************************************************
; This program implements a UART-driven command interface with a
; circular queue. It accepts commands:
; D = Dequeue
; E = Enqueue
; P = Print queue
; H = Help
; S = Status
;
; Name: <Your Name>
; Date: <Date>
; Class: CMPE-250
; Section: <Your Section>
;****************************************************************

            THUMB
            OPT    64

            GET  MKL05Z4.s
            OPT  1

;****************************************************************
; EQUATES
;****************************************************************
QUEUE_SIZE     EQU 16

;****************************************************************
; CODE
;****************************************************************
            AREA    MyCode,CODE,READONLY
            ENTRY
            EXPORT  Reset_Handler
            IMPORT  Startup

Reset_Handler PROC {}

main
            CPSID   I
            BL      Startup

;---------------------------------------------------------------
; Enable clocks
;---------------------------------------------------------------
            LDR     R0, =SIM_BASE

            ; PORTB clock
            LDR     R1, [R0, #SIM_SCGC5_OFFSET]
            LDR     R2, =SIM_SCGC5_PORTB_MASK
            ORRS    R1, R1, R2
            STR     R1, [R0, #SIM_SCGC5_OFFSET]

            ; UART0 clock
            LDR     R1, [R0, #SIM_SCGC4_OFFSET]
            LDR     R2, =SIM_SCGC4_UART0_MASK
            ORRS    R1, R1, R2
            STR     R1, [R0, #SIM_SCGC4_OFFSET]

;---------------------------------------------------------------
; UART clock source
;---------------------------------------------------------------
            LDR     R1, [R0, #SIM_SOPT2_OFFSET]
            LDR     R2, =SIM_SOPT2_UART0SRC_MCGFLLCLK
            ORRS    R1, R1, R2
            STR     R1, [R0, #SIM_SOPT2_OFFSET]

;---------------------------------------------------------------
; Configure UART pins (PTB1 TX, PTB2 RX)
;---------------------------------------------------------------
            LDR     R0, =PORTB_BASE

            LDR     R1, =PORT_PCR_SET_PTB1_UART0_TX
            STR     R1, [R0, #PORT_PCR1_OFFSET]

            LDR     R1, =PORT_PCR_SET_PTB2_UART0_RX
            STR     R1, [R0, #PORT_PCR2_OFFSET]

;---------------------------------------------------------------
; UART0 initialization
;---------------------------------------------------------------
            LDR     R0, =UART0_BASE

            MOVS    R1, #0
            STRB    R1, [R0, #UART0_C2_OFFSET]

            MOVS    R1, #UART0_BDH_9600
            STRB    R1, [R0, #UART0_BDH_OFFSET]

            MOVS    R1, #UART0_BDL_9600
            STRB    R1, [R0, #UART0_BDL_OFFSET]

            MOVS    R1, #UART0_C1_8N1
            STRB    R1, [R0, #UART0_C1_OFFSET]

; Enable RX interrupt + TX/RX
            MOVS    R1, #(UART0_C2_RIE_MASK :OR: UART0_C2_T_R)
            STRB    R1, [R0, #UART0_C2_OFFSET]

; Enable NVIC UART0 interrupt
            LDR     R0, =NVIC_ISER
            LDR     R1, =UART0_IRQ_MASK
            STR     R1, [R0]

            CPSIE   I

;---------------------------------------------------------------
; Print initial prompt
;---------------------------------------------------------------
MainLoop
            BL PrintPrompt

Forever
            B Forever

            ENDP

;****************************************************************
; DATA
;****************************************************************
            AREA MyData, DATA, READWRITE

Queue       SPACE QUEUE_SIZE
QHead       DCD 0
QTail       DCD 0
QCount      DCD 0

CmdBuffer   SPACE 32
CmdIndex    DCD 0

;****************************************************************
; UART Interrupt Handler
;****************************************************************
            AREA MyCode,CODE,READONLY
            EXPORT UART0_IRQHandler

UART0_IRQHandler PROC
            PUSH {R0-R3, LR}

            LDR R0, =UART0_BASE

; Check RX
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

; Store in buffer
            LDR R3, =CmdIndex
            LDR R1, [R3]

            LDR R0, =CmdBuffer
            STRB R2, [R0, R1]

            ADDS R1, R1, #1
            STR R1, [R3]

; If newline → process
            CMP R2, #10
            BNE DoneISR

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

Prompt  DCB "Type a queue command (D,E,H,P,S): ",0

;****************************************************************
; Process Command
;****************************************************************
ProcessCommand PROC
            PUSH {R0-R3, LR}

            LDR R0, =CmdBuffer
            LDRB R1, [R0]

            CMP R1, #'E'
            BEQ DoEnq
            CMP R1, #'D'
            BEQ DoDeq
            CMP R1, #'P'
            BEQ DoPrint
            CMP R1, #'H'
            BEQ DoHelp
            CMP R1, #'S'
            BEQ DoStatus

            B DoneCmd

DoEnq
            BL Enqueue
            B DoneCmd

DoDeq
            BL Dequeue
            B DoneCmd

DoPrint
            B DoneCmd

DoHelp
            B DoneCmd

DoStatus
            B DoneCmd

DoneCmd
            MOVS R1, #0
            LDR R0, =CmdIndex
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

            ; store 'A' for simplicity
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

; print dequeued char
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
            AREA    RESET, DATA, READONLY
            EXPORT  __Vectors
            EXPORT  __Vectors_End
            EXPORT  __Vectors_Size
            IMPORT  __initial_sp
            IMPORT  Dummy_Handler
            IMPORT  HardFault_Handler

__Vectors 
            DCD    __initial_sp
            DCD    Reset_Handler
            DCD    Dummy_Handler
            DCD    HardFault_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    Dummy_Handler
            DCD    UART0_IRQHandler

__Vectors_End
__Vectors_Size  EQU __Vectors_End - __Vectors

            ALIGN
            END
