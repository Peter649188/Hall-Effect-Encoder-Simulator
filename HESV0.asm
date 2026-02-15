;***********************************************************************
;Title:		Hall Effect Simulator
;File Name:	hes.asm
;Programmer:	Peter Arthur McDonald
;Start Date:	11 Jun 07
;End Date:	21 Sep 16
;Purpose:	To simulate motor feedback devices. Encoder, Hall Effect, and
;		Resolver.
;Revision History: See end of assembly listing.
;***********************************************************************
    processor 16f877A		;Set processor type.
    #include <p16f877A.inc>

    errorlevel	-302		;Suppress message 302 from list file.
;***********************************************************************
;Initialize the Configuration Bits for the PIC16F877.
;-----------------------------------------------------------------------
;    __config b'00110100000001' ;4MHz Clock.
    __config b'00110100000010'  ;20MHz Clock.
            ;  00------00---- <CP1:CP0>Code Protection enabled.
            ;  --1----------- <Debug> In-Circuit Debugger disabled. RB6,RB7 as I/O.
            ;  ---X---------- Unused.
            ;  ----0--------- <WRT> Flash Memory is not writable by program.
            ;  -----1-------- <CPD> EEPROM read protection disabled.
            ;  ------0------- <LVP> Low voltage in circuit programmer disabled. RB3 as I/O.
            ;  -------O------ <BODEN> Brown out reset disabled.
            ;  ----------0--- </PWRTE> Power up timer enabled.
            ;  -----------0-- <WDTE> Watchdog timer disabled.
            ;  ------------01 <FOSC1:FOSC0> XT-Oscillator selected.
            ;  ------------10 <FOSC1:FOSC0> HS-Oscillator selected.
;***********************************************************************
;Initialize equates.
    ;#DEFINE	SS		PORTA,5	;MAX532 /CS. (SPI SLAVE SELECT).
    #DEFINE	OUT_TYPE_PROG	PORTA,3	;Push Button to Program ULN2003 or AM26LS31.
    #DEFINE	LED_OUT_TYP_PG	PORTA,2	;LED to indicate ULN2003 or AM26LS31 pogramming.
    #DEFINE	LED_IE_PPR_PG	PORTA,1	;LED to indicate IE PPR programming.

    #DEFINE	LED_HE_OC_OUT	PORTC,7	;LED indicating that HE Open Collector Output is selected.
    #DEFINE	LED_HE_DIFF_OUT	PORTC,6	;LED indicating that HE Differential Output is selected.
    #DEFINE	LED_IE_OC_OUT	PORTC,5	;LED indicating that IE Open Collector Output is selected.
    #DEFINE	LED_IE_DIFF_OUT	PORTC,4	;LED indicating that IE Differential Output is selected.
    #DEFINE	FWD_REV_SW	PORTC,1	;FORWARD/REVERSE Switch.
    #DEFINE	START_STOP_SW	PORTC,0	;START/STOP Switch.
 
    #DEFINE	UP_SW		PORTD,7	;UP Push Button.
    #DEFINE	DOWN_SW		PORTD,6	;DOWN Push Button.
    #DEFINE	LEFT_SW		PORTD,5	;LEFT Push Button.
    #DEFINE	RIGHT_SW	PORTD,4	;RIGHT Push Button.
    #DEFINE	ENTER_SW	PORTD,3	;ENTER Push Button.
    #DEFINE	IE_PPR_PROG	PORTD,2	;Push Button to Program IE PPR.
    #DEFINE	IE_LATCH_CLK	PORTD,1	;IC2 74HC374N PIN 11 (CLK).
    #DEFINE	HE_LATCH_CLK	PORTD,0	;IC3 74HC374 PIN 11 (CLK).

    #DEFINE	LED_CW		PORTE,2	;LED indicating CW Pattern Rotation.
    #DEFINE	LED_CCW		PORTE,1	;LED indicating CCW Pattern Rotation.s
;   #DEFINE	TPTACH_SELECT	PORTE,0 ;Select Three Phase Tack Mode.
;   #DEFINE	HE_BYPASS	PORTE,0	;Bypass Hall Effect routines if low.
    #DEFINE	SIMULATOR_KEY	PORTE,0	;HES Simulator only works with J1 Jumper installed.
;***********************************************************************
;Initialize Variables
;-----------------------------------------------------------------------
    CBLOCK	0x20
    I_HE		;Counter to select which Hall Effect Pattern
			;is sent to the Databus.

    I_IE		;Counter to select which Incremental Encoder Pattern
                        ;is sent to the Databus.

    J			;Delay Time Counter
    K			; "           "

    M_IE		;Long Counter variables for Z Pulse Comparison.
    N_IE

    PC_IE_HIGH_BYTE		;Pulse Counter used to trigger Hall Effect Output.
    PC_IE_LOW_BYTE

    HE_TRIGGER__HIGH_BYTE	;Point at which Hall Effect Outputs trigger.
    HE_TRIGGER__LOW_BYTE

    IE_COMPARE_HIGH_BYTE	;Comparison to Long Counter variables.
    IE_COMPARE_LOW_BYTE		;    "							"
    IE_COMPARE_FLAG		;(M_IE,N_IE) = (IE_COMPARE_HIGH_BYTE,IE_COMPARE_LOW_BYTE)

    IE_Z_PULSE_DURATION		;ZPULSE Width.
    IE_Z_PULSE_WIDTH_VALUE	;Variable used to program the Z Pulse Width.
    IE_Z_PULSE_POSITION		;Variable used to set the position the Z Pulse triggers
			        ;in relation to the A or B Pulse.
    IE_Z_PULSE_VALUE_FWD	;Variable used to program the IE_Z_PULSE_POSITION.
    IE_Z_PULSE_VALUE_REV

    IE_FWD_FLAG			;Flags to tell us that we switched from forward to
    IE_REV_FLAG			;reverse while still rotating.

    ADCMEM_HI			;A to D Converter High result
    ADCMEM_LO			;A to D Converter Low result

    LOOP_TIME			;A to D Converter High result is moved to
    DELAY_TIME			;these two variables, and used to speed up
			        ;or slow down the Feedback Patterns sent
				;to PORTB Data Bus.

    OC_DIFR_SEL_FLAG		;1 = ULN2003. 0 = AM26LS31.

    TEMP_FILE			;Tempory Storage.

    TXDATA			;SPI Data Memory.
    ENDC
;***********************************************************************
;Reset Vectors.
    ORG		0000h
;***********************************************************************

;***********************************************************************
;Initialize the PIC16F876
;***********************************************************************

;-----------------------------------------------------------------------
;Switch to Bank 0, because this Bank contains the registers
;for PORTs A,B, and C.
;   BCF		STATUS,RP1	;Bank 0.
;   BCF		STATUS,RP0
    BANKSEL	PORTA
;-----------------------------------------------------------------------
;Initialize the Port's A, B, and C Data Latches to zero's.
;   CLRF	PORTA
;   CLRF	PORTB
;   CLRF	PORTC
;***********************************************************************

;***********************************************************************
;Initialize ADC.
;***********************************************************************

;-----------------------------------------------------------------------
;Switch to Bank 1, because this Bank contains the registers
;for ADCON1, TRISA, TRISB, and TRISC.
;   BSF		STATUS,RP0	;Select Bank 1.
    BANKSEL	ADCON1
;-----------------------------------------------------------------------
;Set the A/D Converter and Digital I/O Pins,
;   MOVLW	0x8E	;  10001110
                        ;  1-------	Right justifiy ADRESH:ADRESL.
                        ;  -XXX----	Not Used.
                        ;  ----1110	Set RA<5:1> as digital I/O.
                        ;		Set RA<0> for analog input.


    MOVLW	0x0E	;  00001110
                        ;  0-------	Left justifiy ADRESH:ADRESL.
                        ;  -XXX----	Not Used.
                        ;  ----1110	Set RA<5:1> as digital I/O.
                        ;		Set RA<0> for analog input.


;   MOVLW	0x06	;  00000110
                        ;  0-------	Left justifiy ADRESH:ADRESL.
                        ;  -XXX----	Not Used.
                        ;  ----0110	Set RA<5:0> as digital I/O.

    MOVWF	ADCON1
;***********************************************************************

;***********************************************************************
;Initialize PORT I/O.
;***********************************************************************

;-----------------------------------------------------------------------
;Set the PORTA for ADC Input.
    MOVLW	0x09	;0000 1001
    MOVWF	TRISA	;XX-- ---- Not available.
                        ;--0- ---- MAX532 /CS (SPI Slave Select).
                        ;---X ---- Not Used.
                        ;---- 1--- Push Button to Program ULN2003 or AM26LS31.
                        ;---- -0-- LED to indicate ULN2003 or AM26LS31 pogramming.
                        ;---- --0- LED to indicate IE PPR programming.
                        ;---- ---1 Analog input for potentiometer.
;-----------------------------------------------------------------------
;Set the PORTB for Output
    MOVLW	0x00	;0000 0000
    MOVWF	TRISB	;Port be used for Data Bus.
;-----------------------------------------------------------------------
;Set the PORTC for I/O.
;    MOVLW	0x13	;0001 0011
;    MOVWF	TRISC	;X--- ----
                        ;-0-- ---- MAX532 /CS
                        ;--0- ---- SDO
                        ;---1 ---- SDI
                        ;---- 0--- SCK
                        ;---- -X--
                        ;---- --1- FORWARD/REVERSE Switch.
                        ;---- ---1 START/STOP Switch.
;-----------------------------------------------------------------------
;Set the PORTC for I/O.
    MOVLW	0x03	;0001 0011
    MOVWF	TRISC	;0--- ---- LED indicating HE Open Collector Output selected.
                        ;-0-- ---- LED indicating HE Differential Output selected.
                        ;--0- ---- LED indicating IE Open Collector Output selected.
                        ;---0 ---- LED indicating IE Differential Output selected.
                        ;---- 0--- 
                        ;---- -0--
                        ;---- --1- FORWARD/REVERSE Switch.
                        ;---- ---1 START/STOP Switch.
;-----------------------------------------------------------------------
;Set the PORTD for I/O.
    MOVLW	0xFC	;1111 1100
    MOVWF	TRISD	;1--- ---- UP Push Button
                        ;-1-- ---- DOWN Push Button
                        ;--1- ---- LEFT Push Button
                        ;---1 ---- RIGHT Push Button
                        ;---- 1--- ENTER Push Button
                        ;---- -1-- Push Button to Program IE PPR.
                        ;---- --0- IC2 74HC374 PIN 11 (CLK)
                        ;---- ---0 IC3 74HC374 PIN 11 (CLK)
;-----------------------------------------------------------------------
;Set the PORTE for Ouputs.
    MOVLW	0x01	;0000 0001
			;---- -0-- LED indicating CW Pattern Rotation.
			;---- --0- LED indicating CCW Pattern Rotation.
    MOVWF	TRISE   ;--------1 Select Three Phase Tack Mode.
;***********************************************************************


;***********************************************************************
;Initialize SPI.
;***********************************************************************
;    MOVLW	B'01000000'	;SPI, Middle of output time sampling.
;    MOVWF	SSPSTAT		;Data transmitted on Rising Edge of SCK.
;-----------------------------------------------------------------------
;Switch to Bank 0, because this Bank contains the registers
;for PORTA, PORTB, PORTC, SSPCON, and ADCON0.
;-----------------------------------------------------------------------
;    BCF	STATUS,RP0	;Select Bank 0
;    BANKSEL	SSPCON
;-----------------------------------------------------------------------
;    MOVLW	B'00100001'	;SPI MASTER MODE, 1/16 Tosc bit time, SSP is on.
;    MOVWF	SSPCON

