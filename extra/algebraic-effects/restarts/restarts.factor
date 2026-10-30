! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors algebraic-effects arrays kernel math math.parser
sequences ;
IN: algebraic-effects.restarts

! Resumable exceptions: signalling a problem is an effect whose
! answer is the replacement value. The handler decides the
! policy: resume with a default, resume with a value computed
! elsewhere, or discontinue (turn it into a real exception
! thrown at the signal site, so cleanups run).

EFFECT: malformed-number string ;

ERROR: invalid-number string ;

: parse-number ( string -- n )
    dup string>number [ nip ] [ malformed-number ] if* ;

: sum-numbers ( strings -- n ) [ parse-number ] map-sum ;

! Policies

: with-default ( body: ( -- obj ) default -- obj )
    [ rot drop swap resume ] curry
    \ malformed-number swap 2array 1array handle ;

: with-strict ( body: ( -- obj ) -- obj )
    {
        { malformed-number [
            [ string>> \ invalid-number boa ] dip discontinue
        ] }
    } handle ;

! Ask some outer handler (e.g. a UI, or a test) for a fix.
EFFECT: ask-replacement string ;

: with-asking ( body: ( -- obj ) -- obj )
    {
        { malformed-number [
            [ string>> ask-replacement ] dip resume
        ] }
    } handle ;
