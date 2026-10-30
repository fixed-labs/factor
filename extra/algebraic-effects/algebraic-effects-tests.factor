! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors algebraic-effects arrays continuations kernel
locals math namespaces sequences tools.test ;
IN: algebraic-effects.tests

EFFECT: ask ;
EFFECT: tell value ;
EFFECT: flip ;

! No handler at all
[ ask ] [ unhandled-effect? ] must-fail-with

! Body that performs nothing
{ 42 } [ [ 42 ] { } handle ] unit-test

! Return clause
{ 43 } [ [ 42 ] { } [ 1 + ] handle-with ] unit-test

! Tail-resumptive
{ 11 } [
    [ ask 1 + ] { { ask [ nip 10 swap resume ] } } handle
] unit-test

! Datastack below the perform site is preserved
{ { 1 2 2 } } [
    [ 1 ask ask 3array ] { { ask [ nip 2 swap resume ] } } handle
] unit-test

! Handler state captured by the clause
{ { 1 10 11 } } [
    [let
        10 :> n!
        [ 1 ask ask 3array ]
        { { ask [ nip n dup 1 + n! swap resume ] } } handle
    ]
] unit-test

! Arguments are passed via the op tuple
{ V{ 1 2 3 } } [
    [let
        V{ } clone :> log
        [ 1 tell drop 2 tell drop 3 tell drop f ]
        { { tell [ [ value>> log push ] dip f swap resume ] } }
        handle drop
        log
    ]
] unit-test

! Zero-shot: handler result replaces the whole computation
{ "aborted" } [
    [ ask "never" append ] { { ask [ 2drop "aborted" ] } } handle
] unit-test

! Return clause applies to the result of resume too (deep)
{ 22 } [
    [ ask ] { { ask [ nip 10 swap resume 2 + ] } } [ 10 + ] handle-with
] unit-test

! Multi-shot: nondeterminism, collect all outcomes
{ { { t t } { t f } { f t } { f f } } } [
    [ flip flip 2array ]
    { { flip [ nip [ t swap resume ] [ f swap resume ] bi append ] } }
    [ 1array ] handle-with
] unit-test

! Multi-shot with datastack state below the perform site
{ { 5 6 6 7 } } [
    [ 1 flip 2 3 ? + 2 flip 0 1 ? + + ]
    { { flip [ nip [ t swap resume ] [ f swap resume ] bi append ] } }
    [ 1array ] handle-with
] unit-test

! Forwarding: inner handler does not handle `ask`
{ 107 } [
    [
        [ ask 7 tell + ]
        { { tell [ [ value>> ] dip resume ] } } handle
    ] { { ask [ nip 100 swap resume ] } } handle
] unit-test

! Inner handler shadows outer for the same op
{ 2 } [
    [
        [ ask ] { { ask [ nip 2 swap resume ] } } handle
    ] { { ask [ nip 1 swap resume ] } } handle
] unit-test

! A clause's own performs go to the *outer* handler (deep
! handlers: the clause runs outside its own handle)
{ 2 } [
    [
        [ ask ] { { ask [ nip ask 1 + swap resume ] } } handle
    ] { { ask [ nip 1 swap resume ] } } handle
] unit-test

! Errors in the body propagate out of handle
[ [ "boom" throw ] { { ask [ 2drop 0 ] } } handle ]
[ "boom" = ] must-fail-with

! Errors after a resume propagate out of the clause's resume
{ "caught boom" } [
    [ ask drop "boom" throw ]
    { { ask [ nip [ f swap resume ] [ nip "caught " prepend ] recover ] } }
    handle
] unit-test

! recover inside the body still works across a resume
{ "inner boom" } [
    [ [ ask drop "boom" throw ] [ "inner " prepend ] recover ]
    { { ask [ nip f swap resume ] } } handle
] unit-test

! Errors in a clause propagate out of handle
[ [ ask ] { { ask [ 2drop "clause" throw ] } } handle ]
[ "clause" = ] must-fail-with

! discontinue: throws at the perform site, so cleanups run
{ t "stop" } [
    [let
        f :> ran!
        [ [ ask ] [ t ran! ] finally ]
        { { ask [ nip "stop" swap [ discontinue ] [ 2nip ] recover ] } }
        handle
        ran swap
    ]
] unit-test

! Zero-shot does NOT run cleanups at the perform site
{ f } [
    [let
        f :> ran!
        [ [ ask ] [ t ran! ] finally ] { { ask [ 2drop 0 ] } } handle drop
        ran
    ]
] unit-test

! Resuming after handle has returned (escaped resumption)
{ { 1 2 3 } } [
    [ 1 tell drop 2 tell drop 3 tell drop f ]
    { { tell [ [ value>> ] dip 2array ] } } handle
    [ dup ] [ first2 f swap resume swap ] produce nip
] unit-test

! Dynamic variables: body sees its own bindings across a
! resume; the clause sees the handle site's bindings.
SYMBOL: color
{ { "outer" "body" } } [
    "outer" color [
        [ "body" color [ ask drop color get ] with-variable ]
        { { ask [ nip color get swap f swap resume 2array ] } }
        handle
    ] with-variable
] unit-test

! Deep loop: 10000 tail resumes must not blow the stacks
{ 10000 } [
    [ 0 10000 [ ask + ] times ]
    { { ask [ nip 1 swap resume ] } } handle
] unit-test

! An op performed after the handle returned is unhandled again
{ 1 } [ [ 1 ] { { ask [ 2drop 0 ] } } handle ] unit-test
[ ask ] [ unhandled-effect? ] must-fail-with
