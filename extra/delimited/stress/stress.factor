! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors arrays command-line delimited formatting kernel
locals math math.parser memory namespaces sequences system ;
IN: delimited.stress

! GC stress: many live generators (suspended fibers) stepped round
! robin while the heap churns, with periodic full gc and compaction.
! Every generator keeps data alive on its own stack across
! suspensions and checks it at the end.
!   ./factor -young=1 -aging=1 -run=delimited.stress 2000 </dev/null

TUPLE: yielded value ;

CONSTANT: steps 40

:: gen-body ( i -- obj )
    V{ } clone :> kept
    steps <iota> [| j |
        i 1000 * j + :> v
        8 v <array> kept push
        v yielded boa perform
        j 1 + = [ "bad resume value" throw ] unless
    ] each
    kept [ first ] map
    steps <iota> [ i 1000 * + ] map sequence=
    [ "corrupted" throw ] unless
    f ;

: gen-clauses ( -- clauses )
    { { yielded [ [ value>> ] dip 2array ] } } ;

: start-gen ( i -- pair/f )
    '[ _ gen-body ] gen-clauses handle* ;

: churn ( -- ) 50 [ 100 f <array> drop ] times ;

SYMBOL: total

:: step-all ( gens round -- gens' )
    gens [
        [
            first2 :> ( v k )
            total [ v + ] change
            churn
            round 1 + k resume-k
        ] [ f ] if*
    ] map ;

:: run-stress ( n -- )
    0 total set
    nano-count :> start
    n <iota> [ start-gen ] map
    steps <iota> [| round |
        round step-all
        round 5 mod 0 = [ gc ] when
        round 13 mod 0 = [ compact-gc ] when
    ] each
    [ ] count 0 = [ "generators left running" throw ] unless
    nano-count start - 1e6 /f :> ms
    n <iota> [ 1000 * steps * steps <iota> sum + ] map-sum :> expected
    expected total get = [ "sum mismatch" throw ] unless
    n steps expected ms
    "ok: %d generators x %d steps, sum %d, %.0f ms\n" printf ;

: stress-main ( -- )
    command-line get [ 2000 ] [ first string>number ] if-empty
    run-stress ;

MAIN: stress-main
