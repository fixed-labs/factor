! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: algebraic-effects algebraic-effects.console io
io.streams.string kernel tools.test ;
IN: algebraic-effects.console.tests

! The program runs without any real IO
{
    "Jake"
    {
        "What is your name?"
        "Hello, Jake!"
        "How old are you?"
        "Next year you will be 43"
    }
} [ [ greet ] { "Jake" "42" } with-mock-console ] unit-test

{
    "Ada"
    { "What is your name?" "Hello, Ada!" "How old are you?" "That is not a number." }
} [ [ greet ] { "Ada" "old" } with-mock-console ] unit-test

! Same program against real (string) streams
{ "Jake" "What is your name?\nHello, Jake!\nHow old are you?\nNext year you will be 43\n" } [
    "Jake\n42\n" [
        [ [ greet ] with-console ] with-string-writer
    ] with-string-reader
] unit-test