;***********************************************************************
;Initialize ADC.
;***********************************************************************

;-----------------------------------------------------------------------
;Initialize the PIC16F876 A/D Converter.
;-----------------------------------------------------------------------
    BANKSEL	ADCON0
    
    BSF		ADCON0,ADCS1	;Initialize Tad to 32Tosc.
    BCF		ADCON0,ADCS0

;   BCF		ADCON0,ADCS1	;Initialize Tad to 8Tosc.
;   BSF		ADCON0,ADCS0

;   BCF		ADCON0,ADCS1	;Initialize Tad to 2Tosc.
;   BCF		ADCON0,ADCS0

    BSF		ADCON0,ADON	;Select ON the A/D Converter.

    BANKSEL	PIE1

    BCF		PIE1,ADIE	;Disable A/D interrupt
    BCF		INTCON,GIE	;Disable Global interrupts.

    BANKSEL	PORTA
;***********************************************************************
;***********************************************************************
;The Data Tables must be in the first 256 Bytes of Program Memory.
;So I parked them here and mad a jump over them, so that the program
;would not lock up at boot up.
;-----------------------------------------------------------------------
    GOTO	MAIN_INI
;***********************************************************************
HE_PATTERN:
;-----------------------------------------------------------------------
    ADDWF	PCL,F		;Staying in first 256 instuctions.

    DT		b'00000100', b'00000110', b'00000010', b'00000011'
    DT		b'00000001', b'00000101'
;***********************************************************************

;***********************************************************************
IE_PATTERN:
;-----------------------------------------------------------------------
    ADDWF	PCL,F		;Staying in first 256 instuctions.

    DT		b'00000001', b'00000000', b'00000010', b'00000011'
;***********************************************************************
IE_Z_PULSE_PATTERN:
;-----------------------------------------------------------------------
    ADDWF	PCL,F		;Staying in first 256 instuctions.

    DT		b'00000101', b'00000100', b'00000110', b'00000111'
;*************************************************************************

;***********************************************************************
;Initialize variables.
;***********************************************************************
MAIN_INI:
;-----------------------------------------------------------------------
    CLRF	I_HE
    CLRF	I_IE
    CLRF	J
    CLRF	K
    CLRF	M_IE
    CLRF	N_IE
    CLRF	PC_IE_HIGH_BYTE
    CLRF	PC_IE_LOW_BYTE
    CLRF	HE_TRIGGER__HIGH_BYTE
    CLRF	HE_TRIGGER__LOW_BYTE
    CLRF	IE_COMPARE_HIGH_BYTE
    CLRF	IE_COMPARE_LOW_BYTE
    CLRF	IE_COMPARE_FLAG
    CLRF	IE_Z_PULSE_DURATION
    CLRF	ADCMEM_HI
    CLRF	ADCMEM_LO
    CLRF	LOOP_TIME
    CLRF	DELAY_TIME
    CLRF	OC_DIFR_SEL_FLAG

    BSF		IE_LATCH_CLK
    BSF		HE_LATCH_CLK
;-----------------------------------------------------------------------
;Turn off programming LED's.
    BSF		LED_IE_PPR_PG
    BSF		LED_OUT_TYP_PG

    BCF		LED_HE_DIFF_OUT
    BCF		LED_HE_OC_OUT
    BCF		LED_IE_DIFF_OUT
    BCF		LED_IE_OC_OUT
    
    BCF		LED_CW
    BCF		LED_CCW
;***********************************************************************
;HES Simulator only works if J1 is jumpered.
HES_SIM_KEY:
    BTFSS	SIMULATOR_KEY	;If J1 is jumped out start the program.
    GOTO	PROGRAM_IE_PPR
    
    BCF		LED_IE_PPR_PG	;All LED's on.
    BCF		LED_OUT_TYP_PG
    BSF		LED_HE_DIFF_OUT
    BSF		LED_HE_OC_OUT
    BSF		LED_IE_DIFF_OUT
    BSF		LED_IE_OC_OUT
    BSF		LED_CW
    BSF		LED_CCW
    
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    
    BSF		LED_IE_PPR_PG	;All LED's off.
    BSF		LED_OUT_TYP_PG
    BCF		LED_HE_DIFF_OUT
    BCF		LED_HE_OC_OUT
    BCF		LED_IE_DIFF_OUT
    BCF		LED_IE_OC_OUT
    BCF		LED_CW
    BCF		LED_CCW
    
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    
    GOTO	HES_SIM_KEY	;Otherwise endless loop.
;***********************************************************************
    
;***********************************************************************
;Program the Incremental Encoder Pulses Per Revolution.
;***********************************************************************
PROGRAM_IE_PPR:
;-----------------------------------------------------------------------
    BTFSS	IE_PPR_PROG		;Push Button to Program IE PPR.
    GOTO	SET_IE_PPR_0

    BCF		LED_IE_PPR_PG
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY

    BSF		LED_IE_PPR_PG
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY

    GOTO	PROGRAM_IE_PPR
;-----------------------------------------------------------------------
;50 PPR = $0032
SET_IE_PPR_0:
    BTFSC	UP_SW
    GOTO	SET_IE_PPR_1

;Set the Incremental Encoder count were the Hall Effect Outputs trigger.
;50/6 = $0008
    MOVLW	0x00
    MOVWF	HE_TRIGGER__HIGH_BYTE
    MOVLW	0x08
    MOVWF	HE_TRIGGER__LOW_BYTE

;Set the point were the Incremental Encoder Z Pulse Output triggers.
    MOVLW	0x00
    MOVWF	IE_COMPARE_HIGH_BYTE
    MOVLW	0x32
    MOVWF	IE_COMPARE_LOW_BYTE

;Start in the middle so that we can go CW or CCW, without blowing
;passed the end limits of 0 or 50 (ppr)
    MOVLW	0x00		;50/2 = 25d = $0019
    MOVWF	M_IE
    MOVLW	0x19
    MOVWF	N_IE

    GOTO	SET_IE_PPR_END
;-----------------------------------------------------------------------
;500 PPR = $01F4
SET_IE_PPR_1:
    BTFSC	DOWN_SW
    GOTO	SET_IE_PPR_2

;Set the Incremental Encoder count were the Hall Effect Outputs trigger.
;500/6 = $0053
    MOVLW	0x00
    MOVWF	HE_TRIGGER__HIGH_BYTE
    MOVLW	0x53
    MOVWF	HE_TRIGGER__LOW_BYTE

;Set the point were the Incremental Encoder Z Pulse Output triggers.
    MOVLW	0x01
    MOVWF	IE_COMPARE_HIGH_BYTE
    MOVLW	0xF4
    MOVWF	IE_COMPARE_LOW_BYTE

;Start in the middle so that we can go CW or CCW, without blowing
;passed the end limits of 0 or 500 (ppr)
    MOVLW	0x00		;500/2 = 250d = $00FA
    MOVWF	M_IE
    MOVLW	0xFA
    MOVWF	N_IE

    GOTO	SET_IE_PPR_END
;-----------------------------------------------------------------------
;1000 PPR = $03E8
SET_IE_PPR_2:
    BTFSC	LEFT_SW
    GOTO	SET_IE_PPR_3

;Set the Incremental Encoder count were the Hall Effect Outputs trigger.
;1000/6 = $00A6
    MOVLW	0x00
    MOVWF	HE_TRIGGER__HIGH_BYTE
    MOVLW	0xA6
    MOVWF	HE_TRIGGER__LOW_BYTE

;Set the point were the Incremental Encoder Z Pulse Output triggers.
    MOVLW	0x03
    MOVWF	IE_COMPARE_HIGH_BYTE
    MOVLW	0xE8
    MOVWF	IE_COMPARE_LOW_BYTE

;Start in the middle so that we can go CW or CCW, without blowing
;passed the end limits of 0 or 1000 (ppr)
    MOVLW	0x01		;1000/2 = 500d = $01F4
    MOVWF	M_IE
    MOVLW	0xF4
    MOVWF	N_IE

    GOTO	SET_IE_PPR_END
;-----------------------------------------------------------------------
;2500 PPR = $09C4
SET_IE_PPR_3:
    BTFSC	RIGHT_SW
    GOTO	SET_IE_PPR_4

;Set the Incremental Encoder count were the Hall Effect Outputs trigger.
;2500/6 = $01A0
    MOVLW	0x01
    MOVWF	HE_TRIGGER__HIGH_BYTE
    MOVLW	0xA0
    MOVWF	HE_TRIGGER__LOW_BYTE

;Set the point were the Incremental Encoder Z Pulse Output triggers.
    MOVLW	0x03
    MOVWF	IE_COMPARE_HIGH_BYTE
    MOVLW	0xE8
    MOVWF	IE_COMPARE_LOW_BYTE

;Start in the middle so that we can go CW or CCW, without blowing
;passed the end limits of 0 or 2500 (ppr)
    MOVLW	0x04		;2500/2 = 1250d = $04E2
    MOVWF	M_IE
    MOVLW	0xE2
    MOVWF	N_IE

    GOTO	SET_IE_PPR_END
;-----------------------------------------------------------------------
;5000 PPR = $1388
SET_IE_PPR_4:
    BTFSC	ENTER_SW
    GOTO	SET_DEFAULT_IE_PPR

;Set the Incremental Encoder count were the Hall Effect Outputs trigger.
;5000/6 = $0341
    MOVLW	0x03
    MOVWF	HE_TRIGGER__HIGH_BYTE
    MOVLW	0x41
    MOVWF	HE_TRIGGER__LOW_BYTE

;Set the point were the Incremental Encoder Z Pulse Output triggers.
    MOVLW	0x13
    MOVWF	IE_COMPARE_HIGH_BYTE
    MOVLW	0x88
    MOVWF	IE_COMPARE_LOW_BYTE

;Start in the middle so that we can go CW or CCW, without blowing
;passed the end limits of 0 or 5000 (ppr)
    MOVLW	0x09		;5000/2 = 2500d = $09C4
    MOVWF	M_IE
    MOVLW	0xC4
    MOVWF	N_IE

    GOTO	SET_IE_PPR_END
;-----------------------------------------------------------------------
;DEFAULT PPR = 1000 PPR (IF no programming push button is pressed after
;the IE_PPR_PROG push button is pressed.)
SET_DEFAULT_IE_PPR:
;Set the Incremental Encoder count were the Hall Effect Outputs trigger.
;1000/6 = $00A6
    MOVLW	0x00
    MOVWF	HE_TRIGGER__HIGH_BYTE
    MOVLW	0xA6
    MOVWF	HE_TRIGGER__LOW_BYTE

;Set the point were the Incremental Encoder Z Pulse Output triggers.
    MOVLW	0x03
    MOVWF	IE_COMPARE_HIGH_BYTE
    MOVLW	0xE8
    MOVWF	IE_COMPARE_LOW_BYTE

;Start in the middle so that we can go CW or CCW, without blowing
;passed the end limits of 0 or 1000 (ppr)
    MOVLW	0x01		;1000/2 = 500d = $01F4
    MOVWF	M_IE
    MOVLW	0xF4
    MOVWF	N_IE
