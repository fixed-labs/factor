! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: combinators continuations delimited formatting io kernel locals math
sequences system ;
IN: delimited.bench

! Capture+resume cost by stack depth: fibers (this vocab) against
! callcc1/continue-with. depth = number of real (non-tail) frames
! between the prompt/handler and the capture point.

TUPLE: ask ;

: nest ( n quot: ( -- x ) -- x )
    over 0 <= [ nip call ] [ [ 1 - ] dip nest 0 + ] if ; inline recursive

: ask-clauses ( -- clauses ) { { ask [ nip f swap resume-k ] } } ;

! perform + resume-k through a handle
: perform-loop ( m -- x ) [ T{ ask } perform drop ] times 0 ;

:: bench-perform-with ( depth m -- ns/op )
    nano-count
    [ depth [ m perform-loop ] nest ]
    [ over ask? [ nip f swap resume-k ] [ unhandled ] if ] handle-with drop
    nano-count swap - m /f ;

:: bench-perform ( depth m -- ns/op )
    nano-count
    [ depth [ m perform-loop ] nest ] ask-clauses handle drop
    nano-count swap - m /f ;

! shift0 + resume-k through a reset0
: shift0-loop ( m -- x ) [ [ f swap resume-k ] shift0 drop ] times 0 ;

:: bench-shift0 ( depth m -- ns/op )
    nano-count
    [ depth [ m shift0-loop ] nest ] reset0 drop
    nano-count swap - m /f ;

! callcc1 capture + continue-with resume-k (a lower bound for a
! handler built on callcc: no jump to the handler at all)
: callcc-loop ( m -- x )
    [ [ ] callcc1 [ f swap continue-with ] when* ] times 0 ;

:: bench-callcc ( depth m -- ns/op )
    nano-count
    depth [ m callcc-loop ] nest drop
    nano-count swap - m /f ;

! for reference: recover is built on ifcc, so it copies too
: recover-loop ( m -- x ) [ [ ] [ drop ] recover ] times 0 ;

:: bench-recover ( depth m -- ns/op )
    nano-count
    depth [ m recover-loop ] nest drop
    nano-count swap - m /f ;

! prompt installation (fiber creation + finish)
:: bench-reset0 ( depth m -- ns/op )
    nano-count
    depth [ m [ [ 0 ] reset0 drop ] times 0 ] nest drop
    nano-count swap - m /f ;

:: bench-handle ( depth m -- ns/op )
    nano-count
    depth [ m [ [ 0 ] ask-clauses handle drop ] times 0 ] nest drop
    nano-count swap - m /f ;

: ops-for ( depth -- m ) 1000 > 2000 20000 ? ;

: row ( depth -- )
    {
        [ ]
        [ 200000 bench-perform ]
        [ 200000 bench-perform-with ]
        [ 200000 bench-shift0 ]
        [ dup ops-for bench-callcc ]
        [ dup ops-for bench-recover ]
        [ 50000 bench-reset0 ]
        [ 50000 bench-handle ]
    } cleave
    "%6d %10.1f %10.1f %10.1f %12.1f %12.1f %10.1f %10.1f\n" printf flush ;

: run-bench ( -- )
    ! warm up
    { 10 100 } [ [ 1000 bench-perform drop ] [ 1000 bench-shift0 drop ] [ 100 bench-callcc drop ] tri ] each
    "depth    perform  perform-w     shift0   callcc1+cw      recover      reset0     handle" print
    "        (ns/op)    (ns/op)    (ns/op)      (ns/op)      (ns/op)    (ns/op)    (ns/op)" print
    { 0 10 100 1000 10000 } [ row ] each ;



! forwarding: the matching handler is h empty handlers further out
: nest-handlers ( h quot: ( -- obj ) -- obj )
    over 0 <= [ nip call( -- obj ) ] [
        [ 1 - ] dip [ nest-handlers ] 2curry { } handle
    ] if ;

:: bench-forward ( h m -- ns/op )
    nano-count
    [ h [ m perform-loop ] nest-handlers ] ask-clauses handle drop
    nano-count swap - m /f ;

! creating m fibers that stay alive (context pool exhausted), then
! discarding them
:: bench-create-live ( m -- create-ns discard-ns )
    nano-count
    m [ [ [ ] shift0 ] reset0 ] replicate
    nano-count rot - m /f swap
    nano-count swap [ discard ] each nano-count swap - m /f ;

: run-bench-2 ( -- )
    "handlers between perform and its handler:" print
    { 0 1 5 20 } [ dup 20000 bench-forward "  %3d skipped: %8.1f ns/op\n" printf ] each
    "fibers kept alive (pool of 10 exhausted):" print
    { 10 1000 10000 } [
        dup bench-create-live
        "  %6d live: create+suspend %8.1f ns, discard %8.1f ns\n" printf
    ] each ;

: bench-main ( -- ) run-bench run-bench-2 ;

MAIN: bench-main
