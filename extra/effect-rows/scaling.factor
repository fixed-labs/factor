! Scaling experiment: with only the io stream protocol annotated
! (effect-rows.streams), how well does transitive inference recover io
! rows for ordinary basis words, how many words does it have to infer, and
! how long does it take? Run: ./factor extra/effect-rows/scaling.factor
USING: accessors calendar effect-rows effect-rows.streams formatting
io io.encodings.utf8 io.files kernel math namespaces prettyprint
sequences sequences.private sets sorting tools.time words ;
IN: effect-rows.scaling

SYMBOL: result

: measure ( quot -- )
    dup [ [ infer-effects nip result set-global ] with-transitive-rows ] curry benchmark
    1,000,000 /i
    [ unparse ] dip
    result get-global [ name>> ] map ", " join
    rows-inferred get-global
    row-failures get-global cardinality
    "%-52s %5d ms  row: {%s}  inferred %d words, %d failed\n" printf ;

"-- cold cache: a fresh fixpoint for the first root --" print
reset-row-cache
[ "x" print ] measure
[ 3 . ] measure
[ 1 2 3 "%d %d %d\n" printf ] measure
[ "/tmp/x" utf8 file-lines drop ] measure
[ 1 2 + drop ] measure
[ { 3 1 2 } sort drop ] measure
[ "a" "b" append drop ] measure
[ H{ } clone [ 1 2 ] dip set-at ] measure
[ now drop ] measure

"-- why is stream-io in these rows? shortest call chain to an annotated word --" print
{ set-at sort now (append) assoc-union print }
[ dup stream-io row-witness [ name>> ] map " -> " join "%s: %s\n" printf ] each

"-- after reset, each root cold (reset before each) --" print
{ [ 1 2 + drop ] [ now drop ] [ { 3 1 2 } sort drop ] }
[ reset-row-cache measure ] each

"Sample of words whose bodies could not be inferred (assumed pure):" print
reset-row-cache [ [ [ 3 . ] infer-effects 2drop ] with-transitive-rows ] call
row-failures get-global members [ name>> ] map sort 25 index-or-length head .
