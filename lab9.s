TTL Program Title for Listing Header Goes Here
;****************************************************************
; CMPE-250 Lab 9 - Serial I/O Driver
; Name:  <Your name here>
; Date:  <Date completed here>
; Class: CMPE-250
; Section: <Your section>
;****************************************************************

            THUMB
            OPT    64

            GET  MKL05Z4.s
            OPT  1

;****************************************************************
;EQUates
;****************************************************************

; UART status masks
UART0_RDRF_MASK EQU 0x20
UART0_TDRE_MASK EQU 0x80

;****************************************************************
;Program
;****************************************************************

            AREA    MyCode,CODE,READONLY
            ENTRY
            EXPORT  Reset_Handler
            IMPORT  Startup

Reset_Handler  PROC  {}
main
;---------------------------------------------------------------
            CPSID   I
            BL      Startup
;---------------------------------------------------------------

            BL      UART_Init

MainLoop
            BL      PrintMenu
            BL      GetChar

            CMP     R0, #'D'
            BEQ     HandleD

            CMP     R0, #'E'
            BEQ     HandleE

            CMP     R0, #'H'
            BEQ     HandleH

            CMP     R0, #'P'
            BEQ     HandleP

            CMP     R0, #'S'
            BEQ     HandleS

            B       MainLoop

;---------------- UART INIT ----------------

UART_Init
            PUSH    {R0-R2, LR}

            ; Enable UART0 clock (SIM_SCGC4)
            LDR     R0, =SIM_SCGC4
            LDR     R1, [R0]
            LDR     R2, =SIM_SCGC4_UART0_MASK
            ORRS    R1, R1, R2
            STR     R1, [R0]

            ; Select clock source
            LDR     R0, =SIM_SOPT2
            LDR     R1, [R0]
            LDR     R2, =SIM_SOPT2_UART0SRC_MASK
            BICS    R1, R1, R2
            LDR     R2, =SIM_SOPT2_UART0SRC(1)
            ORRS    R1, R1, R2
            STR     R1, [R0]

            POP     {R0-R2, LR}
            BX      LR

;---------------- GET CHAR ----------------

GetChar
WaitRx
            LDR     R1, =UART0_BASE
            LDR     R2, [R1, #UART0_S1_OFFSET]
            ANDS    R2, R2, #UART0_RDRF_MASK
            CMP     R2, #0
            BEQ     WaitRx

            LDRB    R0, [R1, #UART0_D_OFFSET]
            BX      LR

;---------------- PUT CHAR ----------------

PutChar
WaitTx
            LDR     R1, =UART0_BASE
            LDR     R2, [R1, #UART0_S1_OFFSET]
            ANDS    R2, R2, #UART0_TDRE_MASK
            CMP     R2, #0
            BEQ     WaitTx

            STRB    R0, [R1, #UART0_D_OFFSET]
            BX      LR

;---------------- PRINT STRING ----------------

PrintString
            PUSH    {R1-R2, LR}

NextChar
            LDRB    R1, [R0]
            CMP     R1, #0
            BEQ     Done

            MOV     R0, R1
            BL      PutChar

            ADDS    R0, R0, #1
            B       NextChar

Done
            POP     {R1-R2, LR}
            BX      LR

;---------------- MENU ----------------

PrintMenu
            PUSH    {LR}
            LDR     R0, =MenuText
            BL      PrintString
            POP     {LR}
            BX      LR

MenuText DCB "Type a queue command (D,E,H,P,S): ",0

;---------------- HANDLERS ----------------

HandleD
            LDR     R0, =MsgD
            BL      PrintString
            B       MainLoop

HandleE
            LDR     R0, =MsgE
            BL      PrintString
            B       MainLoop

HandleH
            LDR     R0, =MsgH
            BL      PrintString
            B       MainLoop

HandleP
            LDR     R0, =MsgP
            BL      PrintString
            B       MainLoop

HandleS
            LDR     R0, =MsgS
            BL      PrintString
            B       MainLoop

;---------------- MESSAGES ----------------

MsgD DCB "D selected",13,10,0
MsgE DCB "E selected",13,10,0
MsgH DCB "H selected",13,10,0
MsgP DCB "P selected",13,10,0
MsgS DCB "S selected",13,10,0

            ENDP

;****************************************************************
; Vector Table
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

__Vectors_End
__Vectors_Size  EQU     __Vectors_End - __Vectors

            ALIGN
            END
