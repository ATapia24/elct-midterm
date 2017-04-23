/*
 * This software is intended to generate a PWM signal to control
 * a servo motor. Everything is handled using timers and interrupts
 * the PWM signal can be adjusted by placing a quadrature encoder
 * on the INT0 and INT1 pins
 *
 * Author: Christopher Cox
 * Email: thetaco.dyndns@gmail.com
 * Date: 4/22/17
 * File: Midterm.asm
 */

.nolist
.include "tn2313def.inc"
.list

// Variables used for constants etc
.def	MAXH = R15
.def	MAXL = R14
.def	INC_SIZEH = R13
.def	INC_SIZEL = R12
.def	MINH = R9
.def	MINL = R8

// The register that holds the current PWM set
.def	PWsetH = R11
.def	PWsetL = R10

.equ	DEFAULT_PW = $05DC // The default setting for the pulse width

.equ	FREQUENCY = $4E20 // The top of the timer at no clock divide (50hz)

.def	TEMP = R16 // Middleman register
.def	DBcount = R17 // Holds the loop count for debouncing
.def	DBcompare = R18 // Holds a port for debounce checking

.def	PINDinput = R17 // Holds PIND for comparison (make sure
						// you push to the stack, since this
						// register is already used)

.equ 	LOOP_COUNT = $01 // Determines how many cyles are used
						 // for debouncing

.equ	INCREMENT_SIZE = $0001 // The size by which the pwm signal is
							 // modified
.equ	MAX_SIZE = $07D0
.equ	MIN_SIZE = $03E8

.org	$0000
		rjmp RESET

// Configure the function for int0
.org	INT0addr
		rjmp INT0_FIRED

// Configure the function for int1
.org	INT1addr
		rjmp INT1_FIRED

// Make sure we keep the program out of the interrupt vector space!
.org	INT_VECTORS_SIZE

RESET:

	// set the stack pointer
	ldi		TEMP, low(RAMEND)
	out		SPL, TEMP

	// Configure the inter. sense control bits for INT0 and INT1
	// for any logical change
	ldi 	TEMP, (0 << ISC11) | (1 << ISC10) | (0 << ISC01) | (1 << ISC00)
	out		MCUCR, TEMP

	// Enable both interrupts in the GIMSk
	ldi		TEMP, (1 << INT1) | (1 << INT0)
	out		GIMSK, TEMP

	// Load up the constants
	ldi		TEMP, high(MAX_SIZE)
	mov		MAXH, TEMP

	ldi		TEMP, low(MAX_SIZE)
	mov		MAXL, TEMP

	ldi		TEMP, high(MIN_SIZE)
	mov		MINH, TEMP

	ldi		TEMP, low(MIN_SIZE)
	mov		MINL, TEMP

	ldi		TEMP, high(INCREMENT_SIZE)
	mov		INC_SIZEH, TEMP

	ldi		TEMP, low(INCREMENT_SIZE)
	mov		INC_SIZEL, TEMP

	// Load up the pulse width set
	ldi		TEMP, high(DEFAULT_PW)
	mov		PWsetH, TEMP

	ldi		TEMP, low(DEFAULT_PW)
	mov 	PWsetL, TEMP

	// Set OCR1B as an output
	ldi		TEMP, (1 << PB4)
	out		DDRB, TEMP

	// Load the value into OCR1A
	ldi		TEMP, high(FREQUENCY)
	out		OCR1AH, TEMP
	
	ldi		TEMP, low(FREQUENCY)
	out		OCR1AL, TEMP

	// Load the value into OCR1B
	out		OCR1BH, PWsetH
	out		OCR1BL, PWsetL

	// Configure timer1's many registers! (We will use OCR1B to output the singal)
	// First comes TCCR1A
	ldi		TEMP, (1 << COM1B1) | (0 << COM1B0) | (1 << WGM11) | (1 << WGM10)
	out		TCCR1A, TEMP

	// Next comes TCCR1B (The clock doesn't need to be divided)
	ldi		TEMP, (1 << WGM13) | (1 << WGM12) | (0 << CS12) | (0 << CS11) | (1 << CS10)
	out		TCCR1B, TEMP

	// Enable the interrupts
	sei

MAIN:

	nop

	rjmp MAIN