;-----------------------------------------------------------------------
SET_IE_PPR_END:
    BCF		LED_IE_PPR_PG
;***********************************************************************
;Program the Simulator's Output Type. ULN2003 or AM26LS31.
;***********************************************************************
PROGRAM_OUTPUT_TYPE:
;-----------------------------------------------------------------------
    BTFSS	OUT_TYPE_PROG	;Push Button to Program ULN2003 or AM26LS31.
    GOTO	SET_OUT_TYPE_0

    BCF		LED_OUT_TYP_PG
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY

    BSF		LED_OUT_TYP_PG
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY

    GOTO	PROGRAM_OUTPUT_TYPE
;-----------------------------------------------------------------------
;Output Type = IE and HE to AM26LS31.
SET_OUT_TYPE_0:
    BTFSC	UP_SW
    GOTO	SET_OUT_TYPE_1

    MOVLW	0x00
    MOVWF	OC_DIFR_SEL_FLAG
    
    BSF		LED_HE_DIFF_OUT
    BSF		LED_IE_DIFF_OUT

    GOTO	SET_OUT_TYPE_END
;-----------------------------------------------------------------------
;Output Type = IE and HE to ULN2003.
SET_OUT_TYPE_1:
    BTFSC	DOWN_SW
    GOTO	SET_OUT_TYPE_2

    MOVLW	0x01
    MOVWF	OC_DIFR_SEL_FLAG

    BSF		LED_HE_OC_OUT
    BSF		LED_IE_OC_OUT
    
    GOTO	SET_OUT_TYPE_END
;-----------------------------------------------------------------------
;Output Type = IE to AM26LS31 and HE to ULN2003
SET_OUT_TYPE_2:
    BTFSC	LEFT_SW
    GOTO	SET_OUT_TYPE_3

    MOVLW	0x02
    MOVWF	OC_DIFR_SEL_FLAG

    BSF		LED_HE_OC_OUT
    BSF		LED_IE_DIFF_OUT
    
    GOTO	SET_OUT_TYPE_END
;-----------------------------------------------------------------------
;Output Type = HE to AM26LS31 and IE to ULN2003.
SET_OUT_TYPE_3:
    BTFSC	RIGHT_SW
    GOTO	SET_DEFAULT_OUT_TYPE

    MOVLW	0x03
    MOVWF	OC_DIFR_SEL_FLAG

    BSF		LED_HE_DIFF_OUT
    BSF		LED_IE_OC_OUT
    
    GOTO	SET_OUT_TYPE_END
;-----------------------------------------------------------------------
;DEFAULT Output Type is IE and HE to AM26LS31.(IF no programming push
;button is pressed after the IE_PPR_PROG push button is pressed.)
SET_DEFAULT_OUT_TYPE:
    MOVLW	0x00				;1 = ULN2003. 0 = AM26LS31.
    MOVWF	OC_DIFR_SEL_FLAG
    
    BSF		LED_HE_DIFF_OUT
    BSF		LED_IE_DIFF_OUT
;-----------------------------------------------------------------------
SET_OUT_TYPE_END:
    BCF		LED_OUT_TYP_PG
;***********************************************************************
;Program where the Z Pulse triggers in relation to the A or B Pulses.
;***********************************************************************
PROGRAM_IE_Z_PULSE_POSITION:
;-----------------------------------------------------------------------
    BTFSS	IE_PPR_PROG		;Push Button to Program IE PPR.
    GOTO	SET_IE_Z_PULSE_POSITION_0

    BCF		LED_IE_PPR_PG
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    
    BSF		LED_IE_PPR_PG
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    
    GOTO	PROGRAM_IE_Z_PULSE_POSITION
;-----------------------------------------------------------------------
;Z Pulse falls on Leading Edge of B Pulse.
SET_IE_Z_PULSE_POSITION_0:
    BTFSC	UP_SW
    GOTO	SET_IE_Z_PULSE_POSITION_1

;FWD VALUE.
    MOVLW	0x01
    MOVWF	IE_Z_PULSE_VALUE_FWD
;REV VALUE
    MOVLW	0x00
    MOVWF	IE_Z_PULSE_VALUE_REV

    GOTO	SET_IE_Z_PULSE_POSITION_END
;-----------------------------------------------------------------------
;Z Pulse falls on Leading Edge of A Pulse.
SET_IE_Z_PULSE_POSITION_1:
    BTFSC	DOWN_SW
    GOTO	SET_IE_Z_PULSE_POSITION_2

;FWD VALUE.
    MOVLW	0x02
    MOVWF	IE_Z_PULSE_VALUE_FWD
;REV VALUE
    MOVLW	0x01
    MOVWF	IE_Z_PULSE_VALUE_REV

    GOTO	SET_IE_Z_PULSE_POSITION_END
;-----------------------------------------------------------------------
;Z Pulse falls on Trailing Edge of B Pulse.
SET_IE_Z_PULSE_POSITION_2:
    BTFSC	LEFT_SW
    GOTO	SET_IE_Z_PULSE_POSITION_3

;FWD VALUE.
    MOVLW	0x03
    MOVWF	IE_Z_PULSE_VALUE_FWD
;REV VALUE
    MOVLW	0x02
    MOVWF	IE_Z_PULSE_VALUE_REV

    GOTO	SET_IE_Z_PULSE_POSITION_END
;-----------------------------------------------------------------------
;Z Pulse falls on Trailing Edge of A Pulse.
SET_IE_Z_PULSE_POSITION_3:
    BTFSC	RIGHT_SW
    GOTO	SET_DEFAULT_IE_Z_PULSE_POSITION

;FWD VALUE.
    MOVLW	0x00
    MOVWF	IE_Z_PULSE_VALUE_FWD
;REV VALUE
    MOVLW	0x03
    MOVWF	IE_Z_PULSE_VALUE_REV

    GOTO	SET_IE_Z_PULSE_POSITION_END
;-----------------------------------------------------------------------
;Z Pulse falls on Leading Edge of B Pulse.
SET_DEFAULT_IE_Z_PULSE_POSITION:
;FWD VALUE.
    MOVLW	0x01
    MOVWF	IE_Z_PULSE_VALUE_FWD
;REV VALUE
    MOVLW	0x00
    MOVWF	IE_Z_PULSE_VALUE_REV
;-----------------------------------------------------------------------
SET_IE_Z_PULSE_POSITION_END:
    BCF		LED_IE_PPR_PG
;***********************************************************************
;Program the Z Pulse's Width.
;***********************************************************************
PROGRAM_Z_PULSE_WIDTH:
;-----------------------------------------------------------------------
    BTFSS	OUT_TYPE_PROG		;Push Button to Program ULN2003 or AM26LS31.
    GOTO	SET_Z_PULSE_WIDTH_0

    BCF		LED_OUT_TYP_PG
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    
    BSF		LED_OUT_TYP_PG
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    CALL	GP_DELAY
    
    GOTO	PROGRAM_Z_PULSE_WIDTH
;-----------------------------------------------------------------------
;Z PULSE WIDTH = HIGH LOW LOW LOW
SET_Z_PULSE_WIDTH_0:
    BTFSC	UP_SW
    GOTO	SET_Z_PULSE_WIDTH_1

    MOVLW	0x1
    MOVWF	IE_Z_PULSE_WIDTH_VALUE

    GOTO	SET_Z_PULSE_WIDTH_END
;-----------------------------------------------------------------------
;Z PULSE WIDTH = HIGH HIGH LOW LOW
SET_Z_PULSE_WIDTH_1:
    BTFSC	DOWN_SW
    GOTO	SET_Z_PULSE_WIDTH_2

    MOVLW	0x2
    MOVWF	IE_Z_PULSE_WIDTH_VALUE

    GOTO	SET_Z_PULSE_WIDTH_END
;-----------------------------------------------------------------------
;Z PULSE WIDTH = HIGH HIGH HIGH LOW
SET_Z_PULSE_WIDTH_2:
    BTFSC	LEFT_SW
    GOTO	SET_Z_PULSE_WIDTH_3

    MOVLW	0x3
    MOVWF	IE_Z_PULSE_WIDTH_VALUE

    GOTO	SET_Z_PULSE_WIDTH_END
;-----------------------------------------------------------------------
;Z PULSE WIDTH = HIGH HIGH HIGH HIGH
SET_Z_PULSE_WIDTH_3:
    BTFSC	RIGHT_SW
    GOTO	SET_DEFAULT_Z_PULSE_WIDTH

    MOVLW	0x4
    MOVWF	IE_Z_PULSE_WIDTH_VALUE

    GOTO	SET_Z_PULSE_WIDTH_END
;-----------------------------------------------------------------------
;DEFAULT Z PULSE WIDTH = HIGH HIGH HIGH HIGH
SET_DEFAULT_Z_PULSE_WIDTH:
    MOVLW	0x4
    MOVWF	IE_Z_PULSE_WIDTH_VALUE
;-----------------------------------------------------------------------
SET_Z_PULSE_WIDTH_END:
    BCF		LED_OUT_TYP_PG
;***********************************************************************
;Initialize outputs to Incremental Encoder Patterns.
;-----------------------------------------------------------------------
    MOVF	I_IE,W
    CALL	IE_PATTERN

;Store pattern in Temp File before SWAPF.
    MOVWF	TEMP_FILE
;-----------------------------------------------------------------------
;-----------------------------------------------------------------------
;IE and HE sent to AM26LS31.
INI_IE_OUTPUT_TYPE_0:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x00
    BTFSS	STATUS,Z
    GOTO	INI_IE_OUTPUT_TYPE_1

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		IE_LATCH_CLK
    NOP
    NOP
    BSF		IE_LATCH_CLK

    GOTO	INI_IE_END_PROCESS

;IE and HE sent to ULN2003.
INI_IE_OUTPUT_TYPE_1:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x01
    BTFSS	STATUS,Z
    GOTO	INI_IE_OUTPUT_TYPE_2

    SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		IE_LATCH_CLK
    NOP
    NOP
    BSF		IE_LATCH_CLK

    GOTO	INI_IE_END_PROCESS

;IE sent to AM26LS31 and HE sent to ULN2003.
INI_IE_OUTPUT_TYPE_2:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x02
    BTFSS	STATUS,Z
    GOTO	INI_IE_OUTPUT_TYPE_3

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		IE_LATCH_CLK
    NOP
    NOP
    BSF		IE_LATCH_CLK

    GOTO	INI_IE_END_PROCESS

;HE sent to AM26LS31 and IE sent to ULN2003.
INI_IE_OUTPUT_TYPE_3:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x03
    BTFSS	STATUS,Z
    GOTO	INI_IE_END_PROCESS

    SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		IE_LATCH_CLK
    NOP
    NOP
    BSF		IE_LATCH_CLK

INI_IE_END_PROCESS:    
;-----------------------------------------------------------------------
;Initialize outputs to Hall Effect Patterns.
;-----------------------------------------------------------------------
    MOVF	I_HE,W
    CALL	HE_PATTERN

;Store pattern in Temp File.
    MOVWF	TEMP_FILE
;-----------------------------------------------------------------------
;IE and HE sent to AM26LS31.
INI_HE_OUTPUT_TYPE_0:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x00
    BTFSS	STATUS,Z
    GOTO	INI_HE_OUTPUT_TYPE_1

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		HE_LATCH_CLK
    NOP
    NOP
    BSF		HE_LATCH_CLK

    GOTO	INI_HE_END_PROCESS

