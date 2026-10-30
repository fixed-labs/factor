! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors assocs classes classes.private classes.tuple
classes.tuple.parser combinators continuations effects kernel kernel.private
hashtables namespaces parser sequences words ;
IN: algebraic-effects

! Algebraic effects and deep handlers built on Factor's
! undelimited, copying callcc. See NOTES.md for the design.

ERROR: unhandled-effect op ;

! A first-class resumption: the captured perform site plus the
! handler to reinstall around it (deep handlers).
TUPLE: resumption continuation handler ;

TUPLE: handler clauses return ;

C: <handler> handler

<PRIVATE

! The current prompt lives in a mutable cell, bound in the
! namestack by each handle. The cell is mutated when a region
! is re-entered via resume, so every captured copy of the
! namestack sees the live prompt.
SYMBOL: current-prompt

! The cell also records the thread that owns it: threads inherit
! the namestack, and a child thread must not abort into its
! parent's handle site.
TUPLE: prompt-cell k thread ;

: current-thread ( -- thread ) OBJ-CURRENT-THREAD special-object ; inline

: live-prompt? ( -- ? )
    current-prompt get [ thread>> current-thread eq? ] [ f ] if* ;

! Messages sent to a handle site (prompt).
TUPLE: returned value ;
TUPLE: raised error ;
TUPLE: performed op k ;

! Messages sent back to a perform site.
TUPLE: resume-msg value prompt ;
TUPLE: discontinue-msg error prompt ;

: abort-to-prompt ( msg -- * )
    current-prompt get k>> continue-with ;

: run-region ( body: ( -- obj ) -- * )
    [ call( -- obj ) returned boa ] [ nip raised boa ] recover
    abort-to-prompt ;

: find-clause ( op handler -- quot/f )
    clauses>> [ drop swap instance? ] with assoc-find drop nip ;

DEFER: (handle)

PRIVATE>

: perform ( op -- result )
    live-prompt? [ dup unhandled-effect ] unless
    [ performed boa abort-to-prompt ] callcc1 nip
    dup prompt>> current-prompt get
    [ k<< ] [ current-thread swap thread<< ] bi
    dup resume-msg? [ value>> ] [ error>> throw ] if ;

! Resume under a different handler than the one that caught the
! op. With it a clause can implement shallow-handler patterns
! (e.g. state machines that change handler per step).
: resume-with ( value resumption handler -- obj )
    [ continuation>> ] dip
    [
        [
            [ current-prompt get k>> resume-msg boa ] dip
            continue-with
        ] 2curry
    ] dip (handle) ;

: resume ( value resumption -- obj ) dup handler>> resume-with ;

: discontinue ( error resumption -- obj )
    [ continuation>> ] [ handler>> ] bi
    [
        [
            [ current-prompt get k>> discontinue-msg boa ] dip
            continue-with
        ] 2curry
    ] dip (handle) ;

<PRIVATE

! Not ours: re-perform at our handle site (outside our region,
! so the next handler out sees it), then resume with the answer.
: forward ( op k handler -- obj )
    [ perform ] 2dip resumption boa resume ;

: dispatch ( msg handler -- obj )
    over returned? [
        [ value>> ] [ return>> ] bi* call( obj -- obj )
    ] [
        over raised? [
            drop error>> rethrow
        ] [
            [ [ op>> ] [ k>> ] bi ] dip
            pick over find-clause [
                [ resumption boa ] dip call( op r -- obj )
            ] [
                forward
            ] if*
        ] if
    ] if ;

:: (handle) ( body handler -- obj )
    [| k |
        k current-thread prompt-cell boa current-prompt associate
        [ body run-region ] with-variables
    ] callcc1
    handler dispatch ;

PRIVATE>

: handle-with ( body: ( -- obj ) clauses return: ( obj -- obj' ) -- obj' )
    handler boa (handle) ;

: handle ( body: ( -- obj ) clauses -- obj )
    [ ] handle-with ;

! EFFECT: name slots... ;
! Defines a tuple class `name` and makes the word `name`
! construct an instance from its slots and perform it, like
! ERROR: does with throw.

PREDICATE: effect-class < tuple-class "effect-class" word-prop ;

M: effect-class reset-class
    [ call-next-method ] [ "effect-class" remove-word-prop ] bi ;

: define-effect-class ( class superclass slots -- )
    {
        [ define-tuple-class ]
        [ 2drop reset-generic ]
        [ 2drop t "effect-class" set-word-prop ]
        [
            2drop
            [ ]
            [ [ boa perform ] curry ]
            [ all-slots [ name>> ] map { "result" } <effect> ]
            tri define-declared
        ]
    } 3cleave ;

SYNTAX: EFFECT:
    parse-tuple-definition
    pick save-location
    define-effect-class ;
