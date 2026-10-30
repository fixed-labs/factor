! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors arrays combinators compiler.tree.builder
effects effects.parser fry hash-sets kernel lexer locals
namespaces parser sequences sets sorting splitting stack-checker
stack-checker.state stack-checker.values summary vectors
vocabs.parser words words.symbol ;
IN: effect-rows

! Effect labels

: algebraic-effect? ( obj -- ? )
    dup word? [ "algebraic-effect" word-prop >boolean ] [ drop f ] if ;

: define-algebraic-effect ( word -- )
    [ define-symbol ] [ t "algebraic-effect" set-word-prop ] bi ;

SYNTAX: EFFECT: scan-new-word define-algebraic-effect ;

! Row effects: a stack effect plus the effects a word may perform

TUPLE: row-effect < effect
    { labels array read-only }
    { row-var read-only } ;

: sort-labels ( seq -- array )
    members [ name>> ] sort-by >array ;

: <row-effect> ( effect labels row-var -- row-effect )
    [
        { [ in>> ] [ out>> ] [ terminated?>> ] [ in-var>> ] [ out-var>> ] }
        cleave
    ] 2dip [ sort-labels ] dip row-effect boa ;

: ensure-row ( effect -- row-effect )
    dup row-effect? [ { } f <row-effect> ] unless ;

M: row-effect clone
    [ call-next-method ] [ labels>> ] [ row-var>> ] tri <row-effect> ;

: row-picture ( row-effect -- str )
    [ labels>> [ name>> ] map ]
    [ row-var>> [ ".." prepend 1array ] [ { } ] if* ] bi append
    "|" prefix " " join ;

M: row-effect effect>string
    [ call-next-method but-last ] [ row-picture ] bi " )" 3append ;

! The row of an effect, or f f when it carries no row information
: row-of ( effect -- labels var )
    dup row-effect? [ [ labels>> ] [ row-var>> ] bi ] [ drop f f ] if ;

! Parsing ( in -- out | labels ..var )

ERROR: not-an-algebraic-effect name ;
ERROR: duplicate-row-variable name ;

M: not-an-algebraic-effect summary
    name>> "Not an algebraic effect (define it with EFFECT:): " prepend ;

: parse-row-label ( token -- label )
    dup parse-word dup algebraic-effect?
    [ nip ] [ drop not-an-algebraic-effect ] if ;

DEFER: parse-row-effect

: parse-row-datum ( token -- value )
    dup "(" = [ drop parse-row-effect ] [
        parse-datum dup parsing-word? [
            V{ } clone swap execute-parsing
            dup length 1 = [ first ] [ bad-effect ] if
        ] when
    ] if ;

: parse-row-value ( token -- value )
    ":" ?tail [ scan-token parse-row-datum 2array ] when ;

:: parse-row-side ( ends -- var values end )
    f :> var!
    V{ } clone :> values
    f :> end!
    t :> first?!
    [
        scan-token :> tok
        {
            { [ tok ends member? ] [ tok end! f ] }
            { [ tok ")" = ] [ stack-effect-omits-dashes ] }
            { [ tok { "(" "--" "|" } member? ] [ bad-effect ] }
            { [ tok ".." head? ] [
                first? [ tok 2 tail var! ] [ invalid-row-variable ] if t
            ] }
            [ tok parse-row-value values push t ]
        } cond
        f first?!
    ] loop
    var values >array end ;

:: parse-row-labels ( -- labels var )
    V{ } clone :> labels
    f :> var!
    [
        scan-token :> tok
        {
            { [ tok ")" = ] [ f ] }
            { [ tok ".." head? ] [
                var [ tok duplicate-row-variable ] when
                tok 2 tail var! t
            ] }
            [ tok parse-row-label labels push t ]
        } cond
    ] loop
    labels >array var ;

! Parse the rest of an effect after its opening "(". Without a "|" the
! result is an ordinary effect; with one, a row-effect.
: parse-row-effect ( -- effect )
    { "--" } parse-row-side drop
    { ")" "|" } parse-row-side
    [ <variable-effect> ] dip
    "|" = [ parse-row-labels <row-effect> ] when ;