;IE and HE sent to ULN2003.
INI_HE_OUTPUT_TYPE_1:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x01
    BTFSS	STATUS,Z
    GOTO	INI_HE_OUTPUT_TYPE_2

    SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		HE_LATCH_CLK
    NOP
    NOP
    BSF		HE_LATCH_CLK

    GOTO	INI_HE_END_PROCESS

;IE sent to AM26LS31 and HE sent to ULN2003.
INI_HE_OUTPUT_TYPE_2:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x02
    BTFSS	STATUS,Z
    GOTO	INI_HE_OUTPUT_TYPE_3

    SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		HE_LATCH_CLK
    NOP
    NOP
    BSF		HE_LATCH_CLK

    GOTO	INI_HE_END_PROCESS

;HE sent to AM26LS31 and IE sent to ULN2003.
INI_HE_OUTPUT_TYPE_3:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x03
    BTFSS	STATUS,Z
    GOTO	INI_HE_END_PROCESS

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		HE_LATCH_CLK
    NOP
    NOP
    BSF		HE_LATCH_CLK
    
INI_HE_END_PROCESS:
;***********************************************************************
;Allows for bypass of MAIN_INI.
MAIN_INI_RUN:
;-----------------------------------------------------------------------
;Turn off CW and CCW LED's to indicate STOP.
    BCF		LED_CW
    BCF		LED_CCW
;***********************************************************************
MAIN:
;-----------------------------------------------------------------------
    BTFSS	UP_SW
    GOTO	MAIN
;-----------------------------------------------------------------------
    BTFSS	DOWN_SW
    GOTO	MAIN
;-----------------------------------------------------------------------
    BTFSS	LEFT_SW
    GOTO	MAIN
;-----------------------------------------------------------------------
    BTFSS	RIGHT_SW
    GOTO	MAIN
;-----------------------------------------------------------------------
    BTFSS	ENTER_SW
    GOTO	MAIN_INI
;-----------------------------------------------------------------------
    BTFSS	START_STOP_SW
    GOTO	RUN_MAIN
;-----------------------------------------------------------------------
;   BTFSS	ESTOP_SW
;   GOTO	ESTOP_IN_PROCESS
;-----------------------------------------------------------------------
    GOTO	MAIN
;***********************************************************************
;Process Subroutines.
;-----------------------------------------------------------------------
RUN_MAIN:
;-----------------------------------------------------------------------
    BTFSC	START_STOP_SW		;Is the START/STOP switch on?
    GOTO	MAIN_INI_RUN		;No, so go back to MAIN.
;***********************************************************************

;*************************************************************************
;Program's Simulation Subroutines
;***********************************************************************


;***********************************************************************
;INCREMENTAL ENCODER SIMULATION
;***********************************************************************
    

;***********************************************************************
;TEST VALUES FOR ZPULSE. 1002d = 0x3EA.
;-----------------------------------------------------------------------
;IE_MAIN:	;REMOVE THIS WHEN EDITOR IS COMPLETE.
;   MOVLW	0x03
;   MOVWF	IE_COMPARE_HIGH_BYTE
;   MOVLW	0xEA
;   MOVWF	IE_COMPARE_LOW_BYTE
;-----------------------------------------------------------------------
;Sequence through pattern in forward or reverse direction.
IE_FWD_REV_SELECT:
    CALL	SWITCH_DEBOUNCE
    BTFSC	FWD_REV_SW
    GOTO	IE_RUN_REV
;-----------------------------------------------------------------------
;Incremental Encoder Run Forward (B Pulse leads A Pulse).
IE_RUN_FWD:
;-----------------------------------------------------------------------    
;Turn on CW LED, and turn off CCW LED.
    BSF		LED_CW
    BCF		LED_CCW
;-----------------------------------------------------------------------
;Test switch inputs within the Run Forward loop.
;-----------------------------------------------------------------------
    BTFSC	START_STOP_SW		;Is the START/STOP SWITCH on?
    GOTO	MAIN_INI_RUN		;No, so go back to MAIN.
;-----------------------------------------------------------------------
;Sequence through pattern in forward or reverse direction.
    BTFSC	FWD_REV_SW
    GOTO	IE_RUN_REV
;-----------------------------------------------------------------------
;For Forward Direction (FWD_REV_SW IS CLOSED)....
;This determines where the Z Pulse will trigger at in relation to the
;A or B Pulse's Leading or Trailing Edges.
    MOVFW	IE_Z_PULSE_VALUE_FWD
    MOVWF	IE_Z_PULSE_POSITION
;-----------------------------------------------------------------------
;If Three Phase Tach Mode is selected, jump to the CALL to HE_MAIN. Thus
;skipping over the calculations to fire the Hall Effect Output. This will
;allow a faster frequency Hall Effect Output.
;    BTFSS      TPTACH_SELECT
;    GOTO	HE_MAIN_FWD
;-----------------------------------------------------------------------
;If the HE Bypass Jumper is jumped out, skip over the Hall Effect routine.
;This will remove the Incremental Encoder waveform jitter.
;Bypass Jumper installed = skip over the Hall Effect routine.
;    BTFSS      HE_BYPASS
;    GOTO	HE_TRIGGER_END_FWD
;-----------------------------------------------------------------------
;Combine the Incremental Encoder and Hall Effect signals.
;When Pulse Counter = 1000/6 = (0xA7) then send the Hall Effect signal.

;Long Counter for trigger Hall Effect Outputs.
    INCF	PC_IE_LOW_BYTE,F
    BTFSC	STATUS,Z
    INCF	PC_IE_HIGH_BYTE,F

;Set trigger the Hall Effect Output if PC_IE_HIGH_BYTE = HE_TRIGGER__HIGH_BYTE
;and PC_IE_LOW_BYTE = HE_TRIGGER_LOW_BYTE.
    MOVF	PC_IE_HIGH_BYTE,W
    SUBWF	HE_TRIGGER__HIGH_BYTE,W
    BTFSS	STATUS,Z
    GOTO	HE_TRIGGER_END_FWD

    MOVF	PC_IE_LOW_BYTE,W
    SUBWF	HE_TRIGGER__LOW_BYTE,W
    BTFSS	STATUS,Z
    GOTO	HE_TRIGGER_END_FWD

HE_MAIN_FWD:
    CALL	HE_MAIN
    CLRF	PC_IE_HIGH_BYTE
    CLRF	PC_IE_LOW_BYTE

HE_TRIGGER_END_FWD:
;-----------------------------------------------------------------------
Z_RUN_FWD:
    CALL	Z_OUT_PULSE_TRIGGER
;-----------------------------------------------------------------------
    CALL	POTENTIOMETER
;-----------------------------------------------------------------------
    INCF	I_IE,F

    MOVF	I_IE,W			;Move I Index to the W Register.
    SUBLW	0x04			;Subtract 4 decimal from the W Register.
    BTFSS	STATUS,Z		;Test the Z Flag.
    GOTO	IE_PROCESS		;I Index not equal to 4 decimal, so go to PROCESS.
    MOVLW	0x00			;The lowest I Index value is 0 decimal.
    MOVWF	I_IE			;Move 0 decimal to I Index.
    GOTO	IE_PROCESS
;-----------------------------------------------------------------------
;Incremental Encoder Run Reverse (A Pulse leads B Pulse).
IE_RUN_REV:
;-----------------------------------------------------------------------    
;Turn on CCW LED, and turn off CW LED.
    BCF		LED_CW
    BSF		LED_CCW
;-----------------------------------------------------------------------
;Test switch inputs within the Run Forward loop.
;-----------------------------------------------------------------------
    BTFSC	START_STOP_SW		;Is the START/STOP SWITCH on?
    GOTO	MAIN_INI_RUN		;No, so go back to MAIN.
;-----------------------------------------------------------------------
;Sequence through pattern in forward or reverse direction.
    BTFSS	FWD_REV_SW
    GOTO	IE_RUN_FWD
;-----------------------------------------------------------------------
;For Reverse Direction (FWD_REV_SW IS OPEN)....
;This determines where the Z Pulse will trigger at in relation to the
;A or B Pulse's Leading or Trailing Edges.
    MOVFW	IE_Z_PULSE_VALUE_REV
    MOVWF	IE_Z_PULSE_POSITION
;-----------------------------------------------------------------------
;If Three Phase Tach Mode is selected, jump to the CALL to HE_MAIN. Thus
;skipping over the calculations to fire the Hall Effect Output. This will
;allow a faster frequency Hall Effect Output.
;    BTFSS      TPTACH_SELECT
;    GOTO	HE_MAIN_REV
;-----------------------------------------------------------------------
;If the HE Bypass Jumper is jumped out, skip over the Hall Effect routine.
;This will remove the Incremental Encoder waveform jitter.
;Bypass Jumper installed = skip over the Hall Effect routine.
;    BTFSS      HE_BYPASS
;    GOTO	HE_TRIGGER_END_REV
;-----------------------------------------------------------------------
;Combine the Incremental Encoder and Hall Effect signals.
;When Pulse Counter = 1000/6 = (0xA7) then send the Hall Effect signal.

;Long Counter for trigger Hall Effect Outputs.
    INCF	PC_IE_LOW_BYTE,F
    BTFSC	STATUS,Z
    INCF	PC_IE_HIGH_BYTE,F

;Set trigger the Hall Effect Output if PC_IE_HIGH_BYTE = HE_TRIGGER__HIGH_BYTE
;and PC_IE_LOW_BYTE = HE_TRIGGER_LOW_BYTE.
    MOVF	PC_IE_HIGH_BYTE,W
    SUBWF	HE_TRIGGER__HIGH_BYTE,W
    BTFSS	STATUS,Z
    GOTO	HE_TRIGGER_END_REV

    MOVF	PC_IE_LOW_BYTE,W
    SUBWF	HE_TRIGGER__LOW_BYTE,W
    BTFSS	STATUS,Z
    GOTO	HE_TRIGGER_END_REV

HE_MAIN_REV:
    CALL	HE_MAIN
    CLRF	PC_IE_HIGH_BYTE
    CLRF	PC_IE_LOW_BYTE

HE_TRIGGER_END_REV:
;-----------------------------------------------------------------------
Z_RUN_REV:
    CALL	Z_OUT_PULSE_TRIGGER
;-----------------------------------------------------------------------
    CALL	POTENTIOMETER
;-----------------------------------------------------------------------
    DECF	I_IE,F

    MOVF	I_IE,W			;Move I Index to the W Register.
    SUBLW	0xFF			;Subtract -1 decimal from the W Register.
    BTFSS	STATUS,Z		;Test the Z Flag.
    GOTO	IE_PROCESS		;I Index not equal to 0 decimal, so go to PROCESS.
    MOVLW	0x03			;The highest I Index value is 3 decimal.
    MOVWF	I_IE			;Move 3 decimal to I Index.
;-----------------------------------------------------------------------
;-----------------------------------------------------------------------
IE_PROCESS:
;-----------------------------------------------------------------------
;Send Incremental Encoder Pattern to Data Bus PortB, contiuously looping
;based upon the variable LOOP_TIME, and delayed for the duration of
;variable DELAY_TIME.
;-----------------------------------------------------------------------
    MOVF	IE_COMPARE_FLAG,W
    SUBLW	0x01
    BTFSC	STATUS,Z
    GOTO	IE_Z_PULSE_PATTERN_CALL
    MOVF	I_IE,W
    CALL	IE_PATTERN

