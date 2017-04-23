## What should this be programed on?
This code was designed to be ran on an AT Tiny 2313 (AVR Microcontroller)

## Can this be put on anything else?
That depends on the microcontroller you're using. You might have to change the way you configure interrupts, and you'll obviously have to change the include file that you're using.

## What does the program itself do?
It just produces a 50hz signal that is designed to control a servo motor. This assumes that your servo takes 1.5ms for middle, 1.0ms for full left, and 2.0ms for full right
