# effect-rows: algebraic effects in Factor's static stack-effect system

Angle B of the effects experiment: *static* tracking of which algebraic
effects a word may perform, inferred by the stack checker and checked
against declarations. Runtime semantics (perform/handle, continuations)
are out of scope here; the demo handlers use dynamic variables as a
stand-in, and could be swapped for a real perform/handle runtime.

## Syntax

A stack effect may end with an *effect row* after a `|`:

    ( x -- y | io state )      ! may perform io and state
    ( x -- y | )               ! explicitly pure
    ( quot: ( ..a -- ..b | state ..e ) -- ..b | ..e )   ! row variable ..e

* Labels are words defined with `EFFECT: name`. They are resolved through
  the normal vocabulary search path, so a typo is a parse error and two
  vocabularies can define distinct effects with the same name.
* A row variable reuses the `..name` spelling that stack rows already use
  (`..a`). It stands for "whatever other effects", and is what makes a
  quotation parameter effect-polymorphic.
* Why `|`: it is unused in effect syntax, sits after the outputs (so the
  stack part of the effect reads exactly as before), and mirrors row
  notation from Koka/Frank (`<io,state|e>`). Putting effects *inside* the
  `( -- )` keeps a single declaration per word, and it composes with nested
  quotation effects for free: `quot: ( x -- y | io )` is just a nested
  effect with a row.

The row syntax is only understood by the opt-in definers below; core's
`( -- )` parser is unchanged.

## Definers (all in `effect-rows`)

* `EFFECT: state` -- declare an effect label.
* `E: word ( ... -- ... | row ) body ;` -- a *checked* definition. Its
  body's effect row is inferred and must be a subset of the declared row.
  Checked at parse time, right after the definition, so a violation is a
  parse error with a source location. `E:` words are non-inline.
  A "primitive effect-performing word" is just an `E:` word that declares
  more than its body does (e.g. `get-state ( -- x | state )`).
* `EFFECTFUL: word ( ... | row )` -- *assert* a row for an existing word
  (e.g. `print` in `basis/io`), without editing its vocabulary; like
  `HINTS:`. The stack part must match the word's declared effect.
* `HANDLER: name ( ... ) body ;` -- an inline combinator that is *trusted*
  to discharge effects (see rules). Only handlers may remove effects.

## Representation

`row-effect` is a subclass of core's `effect` tuple, adding `labels` (an
array of effect words) and `row-var` (a string or f). Because it is an
`effect`, it can be the word's `"declared-effect"` and every existing
consumer (stack checker, compiler, prettyprinter via an `effect>string`
method) keeps working on the stack part. Nested quotation effects in
`in>>` are row-effects too, so the stack checker's `declared-effect`
values carry them to the place where the quotation is called.

## Inference

The stack checker gets one tiny opt-in hook (three call sites in
`basis/stack-checker`): an `inference-observer` variable, `f` by default.
When set, it is told about

1. every word application (`M: word apply-object`), and
2. entering/leaving the call of a declared quotation parameter of an inline
   combinator (`M: declared-effect infer-call*`) and of a runtime-effect
   quotation parameter of a non-inline word (`M: runtime-effect infer-call*`).

The effect-rows observer keeps a stack of scopes (sets of labels):

* **Word application.** A non-inline word contributes the labels of its
  declared row (if any); any word contributes the labels asserted by
  `EFFECTFUL:`. Inline words contribute nothing themselves: the stack
  checker infers their bodies in place, so the effects of their bodies are
  observed directly. Unannotated non-inline words are assumed pure (see
  NOTES for the soundness discussion).
* **Branches.** `if`/`case`/`cond` infer every branch, so the row is the
  union of the branches -- an over-approximation, as with any effect system.
* **Quotation parameters / handlers.** When an inline combinator `W` calls
  its declared quotation parameter `q`, a fresh scope collects the
  quotation's effects `R`. On exit:
  - If `q`'s declared effect has no row (ordinary `each`, `map`, `dip`,
    `bi`, ...), `R` escapes unchanged: *these combinators are
    effect-polymorphic for free*, because Factor inlines them.
  - If `q` declares a row `Lq` (with optional variable `vq`), each effect
    `e` in `R` not in `Lq` requires `vq`; otherwise it is a
    `quotation-effect-mismatch` error.
  - If `W` is a `HANDLER:` with declared row `Lw | vw`, an effect `e` in `R`
    escapes iff (`e` in `Lq` and `e` in `Lw`) or (`e` not in `Lq` and
    `vq = vw`). So `( quot: ( ..a -- ..b | state ..e ) -- ..b | ..e )`
    discharges `state` and passes everything else through `..e`. A
    non-handler never discharges: everything in `R` escapes.
  - A runtime quotation parameter (non-inline word calling its `quot:`
    argument) contributes the labels its declared row names.
* **Checking.** For an `E:` word, the tree builder (`build-tree`, i.e. the
  same inference the optimizing compiler runs) is run with the observer
  bound; the final scope must be a subset of the declared labels, else
  `undeclared-effects`. `infer-effects ( quot -- effect labels )` does the
  same for a quotation, for REPL use and tests.

## Polymorphism over quotation effects

Factor's stack rows (`..a`) are only meaningful for inline combinators,
whose bodies are re-inferred at each use with the actual quotation. Effect
rows ride on the same mechanism: instantiating `..e` at a call site is
simply observing the inlined body with the actual quotation. Explicit row
variables matter in exactly two places: (1) handler declarations, where
`..e` says which effects pass through vs. are discharged, and (2)
constraining a quotation parameter (`quot: ( x -- y | )` = must be pure),
where omitting the variable makes extra effects an error.

## Slice

* `effect-rows` -- syntax, row-effect, observer, checker, errors.
* `effect-rows.state` -- `EFFECT: state`, `get-state`, `put-state`, and the
  `with-state` handler.
* `effect-rows.io` -- `EFFECT: io` and `EFFECTFUL:` annotations on a few
  `io` words.
* Tests for accepted and rejected programs.

## Additions after the first slice

* `effect-rows.streams` -- the io stream-protocol generics asserted as
  `stream-io`, for the scaling experiment.
* Transitive mode: `with-transitive-rows` makes an unannotated non-inline
  word contribute the row inferred from its body (via `build-tree`), and a
  generic word the union of its methods. Rows are cached globally; the
  cache is dropped when a cached or annotated word is redefined. Recursion
  is handled by re-running the root until no cached row changes.
  `row-witness ( word label -- path )` returns a shortest call chain to a
  word that carries the label directly. See NOTES.md for what this shows
  about basis.