: scan-row-effect ( -- effect )
    "(" expect parse-row-effect ;

! Inference: an observer plugged into the stack checker

TUPLE: row-observer scopes ;

: <row-observer> ( -- observer )
    HS{ } clone 1vector row-observer boa ;

: current-scope ( observer -- set ) scopes>> last ;

: asserted-labels ( word -- seq )
    "effect-row" word-prop [ labels>> ] [ { } ] if* ;

: declared-labels ( word -- seq )
    dup inline? [ drop { } ] [ stack-effect row-of drop ] if ;

: word-labels ( word -- seq )
    [ asserted-labels ] [ declared-labels ] bi append ;

: add-labels ( seq observer -- )
    current-scope '[ _ adjoin ] each ;

M: row-observer observe-word
    [ word-labels ] dip add-labels ;

M: row-observer observe-quotation-enter
    nip HS{ } clone swap scopes>> push ;

ERROR: quotation-effect-mismatch combinator effects allowed ;

M: quotation-effect-mismatch summary
    drop "A quotation performs effects its combinator's declaration does not allow" ;

:: check-quotation-row ( effects q-effect combinator -- )
    q-effect row-of :> ( lq vq )
    q-effect row-effect? vq not and [
        effects lq diff [ combinator swap lq quotation-effect-mismatch ] unless-empty
    ] when ;

: handler? ( word -- ? ) "effect-handler" word-prop >boolean ;

! Which of a handler's quotation effects escape the handler
:: handler-escaping ( effects q-effect handler -- effects' )
    q-effect row-of :> ( lq vq )
    handler stack-effect row-of :> ( lw vw )
    effects [| e |
        e lq member? [ e lw member? ] [ vq vw = vq and ] if
    ] filter ;

GENERIC: escaping ( effects known -- effects' )

M: object escaping drop ;

! A non-inline word calling its quotation argument: the declared row of
! the quotation parameter is what the call may perform.
M: runtime-effect escaping nip effect>> row-of drop ;

M:: declared-effect escaping ( effects known -- effects' )
    known effect>> :> q
    known word>> :> w
    effects q w check-quotation-row
    w handler? q row-effect? and
    [ effects q w handler-escaping ] [ effects ] if ;

M: row-observer observe-quotation-exit
    [ scopes>> pop members swap escaping ] keep add-labels ;

: with-row-observer ( quot -- labels )
    <row-observer> [ inference-observer rot with-variable ] keep
    scopes>> first members sort-labels ; inline

:: infer-effects ( quot -- effect labels )
    f :> e!
    [ quot infer e! ] with-row-observer e swap ;

: inferred-row ( word -- labels )
    '[ _ build-tree drop ] with-row-observer ;

ERROR: undeclared-effects word effects declared ;

M: undeclared-effects summary
    drop "A word performs effects missing from its declared effect row" ;

: check-word-row ( word -- )
    dup inferred-row over stack-effect row-of drop diff
    [ drop ] [ over stack-effect row-of drop undeclared-effects ] if-empty ;

! Definers

: (E:) ( -- word def effect )
    [
        scan-new-word scan-row-effect ensure-row
        parse-definition swap
    ] with-definition ;

: define-row-word ( word def effect -- word )
    [ define-declared ] 3keep 2drop ;

SYNTAX: E: (E:) define-row-word check-word-row ;

SYNTAX: HANDLER:
    (E:) define-row-word
    [ make-inline ] [ t "effect-handler" set-word-prop ] bi ;

ERROR: effectful-mismatch word declared asserted ;

M: effectful-mismatch summary
    drop "EFFECTFUL: stack effect does not match the word's declared effect" ;

SYNTAX: EFFECTFUL:
    scan-word scan-row-effect ensure-row
    2dup [ stack-effect ] dip effect=
    [ "effect-row" set-word-prop ]
    [ over stack-effect swap effectful-mismatch ] if ;
