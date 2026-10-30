! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: algebraic-effects algebraic-effects.state arrays kernel
math sequences tools.test ;
IN: algebraic-effects.state.tests

: counter ( -- obj )
    get-state 1 + put-state drop
    get-state 10 * put-state drop
    get-state 2 + ;

{ 22 20 } [ [ counter ] 1 run-state ] unit-test
{ 22 20 } [ [ counter ] 1 run-state! ] unit-test

{ "done" 5050 } [
    [ 100 [ 1 + [ + ] curry modify-state ] each-integer "done" ] 0 run-state
] unit-test

{ "done" 5050 } [
    [ 100 [ 1 + [ + ] curry modify-state ] each-integer "done" ] 0 run-state!
] unit-test

! Many operations: checks the native stacks do not grow per op
{ 20000 20000 } [
    [ 20000 [ [ 1 + ] modify-state ] times get-state ] 0 run-state!
] unit-test

{ 5000 5000 } [
    [ 5000 [ [ 1 + ] modify-state ] times get-state ] 0 run-state
] unit-test

! Two nested state handlers: inner shadows outer
{ { 100 100 } 2 } [
    [
        [ get-state get-state 2array ] 100 run-state drop
        [ 1 + ] modify-state
    ] 1 run-state!
] unit-test
