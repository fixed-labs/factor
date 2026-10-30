! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors algebraic-effects arrays kernel ;
IN: algebraic-effects.state

! The state effect: get-state / put-state.

EFFECT: get-state ;
EFFECT: put-state value ;

: modify-state ( quot: ( s -- s' ) -- )
    [ get-state ] dip call put-state drop ; inline

! Pure state-passing handler, the textbook encoding: the handled
! computation denotes a function ( s -- result s ). Resumptions
! are called in non-tail position.
!
! The steps are named words on purpose: a `call(` inside a
! curried quotation literal runs in the non-optimizing JIT,
! where `call(` is the checking `call-effect`, which is NOT a
! tail call. Every operation would then leave frames on the
! handle-site callstack, and since every perform copies the
! callstack, run time became quadratic (4000 iterations: 25 s).
<PRIVATE

: get-step ( s r -- r s ) over swap resume call( s -- r s ) ;

: put-step ( old new r -- r s ) rot drop f swap resume call( s -- r s ) ;

PRIVATE>

: run-state ( body: ( -- obj ) init -- result final )
    [
        {
            { get-state [ nip [ get-step ] curry ] }
            { put-state [ [ value>> ] dip [ put-step ] 2curry ] }
        } [ [ swap ] curry ] handle-with
    ] dip swap call( s -- r s ) ;

! Imperative handler: state in a mutable cell, every clause is
! tail-resumptive. (Not written with locals on purpose: a closure
! over a local ends in `drop-locals`, which puts `resume` out of
! tail position and makes the native stacks grow per operation.)
TUPLE: state-cell value ;

: run-state! ( body: ( -- obj ) init -- result final )
    state-cell boa [
        [ [ rot drop value>> swap resume ] curry \ get-state swap 2array ]
        [ [ rot value>> swap value<< f swap resume ] curry \ put-state swap 2array ]
        bi 2array handle
    ] keep value>> ;
