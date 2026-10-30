! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors algebraic-effects algebraic-effects.restarts
continuations destructors kernel math tools.test ;
IN: algebraic-effects.restarts.tests

{ 6 } [ [ { "1" "2" "3" } sum-numbers ] 0 with-default ] unit-test
{ 4 } [ [ { "1" "x" "3" } sum-numbers ] 0 with-default ] unit-test
{ 104 } [ [ { "1" "x" "3" } sum-numbers ] 100 with-default ] unit-test

[ [ { "1" "x" "3" } sum-numbers ] with-strict ]
[ invalid-number? ] must-fail-with

{ "x" } [
    [ [ { "1" "x" "3" } sum-numbers ] with-strict ]
    [ string>> ] recover
] unit-test

! Strict mode runs cleanups at the signal site
TUPLE: probe < disposable ;
M: probe dispose* drop ;

: use-probe ( probe -- quot )
    [ [ &dispose drop { "1" "x" } sum-numbers drop ] with-destructors f ] curry ;

{ t } [
    probe new-disposable dup use-probe
    [ with-strict drop ] curry [ drop ] recover
    disposed>>
] unit-test

! Zero-shot abort does NOT run cleanups at the signal site:
! the perform site is simply abandoned.
{ f } [
    probe new-disposable dup use-probe
    { { malformed-number [ 2drop -1 ] } } handle drop
    disposed>>
] unit-test

! Asking an outer handler for the replacement
{ 46 } [
    [ [ { "1" "forty-two" "3" } sum-numbers ] with-asking ]
    { { ask-replacement [ nip 42 swap resume ] } } handle
] unit-test

! Restarts compose with ordinary exceptions in the body
{ "real error" } [
    [ [ { "1" "x" } sum-numbers "real error" throw ] 0 with-default ]
    [ ] recover
] unit-test
