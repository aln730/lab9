            TTL Program Title for Listing Header Goes Here
;****************************************************************
;Descriptive comment header goes here.
;(What does the program do?)
;Name:  <Your name here>
;Date:  <Date completed here>
;Class:  CMPE-250
;Section:  <Your lab section, day, and time here>
;---------------------------------------------------------------
;Keil Template for KL05
;R. W. Melton
;September 13, 2020
;****************************************************************
;Assembler directives
            THUMB
            OPT    64  ;Turn on listing macro expansions
;****************************************************************
;Include files
            GET  MKL05Z4.s     ;Included by start.s
            OPT  1   ;Turn on listing
;****************************************************************
;EQUates
;****************************************************************
;Program
;Linker requires Reset_Handler
            AREA    MyCode,CODE,READONLY
            ENTRY
            EXPORT  Reset_Handler
            IMPORT  Startup
Reset_Handler  PROC  {}
main
;---------------------------------------------------------------
;Mask interrupts
            CPSID   I
;KL05 system startup with 48-MHz system clock
            BL      Startup
;---------------------------------------------------------------
;>>>>> begin main program code <<<<<
            BL      UART0_Init

            LDR     R0, =Msg
            BL      PrintString
;>>>>>   end main program code <<<<<
;Stay here
            B       .
            ENDP    ;main
;>>>>> begin subroutine code <<<<<
;---------------------------------------------------------------
; UART0_Init
;---------------------------------------------------------------
UART0_Init
            PUSH    {R0-R2, LR}

; Enable clocks
            LDR     R0, =SIM_SCGC4
            LDR     R1, [R0]
            LDR     R2, =SIM_SCGC4_UART0_MASK
            ORRS    R1, R1, R2
            STR     R1, [R0]

            LDR     R0, =SIM_SCGC5
            LDR     R1, [R0]
            LDR     R2, =SIM_SCGC5_PORTB_MASK
            ORRS    R1, R1, R2
            STR     R1, [R0]

; Configure pins
            LDR     R0, =PORTB_PCR1
            LDR     R1, =PORT_PCR_SET_PTB1_UART0_TX
            STR     R1, [R0]

            LDR     R0, =PORTB_PCR2
            LDR     R1, =PORT_PCR_SET_PTB2_UART0_RX
            STR     R1, [R0]

