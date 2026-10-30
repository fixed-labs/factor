! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors algebraic-effects arrays io kernel math math.parser
sequences vectors ;
IN: algebraic-effects.console

! Console IO as effects, so programs can run against the real
! streams or against a scripted mock without touching io.

EFFECT: input-line ;
EFFECT: output-line string ;

: say ( string -- ) output-line drop ;

! Real IO: delegate to the current input/output streams.
: with-console ( body: ( -- obj ) -- obj )
    {
        { input-line [ nip readln swap resume ] }
        { output-line [ [ string>> print ] dip f swap resume ] }
    } handle ;

<PRIVATE

TUPLE: script inputs outputs ;

: next-input ( script -- line/f )
    inputs>> [ f ] [ pop ] if-empty ;

: mock-clauses ( script -- clauses )
    [ [ rot drop next-input swap resume ] curry \ input-line swap 2array ]
    [ [ rot string>> swap outputs>> push f swap resume ] curry \ output-line swap 2array ]
    bi 2array ;

PRIVATE>

! Mock IO: inputs come from a sequence, outputs are collected.
: with-mock-console ( body: ( -- obj ) inputs -- obj outputs )
    <reversed> >vector V{ } clone script boa
    [ mock-clauses handle ] keep outputs>> { } like ;

! An example program.
: greet ( -- name )
    "What is your name?" say
    input-line dup "Hello, " "!" surround say
    "How old are you?" say
    input-line string>number
    [ 1 + number>string "Next year you will be " prepend say ]
    [ "That is not a number." say ] if* ;