// The function that is called when INT0 senses a change
INT0_FIRED:

	push TEMP
	push PINDinput

	// Debounce!
	rcall DEBOUNCE

	// Get whatever is currently on port D
	in		PINDinput, PIND
	// Load the current status of PD3 into the T bit
	bst		PINDinput, PD3

	// Make sure there is nothing in TEMP
	clr		TEMP

	// Load in PD3 into the PD2 spot in temp
	bld		TEMP, PD2

	// Make sure there is no noise in PINDinput
	andi	PINDinput, (1 << PD2)
	
	// XOR the two together to see if they are the same
	eor		TEMP, PINDinput

	// If they are not equal, then we know the knob is moving
	// counter clockwise
	brne	INT0_COUNTER_CLOCKWISE

	// If they are equal, then it's clockwise
	rcall CLOCKWISE

	// Make sure we don't run over the counter clockwise function
	rjmp INT0_FINISHED
	
	INT0_COUNTER_CLOCKWISE:
		
		rcall COUNTER_CLOCKWISE

	INT0_FINISHED:

	pop PINDinput
	pop TEMP

	reti

// The function that is called when INT1 senses a change
INT1_FIRED:

	push TEMP
	push PINDinput

	// Debounce!
	rcall DEBOUNCE

	// Get whatever is currently on port D
	in		PINDinput, PIND
	// Load the current status of PD3 into the T bit
	bst		PINDinput, PD3

	// Make sure there is nothing in TEMP
	clr		TEMP

	// Load in PD3 into the PD2 spot in temp
	bld		TEMP, PD2

	// Make sure there is no noise in PINDinput
	andi	PINDinput, (1 << PD2)
	
	// XOR the two together to see if they are the same
	eor		TEMP, PINDinput

	// If they are not equal, then we know the knob is moving
	// clockwise
	brne	INT1_CLOCKWISE

	// If they are equal, then it's counter clockwise
	rcall 	COUNTER_CLOCKWISE

	// Make sure we don't run over the clockwise function
	rjmp 	INT1_FINISHED
	
	INT1_CLOCKWISE:
		
		rcall 	CLOCKWISE

	INT1_FINISHED:

	pop 	PINDinput
	pop 	TEMP

	reti

// Handles clockwise movement
CLOCKWISE:

	// Increment the PW signal if it's not over max

	push 	TEMP

	// Add to PWset and check to see if it's over
	// the max setting
	add		PWsetL, INC_SIZEL
	adc		PWsetH, INC_SIZEH
	
	cp		PWsetL, MAXL
	cpc		PWsetH, MAXH

	// If PWset is greater or equal to MAX, then set
	// it to the max set above
	brge	CW_GREATER_EQUAL

	// If it's not greater or equal too, increment by the
	// set value above
	rjmp	CW_FINISHED

	CW_GREATER_EQUAL:

		// Set it to the max value
		mov		PWsetH, MAXH
		mov		PWsetL, MAXL

	CW_FINISHED:

		// Load the value into OCR1B
		out		OCR1BH, PWsetH
		out		OCR1BL, PWsetL

	pop 	TEMP		

	ret

// Handles counter clockwise movement
COUNTER_CLOCKWISE:

	push 	TEMP

	// Decrement the PW signal if it's not under min
	// Subtract to PWset and check to see if it's under
	// the min setting
	sub		PWsetL, INC_SIZEL
	sbc		PWsetH, INC_SIZEH
	
	cp		PWsetL, MINL
	cpc		PWsetH, MINH

	// If PWset is less than to MIN, then set
	// it to the MIN value
	brmi	CCW_LESS_THAN

	// If it isn't less, then just write it to OCR1B
	rjmp CCW_FINISHED

	CCW_LESS_THAN:

		// Set it to the min value
		mov		PWsetH, MINH
		mov		PWsetL, MINL

	CCW_FINISHED:

		// Load the value into OCR1B
		out		OCR1BH, PWsetH
		out		OCR1BL, PWsetL
		
		pop 	TEMP	

	ret

// The debounce function for both INT0 and INT1
DEBOUNCE:

	push 	DBcount
	push 	DBcompare
	push 	TEMP

	DBstart:

		// load up the intial loop value
		ldi		DBcount, LOOP_COUNT
		// Load up the register copy
		in		DBcompare, PIND
		// Isolate the bits we want
		andi	DBcompare, (1 << PD3) | (1 << PD2)

	DBloop:

		// Load up the temp variable with the current value on portD
		in		TEMP, PIND
		// Isolate the same bits
		andi	TEMP, (1 << PD3) | (1 << PD2)
		
		// Compare the two to see if there was a difference
		cp		TEMP, DBcompare

		// If they are not the same, start over again
		brne	DBstart

		// If we get here, then they are still the same, so decrement
		dec		DBcount

		// If the operation still isn't zero, loop again
		brne 	DBloop

	pop 	TEMP
	pop 	DBcompare
	pop		DBcount

	ret
		
		