; Disable UART
            LDR     R0, =UART0_BASE
            MOVS    R1, #0
            STRB    R1, [R0, #UART0_C2_OFFSET]

; Baud rate 9600
            MOVS    R1, #UART0_BDH_9600
            STRB    R1, [R0, #UART0_BDH_OFFSET]

            MOVS    R1, #UART0_BDL_9600
            STRB    R1, [R0, #UART0_BDL_OFFSET]

; 8N1
            MOVS    R1, #UART0_C1_8N1
            STRB    R1, [R0, #UART0_C1_OFFSET]

; Enable TX and RX
            LDR     R1, =UART0_C2_T_R
            STRB    R1, [R0, #UART0_C2_OFFSET]

            POP     {R0-R2, LR}
            BX      LR

;---------------------------------------------------------------
; PrintString
; R0 = address of null-terminated string
;---------------------------------------------------------------
PrintString
            PUSH    {R1, LR}

NextChar
            LDRB    R1, [R0]
            CMP     R1, #0
            BEQ     Done

            MOV     R0, R1
            BL      PutChar

            ADDS    R0, R0, #1
            B       NextChar

Done
            POP     {R1, LR}
            BX      LR

;---------------------------------------------------------------
; PutChar
; R0 = character
;---------------------------------------------------------------
PutChar
WaitTX
            LDR     R1, =UART0_BASE
            LDRB    R2, [R1, #UART0_S1_OFFSET]

            MOVS    R3, #UART0_S1_TDRE_MASK
            ANDS    R2, R2, R3
            CMP     R2, #0
            BEQ     WaitTX

            STRB    R0, [R1, #UART0_D_OFFSET]
            BX      LRs
;>>>>>   end subroutine code <<<<<
            ALIGN
;****************************************************************
;Vector Table Mapped to Address 0 at Reset
;Linker requires __Vectors to be exported
            AREA    RESET, DATA, READONLY
            EXPORT  __Vectors
            EXPORT  __Vectors_End
            EXPORT  __Vectors_Size
            IMPORT  __initial_sp
            IMPORT  Dummy_Handler
            IMPORT  HardFault_Handler
__Vectors 
                                      ;ARM core vectors
            DCD    __initial_sp       ;00:end of stack
            DCD    Reset_Handler      ;01:reset vector
            DCD    Dummy_Handler      ;02:NMI
            DCD    HardFault_Handler  ;03:hard fault
            DCD    Dummy_Handler      ;04:(reserved)
            DCD    Dummy_Handler      ;05:(reserved)
            DCD    Dummy_Handler      ;06:(reserved)
            DCD    Dummy_Handler      ;07:(reserved)
            DCD    Dummy_Handler      ;08:(reserved)
            DCD    Dummy_Handler      ;09:(reserved)
            DCD    Dummy_Handler      ;10:(reserved)
            DCD    Dummy_Handler      ;11:SVCall (supervisor call)
            DCD    Dummy_Handler      ;12:(reserved)
            DCD    Dummy_Handler      ;13:(reserved)
            DCD    Dummy_Handler      ;14:PendSV (PendableSrvReq)
                                      ;   pendable request 
                                      ;   for system service)
            DCD    Dummy_Handler      ;15:SysTick (system tick timer)
            DCD    Dummy_Handler      ;16:DMA channel 0 transfer 
                                      ;   complete/error
            DCD    Dummy_Handler      ;17:DMA channel 1 transfer
                                      ;   complete/error
            DCD    Dummy_Handler      ;18:DMA channel 2 transfer
                                      ;   complete/error
            DCD    Dummy_Handler      ;19:DMA channel 3 transfer
                                      ;   complete/error
            DCD    Dummy_Handler      ;20:(reserved)
            DCD    Dummy_Handler      ;21:FTFA command complete/
                                      ;   read collision
            DCD    Dummy_Handler      ;22:low-voltage detect;
                                      ;   low-voltage warning
            DCD    Dummy_Handler      ;23:low leakage wakeup
            DCD    Dummy_Handler      ;24:I2C0
            DCD    Dummy_Handler      ;25:(reserved)
            DCD    Dummy_Handler      ;26:SPI0
            DCD    Dummy_Handler      ;27:(reserved)
            DCD    Dummy_Handler      ;28:UART0 (status; error)
            DCD    Dummy_Handler      ;29:(reserved)
            DCD    Dummy_Handler      ;30:(reserved)
            DCD    Dummy_Handler      ;31:ADC0
            DCD    Dummy_Handler      ;32:CMP0
            DCD    Dummy_Handler      ;33:TPM0
            DCD    Dummy_Handler      ;34:TPM1
            DCD    Dummy_Handler      ;35:(reserved)
            DCD    Dummy_Handler      ;36:RTC (alarm)
            DCD    Dummy_Handler      ;37:RTC (seconds)
            DCD    Dummy_Handler      ;38:PIT
            DCD    Dummy_Handler      ;39:(reserved)
            DCD    Dummy_Handler      ;40:(reserved)
            DCD    Dummy_Handler      ;41:DAC0
            DCD    Dummy_Handler      ;42:TSI0
            DCD    Dummy_Handler      ;43:MCG
            DCD    Dummy_Handler      ;44:LPTMR0
            DCD    Dummy_Handler      ;45:(reserved)
            DCD    Dummy_Handler      ;46:PORTA
            DCD    Dummy_Handler      ;47:PORTB
__Vectors_End
__Vectors_Size  EQU     __Vectors_End - __Vectors
            ALIGN
;****************************************************************
;Constants
            AREA    MyConst,DATA,READONLY
;>>>>> begin constants here <<<<<
Msg     DCB "Hello UART",13,10,0
;>>>>>   end constants here <<<<<
            ALIGN
;****************************************************************
;Variables
            AREA    MyData,DATA,READWRITE
;>>>>> begin variables here <<<<<
;>>>>>   end variables here <<<<<
            ALIGN
            END