;Store pattern in Temp File before SWAPF.
    MOVWF	TEMP_FILE
;-----------------------------------------------------------------------
;IE and HE sent to AM26LS31.
IE_OUTPUT_TYPE_0:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x00
    BTFSS	STATUS,Z
    GOTO	IE_OUTPUT_TYPE_1

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		IE_LATCH_CLK
    NOP
    NOP
    BSF		IE_LATCH_CLK

    GOTO	IE_PROCESS_TIME

;IE and HE sent to ULN2003.
IE_OUTPUT_TYPE_1:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x01
    BTFSS	STATUS,Z
    GOTO	IE_OUTPUT_TYPE_2

    SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		IE_LATCH_CLK
    NOP
    NOP
    BSF		IE_LATCH_CLK

    GOTO	IE_PROCESS_TIME

;IE sent to AM26LS31 and HE sent to ULN2003.
IE_OUTPUT_TYPE_2:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x02
    BTFSS	STATUS,Z
    GOTO	IE_OUTPUT_TYPE_3

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		IE_LATCH_CLK
    NOP
    NOP
    BSF		IE_LATCH_CLK

    GOTO	IE_PROCESS_TIME

;HE sent to AM26LS31 and IE sent to ULN2003.
IE_OUTPUT_TYPE_3:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x03
    BTFSS	STATUS,Z
    GOTO	IE_PROCESS_TIME

    SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		IE_LATCH_CLK
    NOP
    NOP
    BSF		IE_LATCH_CLK

    GOTO	IE_PROCESS_TIME
;-----------------------------------------------------------------------
IE_Z_PULSE_PATTERN_CALL:
    MOVF	I_IE,W
    CALL	IE_Z_PULSE_PATTERN

;Store pattern in Temp File before SWAPF.
    MOVWF	TEMP_FILE

;IE and HE sent to AM26LS31.
IE_Z_OUTPUT_TYPE_0:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x00
    BTFSS	STATUS,Z
    GOTO	IE_Z_OUTPUT_TYPE_1

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		IE_LATCH_CLK
    NOP
    NOP
    BSF		IE_LATCH_CLK

    GOTO	SET_Z_PULSE_WIDTH

;IE and HE sent to ULN2003.
IE_Z_OUTPUT_TYPE_1:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x01
    BTFSS	STATUS,Z
    GOTO	IE_Z_OUTPUT_TYPE_2

    SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		IE_LATCH_CLK
    NOP
    NOP
    BSF		IE_LATCH_CLK

    GOTO	SET_Z_PULSE_WIDTH

;IE sent to AM26LS31 and HE sent to ULN2003.
IE_Z_OUTPUT_TYPE_2:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x02
    BTFSS	STATUS,Z
    GOTO	IE_Z_OUTPUT_TYPE_3

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		IE_LATCH_CLK
    NOP
    NOP
    BSF		IE_LATCH_CLK

    GOTO	SET_Z_PULSE_WIDTH

;HE sent to AM26LS31 and IE sent to ULN2003.
IE_Z_OUTPUT_TYPE_3:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x03
    BTFSS	STATUS,Z
    GOTO	SET_Z_PULSE_WIDTH

    SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		IE_LATCH_CLK
    NOP
    NOP
    BSF		IE_LATCH_CLK

;Set the width of the Z Pulse.
SET_Z_PULSE_WIDTH:
    INCF	IE_Z_PULSE_DURATION,F
    MOVF	IE_Z_PULSE_DURATION,W
    SUBWF	IE_Z_PULSE_WIDTH_VALUE,W	;This is set at initial programming.
    BTFSS	STATUS,Z
    GOTO	IE_PROCESS_TIME

;Reset the Z Pulse variables.
    CLRF	IE_COMPARE_FLAG
    CLRF	IE_Z_PULSE_DURATION

IE_PROCESS_TIME:
    MOVF	LOOP_TIME,W
    SUBLW	0x00
    BTFSC	STATUS,Z
    GOTO	IE_END_PROCESS

    CALL	DELAY_TIMELOOP
    MOVLW	0x01
    SUBWF	LOOP_TIME,F
    GOTO	IE_FWD_REV_SELECT

IE_END_PROCESS:
    GOTO	RUN_MAIN
;***********************************************************************
Z_OUT_PULSE_TRIGGER:
;-----------------------------------------------------------------------
;The full A Pulse cycle consists of four patterns.
;When I_IE... 	A Pulse is...
;	0				High
;	1				Low
;	2				Low
;	3				High

;The full B Pulse cycle consists of four patterns.
;When I_IE... 	B Pulse is...
;	0				Low
;	1				Low
;	2				High
;	3				High

;And thus, if we look at I_IE to see when we have reached 3, we know
;we have made a full encoder pulse cycle. And then we can increment
;the long counter. Otherwise, skip the long counter routine.
;This has the added benefit of being able to position the point at
;which the Z Pulse triggers in relation to the A or B Pulse. To get
;the proper Z Pulse alignment to the A or B Pulses in either direction
;we must use different I_IE values. That is the reason for the
;IE_Z_PULSE_POSITION variable. It changes depending upon the FWD_REV_SW
;being closed or open.
    MOVF	I_IE,W
    SUBWF	IE_Z_PULSE_POSITION	;This value is set by the FWD_REV_SW.
    BTFSS	STATUS,Z
    GOTO	IE_END_LONG_COUNTCOMPARE
;-----------------------------------------------------------------------
;Are we rotating CW(FWD) or CCW(REV)?	FWD = CLOSED, REV = OPENED.
    BTFSC	FWD_REV_SW
    GOTO	IE_LONG_COUNT_REV
;-----------------------------------------------------------------------
;This counter will count from 0x00 to 0xFFFF, and then reset to 0x00
;and start again.
IE_LONG_COUNT_FWD:
    INCF	N_IE,F		;Increment the Low byte
    BTFSC	STATUS,Z	;Do we have Zero (Multiple of 256)?
    INCF	M_IE,F		;Increment High byte (if necessary)

;Set IE_COMPARE_FLAG if M_IE = IE_COMPARE_HIGH_BYTE and N_IE = IE_COMPARE_LOW_BYTE.
IE_LONG_COUNTCOMPARE_FWD:
    MOVF	M_IE,W
    SUBWF	IE_COMPARE_HIGH_BYTE,W
    BTFSS	STATUS,Z
    GOTO	IE_END_LONG_COUNTCOMPARE

    MOVF	N_IE,W
    SUBWF	IE_COMPARE_LOW_BYTE,W
    BTFSS	STATUS,Z
    GOTO	IE_END_LONG_COUNTCOMPARE

    MOVLW	0x01
    MOVWF	IE_COMPARE_FLAG

;Reset the Z Pulse Long Counters.
    CLRF	M_IE
    CLRF	N_IE

    GOTO	IE_END_LONG_COUNTCOMPARE
;-----------------------------------------------------------------------
;This counter will count from 0xFFFF to 0x00, and then reset to 0xFFFF
;and start again.
IE_LONG_COUNT_REV:
    MOVF	N_IE,F		;Set "Z" if LOW "Reg" == 0
    BTFSC	STATUS,Z
    DECF	M_IE,F		;If Low byte is Zero, Decrement High
    DECF	N_IE,F

;Set IE_COMPARE_FLAG if M_IE = 0x00 and N_IE = 0x00.
IE_LONG_COUNTCOMPARE_REV:
    MOVF	M_IE,W
    SUBLW	0x00
    BTFSS	STATUS,Z
    GOTO	IE_END_LONG_COUNTCOMPARE

    MOVF	N_IE,W
    SUBLW	0x00
    BTFSS	STATUS,Z
    GOTO	IE_END_LONG_COUNTCOMPARE

    MOVLW	0x01
    MOVWF	IE_COMPARE_FLAG

;Reset the Z Pulse Long Counters.
    MOVF	IE_COMPARE_HIGH_BYTE,W
    MOVWF	M_IE

    MOVF	IE_COMPARE_LOW_BYTE,W
    MOVWF	N_IE
;-----------------------------------------------------------------------
IE_END_LONG_COUNTCOMPARE:
    RETURN
;-----------------------------------------------------------------------

;***********************************************************************
;HALL EFFECT SIMULATION
;***********************************************************************


;***********************************************************************
HE_MAIN:
;-----------------------------------------------------------------------
;Sequence through pattern in forward or reverse direction.
HE_FWD_REV_SELECT:
;    CALL	SWITCH_DEBOUNCE
;    BTFSC	FWD_REV_SW
;    GOTO	HE_RUN_REV
;-----------------------------------------------------------------------
;Hall Effect Run Forward.
HE_RUN_FWD:
;-----------------------------------------------------------------------
;Test switch inputs within the Run Forward loop.
;-----------------------------------------------------------------------
;    BTFSC	START_STOP_SW		;Is the START/STOP SWITCH on?
;    GOTO	MAIN_INI_RUN		;No, so go back to MAIN.
;-----------------------------------------------------------------------
;Sequence through pattern in forward or reverse direction.
    BTFSC	FWD_REV_SW
    GOTO	HE_RUN_REV
;-----------------------------------------------------------------------
    INCF	I_HE,F

    MOVF	I_HE,W			;Move I Index to the W Register.
    SUBLW	0x06			;Subtract 6 decimal from the W Register.
    BTFSS	STATUS,Z		;Test the Z Flag.
    GOTO	HE_PROCESS		;I Index not equal to 6 decimal, so go to PROCESS.
    MOVLW	0x00			;The lowest I Index value is 0 decimal.
    MOVWF	I_HE			;Move 0 decimal to I Index.
    GOTO	HE_PROCESS
;-----------------------------------------------------------------------
;Hall Effect Run Reverse.
HE_RUN_REV:
;-----------------------------------------------------------------------
;Test switch inputs within the Run Forward loop.
;-----------------------------------------------------------------------
;    BTFSC	START_STOP_SW		;Is the START/STOP SWITCH on?
;    GOTO	MAIN_INI_RUN		;No, so go back to MAIN.
;-----------------------------------------------------------------------
;Sequence through pattern in forward or reverse direction.
    BTFSS	FWD_REV_SW
    GOTO	HE_RUN_FWD
;-----------------------------------------------------------------------
    DECF	I_HE,F

    MOVF	I_HE,W			;Move I Index to the W Register.
    SUBLW	0xFF			;Subtract -1 decimal from the W Register.
    BTFSS	STATUS,Z		;Test the Z Flag.
    GOTO	HE_PROCESS		;I Index not equal to 0 decimal, so go to PROCESS.
    MOVLW	0x05			;The highest I Index value is 5 decimal.
    MOVWF	I_HE			;Move 5 decimal to I Index.
;-----------------------------------------------------------------------
HE_PROCESS:
;-----------------------------------------------------------------------
;Send Hall Effect Pattern to Data Bus PortB, contiuously looping based upon
;the variable LOOP_TIME, and delayed for the duration of variable DELAY_TIME.
;-----------------------------------------------------------------------
    MOVF	I_HE,W
    CALL	HE_PATTERN

;Store pattern in Temp File.
    MOVWF	TEMP_FILE
;-----------------------------------------------------------------------
;IE and HE sent to AM26LS31.
HE_OUTPUT_TYPE_0:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x00
    BTFSS	STATUS,Z
    GOTO	HE_OUTPUT_TYPE_1

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		HE_LATCH_CLK
    NOP
    NOP
    BSF		HE_LATCH_CLK

    GOTO	HE_END_PROCESS

