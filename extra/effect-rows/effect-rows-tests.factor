! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors continuations effect-rows effect-rows.io effect-rows.state
effects eval io kernel lexer math math.parser sequences tools.test vocabs.parser words ;
IN: effect-rows.tests

: unwrap ( error -- error' )
    dup [ lexer-error? ] [ condition? ] bi or [ error>> unwrap ] when ;

! ---- syntax and printing

{ "( -- x | state )" } [ \ get-state stack-effect effect>string ] unit-test
{ "( x -- | state )" } [ \ put-state stack-effect effect>string ] unit-test
{ "( ..a init quot: ( ..a -- ..b | state ..e ) -- ..b final | ..e )" }
[ \ with-state stack-effect effect>string ] unit-test
{ { state } } [ \ get-state stack-effect labels>> ] unit-test
{ t } [ \ with-state handler? ] unit-test
{ t } [ \ print "effect-row" word-prop row-effect? ] unit-test

[ "USING: effect-rows ; IN: effect-rows.tests.p1 E: p1 ( -- | nonsense ) ;" eval( -- ) ]
[ unwrap no-word-error? ] must-fail-with ! unknown label word

[ "USING: effect-rows kernel ; IN: effect-rows.tests.p2 E: p2 ( -- | dup ) ;" eval( -- ) ]
[ unwrap not-an-algebraic-effect? ] must-fail-with

[ "USING: effect-rows effect-rows.state ; IN: effect-rows.tests.p3 E: p3 ( -- | ..e ..f ) ;" eval( -- ) ]
[ unwrap duplicate-row-variable? ] must-fail-with

[ "USING: effect-rows effect-rows.io io ; IN: effect-rows.tests.p4 EFFECTFUL: print ( a b -- | io )" eval( -- ) ]
[ unwrap effectful-mismatch? ] must-fail-with

! ---- inference on quotations

{ { } } [ [ 1 2 + drop ] infer-effects nip ] unit-test
{ { state } } [ [ get-state drop ] infer-effects nip ] unit-test
{ { io state } } [ [ get-state print ] infer-effects nip ] unit-test
! branches: union
{ { io state } } [ [ [ get-state drop ] [ "x" print ] if ] infer-effects nip ] unit-test
! ordinary inline combinators are effect-polymorphic for free
{ { state } } [ [ [ get-state + ] map ] infer-effects nip ] unit-test
{ { io } } [ [ [ number>string print ] each ] infer-effects nip ] unit-test
{ { state } } [ [ [ get-state ] dip 2drop ] infer-effects nip ] unit-test
{ { io } } [ [ [ print ] curry call ] infer-effects nip ] unit-test
! the stack part is still inferred as usual
{ ( x -- x ) } [ [ [ get-state + ] map ] infer-effects drop ] unit-test

! handlers discharge
{ { } } [ [ 0 [ get-state 1 + put-state ] with-state drop ] infer-effects nip ] unit-test
! ... but other effects pass through the handler's row variable
{ { io } } [ [ 0 [ "hi" print get-state put-state ] with-state drop ] infer-effects nip ] unit-test
! nested in a polymorphic combinator, both directions
{ { } } [ [ 0 [ [ get-state + put-state ] each ] with-state ] infer-effects nip ] unit-test
{ { state } } [ [ [ 0 [ get-state + put-state ] with-state drop ] each get-state drop ] infer-effects nip ] unit-test
! a handler built from another handler
{ { } } [ [ 0 [ get-state 1 + put-state ] with-pure-state drop ] infer-effects nip ] unit-test
! with-pure-state's quotation row has no row variable: io is rejected
[ [ 0 [ "hi" print ] with-pure-state drop ] infer-effects ]
[ quotation-effect-mismatch? ] must-fail-with

! ---- checked definitions

E: count-to ( n -- total | ) 0 [ [ get-state + put-state ] each-integer ] with-state ;
{ 10 } [ 5 count-to ] unit-test
{ { } } [ \ count-to inferred-row ] unit-test

E: bump ( -- | state ) get-state 1 + put-state ;
E: bump-thrice ( -- n | ) 0 [ bump bump bump ] with-state ;
{ 3 } [ bump-thrice ] unit-test

E: chatty-count ( seq -- n | io ) 0 [ [ dup number>string print get-state + put-state ] each ] with-state ;
{ 6 } [ { 1 2 3 } chatty-count ] unit-test

! declaring more than the body performs is allowed (a "primitive" effect)
E: maybe-io ( -- | io state ) ;
{ { io state } } [ [ maybe-io ] infer-effects nip ] unit-test

! non-inline words with a runtime quotation parameter
E: call-io ( quot: ( -- | io ) -- | io ) call ;
{ { io } } [ [ [ ] call-io ] infer-effects nip ] unit-test

! ---- rejected definitions

[ "USING: effect-rows effect-rows.state kernel ; IN: effect-rows.tests.r1 E: r1 ( -- x | ) get-state ;" eval( -- ) ]
[ unwrap undeclared-effects? ] must-fail-with

[ "USING: effect-rows effect-rows.state kernel ; IN: effect-rows.tests.r2 E: r2 ( -- | ) get-state drop ;" eval( -- ) ]
[ unwrap effects>> { state } = ] must-fail-with

! state is discharged but io escapes and is not declared
[ "USING: effect-rows effect-rows.io effect-rows.state io kernel ; IN: effect-rows.tests.r3 E: r3 ( -- n | ) 0 [ \"x\" print ] with-state ;" eval( -- ) ]
[ unwrap effects>> { io } = ] must-fail-with

! effect hidden inside a polymorphic combinator
[ "USING: effect-rows effect-rows.state kernel sequences ; IN: effect-rows.tests.r4 E: r4 ( seq -- seq' | ) [ get-state + ] map ;" eval( -- ) ]
[ unwrap effects>> { state } = ] must-fail-with

! calling an effectful non-inline E: word
[ "USING: effect-rows effect-rows.state ; IN: effect-rows.tests.r5 E: r5 ( -- n | ) bump-thrice bump-thrice drop bump ;" eval( -- ) ]
[ unwrap undeclared-effects? ] must-fail-with

! a quotation that violates the handler's declared quotation row
[ "USING: effect-rows effect-rows.io effect-rows.state io kernel ; IN: effect-rows.tests.r6 E: r6 ( -- n | io ) 0 [ \"x\" print ] with-pure-state ;" eval( -- ) ]
[ unwrap quotation-effect-mismatch? ] must-fail-with
