            TTL KL05 Bare Metal Assembly Startup
;****************************************************************
;* Flash configuration image for area at 0x400-0x40F(+)
;* SystemInit subroutine (++)
;* SetClock48MHz subroutine (+, +++)
;+:Following [3]
;++:Following [1].1.1.4.2 Startup routines and [2]
;+++:Following [1].4.1 Clocking
;[1] Freescale Semiconductor, <B>Kinetis L Peripheral Module Quick
;    Reference</B>, KLQRUG, Rev. 0, 9/2012.
;[2] Freescale Semiconductor, <B>KL05 Sub-Family Reference Manual</B>,
;    KL05P48M48SF1RM, Rev. 3.1, 11/2012.
;[3] Freescale startup_MKL05Z4.s and system_MKL05Z4.c
;    Device specific configuration file for MKL05Z4
;    rev. 2.2, 4/12/2013
;[4] RIT CMPE-250 KL46 Bare Metal Assembly Startup, 2/5/2018
;Name:  R. W. Melton
;Date:  January 13, 2025
;Class:  CMPE 250
;Section:  All sections
;****************************************************************
;Assembler directives
            THUMB
            OPT    64  ;Turn on listing macro expansions
;****************************************************************
;Include files
;  MKL05Z4.s
            GET  MKL05Z4.s
            OPT  1   ;Turn on listing
;****************************************************************
;EQUates
;---------------------------------------------------------------
;Clock source values
;External crystal frequency (Hz)
CPU_XTAL_CLK_HZ       EQU  32768
;Slow internal oscillator frequency (Hz)
CPU_INT_SLOW_CLK_HZ   EQU  32768
;Fast internal oscillator frequency (Hz)
CPU_INT_FAST_CLK_HZ   EQU  4000000
;Default system clock frequency (Hz)
DEFAULT_SYSTEM_CLOCK  EQU  47972352
;---------------------------------------------------------------
;MCG_C1 MCG Control 1 Register
; 00-->7-6:CLKS=clock source select (FLL)
;000-->5-3:FRDIV=FLL external reference divider (1 for LF range)
;  0-->  2:IREFS=internal reference select (for FLL) (external)
;  1-->  1:IRCLKEN=internal reference clock (MCGIRCLK) enable
;  0-->  0:IREFSTEN=internal reference stop enable
MCG_C1_FLL_DIV1_IRCLKEXTSTOP  EQU  MCG_C1_IRCLKEN_MASK
;---------------------------------------------------------------
;MCG_C2 MCG Control 2 Register 
; 0-->  7:LOCRE0=loss of clock reset enable (interrupt, not reset)
;00-->5-4:RANGE0=frequency range select (low frequency)
; 0-->  3:HGO0=high gain oscillator select (low-power)
; 1-->  2:EREFS0=external reference select (oscillator)
; 0-->  1:LP=low power select (FLL not disabled in bypass)
; 0-->  0:IRCS=internal reference clock select (slow)
MCG_C2_LF_EREFOSC  EQU  MCG_C2_EREFS0_MASK
;---------------------------------------------------------------
;MCG_C4 MCG Control 4 Register
;  1-->   7:DMX32=DCO maximum frequency with 32.768 kHz ref
;                (25%)
;  01-->6-5:DRST_DRS=DCO range select (mid range)
;keep-->4-1:FCTRIM=fast internal reference clock trim setting
;keep-->  0:SCFTRIM=slow internal reference clock fine trim
MCG_C4_DCO_25PMAX_MID  EQU  (MCG_C4_DMX32_MASK :OR: \
                             (1 << MCG_C4_DRST_DRS_SHIFT))
;---------------------------------------------------------------
;Port A
PORT_PCR_SET_PTA3_EXTAL  EQU  (PORT_PCR_ISF_MASK :OR: \
                               PORT_PCR_MUX_SELECT_0_MASK)
PORT_PCR_SET_PTA4_XTAL   EQU  (PORT_PCR_ISF_MASK :OR: \
                               PORT_PCR_MUX_SELECT_0_MASK)
