! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors arrays assocs combinators combinators.short-circuit compiler.tree.builder compiler.units
continuations effects effects.parser fry generic hash-sets kernel
lexer locals namespaces parser sequences sets sorting splitting stack-checker
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

! scopes: a stack of label sets; seen: every word applied (call edges)
TUPLE: row-observer scopes seen ;

: <row-observer> ( -- observer )
    HS{ } clone 1vector HS{ } clone row-observer boa ;

: current-scope ( observer -- set ) scopes>> last ;

: asserted-labels ( word -- seq )
    "effect-row" word-prop [ labels>> ] [ { } ] if* ;

: declared-labels ( word -- seq )
    dup inline? [ drop { } ] [ stack-effect row-of drop ] if ;

! When true, the row of an unannotated non-inline word is inferred from its
! body (and a generic's row is the union of its methods' rows) instead of
! being assumed empty. See "Transitive rows" below.
SYMBOL: transitive-rows?

DEFER: transitive-labels

! Labels a word carries itself, by assertion or declaration (f: none)
: direct-labels ( word -- seq/f )
    {
        { [ dup "effect-row" word-prop ] [ asserted-labels ] }
        { [ dup inline? ] [ drop { } ] }
        { [ dup stack-effect row-effect? ] [ declared-labels ] }
        [ drop f ]
    } cond ;

: word-labels ( word -- seq )
    dup direct-labels [ nip ] [
        transitive-rows? get [ transitive-labels ] [ drop { } ] if
    ] if* ;

: add-labels ( seq observer -- )
    current-scope '[ _ adjoin ] each ;

M: row-observer observe-word
    [ seen>> adjoin ] [ [ word-labels ] dip add-labels ] 2bi ;

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

: (with-row-observer) ( quot -- observer )
    <row-observer> [ inference-observer rot with-variable ] keep ; inline

: observer-labels ( observer -- labels )
    scopes>> first members sort-labels ;

: with-row-observer ( quot -- labels )
    (with-row-observer) observer-labels ; inline

: inferred-row ( word -- labels )
    '[ _ build-tree drop ] with-row-observer ;

! Transitive rows. Rows of unannotated words are computed on demand and
! cached globally (the cache is dropped whenever definitions change).
! Recursion, including through generic dispatch, is handled by iterating
! from the root until no cached row changes; rows reached by a finished
! root are final.

SYMBOL: row-cache
SYMBOL: final-rows
SYMBOL: row-changed?
SYMBOL: row-failures
SYMBOL: rows-inferred
SYMBOL: visited
SYMBOL: row-callees

: reset-row-cache ( -- )
    H{ } clone row-cache set-global
    HS{ } clone final-rows set-global
    HS{ } clone row-failures set-global
    H{ } clone row-callees set-global
    0 rows-inferred set-global ;

reset-row-cache

SINGLETON: row-cache-observer
! Macro expansion during inference can finish nested compilation units
! (temporary words), so only drop the cache when a word it depends on changed.
: row-relevant? ( obj -- ? )
    dup word? [
        {
            [ row-cache get-global key? ]
            [ "effect-row" word-prop ]
            [ stack-effect row-effect? ]
        } 1||
    ] [ drop f ] if ;

M: row-cache-observer definitions-changed
    drop members [ row-relevant? ] any? [ reset-row-cache ] when ;

row-cache-observer definition-observers get-global member-eq?
[ row-cache-observer add-definition-observer ] unless

: cached-row ( word -- seq ) row-cache get-global at [ { } ] unless* ;

GENERIC: body-labels ( word -- seq )

M: word body-labels
    dup primitive? [ drop { } ] [
        [
            dup '[ _ build-tree drop ] (with-row-observer)
            [ seen>> members swap row-callees get-global set-at ]
            [ observer-labels ] bi
        ] [ drop row-failures get-global adjoin { } ] recover
    ] if ;

M: generic body-labels
    dup "methods" word-prop values
    [ swap row-callees get-global set-at ]
    [ [ word-labels ] map concat ] bi ;

: transitive-labels ( word -- seq )
    dup final-rows get-global in? [ cached-row ] [
        dup visited get in? [ cached-row ] [
            dup visited get adjoin
            rows-inferred counter drop
            dup body-labels sort-labels over cached-row over =
            [ drop ] [ over row-cache get-global set-at t row-changed? set-global ] if
            cached-row
        ] if
    ] if ;

:: fixpoint-row ( quot: ( -- labels ) -- labels )
    f :> result!
    HS{ } clone :> seen
    [
        HS{ } clone visited [
            f row-changed? set-global
            quot call result!
            visited get members seen adjoin-all
        ] with-variable
        row-changed? get-global
    ] loop
    seen members final-rows get-global adjoin-all
    result ; inline

: root-row ( quot: ( -- labels ) -- labels )
    transitive-rows? get [ fixpoint-row ] [ call ] if ; inline

: with-transitive-rows ( ..a quot: ( ..a -- ..b ) -- ..b )
    [ t transitive-rows? ] dip with-variable ; inline

! After a transitive inference: a shortest call chain from word to a word
! that carries label directly. Explains where a label in a row comes from.
:: row-witness ( word label -- path/f )
    HS{ } clone :> seen
    V{ } clone :> queue
    f :> found!
    0 :> i!
    word 1array queue push
    word seen adjoin
    [ found not i queue length < and ] [
        i queue nth :> path
        i 1 + i!
        path last :> w
        label w direct-labels member? [ path found! ] [
            w row-callees get-global at [| c |
                c seen in? [
                    c seen adjoin
                    path c suffix queue push
                ] unless
            ] each
        ] if
    ] while
    found ;

:: infer-effects ( quot -- effect labels )
    f :> e!
    [ [ quot infer e! ] with-row-observer ] root-row e swap ;

ERROR: undeclared-effects word effects declared ;

M: undeclared-effects summary
    drop "A word performs effects missing from its declared effect row" ;

: check-word-row ( word -- )
    dup '[ _ inferred-row ] root-row over stack-effect row-of drop diff
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