;IE and HE sent to ULN2003.
HE_OUTPUT_TYPE_1:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x01
    BTFSS	STATUS,Z
    GOTO	HE_OUTPUT_TYPE_2

    SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		HE_LATCH_CLK
    NOP
    NOP
    BSF		HE_LATCH_CLK

    GOTO	HE_END_PROCESS

;IE sent to AM26LS31 and HE sent to ULN2003.
HE_OUTPUT_TYPE_2:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x02
    BTFSS	STATUS,Z
    GOTO	HE_OUTPUT_TYPE_3

    SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		HE_LATCH_CLK
    NOP
    NOP
    BSF		HE_LATCH_CLK

    GOTO	HE_END_PROCESS

;HE sent to AM26LS31 and IE sent to ULN2003.
HE_OUTPUT_TYPE_3:
    MOVFW	OC_DIFR_SEL_FLAG
    SUBLW	0x03
    BTFSS	STATUS,Z
    GOTO	HE_END_PROCESS

;Send the pattern to the PORTB (Databus).
    MOVFW	TEMP_FILE
    MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
    BCF		HE_LATCH_CLK
    NOP
    NOP
    BSF		HE_LATCH_CLK

HE_END_PROCESS:
    RETURN

;*************************************************************************
;Program's Subroutines
;***********************************************************************

;***********************************************************************
;ADC Setup Time Delay Subroutine. 20 microseconds.
;-----------------------------------------------------------------------
DEL_20:
    MOVLW	0x07		;Delay 20 microseconds.
    MOVWF	J
DEC_20:
    DECFSZ	J,F
    GOTO	DEC_20		;Repeat until J = 0.
    RETURN
;***********************************************************************
;Hall Effect Process Time Delay Subroutine.
;-----------------------------------------------------------------------
DELAY_TIMELOOP:
    MOVF	DELAY_TIME,W	;Load J Counter with Loop Count.
    MOVWF	J
LOAD_K:
    MOVF	DELAY_TIME,W	;Load K Counter with Loop Count.
    MOVWF	K
DEC_K:
    DECFSZ	K,F		;Decrement the K Counter.
    GOTO	DEC_K		;Z Flag not equal to zero.
    DECFSZ	J,F		;Decrement the J Counter.
    GOTO	LOAD_K		;Z Flag not equal to zero.
    RETURN			;End of time delay.
;***********************************************************************
;Switch Debounce Time Delay Subroutine.
;-----------------------------------------------------------------------
SWITCH_DEBOUNCE:
    MOVLW	0x0F		;Load J Counter with Loop Count.
    MOVWF	J
SD_LOAD_K:
    MOVLW	0x0F		;Load K Counter with Loop Count.
    MOVWF	K
SD_DEC_K:
    DECFSZ	K,F		;Decrement the K Counter.
    GOTO	SD_DEC_K	;Z Flag not equal to zero.
    DECFSZ	J,F		;Decrement the J Counter.
    GOTO	SD_LOAD_K	;Z Flag not equal to zero.
    RETURN			;End of time delay.
;***********************************************************************
;General Purpose Time Delay Subroutine.
;-----------------------------------------------------------------------
GP_DELAY:
    MOVLW	0x7F		;Load J Counter with Loop Count.
    MOVWF	J
GP_LOAD_K:
    MOVLW	0x7F		;Load K Counter with Loop Count.
    MOVWF	K
GP_DEC_K:
    DECFSZ	K,F		;Decrement the K Counter.
    GOTO	GP_DEC_K	;Z Flag not equal to zero.
    DECFSZ	J,F		;Decrement the J Counter.
    GOTO	GP_LOAD_K	;Z Flag not equal to zero.
    RETURN			;End of time delay.
;***********************************************************************
;Analog to Digital Converter routine to get voltage from potentiometer.
;And based upon the potentiometer setting, speed up or slow down the
;Hall Effect Pattern and Incremental Encoder Pattern sent to PORTC.
POTENTIOMETER:
;-----------------------------------------------------------------------
;Switch to Bank 0, because this Bank contains the registers ADCON0.
;   BCF		STATUS,RP1
;   BCF		STATUS,RP0	;Select Bank 0
    BANKSEL	ADCON0
;-----------------------------------------------------------------------
    MOVLW	0x00		;Initialize ADCMEM_HI and ADCMEM_LO to zero.
    MOVWF	ADCMEM_HI
    MOVWF	ADCMEM_LO
;-----------------------------------------------------------------------
    CALL	DEL_20		;Delay 20 microseconds.
    BSF		ADCON0,GO	;Start A/D conversion.

ADC_GO_DONE:
    BTFSC	ADCON0,GO	;Test GO/DONE bit.
    GOTO	ADC_GO_DONE	;Still processing, so go back to ADC_GO_DONE.

    MOVF	ADRESH,W	;Get A/D Conversion High Byte value.
    MOVWF	ADCMEM_HI	;Store A/D Conversion value in Tempory
                        ;Memory High.
;-----------------------------------------------------------------------
;Switch to Bank 1, because this Bank contains the registers for ADRESL.
;   BSF		STATUS,RP0	;Select Bank 1.
    BANKSEL	ADRESL
;-----------------------------------------------------------------------
    MOVF	ADRESL,W	;Get A/D Conversion Low Byte value.
;-----------------------------------------------------------------------
;Switch to Bank 0, because this Bank contains the registers
;for PORTA, PORTB, PORTC, and ADCON0.
;   BCF		STATUS,RP0	;Select Bank 0
    BANKSEL	ADCON0
;-----------------------------------------------------------------------
    MOVWF	ADCMEM_LO	;Store A/D Conversion value in Tempory
				;Memory Low.
;-----------------------------------------------------------------------
    MOVF	ADCMEM_HI,W	;Move ADC to Time Period.
    MOVWF	LOOP_TIME
    MOVWF	DELAY_TIME

;-----------------------------------------------------------------------
;   BTFSC	ESTOP_SW	;Is EMERGENCY STOP switch on?
;-----------------------------------------------------------------------
    RETURN
;-----------------------------------------------------------------------

;-----------------------------------------------------------------------
;Turn off Hall Effect Pattern at PORTC and turn Tri-state AM26LS31.
;WARNING...YOU MUST TURN OFF POWER TO RESET FROM AN EMERGENCY STOP!!!
ESTOP_IN_PROCESS:
    CALL	SWITCH_DEBOUNCE

;DISABLE OUTPUTS HERE....

    GOTO	ESTOP_IN_PROCESS	;MUST POWER DOWN BECAUSE OFF ENDLESS LOOP.
;*************************************************************************
;SPI Output Subroutine.
;TXD_SPI:
;-----------------------------------------------------------------------
;    BCF		SS			;Enable Chip Select Output (Low).
;    MOVF	TXDATA,W		;Get Char to W.
;    MOVWF	SSPBUF			;Put in SSPBUF.
;    BANKSEL	SSPSTAT			;Bank 1.
;CHAR1:
;    BTFSS	SSPSTAT,BF		;Data transfer complete? (Buffer Full?)
;    GOTO	CHAR1			;If not, check again.
;    BANKSEL	SSPBUF			;Bank 0.
;    MOVF	SSPBUF,W		;Read SSPBUF register data is not used.
;    BSF		SS			;Disable slave select output (High).

;    RETURN
;-----------------------------------------------------------------------
    END
;*************************************************************************
;Programmer's Notes:
;-----------------------------------------------------------------------
;18 Jun 07
;Test hardware and code at the shop. Viewed waveforms
;on oscilloscope with good 120 degree phase shift
;between HE1, HE2, and HE3.

;ENABLE Switch functioned good.
;FWDREV Switch functioned good.

;The fastest frequency was 909Hz.
;The slowest at about 1Hz.
;*************************************************************************
;Revision History:
;-----------------------------------------------------------------------
;17 Jun 07
;First release

;19 Jun 07
;Changed code from this...
;	MOVF	I,W
;	CALL	HE_PATTERN
;	MOVWF	PORTC

;PROCESSTIMEFWD:
;	MOVF	LOOP_TIME,W
;	SUBLW	0x00
;	BTFSS	STATUS,Z			;This changed.
;	GOTO	PROCESSTIME1FWD		;This changed.
;	GOTO	ENDPROCESSFWD		;This changed.

;PROCESSTIME1FWD:					;This changed.
;	CALL	DELAY_TIME
;	MOVLW	0x01
;	SUBWF	LOOP_TIME,F
;	GOTO	HE_RUN_FWD

;ENDPROCESSFWD:
;	GOTO	IE_MAIN


;To this...
;	MOVF	I,W
;	CALL	HE_PATTERN
;	MOVWF	PORTC

;PROCESSTIMEFWD:
;	MOVF	LOOP_TIME,W
;	SUBLW	0x00
;	BTFSC	STATUS,Z
;	GOTO	ENDPROCESSFWD

;	CALL	DELAY_TIME
;	MOVLW	0x01
;	SUBWF	LOOP_TIME,F
;	GOTO	HE_RUN_FWD

;ENDPROCESSFWD:
;	GOTO	IE_MAIN


;And added these Inputs and Outputs to add the ability to
;select if the Hall Effect patterns go to Opto-Couplers
;or AM26LS31.

;#DEFINE    OC_DIFF_SW	PORTA,3	;Determine if PORTC Hall Effect
                                ;Pattern goes to Opto-Couplers or
                                ;AM26LS31. (Switch Input)
;#DEFINE    OC_DIFF_OUT	PORTA,5	;Output to 74HC244 and 26LS31 Enables.


;And added the ability to shut down the Hall Effect Simulator's
;Outputs in the event that things go badly while troubleshooting
;a servodrive with this tester.

;#DEFINE    ESTOP_SW   PORTA,4	;Emergency Stop the PORTC output.
                                ;(Completely turn off PORTC outputs)
                                ;(Switch Input)


;20 Jun 07
;Set up the OC_DIFF_SW as a push button. I have a toggle
;flag (OC_DIFF_FLAG) to determine if the Hall Effect
;Pattern at PORTC is sent to the Opto-Couplers or
;the AM26LS31.

;Added CLRF PORTC to HE_OC_DIFF_SELECT routine so that
;when we change from Opto-Coupler outputs to
;AM26LS31 outputs, and visa-vie, there is no Hall Effect
;Pattern "left" on the PORTC after the change.

;23 Jun 07
;Added the Incremental Encoder routine. The HE_IE_SW switch
;input determines if the Hall Effect Pattern routine is
;used, or the Incremental Encoder Pattern routine is used.
;This must be decided before power is applied so that we
;don't change from one pattern to the other while the
;pattern is running. If the simulator is connected to
;a servodrive, switching the patterns may cause problems.

;At this moment, the Incremental Encoder Z_Pulse is fixed
;to pulse when the A/B Output count reaches 500 pulses.

;I plan on having a programmable count at which point the
;Z_Pulse will trigger on.
;-----------------------------------------------------------------------
;19-20 Nov 08	hes10

;I have revised the code to fit the hardware changes.
;I started block-diagramming the function 12-16 Nov 08.
;I started constructing the circuit on 18 Nov 08.
;-----------------------------------------------------------------------
;1-3 Dec 08
;Streamlined code. Removed redundancy.
;-----------------------------------------------------------------------
;5 Dec 08
;Fixed code so that a full Z pulse is output, instead
;of a blip.
;-----------------------------------------------------------------------
;9 Dec 08
;Set up the SPI initialization code.