;---------------------------------------------------------------
;OSC0_CR
;1-->7:ERCLKEN=external reference enable
;0-->5:EREFSTEN=external reference stop enable
;0-->3:SC2P=oscillator 2-pF capacitor load configure (disabled)
;0-->2:SC4P=oscillator 4-pF capacitor load configure (disabled)
;0-->1:SC8P=oscillator 8-pF capacitor load configure (disabled)
;0-->0:SC16P=oscillator 16-pF capacitor load configure (disabled)
OSC0_CR_ERCLK_STOP_NOLOAD  EQU OSC_CR_ERCLKEN_MASK
;---------------------------------------------------------------
;SIM_CLKDIV1
;0000-->31-28:OUTDIV1=clock 1 output divider value (1)
;             :set divider for core/system clock,
;             :from which bus/flash clocks are derived
;             :divide by OUTDIV1 + 1
;001-->18-16:OUTDIV4=clock 4 output divider value (2)
;             :sets divider for bus and flash clocks,
;             :relative to core/system clock
;             :divide by OUTDIV4 + 1
SIM_CLKDIV1_COREDIV1_BUSDIV2  EQU  (1 << SIM_CLKDIV1_OUTDIV4_SHIFT)
;---------------------------------------------------------------
;SIM_COPC
;00-->3-2:COPT=COP watchdog timeout (disabled)
; 0-->  1:COPCLKS=COP clock select (x)
; 0-->  0:COPW=COP windowed mode (x)
SIM_COPC_COP_DISABLED  EQU  0
;****************************************************************
            AREA    Start,CODE,READONLY
            EXPORT  Startup
;---------------------------------------------------------------
Startup     PROC    {}
;****************************************************************
;Performs the following startup tasks
;* System initialization
;* Mask interrupts
;* Configure 48-MHz system clock
;Calls:  SystemInit
;        SetClock48MHz
;Input:  None
;Output:  None
;Modifies:  R0-R15;APSR
;****************************************************************
;Save return address
            PUSH    {LR}
;Initialize system
            BL      SystemInit
;Mask interrupts
            CPSID   I
;Configure 48-MHz system clock
            BL      SetClock48MHz
;Return
            POP     {PC}
            ENDP    ;Startup
;---------------------------------------------------------------
SystemInit  PROC    {}
;****************************************************************
;Performs the following system initialization tasks.
;* Mask interrupts
;* Disable watchdog timer (+)
;* Initialize registers to known state for debugger
;+:Following [1].1.1.4.2 Startup routines: 1 Disable watchdog
;[1] Freescale Semiconductor, <B>Kinetis L Peripheral Module Quick
;    Reference</B>, KLQRUG, Rev. 0, 9/2012.
;Input:  None
;Output:  None
;Modifies:  R0-R15;APSR
;****************************************************************
;Mask interrupts
            CPSID   I
