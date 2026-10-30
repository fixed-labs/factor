! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: algebraic-effects algebraic-effects.generators
algebraic-effects.state arrays kernel math sequences tools.test ;
IN: algebraic-effects.generators.tests

: naturals ( -- obj ) 0 [ dup yield-value drop 1 + t ] loop ;

: fibs ( -- a b ) 0 1 [ over yield-value drop [ + ] keep swap t ] loop ;

: tree-walk ( tree -- )
    dup array? [ [ tree-walk ] each ] [ yield-value drop ] if ;

{ { 1 2 3 } } [ [ 1 yield-value drop 2 yield-value drop 3 yield-value drop f ] collect ] unit-test

{ { 1 2 3 4 5 } } [ [ { 1 { 2 { 3 4 } } 5 } tree-walk f ] collect ] unit-test

! Infinite generator, pulled lazily
{ { 0 1 2 3 4 } } [ [ naturals ] <gen> 5 gen-take ] unit-test
{ { 0 1 1 2 3 5 8 13 } } [ [ fibs drop ] <gen> 8 gen-take ] unit-test

! Finite generator runs out
{ { 1 2 3 4 5 } } [ [ { 1 { 2 { 3 4 } } 5 } tree-walk f ] <gen> gen>array ] unit-test
{ 1 t f f } [
    [ 1 yield-value drop f ] <gen> [ gen-next ] [ gen-next ] bi
] unit-test

! Two generators interleaved: independent prompts
{ { { 0 0 } { 1 1 } { 2 1 } { 3 2 } } } [
    [ naturals ] <gen> [ fibs drop ] <gen>
    4 [ 2dup [ gen-next drop ] bi@ 2array ] replicate 2nip
] unit-test

! Generator body using another effect: forwarded to the handler
! around the *resume* (gen-next), not around the creation.
{ { 10 11 12 } 13 } [
    [
        [ 3 [ drop get-state dup 1 + put-state drop yield-value drop ] each-integer f ] <gen>
        3 gen-take
    ] 10 run-state!
] unit-test

! A generator's yields can be summed while it runs, push-style
{ 4950 } [
    [ 100 [ yield-value drop ] each-integer f ] collect sum
] unit-test