;Started using the BANKSEL directive to switch banks.
;-----------------------------------------------------------------------
;4 Feb 09
;Added an XOR test to see if the A and B Pulses are both
;high before allowing the Z pulse subroutine to be accessed.
;This will fix the Z pulse to turn on only when A and B
;pulses are high. I haven't tested it yet in hardware.
;At this time the Z pulse 'hits' at any point in relation
;to the A and B pulse. A 'real' incremental encoder does
;not do this. Because the code wheel is a fixed entity.
;-----------------------------------------------------------------------
;6 Feb 09
;It did not work. I got multiple home pulses. Because the
;Z Pulse would only output when the A and B were high.
;When the A and B were low, the Z Pulse would be low.
;Then because I was still in the Z Pulse subroutine, the
;Z Pulse would go high again when the A and B Pulses were
;both high. I will have to think of another solution,
;so I made version hes11 to continue using the code
;without the XOR.
;-----------------------------------------------------------------------
;hes10 still has the XOR code.
;-----------------------------------------------------------------------
;Renamed Z_OUT_PULSE to Z_OUT_PULSE_TRIGGER.
;-----------------------------------------------------------------------
;hes12.
;I added the following code (shown below) to the
;Z_OUT_PULSE_TRIGGER	subroutine. This also fixed
;the problem with the Z Pulse triggering at arbitray
;times in relation to the A and B pulses.
;With the code the way it is now, the Z Pulse triggers
;on the falling edge of the A pulse. With a little bit
;of experimentation, I should be able to pick where I
;want it to trigger.
;-----------------------------------------------------------------------
;The full A Pulse cycle consists of four patterns.
;When I_IE... 	A Pulse is...
;	0				Low
;	1				Low
;	2				High
;	3				High

;And thus, if we look at I_IE to see when we have reached 3, we know
;we have made a full encoder pulse cycle. And then we can increment
;the long counter. Otherwise, skip the long counter routine.
;	MOVF	I_IE,W
;	SUBLW	0x03
;	BTFSS	STATUS,Z
;	GOTO	IE_END_LONG_COUNTCOMPARE
;-----------------------------------------------------------------------
;I changed the above code to this....

;	MOVF	I_IE,W
;	SUBWF	IE_Z_PULSE_POSITION	;This value is set by the FWD_REV_SW.
;	BTFSS	STATUS,Z
;	GOTO	IE_END_LONG_COUNTCOMPARE

;This has the added benefit of being able to position the point at
;which the Z Pulse triggers in relation to the A or B Pulse. To get
;the proper Z Pulse alignment to the A or B Pulses in either direction
;we must use different I_IE values. That is the reason for the
;IE_Z_PULSE_POSITION variable. It changes depending upon the FWD_REV_SW
;being closed or open.
;-----------------------------------------------------------------------

;***********************************************************************
;Z PULSE TRIGGER POSITION CHART.
;-----------------------------------------------------------------------
;FWD_REV_SW
;-----------------------------------------------------------------------
;IE_Z_PULSE_POSITION Value  CLOSED(FWD)		OPEN(REV)
;-----------------------------------------------------------------------
;0x00			    TE OF A		LE OF B
;-----------------------------------------------------------------------
;0x01			    LE OF B		LE OF A
;-----------------------------------------------------------------------
;0x02			    LE OF A		TE OF B
;-----------------------------------------------------------------------
;0x03			    TE OF B		TE OF A
;-----------------------------------------------------------------------
; LE = LEADING EDGE, TE = TRAILING EDGE
;-----------------------------------------------------------------------

;Near the beginning of the IE_RUN_FWD and IE_RUN_REV routines is the
;code shown below. For example, if you want the Z Pulse to trigger on
;the leading edge of the B Pulse, you would put a 0x01 into the
;IE_Z_PULSE_POSITION for the IE_RUN_FWD routine. A put a 0x00 into
;the IE_Z_PULSE_POSITION for the IE_RUN_REV routine.

;-----------------------------------------------------------------------
;This positions the Z Pulse to trigger on the leading edge of the B Pulse
;for Forward Direction (FWD_REV_SW is closed).
;	MOVLW	0x01
;	MOVWF	IE_Z_PULSE_POSITION
;-----------------------------------------------------------------------
;9 Feb 09
;With hes13 I am attempting to code the Z Pulse Trigger
;so that it acts like a real encoder. For example, I have
;a 1000 ppr incremental encoder. And I rotate CW for
;500 pulses, and then rotate CCW, I should hit the Z Pulse
;when I have reached 500 pulses. As of now, it is 1000 pulses
;in either direction to the Z Pulse.

;This code almost works, but there has to be an easier way
;that would work. So I programmed the IC for hes12 until
;I can think of a better way.


;Changed the Long Counters to this...

;Incrementing 16 Bit Number.
; incf    Reg, f	;  Increment the Low byte
; btfsc   STATUS, Z	;  Do we have Zero (Multiple of 256)?
; incf    Reg + 1, f	;  Increment High byte (if necessary)

;Decrementing 16 Bit Number.
; movf    Reg, f	;  Set "Z" if LOW "Reg" == 0
; btfsc   STATUS, Z
; decf    Reg + 1, f     ;  If Low byte is Zero, Decrement High
; decf    Reg, f

;And hes14 works just like an encoder should.
;-----------------------------------------------------------------------
;10 Feb 08
;Added the Grey Push Button LED's (2 each) to the circuit
;to tell us when we are in programming mode. The Grey
;Push Buttons allow the Incremental Encoder PPR and the
;Simulator's Output Type to be programmed into the program.

;Added the PROGRAM_IE_PPR and PROGRAM_OUTPUT_TYPE routines
;to the code so that we can change the Incremental Encoder's
;Pulses Per Revolution and the Output Type: ULN2003 or
;AM26LS31.

;How the 10 Feb 09 changes work......
;At power up, and after initialization, the LED_IE_PPR_PG
;LED blinks to indicate that we are in PROGRAM_IE_PPR mode.
;By pressing and holding the following key (see chart below),
;and then pressing the IE_PPR_PROG key the incremental
;encoder's PPR is set into the program.
;Then the LED_IE_PPR_PG LED stays steady on to indicate that
;this part of programming is finished.

;NOTE: If you press the IE_PPR_PROG key, without pressing and
;holding the following key (see chart below), the program defaults
;to 1000 pulses per revolution.

;Next the LED_OUT_TYP_PG LED blinks to indicate that we are in
;OUT_TYPE_PROG mode. By pressing and holding the following key
;(see chart below), and the pressing the OUT_TYPE_PROG key the
;Simulator's output is set into the program.

;NOTE: If you press the OUT_TYPE_PROG key, without pressing and
;holding the following key (see chart below), the program defaults
;to AM26LS31 Differential Outputs.

;PROGRAMMING CHART (* = DEFAULT)

;PROGRAM_IE_PPR MODE KEYS		OUT_TYPE_PROG MODE KEYS
; UP_SW.........50 PPR			*UP_SW......AM26LS31
; DOWN_SW......500 PPR			 DOWN_SW....ULN2003
;*LEFT_SW.....1000 PPR
; RIGHT_SW....2500 PPR
; ENTER_SW....5000 PPR

;NOTE: While the encoder simulation is STOPPED, ie. START_STOP_SW
;is opened. You can press the ENTER_SW to get back into programming
;mode to change the Incremental Encoder's ppr and the Simulator's
;Output Type. This also re-initializes all of the program variables.

;-----------------------------------------------------------------------
;Added this to the PROGRAM_IE_PPR mode code to set the
;point at which the Hall Effect Outputs trigger. This point
;is 1/6th of the PPR. Each PPR has its own Hall Effect trigger
;point because of the different PPR selections.

;Set the Incremental Encoder count were the Hall Effect Outputs trigger.
;1000/6 = $00A6
;	MOVLW	0x00
;	MOVWF	HE_TRIGGER__HIGH_BYTE
;	MOVLW	0xA6
;	MOVWF	HE_TRIGGER__LOW_BYTE

;And added this to the forward and reverse routines. It counts
;the number of Incremental Encoder Pulses with PC_IE_HIGH_BYTE
;and PC_IE_LOW_BYTE. Then it compares this value with
;HE_TRIGGER_HIGH_BYTE and HE_TRIGGER_LOW_BYTE. If they are
;equal a CALL is made to HE_MAIN where the HALL EFFECT OUTPUTS
;are processed. Then PC_IE_HIGH_BYTE and PC_IE_LOW_BYTE are cleared
;to again count from zero.
;If they are not equal, then the CALL and CLRF are skipped over.

;Combine the Incremental Encoder and Hall Effect signals.
;When Pulse Counter = 1000/6 = (0xA7) then send the Hall Effect signal.

;Long Counter for trigger Hall Effect Outputs.
;	INCF	PC_IE_LOW_BYTE,F
;	BTFSC	STATUS,Z
;	INCF	PC_IE_HIGH_BYTE,F

;Set trigger the Hall Effect Output if PC_IE_HIGH_BYTE = HE_TRIGGER__HIGH_BYTE
;and PC_IE_LOW_BYTE = HE_TRIGGER_LOW_BYTE.
;	MOVF	PC_IE_HIGH_BYTE,W
;	SUBWF	HE_TRIGGER__HIGH_BYTE,W
;	BTFSS	STATUS,Z
;	GOTO	HE_TRIGGER_END_REV

;	MOVF	PC_IE_LOW_BYTE,W
;	SUBWF	HE_TRIGGER__LOW_BYTE,W
;	BTFSS	STATUS,Z
;	GOTO	HE_TRIGGER_END_REV

;	CALL	HE_MAIN
;	CLRF	PC_IE_HIGH_BYTE
;	CLRF	PC_IE_LOW_BYTE
;HE_TRIGGER_END_REV:
;-----------------------------------------------------------------------
;11 Feb 09
;Added PROGRAM_IE_Z_PULSE_POSITION and PROGRAM_Z_PULSE_WIDTH
;routines to the code. The PROGRAM_IE_Z_PULSE_POSITION lets
;you program where the Z Pulse will trigger in relation to
;the A and B pulse edges. The PROGRAM_Z_PULSE_WIDTH routine
;lets you program the width of the Z Pulse.

;15 Jun 09
;Added the following code so that the outputs would be
;pre-loaded with an Incremental Encoder Pattern and a
;Hall Effect Pattern. I had to add this because I worked
;on an Indramat Servo Drive that required a proper Hall
;Effect Pattern. Otherwise it would trip on the 111 Hall
;Effect Pattern that was at the outputs when I first turned
;on the simulator. This code is placed right before the
;label "PROGRAM_IE_PPR".
;***********************************************************************
;Initialize outputs to Incremental Encoder Patterns.
;-----------------------------------------------------------------------
;	MOVF	I_IE,W
;	CALL	IE_PATTERN

;Store pattern in Temp File before SWAPF.
;	MOVWF	TEMP_FILE