;Disable COP watchdog timer
            LDR     R0,=SIM_COPC
            MOVS    R1,#SIM_COPC_COP_DISABLED
            STR     R1,[R0,#0]
;Put return address on stack
            PUSH    {LR}
;Initialize registers
            LDR     R1,=0x11111111
            ADDS    R2,R1,R1
            ADDS    R3,R2,R1
            ADDS    R4,R3,R1
            ADDS    R5,R4,R1
            ADDS    R6,R5,R1
            ADDS    R7,R6,R1
            MOV     R8,R1
            ADD     R8,R8,R7
            MOV     R9,R1
            ADD     R9,R9,R8
            MOV     R10,R1
            ADD     R10,R10,R9
            MOV     R11,R1
            ADD     R11,R11,R10
            MOV     R12,R1
            ADD     R12,R12,R11
            MOV     R14,R2
            ADD     R14,R14,R12
            MOV     R0,R1
            ADD     R0,R0,R14
            MSR     APSR,R0
            LDR     R0,=0x05250113
            POP     {PC}
            ENDP    ;SystemInit
;---------------------------------------------------------------
SetClock48MHz  PROC  {R0-R14}
;****************************************************************
;Multipurpose clock generator (MCG) in FLL engaged external (FEE) mode
;Establishes 48-MHz FLL clock from 32.678-kHz external crystal
;Core clock = 47.97MHz
;BusClock = 23.98MHz
;Corresponds to CLOCK_SETUP = 1 in system_MKL05Z4.c
;Follows [3], [2].24.5.1 MCG module initialization sequence,
;  and [1].4.1 Clocking 3: Configuration examples,
;[1] Freescale Semiconductor, <B>Kinetis L Peripheral Module Quick
;    Reference</B>, KLQRUG, Rev. 0, 9/2012.
;[2] Freescale Semiconductor, <B>KL05 Sub-Family Reference Manual</B>,
;    KL05P48M48SF1RM, Rev. 3.1, 11/2012.
;[3] Freescale startup_MKL05Z4.s and system_MKL05Z4.c
;    rev. 1.6, 4/11/2013
;Input:  None
;Output:  None
;Modifies:  APSR
;****************************************************************
            PUSH    {R0-R3}
;Configure for external clock from external 32-kHz oscillator
;  EXTAL0 on PTA3
;  XTAL0 on PTA4
            ;Enable PORT A
            LDR      R0,=SIM_SCGC5
            LDR      R1,=SIM_SCGC5_PORTA_MASK
            LDR      R2,[R0,#0]
            ORRS     R2,R2,R1
            STR      R2,[R0,#0]
            ;Set PORT A Pin 3 for EXTAL0
            LDR      R0,=PORTA_BASE
            LDR      R1,=PORT_PCR_SET_PTA3_EXTAL
            STR      R1,[R0,#PORTA_PCR3_OFFSET]
            ;Set PORT A Pin 4 for XTAL0
            ;PORT_PCR_SET same as PTA3 already in R1
            ;LDR     R1,=PORT_PCR_SET_PTA4_EXTAL
            STR      R1,[R0,#PORTA_PCR4_OFFSET]
;Update clock dividers:  system/core = 1; bus/flash = 2
;[1] defers this step until first part of switching to FEE mode
            LDR      R0,=SIM_CLKDIV1
            LDR      R1,=SIM_CLKDIV1_COREDIV1_BUSDIV2
            STR      R1,[R0,#0]
;------------------------------------------
;Establish FLL engaged external mode (FEE)
;------------------------------------------
;First configure oscillator settings in MCG_C2
;  RANGE is determined from external frequency
;  Since RANGE affects FRDIV, it must be set
;  correctly even with an external clock
;  * Low frequency range
;  * External reference oscillator
            LDR     R0,=MCG_BASE
            MOVS    R1,#MCG_C2_LF_EREFOSC
            STRB    R1,[R0,#MCG_C2_OFFSET]
;Enable external reference clock OSCERCLK,
;without additional oscillator load
            LDR     R2,=OSC0_CR
            MOVS    R1,#OSC0_CR_ERCLK_STOP_NOLOAD
            STRB    R1,[R2,#0]
;FRDIV set to keep FLL ref clock within
;correct range, determined by ref clock.
;  For 1-KHz ref, need divide by 1 (FRDIV = 0)
;  CLKS must be set to 2_00 to select FLL
;  Clearing IREFS selects and enables
;    external oscillator
;  [3] sets IRCLKEN for internal reference clock as MCGIRCLK
;  [2] states this is optional:  convenient to allow
;      switching between internal and external but
;      consumes more power
            MOVS    R1,#MCG_C1_FLL_DIV1_IRCLKEXTSTOP
            STRB    R1,[R0,#MCG_C1_OFFSET]
;Wait for oscillator initialization cycles
;to complete and become stable
;[2] suggests doing this step here
;[3] omits this step
            MOVS    R1,#MCG_S_OSCINIT0_MASK
SetClock48MHz_Wait_MCG_S_OSCINIT0                      ;repeat {
            LDRB    R2,[R0,#MCG_S_OFFSET]
            TST     R1,R2
            BEQ     SetClock48MHz_Wait_MCG_S_OSCINIT0  ;} until OSCINIT0
;Wait for source of the FLL reference clock 
;to be the external reference clock.
;[2] suggests doing this step here
;[3] defers until after MCG_C4 initialization
;(MCG_S:  IREFST becomes 0)
            MOVS    R1,#MCG_S_IREFST_MASK
SetClock48MHz_Wait_MCG_S_IREFST_Clear                      ;do {
            LDRB    R2,[R0,#MCG_S_OFFSET]
            TST     R1,R2
            BNE     SetClock48MHz_Wait_MCG_S_IREFST_Clear  ;} while IREFST
;[1] omits this step
;Reference range:  31.25–39.0625 kHz
;FLL factor:  1280
;DCO range:  40–50 MHz
;Preserve FCTRIM and SCFTRIM
            LDRB    R2,[R0,#MCG_C4_OFFSET]
            MOVS    R1,#MCG_C4_DRST_DRS_MASK
            MOVS    R3,#MCG_C4_DCO_25PMAX_MID
            BICS    R2,R2,R1
            ORRS    R2,R2,R3
            STRB    R2,[R0,#MCG_C4_OFFSET]
;Wait until output of FLL is selected [3]
            MOVS    R1,#MCG_S_CLKST_MASK
SetClock48MHz_Wait_MCG_FLL_Selected                      ;do {
            LDRB    R2,[R0,#MCG_S_OFFSET]
            TST     R1,R2
            BNE     SetClock48MHz_Wait_MCG_FLL_Selected  ;} while CLKST
;Now have 48-MHz FLL clock,
;48-MHz core clock, and 24-MHz bus clock
            POP     {R0-R3}
            BX      LR
            ENDP    ;SetClock48MHz
;****************************************************************
            ALIGN
;Program template for CMPE-250 uses main as "Reset_Handler"
;           EXPORT  Reset_Handler
;****************************************************************
;Goto main
;****************************************************************
;           LDR     R0,=main
;           BX      R0
            EXPORT  Dummy_Handler
            EXPORT  HardFault_Handler  [WEAK]
Dummy_Handler  PROC  {}
HardFault_Handler
;****************************************************************
;Dummy exception handler (infinite loop)
;****************************************************************
            B       .
            ENDP    ;Dummy_Handler
;---------------------------------------------------------------
            ALIGN
;****************************************************************
            AREA    |.ARM.__at_0xC0|,DATA,NOALLOC,READONLY
;Program once field:  0xC0-0xFF
            SPACE   0x40
;****************************************************************
            IF      :LNOT::DEF:RAM_TARGET
            AREA    |.ARM.__at_0x400|,CODE,READONLY
            DCB     FCF_BACKDOOR_KEY0,FCF_BACKDOOR_KEY1
            DCB     FCF_BACKDOOR_KEY2,FCF_BACKDOOR_KEY3
            DCB     FCF_BACKDOOR_KEY4,FCF_BACKDOOR_KEY5
            DCB     FCF_BACKDOOR_KEY6,FCF_BACKDOOR_KEY7
            DCB     FCF_FPROT0,FCF_FPROT1,FCF_FPROT2,FCF_FPROT3
            DCB     FCF_FSEC,FCF_FOPT,0xFF,0xFF
            ENDIF
;****************************************************************
            AREA    |.ARM.__at_0x1FFFFC00|,DATA,READWRITE,ALIGN=3
            EXPORT  __initial_sp
;Allocate system stack beginning at lowest address of RAM
            IF      :LNOT::DEF:SSTACK_SIZE
SSTACK_SIZE EQU     0x00000100
            ENDIF
Stack_Mem   SPACE   SSTACK_SIZE
__initial_sp
;****************************************************************
            END
