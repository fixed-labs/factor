! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors arrays concurrency.promises continuations
delimited fry kernel make math memory namespaces sequences
threads tools.test ;
IN: delimited.tests

! ---- reset0 / shift0 ----

{ 3 } [ [ 3 ] reset0 ] unit-test

! abort: k is never resumed
{ 42 } [ [ 1 [ discard 42 ] shift0 + ] reset0 ] unit-test

! resume-k once; handler post-processes
{ 12 } [ [ 1 [ 10 swap resume-k 1 + ] shift0 + ] reset0 ] unit-test

! two shifts in one body, each resumed by its own handler invocation
{ 111 } [
    [ [ 1 swap resume-k ] shift0 [ 10 swap resume-k ] shift0 + 100 + ] reset0
] unit-test

! nested resets: shift0 goes to the nearest one
{ { 2 20 } } [
    [
        [ [ 2 swap resume-k ] shift0 ] reset0
        [ 20 swap resume-k ] shift0 2array
    ] reset0
] unit-test

! one-shot: a second resume-k fails
[
    [ [ ] shift0 drop 1 ] reset0 ! returns k
    [ 1 swap resume-k drop ] [ 2 swap resume-k drop ] bi
] [ continuation-not-resumable? ] must-fail-with

! no prompt
[ [ ] shift0 ] [ no-prompt? ] must-fail-with

! ---- effects ----

TUPLE: ask ;
TUPLE: tell value ;
TUPLE: emit value ;
TUPLE: get-state ;
TUPLE: put-state value ;

: reader ( body value -- obj )
    [ ask ] dip '[ nip _ swap resume-k ] 2array 1array handle ; inline

{ 5 } [ [ ask new perform 2 + ] 3 reader ] unit-test

! generator via emit: clause collects then resumes
{ { 1 2 3 } f } [
    [
        [ { 1 2 3 } [ emit boa perform drop ] each f ]
        { { emit [ [ value>> , ] [ f swap resume-k ] bi* ] } } handle
    ] { } make swap
] unit-test

! state effect iterated a million times: the handler's stack must
! not grow per perform (clauses resume-k in tail position)
SYMBOL: cell-state

: counter-body ( n -- obj )
    [ get-state new perform 1 + put-state boa perform drop ] times
    get-state new perform ;

: state-clauses ( -- clauses )
    {
        { get-state [ nip cell-state get swap resume-k ] }
        { put-state [ [ value>> cell-state set ] dip f swap resume-k ] }
    } ;

{ 1000000 } [
    0 cell-state [ [ 1000000 counter-body ] state-clauses handle ] with-variable
] unit-test

! perform from deep inside the body
: deep ( n quot: ( -- obj ) -- obj )
    over 0 = [ nip call ] [ [ 1 - ] dip deep 0 + ] if ; inline recursive

{ 8 } [ [ 1000 [ ask new perform ] deep ] 8 reader ] unit-test
{ 8 } [ [ 10000 [ ask new perform ] deep ] 8 reader ] unit-test

! nested handlers: the inner one has no tell clause, so tell is
! forwarded to the outer handler
SYMBOL: told
{ 7 V{ 99 } } [
    V{ } clone told set-global
    [ [ 99 tell boa perform drop ask new perform ] 7 reader ]
    { { tell [ [ value>> told get-global push ] dip f swap resume-k ] } } handle
    told get-global
] unit-test

! shift0 inside a handle body goes past the handle to the reset0
{ 30 } [
    [ [ [ 10 swap resume-k 20 + ] shift0 ] 0 reader ] reset0
] unit-test

! ---- errors ----

! error in body propagates out of handle
[ [ "boom" throw ] { } handle ] [ "boom" = ] must-fail-with

! error after a resume-k propagates out of resume, into the clause
{ "caught" } [
    [ ask new perform drop "boom" throw ]
    { { ask [ nip [ f swap resume-k ] [ 2drop "caught" ] recover ] } } handle
] unit-test

! recover inside the body around a perform
{ 9 } [
    [ [ ask new perform ] [ drop 0 ] recover ] 9 reader
] unit-test

! throw-k raises at the perform site, caught in the body
{ "inner" } [
    [ [ ask new perform ] [ drop "inner" ] recover ]
    { { ask [ nip "x" swap throw-k ] } } handle
] unit-test

! clause throws: propagates out of handle
[
    [ ask new perform ] { { ask [ 2drop "clause" throw ] } } handle
] [ "clause" = ] must-fail-with

! discard runs cleanup in the body
SYMBOL: cleaned
{ t } [
    f cleaned set-global
    [ [ ask new perform ] [ t cleaned set-global ] finally ]
    { { ask [ nip discard 0 ] } } handle drop
    cleaned get-global
] unit-test

! handle discards an unresumed k automatically
{ 0 t } [
    f cleaned set-global
    [ [ ask new perform ] [ t cleaned set-global ] finally ]
    { { ask [ 2drop 0 ] } } handle
    cleaned get-global
] unit-test

! ---- dynamic variables ----

SYMBOL: dyn

{ 5 } [ 5 dyn [ [ dyn get ] reset0 ] with-variable ] unit-test

! body binding is not seen by the clause; clause sees handler's
{ { 5 7 } } [
    5 dyn [
        [ 7 dyn [ ask new perform dyn get 2array ] with-variable ]
        { { ask [ nip dyn get swap resume-k ] } } handle
    ] with-variable
] unit-test

! set inside body on a body binding stays local
{ 5 } [
    5 dyn [
        [ 1 dyn [ 6 dyn set ask new perform ] with-variable ] 0 reader drop
        dyn get
    ] with-variable
] unit-test

! ---- GC ----

{ { 0 1 2 3 4 5 6 7 8 9 } } [
    [
        10 <iota> >array [ ] map
        ask new perform drop
        gc compact-gc
    ] { { ask [ nip gc 1000 [ 1000 0 <array> ] replicate drop f swap resume-k ] } } handle
] unit-test

! many suspended fibers across a full gc and compaction
{ 5050 } [
    101 <iota> [ '[ 100 _ <array> [ ] shift0 drop first ] reset0 ] map
    gc compact-gc
    [ 0 swap resume-k ] map sum
] unit-test

! ---- threads ----

{ 3 } [ [ yield 1 sleep 3 ] reset0 ] unit-test

! resume-k from a different thread
{ 11 } [
    [ ask new perform 1 + ] { { ask [
        nip <promise> [ '[ 10 _ resume-k _ fulfill ] in-thread ] keep
        ?promise
    ] } } handle
] unit-test

! ---- leak check: many aborts must free their contexts ----

{ 100000 } [
    0 100000 [ [ ask new perform ] { { ask [ 2drop 1 ] } } handle + ] times
] unit-test

! ---- handle-with / clause lookup ----

! hand-written dispatcher; unhandled forwards outward
{ 7 V{ 99 } } [
    V{ } clone told set-global
    [
        [ 99 tell boa perform drop ask new perform ]
        [ over ask? [ nip 7 swap resume-k ] [ unhandled ] if ] handle-with
    ]
    { { tell [ [ value>> told get-global push ] dip f swap resume-k ] } } handle
    told get-global
] unit-test

! a clause keyed by a superclass or object matches
TUPLE: base-eff ;
TUPLE: sub-eff < base-eff ;
{ 1 2 } [
    [ sub-eff new perform ] { { base-eff [ nip 1 swap resume-k ] } } handle
    [ 5 perform ] { { object [ nip 2 swap resume-k ] } } handle
] unit-test

! an effect nobody handles
[ [ 5 perform ] { { ask [ 2drop 0 ] } } handle ] [ no-prompt? ] must-fail-with
