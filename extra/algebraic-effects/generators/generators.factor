! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors algebraic-effects arrays kernel locals math
sequences vectors ;
IN: algebraic-effects.generators

! Generators from a single `yield-value` effect.

EFFECT: yield-value value ;

! Push-based: run the body to completion, collecting yields.
:: collect ( body: ( -- obj ) -- seq )
    V{ } clone :> acc
    body {
        { yield-value [ [ value>> acc push ] dip f swap resume ] }
    } handle drop
    acc { } like ;

! Pull-based: the clause does not resume; it returns the value
! and the resumption, which `gen-next` resumes later, after the
! handle that captured it has already returned.
TUPLE: gen body step ;

: <gen> ( body: ( -- obj ) -- gen ) f gen boa ;

<PRIVATE

: gen-start ( body -- step )
    { { yield-value [ [ value>> ] dip 2array ] } }
    [ drop f ] handle-with ;

: advance ( gen -- step )
    dup body>> [
        [ f >>body drop ] dip gen-start
    ] [
        step>> [ second f swap resume ] [ f ] if*
    ] if* ;

PRIVATE>

: gen-next ( gen -- value/f ? )
    [ advance ] keep over >>step drop
    [ first t ] [ f f ] if* ;

:: gen-take ( gen n -- seq )
    n <vector> :> acc
    [ acc length n < [ gen gen-next [ acc push t ] [ drop f ] if ] [ f ] if ]
    loop
    acc { } like ;

:: gen>array ( gen -- seq )
    V{ } clone :> acc
    [ gen gen-next [ acc push t ] [ drop f ] if ] loop
    acc { } like ;
