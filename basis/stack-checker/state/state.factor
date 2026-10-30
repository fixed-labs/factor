! Copyright (C) 2008, 2010 Slava Pestov.
! See https://factorcode.org/license.txt for BSD license.
USING: assocs arrays namespaces sequences kernel definitions
math effects accessors words classes.algebra
compiler.units stack-checker.values stack-checker.visitor
stack-checker.errors ;
IN: stack-checker.state

SYMBOL: terminated?

! Optional observer for extensions that track extra static information
! during inference (for example extra/effect-rows). It is f by default, in
! which case inference behaves exactly as without it.
SYMBOL: inference-observer

GENERIC: observe-word ( word observer -- )
GENERIC: observe-quotation-enter ( known observer -- )
GENERIC: observe-quotation-exit ( known observer -- )

: ?observe-word ( word -- )
    inference-observer get [ observe-word ] [ drop ] if* ;

: ?observe-quotation-enter ( known -- )
    inference-observer get [ observe-quotation-enter ] [ drop ] if* ;

: ?observe-quotation-exit ( known -- )
    inference-observer get [ observe-quotation-exit ] [ drop ] if* ;

SYMBOL: input-count
SYMBOL: inner-d-index

DEFER: commit-literals

SYMBOL: (meta-d)
SYMBOL: (meta-r)

: meta-d ( -- stack ) commit-literals (meta-d) get ;

: meta-r ( -- stack ) (meta-r) get ;

SYMBOL: literals

: (push-literal) ( obj -- )
    dup <literal> make-known
    [ nip (meta-d) get push ] [ #push, ] 2bi ;

: commit-literals ( -- )
    literals get [ [ (push-literal) ] each ] [ delete-all ] bi ;

: current-stack-height ( -- n )
    meta-d length input-count get - ;

: current-effect ( -- effect )
    input-count get "x" <array>
    meta-d length "x" <array>
    terminated? get <terminated-effect> ;

: check-effect ( required-effect -- )
    [ current-effect ] dip 2dup effect<= [ 2drop ] [ effect-error ] if ;

: init-inference ( -- )
    terminated? off
    V{ } clone (meta-d) set
    V{ } clone literals set
    0 input-count set
    0 inner-d-index set ;
