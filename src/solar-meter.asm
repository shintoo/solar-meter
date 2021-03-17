; ============================================================= ;
; File: solar-meter.asm                                         ;
; Author: Sean Rapp                                             ;
; Date: 03-15-2021                                              ;
; Platform: AVR ATMega328P                                      ;
; Assembler: avra                                               ;
; Program: 8-LED meter measuring solar cell voltage 0-5V        ;
; Configuration: 8 LEDS on Port D, solar cell + is on PC0       ;
; Caveat: I am a beginner at AVR assembly... beware!            ;
; ============================================================= ;


; ===============
; Declarations

; Includes
.nolist
.include "m328Pdef.inc"
.list

; Registers
.def    temp            = r16
.def    overflows       = r17
.def    milliseconds    = r18
.def    leds            = r19
.def    solar_input     = r20


; Macros
.macro delay
        clr     overflows
        ldi     milliseconds, @0
       sec_count:
        cpse    overflows, milliseconds
       rjmp sec_count
.endmacro       


; ===============
; Program

; Handlers
.org 0x0000
  rjmp Reset
.org 0x0020
  rjmp timer_overflow_int

; Tables
; Two are provided, one that scales 0 to 5V, suitable for a 5V solar cell,
; and one that scales 1.2v to 1.5V, suitable for a AA battery.
; Simply comment out the first one and uncomment out the second
; to switch to a AA battery level meter.

; Solar mapping table
; map solar input upper bound to LED image
; Pairs are (solar input voltage 0-255, LED image to display)
mapping:
.db 10, 0,   32,1,   64,3,   96,7,    128,15
.db 169,31, 191,63, 223,127, 255,255


; AA battery mapping table
; map battery input upper bound to LED image
; pairs are (battery input voltage 0-255, LED image to display)
; Battery empty is 1.2V (61), battery full is 1.5V (77)
;mapping:
;.db 61, 0,   63,1,   64,3,   66,7,   68,15
;.db 70,31,   73,63,  76,127, 255,255


Reset:
        ; Set TCNT0 to increment at 250kHz and reset every 250 counts
        ldi     temp, 0b00000011
        out     TCCR0B, temp
        ldi     temp, 249
        out     OCR0A, temp

        ; Set WGM01 to 1 to set OCR0A reset mode
        ldi     temp, 0b00000010
        out     TCCR0A, temp
        ; Enable TCNT0 overflow interrupts
        sts     TIMSK0, temp

        ; Enable ADC by turning off its Power Reduction Register bit
        lds     temp, PRR
        andi    temp, 0b11111110
        sts     PRR, temp

        ; Settings for ADC Multiplexer
        ; ADMUX is ADC Multiplexer Selection Register
        ; AVCC is our reference voltage
        ; Left adjust the result
        ldi     temp, 0b01100000
        sts     ADMUX, temp

        ; Digital input disable register
        lds     temp, DIDR0
        ori     temp, (1<<ADC0D)
        sts     DIDR0, temp

        ; ADC Control and Status Register A
        ; 1 1: Enabe ADC
        ; 2 0: Dont start a conversion yet
        ; 3 0: Disable autotrigger
        ; 4 0: Set by hardware when conversion is complete
        ; 5 0: Disable the ADC Conversion Complete interrupt
        ; 6-8 111: Prescaler factor of 128 between CPU clock and ADC clock
        ldi     temp, 0b10000111
        sts     ADCSRA, temp


        ; ADC Control and Status Register B
        ; Trigger source to be free running mode
        ldi     temp, 0x00
        sts     ADCSRB, temp

        ; Turn on global interrupts
        sei

        ; Initialize ports
        ser     temp
        out     DDRD, temp      ; PortD is output
        ldi     temp, 0b11111110
        out     DDRC, temp      ; PortC is output, ADC0 is input
        clr     temp
        out     PortC, temp     ; Set PortC to 0V (not using pull up on A0)
        out     PortD, temp

        ldi     leds, 0x00      ; Initialize all LEDs to off


main:
        rcall   read_solar
        rcall   display
        delay   100
rjmp main


read_solar:
        lds     temp, ADCSRA            ; Load status and control register A
        ori     temp, (1<<ADSC)         ; Turn on flag for start conversion bit (SC)
        sts     ADCSRA, temp            ; Store back in register
     wait_for_conversion:
        lds     temp, ADCSRA
        sbrc    temp, ADSC
     rjmp wait_for_conversion           ; Loop until start conversion bit cleard by ADC
        lds     solar_input, ADCH
ret


display:
        ldi     ZH, high(2*mapping)
        ldi     ZL, low(2*mapping)
     loop:
        lpm     temp, Z+
        cp      solar_input, temp       ; Compare solar input with table value (solar upper bound)
       brsh    next                     ; If it is not lower, then
        lpm    leds, Z                  ;   load the next table value into LEDs (the image)
        rjmp   return                   ;   Leave the subroutine
       next:
        adiw    ZH:ZL, 1                ; else, move to the next solar upper bound
     rjmp     loop
        return:
        out      PortD, leds
ret

timer_overflow_int:
        inc     overflows
reti
