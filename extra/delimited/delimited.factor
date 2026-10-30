! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors assocs classes classes.algebra combinators
combinators.private sequences
continuations continuations.private hashtables kernel kernel.private namespaces
namespaces.private threads.private ;
IN: delimited

! One-shot delimited continuations built on VM contexts (fibers).
! Each prompt (reset0 / handle) runs its body on a fresh context; a
! capture is a context switch back to the waiting parent, a resume is
! a switch into the suspended context. Nothing is copied. See
! DESIGN.md.

SYMBOLS: +running+ +suspended+ +done+ +failed+ ;

! ctx: alien of the fiber's VM context (valid while not done/failed)
! parent: context waiting for this fiber to suspend or finish
! handler: ( k msg -- obj ), called in the parent on suspension
! body, namestack: only used while starting
TUPLE: fiber ctx parent state handler body namestack ;

ERROR: no-prompt message ;
ERROR: continuation-not-resumable k ;
ERROR: fiber-aborted ;

TUPLE: shifted quot ;
C: <shifted> shifted

<PRIVATE

TUPLE: thrown error ;
C: <thrown> thrown

SINGLETON: abort-token

SYMBOL: current-fiber

: setup-fiber ( fiber -- fiber body )
    context >>ctx
    dup namestack>> set-namestack f >>namestack
    init-catchstack
    dup current-fiber associate >n
    dup body>> [ f >>body ] dip ;

! Runs on the fiber's own stacks. Never returns: switches to the
! parent and recycles this context.
: fiber-main ( fiber -- * )
    setup-fiber
    [ call( -- obj ) +done+ ] [ nip +failed+ ] recover
    ! fiber result state
    pick state<<
    swap parent>> set-context-and-delete ;

! Parent side: k has suspended or finished, msg is what it sent.
: dispatch ( k msg -- obj )
    over state>> {
        { +suspended+ [ over handler>> ( k msg -- obj ) call-effect-unsafe ] }
        { +done+ [ nip ] }
        { +failed+ [ nip rethrow ] }
    } case ;

: check-resumable ( k -- k )
    dup state>> +suspended+ eq? [ continuation-not-resumable ] unless ;

! Switch into k delivering obj; returns when k suspends or finishes.
: switch-in ( obj k -- k msg )
    check-resumable
    +running+ >>state
    context >>parent
    [ ctx>> set-context ] keep swap ;

: <fiber> ( body handler -- fiber )
    fiber new
        swap >>handler
        swap >>body
        get-namestack >>namestack
        context >>parent
        +running+ >>state ;

! Start body on a new context; returns at its first suspension or at
! its end. Leaves the fiber below the message.
: start-fiber ( body handler -- k msg )
    <fiber> dup [ fiber-main ] start-context ;

: nearest-fiber ( msg -- msg fiber )
    current-fiber get [ no-prompt ] unless* ;

! Suspend the nearest fiber, sending msg to its parent. Returns the
! raw value k was resumed with.
: (control-raw) ( msg -- obj )
    nearest-fiber
    +suspended+ >>state
    parent>> set-context ;

: control-result ( obj -- obj )
    {
        { [ dup abort-token eq? ] [ drop fiber-aborted ] }
        { [ dup thrown? ] [ error>> throw ] }
        [ ]
    } cond ;

PRIVATE>

! Resume k with obj. Returns when the computation in k finishes (its
! result) or suspends again (the handler's result for that
! suspension): deep-handler semantics.
: resume-k ( obj k -- obj' )
    switch-in dispatch ;

! Resume k by throwing error at its suspension point.
: throw-k ( error k -- obj' )
    [ <thrown> ] dip resume-k ;

! Abandon a suspended k: throws fiber-aborted at its suspension
! point so cleanup code runs, then frees its context. No-op if k is
! running or finished.
: discard ( k -- )
    dup state>> +suspended+ eq? [
        abort-token swap switch-in
        over state>> {
            { +done+ [ 2drop ] }
            { +failed+ [ nip dup fiber-aborted? [ drop ] [ rethrow ] if ] }
            [ 2drop discard ]
        } case
    ] [ drop ] if ;

<PRIVATE

! Send a control message from inside a prompt body to its nearest
! prompt; returns what that prompt resumes us with.
: (control) ( msg -- obj )
    (control-raw) control-result ;

! A prompt that does not understand msg re-sends it outward from
! its own (parent) context and resumes k with the answer.
: forward ( k msg -- obj )
    (control-raw) dup abort-token eq?
    [ drop discard fiber-aborted ] [ swap resume-k ] if ;

: reset0-handler ( k msg -- obj )
    dup shifted? [ quot>> ( k -- obj ) call-effect-unsafe ] [ forward ] if ;

! handler: ( effect k -- obj ); shift0 messages pass through
: handle-with-dispatch ( k msg handler -- obj )
    over shifted? [ drop forward ] [
        [ swap ] dip ( effect k -- obj ) call-effect-unsafe
    ] if ;

: discard-unresumed ( obj k -- obj )
    dup state>> +suspended+ eq? [ discard ] [ drop ] if ;

! clause lookup: by exact class through a per-handle cache; a miss
! scans the clauses with class<= (so unions, mixins, superclasses
! and object work) and caches the answer, f included.
TUPLE: clause-table clauses { cache hashtable } ;

: <clause-table> ( clauses -- table )
    H{ } clone clause-table boa ;

: scan-clauses ( class clauses -- quot/f )
    [ first class<= ] with find nip dup [ second ] when ;

: lookup-clause ( effect table -- quot/f )
    [ class-of ] dip [ cache>> ] [ clauses>> ] bi
    [ scan-clauses ] curry cache ;

PRIVATE>

! Run quot under a prompt. Inside it, shift0 captures the rest of the
! computation up to here as a one-shot continuation k.
: reset0 ( quot: ( -- obj ) -- obj )
    [ reset0-handler ] start-fiber dispatch ;

! Capture the continuation up to the nearest reset0, abort to it and
! run quot there with k; quot's result becomes the reset0's (or the
! resume's) result. The handler runs outside the prompt and k
! includes it (shift0 semantics).
: shift0 ( quot: ( k -- obj ) -- obj )
    <shifted> (control) ;

! ---- Effect handlers ----

! Perform an effect: suspend to the nearest handler; returns the
! value the handler resumes with.
: perform ( effect -- value )
    (control) ;

! For use in a handle-with handler: pass an effect this handler does
! not handle to the next handler out, and resume k with its answer.
: unhandled ( effect k -- obj )
    swap forward ;

! handler: ( effect k -- obj ) is called for every effect performed
! in body. When handle-with* returns, k may still be suspended (the
! handler may have stored it). handle-with discards it, which suits
! every use where k does not escape.
: handle-with* ( body: ( -- obj ) handler: ( effect k -- obj ) -- obj )
    [ handle-with-dispatch ] curry start-fiber dispatch ;

: handle-with ( body: ( -- obj ) handler: ( effect k -- obj ) -- obj )
    [ handle-with-dispatch ] curry start-fiber
    over [ dispatch ] dip discard-unresumed ;

<PRIVATE

: clause-handler ( clauses -- handler )
    <clause-table> [
        pick swap lookup-clause
        [ ( effect k -- obj ) call-effect-unsafe ] [ unhandled ] if*
    ] curry ;

PRIVATE>

! clauses: assoc of class => quot: ( effect k -- obj ). An effect that
! matches no clause is forwarded to the next handler out.
: handle* ( body: ( -- obj ) clauses -- obj )
    clause-handler handle-with* ;

: handle ( body: ( -- obj ) clauses -- obj )
    clause-handler handle-with ;