;Select the Output IC. 1 = ULN2003. 0 = AM26LS31.
;	MOVFW	OC_DIFR_SEL_FLAG
;	SUBLW	0x00
;	BTFSS	STATUS,Z
;	SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;Send the pattern to the PORTB (Databus).
;	MOVFW	TEMP_FILE
;	MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
;	BCF		IE_LATCH_CLK
;	NOP
;	NOP
;	BSF		IE_LATCH_CLK
;-----------------------------------------------------------------------
;Initialize outputs to Hall Effect Patterns.
;-----------------------------------------------------------------------
;	MOVF	I_HE,W
;	CALL	HE_PATTERN

;Store pattern in Temp File.
;	MOVWF	TEMP_FILE

;Select the Output IC. 1 = ULN2003. 0 = AM26LS31.
;	MOVFW	OC_DIFR_SEL_FLAG
;	SUBLW	0x00
;	BTFSS	STATUS,Z
;	SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;Send the pattern to the PORTB (Databus).
;	MOVFW	TEMP_FILE
;	MOVWF	PORTB

;Latch the PORTB data into 74HC374 (IC3).
;	BCF		HE_LATCH_CLK
;	NOP
;	NOP
;	BSF		HE_LATCH_CLK
;-----------------------------------------------------------------------
;5 Mar 15
;I found that if I selected the ULN2003 Output, the IE Pattern and
;HE Pattern were not initialized to the Outputs. The above initialization
;code was located before the AM26LS31 and ULN2003 were selected. So the
;Outputs only initialized to AM26LS31 because the OC_DIFR_SEL_FLAG was
;always 0x00 when the above code was processed. To fix the bug I moved
;the code to after the Programming Routines and before the Main Routines.
;-----------------------------------------------------------------------
;7 Mar 15
;At the PROGRAM_OUTPUT_TYPE Routine...
;I added two more selections to the Output Type Programming Routine.
;The existing options are IE Pattern and HE Pattern to the AM26LS31.
;Or the IE Pattern and the HE Pattern to both the ULN2003.

;I add the selection options for the IE Pattern to AM26LS31 and the
;HE Pattern to ULN2003. Or the IE Pattern to the ULN2003 and the
;HE Pattern to the AM26LS31.

;I still have to code the actual process for the above selections.
;-----------------------------------------------------------------------
;7 Mar 15
;Started working on the IE_PROCESS to add the IE to AM26LS31 and HE to
;ULN2003. And HE to AM26LS31 and IE to ULN2003.
;-----------------------------------------------------------------------
;8 Mar 15
;Finished the IE_PROCESS and HE_PROCESS Code.

;This is what the old code looked like.

;-----------------------------------------------------------------------
;IE_PROCESS:
;-----------------------------------------------------------------------
;Send Incremental Encoder Pattern to Data Bus PortB, contiuously looping
;based upon the variable LOOP_TIME, and delayed for the duration of
;variable DELAY_TIME.
;-----------------------------------------------------------------------
;	MOVF	IE_COMPARE_FLAG,W
;	SUBLW	0x01
;	BTFSC	STATUS,Z
;	GOTO	IE_Z_PULSE_PATTERN_CALL
;	MOVF	I_IE,W
;	CALL	IE_PATTERN

;;Store pattern in Temp File before SWAPF.
;	MOVWF	TEMP_FILE

;;Select the Output IC. 1 = ULN2003. 0 = AM26LS31.
;	MOVFW	OC_DIFR_SEL_FLAG
;	SUBLW	0x00
;	BTFSS	STATUS,Z
;	SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;;Send the pattern to the PORTB (Databus).
;	MOVFW	TEMP_FILE
;	MOVWF	PORTB

;;Latch the PORTB data into 74HC374 (IC3).
;	BCF		IE_LATCH_CLK
;	NOP
;	NOP
;	BSF		IE_LATCH_CLK

;	GOTO	IE_PROCESS_TIME

;IE_Z_PULSE_PATTERN_CALL:
;	MOVF	I_IE,W
;	CALL	IE_Z_PULSE_PATTERN

;;Store pattern in Temp File before SWAPF.
;	MOVWF	TEMP_FILE

;;Select the Output IC. 1 = ULN2003. 0 = AM26LS31.
;	MOVFW	OC_DIFR_SEL_FLAG
;	SUBLW	0x00
;	BTFSS	STATUS,Z
;	SWAPF	TEMP_FILE,F		;Swap nibbles if sending to ULN2003.

;;Send the pattern to the PORTB (Databus).
;	MOVFW	TEMP_FILE
;	MOVWF	PORTB

;;Latch the PORTB data into 74HC374 (IC2).
;	BCF		IE_LATCH_CLK
;	NOP
;	NOP
;	BSF		IE_LATCH_CLK

;;Set the width of the Z Pulse.
;	INCF	IE_Z_PULSE_DURATION,F
;	MOVF	IE_Z_PULSE_DURATION,W
;	SUBWF	IE_Z_PULSE_WIDTH_VALUE,W	;This is set at initial programming.
;	BTFSS	STATUS,Z
;	GOTO	IE_PROCESS_TIME

;;Reset the Z Pulse variables.
;	CLRF	IE_COMPARE_FLAG
;	CLRF	IE_Z_PULSE_DURATION

;IE_PROCESS_TIME:
;	MOVF	LOOP_TIME,W
;	SUBLW	0x00
;	BTFSC	STATUS,Z
;	GOTO	IE_END_PROCESS

;	CALL	DELAY_TIMELOOP
;	MOVLW	0x01
;	SUBWF	LOOP_TIME,F
;	GOTO	IE_FWD_REV_SELECT

;IE_END_PROCESS:
;	GOTO	RUN_MAIN
;-----------------------------------------------------------------------
;9 Mat 15
;Tested the new code good.
;-----------------------------------------------------------------------
;11 May 15
;Coding for the Three Phase Tach PCB I made.
;Using PortE, Bit0 for the select input.
;1 = Normal Mode. 0 = Three Phase Tack Mode.
;-----------------------------------------------------------------------
;If Three Phase Tach Mode is selected, jump to the CALL to HE_MAIN. Thus
;skipping over the calculations to fire the Hall Effect Output. This will
;allow a faster frequency Hall Effect Output.
;    BTFSS   TPTACH_SELECT
;    GOTO    HE_MAIN_FWD
;-----------------------------------------------------------------------
;12 May 15
;Change FOSC1 and FOSC0 from 01 to 10, so that I could increase the
;simulated Encoder/Hall Effect frequency with a 20MHz Clock instead of
;the 4MHz Clock. I had to decrease the blink rate of the Push Button LED's.
;when setting of the Encoder/Hall Effect parameters at power up. I did this by
;adding three more calls to GPDELAY in the code that blinks the LED's.
;-----------------------------------------------------------------------
;9 Sep 16
;This file used to be TCHES. Now it is HESV0. And it is currently
;programmed into the PIC16F877A on the Hall Effect / Encoder Simulator.
;-----------------------------------------------------------------------
;14 Sep 16    
;Increased the CALL GPDLY for the blinking Programming LED's to compensate
;for the increase from 4MHz Clock to 20MHz Clock.

;In the IE_RUN_FWD and IE_RUN_REV, I Remarked out the code to select the
;3phase Tach Option. This is testing for the Jumper Block connected to
;PORTE Bit0.

;If Three Phase Tach Mode is selected, jump to the CALL to HE_MAIN. Thus
;skipping over the calculations to fire the Hall Effect Output. This will
;allow a faster frequency Hall Effect Output.
;    BTFSS      TPTACH_SELECT
;    GOTO	HE_MAIN_REV
;-----------------------------------------------------------------------
;I changed it to bypass the Hall Effect calculations if the Jumper Block
;is jumped out. Changed PORTE,0 from TPTACH to HE_BYPASS.
;-----------------------------------------------------------------------
;If the HE Bypass Jumper is jumped out, skip over the Hall Effect routine.
;This will remove the Incremental Encoder waveform jitter.
;Bypass Jumper installed = skip over the Hall Effect routine.
;    BTFSS      HE_BYPASS
;    GOTO	HE_TRIGGER_END_FWD
;-----------------------------------------------------------------------
;Modified the Initialization of the Outputs to add the other two combinations
;of AM26LS32 and ULN2003.
;Now at power up, the outputs initialize base upon the Output IC's that you
;program during the selection process with the Programming Push Buttons.
;This is a modification of the 15 Jun 09 code.

;The Outputs get pre-loaded to the following combinations of IC's.
;Incremental Encoder and Hall Effect to AM26LS32.
;Incremental Encoder and Hall Effect to ULN2003.
;Incremental Encoder to AM26LS32. And Hall Effect to ULN2003.
;Incremental Encoder to ULN2003. And Hall Effect to AM26LS32.
;-----------------------------------------------------------------------
;19 Sep 16
;I fixed the Incremental Encoder jitter problem. I did so by remarking out
;the code shown below in the HE_FWD and HE_REV routines.

;***********************************************************************
HE_MAIN:
;-----------------------------------------------------------------------
;Sequence through pattern in forward or reverse direction.
HE_FWD_REV_SELECT:
;    CALL	SWITCH_DEBOUNCE
;    BTFSC	FWD_REV_SW
;    GOTO	HE_RUN_REV
;-----------------------------------------------------------------------
;Hall Effect Run Forward.
HE_RUN_FWD:
;-----------------------------------------------------------------------
;Test switch inputs within the Run Forward loop.
;-----------------------------------------------------------------------
;    BTFSC	START_STOP_SW		;Is the START/STOP SWITCH on?
;    GOTO	MAIN_INI_RUN		;No, so go back to MAIN.
;-----------------------------------------------------------------------
;Sequence through pattern in forward or reverse direction.
    BTFSC	FWD_REV_SW
    GOTO	HE_RUN_REV
;-----------------------------------------------------------------------

    
    
    
    
;-----------------------------------------------------------------------
;Hall Effect Run Reverse.
HE_RUN_REV:
;-----------------------------------------------------------------------
;Test switch inputs within the Run Forward loop.
;-----------------------------------------------------------------------
;    BTFSC	START_STOP_SW		;Is the START/STOP SWITCH on?
;    GOTO	MAIN_INI_RUN		;No, so go back to MAIN.
;-----------------------------------------------------------------------
;Sequence through pattern in forward or reverse direction.
    BTFSS	FWD_REV_SW
    GOTO	HE_RUN_FWD
;-----------------------------------------------------------------------

;-----------------------------------------------------------------------
;20 Sep 16
;Because the jitter problem in the HE_MAIN routines is fixed. I remarked out
;the HE_BYPASS code.

;Added four green LED's to indicatate what type of Outputs are programmed.
;LED1 = HE Open Collector Output
;LED2 = HE Differential Output
;LED3 = IE Open Collector Output
;LED4 = IE Differential Output
    
;Remared out the SPI Code because it was going to be used for the Resolver
;Output. But I never got around to coding it.
;-----------------------------------------------------------------------    
;21 Sep 16
;Added a security key using J1 Jumper to PORTE,0
;If the J1 is jumped then continue on with the program. Otherwise if it is
;open perform the endless loop.
    
;***********************************************************************
;HES Simulator only works if J1 is jumpered.
HES_SIM_KEY:
    BTFSC	SIMULATOR_KEY	;If J1 is jumped out start the program.
    GOTO	HES_SIM_KEY	;Otherwise endless loop.
;***********************************************************************
    
;Change the above code to blink all the LED's on and off if J1 is not jumped.

;Added two red LED's to indicate CW or CCW Pattern Rotation.
;PORTE,2 to LED5 is CW, and PORTE,1 to LED6 is CCW.

