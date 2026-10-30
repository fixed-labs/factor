! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: algebraic-effects continuations formatting io kernel math
sequences tools.time ;
IN: algebraic-effects.benchmark

! Rough costs. Run with:
!   ./factor -run=algebraic-effects.benchmark </dev/null

EFFECT: bump ;
EFFECT: other ;

: plain-word ( -- n ) 1 ;

: bench-plain ( n -- ) 0 swap [ plain-word + ] times drop ;

: bump-clauses ( -- clauses ) { { bump [ nip 1 swap resume ] } } ;

: bump-loop ( n -- obj ) 0 swap [ bump + ] times ;

: bench-perform ( n -- ) [ bump-loop ] curry bump-clauses handle drop ;

: bench-throw ( n -- ) [ [ "x" throw ] [ drop ] recover ] times ;

: bench-callcc ( n -- )
    [ [ 1 swap continue-with ] callcc1 drop ] times ;

: bench-handle ( n -- ) [ [ 1 ] { } handle drop ] times ;

! perform with `d` extra frames between the handle and the
! perform (callcc copies the whole callstack)
: nest ( d quot -- obj )
    over 0 > [ [ 1 - ] dip nest 0 + ] [ nip call( -- obj ) ] if ;

: bench-deep ( n d -- )
    swap [ bump-loop ] curry [ nest ] 2curry bump-clauses handle drop ;

! perform through `h` handlers that do not handle it
: wrap-others ( quot h -- quot' )
    [ [ { { other [ 2drop 0 ] } } handle ] curry ] times ;

: bench-forward ( n h -- )
    [ [ bump-loop ] curry ] dip wrap-others bump-clauses handle drop ;

: ns/op ( quot n -- ns ) [ benchmark ] dip / ; inline

: report ( name quot n -- )
    [ ns/op ] keep "%-38s %10.1f ns/op  (n=%d)\n" printf ; inline

: run-benchmarks ( -- )
    ! warm up
    1000 bench-perform 1000 bench-throw 1000 bench-plain
    "plain word call" [ 1000000 bench-plain ] 1000000 report
    "throw + recover" [ 100000 bench-throw ] 100000 report
    "raw callcc1 + continue-with" [ 100000 bench-callcc ] 100000 report
    "handle, no perform" [ 100000 bench-handle ] 100000 report
    "perform + resume (tail)" [ 100000 bench-perform ] 100000 report
    { 10 100 1000 } [
        [ "perform + resume, +%d frames" sprintf ] keep
        '[ 20000 _ bench-deep ] 20000 report
    ] each
    { 1 4 16 } [
        [ "perform through %d other handlers" sprintf ] keep
        '[ 20000 _ bench-forward ] 20000 report
    ] each ;

MAIN: run-benchmarks
