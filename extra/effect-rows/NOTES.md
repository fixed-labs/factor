# effect-rows: notes

## What works

The full slice in DESIGN.md works end to end, with 44 tests, all passing
(`extra/effect-rows/run-tests.sh`):

* Syntax `( in -- out | labels ..var )`, nested inside quotation
  parameters, printed back by `effect>string`/`see`. Errors for unknown
  labels, non-effect words used as labels, duplicate row variables, and an
  `EFFECTFUL:` whose stack part disagrees with the word.
* Inference: effects flow from non-inline callees with declared rows and
  from `EFFECTFUL:` assertions. They also flow through `if`, `map`, `each`,
  `dip`, `curry`/`call` and any other inline combinator, with no annotation
  on those combinators.
* Handlers: `with-state` discharges `state` and passes everything else
  through `..e`. `with-pure-state` has no row variable on its quotation,
  so an `io` quotation is rejected (`quotation-effect-mismatch`). A handler
  defined in terms of another handler works.
* Checking: `E:` definitions that perform an undeclared effect fail at parse
  time with `undeclared-effects` and a source location. This covers effects
  hidden inside a `map`, effects escaping a handler, and effects coming
  from calling another `E:` word.
* Non-inline words that call a monomorphic quotation argument
  (`quot: ( -- | io )`, which this fork compiles through `call-effect`)
  contribute the quotation's declared row.
* Opt-in transitive mode (`with-transitive-rows`). Rows of unannotated
  words are inferred from their bodies, and a generic's row is the union of
  its methods' rows. Rows are cached, and recursion is resolved by a
  fixpoint. Mutual recursion and generic dispatch are covered by tests.
  `row-witness` gives a call chain that explains why a label is in a row.

The basis change is 28 lines: one variable and three hooks in
`stack-checker.state`, called from `M: word apply-object` and from the
`declared-effect` / `runtime-effect` `infer-call*` methods. Its value is
`f` by default. `./factor -run=tools.test resource:core compiler`:
7,955 test forms, 0 failures. `stack-checker` tests: 0 failures.

## What Factor's design made easy

* **Inlining is effect polymorphism.** Factor checks stack rows (`..a`) by
  re-inferring an inline combinator's body at every use, with the real
  quotation. Effect rows use the same mechanism for free. Instantiating
  `..e` for `each` just means watching the inlined body, so none of
  `sequences`/`kernel`/`combinators` needs an annotation. Explicit row
  variables are only needed where effects are *removed* (handlers) or
  *constrained* (a quotation parameter that must be pure, or must perform
  only `state`).
* **`declared-effect` values already carry what a handler needs.** The
  stack checker wraps each quotation input of an inline word in a
  `declared-effect` that knows the combinator word and the quotation's
  declared effect. The `infer-call*` method on it is exactly the scope of
  "effects performed by this quotation under this handler". The handler
  hook took no new data structures, only a scope push and pop around an
  existing method.
* **Effects are just tuples.** `row-effect < effect` can be a word's
  `"declared-effect"`, and every existing consumer keeps working on the
  stack part: the compiler, `effect=`, row-polymorphism checks and the
  prettyprinter (through one `effect>string` method).
* **Parsing words.** New definers (`E:`, `HANDLER:`, `EFFECTFUL:`,
  `EFFECT:`) live entirely in `extra/`. Labels resolve through the normal
  vocabulary search path, so they are namespaced and typos get Factor's
  usual "no word / add vocab" restarts.
* **`build-tree` is re-entrant.** Checking a word is just running the
  compiler front end with the observer bound. Transitive mode can call it
  again from inside an observer callback for callee bodies.

## What was hard or surprising

* **Effect syntax is parsed by core.** Nested `quot: ( ... )` goes through
  the core `(` parser, which would read `| io` as two more outputs.
  The opt-in definers therefore have their own effect parser, about 60
  lines that mirror `effects.parser`. Making `|` native would mean
  touching `core/effects/parser` (and `effect` itself, if the row should
  survive `clone`/`curry-effect`/`compose-effects`, which rebuild plain
  effects).
* **Check timing vs. `inline`.** `inline` is a separate parsing word that
  comes *after* `;`, so a check run at the end of `E:` cannot know whether
  the word will be inline. I made `E:` non-inline by design, with inline
  handlers going through `HANDLER:`. Checking at the end of the
  compilation unit (a definition observer) would remove the restriction,
  but an error thrown from an observer skips the remaining observers.
  The cleaner route would be to report through `compiler.errors` like
  ordinary inference errors.
* **Nested compilation units during inference.** Macro expansion
  (`define-temp` and friends) finishes compilation units *while* the stack
  checker runs. My first cache-invalidation observer cleared the
  transitive cache in the middle of a fixpoint. It now invalidates only
  when a changed definition is a cached or annotated word.
* **Unannotated means pure.** In the default mode an unannotated
  non-inline word contributes nothing. That is unsound by design: the
  checker only knows about effects someone declared. Transitive mode
  removes most of this, except for FFI (`alien-invoke`), primitives, and
  the ~55 words whose bodies cannot be inferred standalone (macros like
  `cond`/`cleave`, inline-only helpers). Those are assumed pure.
* **Literal quotations passed to non-inline words are not checked.** A
  quotation literal handed to a non-inline `quot: ( -- | io )` parameter is
  just a literal to the stack checker, so its body is never inferred
  against the declared row. A full design would infer literal quotations
  at the push site when the consumer's parameter has a row.
* **Handlers are trusted.** Like the stack effect of an inline word, a
  `HANDLER:` declaration is believed, not verified. Only words marked as
  handlers may discharge, so a plain combinator cannot silently swallow
  an effect. With a real perform/handle runtime (angle A), the handler
  body could be checked: it must install a handler for every label it
  claims to discharge.

## Could this scale to annotating real IO in basis/?

I ran an experiment (`extra/effect-rows/scaling.factor`, output in LOG.md).
I annotated only the 13 io stream-protocol generics (`effect-rows.streams`)
and turned on transitive inference:

| root                         | row          | correct? |
|------------------------------|--------------|----------|
| `"x" print`                  | {stream-io}  | yes      |
| `3 .`                        | {stream-io}  | yes      |
| `... printf`                 | {stream-io}  | yes      |
| `utf8 file-lines`            | {stream-io}  | yes      |
| `1 2 +`                      | {}           | yes      |
| `{ 3 1 2 } sort`             | {stream-io}  | **no**   |
| `"a" "b" append`             | {stream-io}  | **no**   |
| `H{ } set-at`                | {stream-io}  | **no**   |
| `now`                        | {stream-io}  | **no**   |

Cost: the first root reaches ~19-23k words (almost the whole image) and
takes ~10 s cold. After that, the cache answers each root in under 10 ms.

`row-witness` shows why the false positives happen:

    set-at -> linked-assoc=>set-at -> delete-at -> cache-assoc=>delete-at
           -> dispose -> pane-stream=>dispose -> write-gadget
           -> object=>write-gadget -> stream-write
    now -> now-gmt -> unix=>now-gmt -> io-error -> throw-errno -> strerror
        -> alien>string -> c-ptr=>alien>string -> stream-read-until

My view:

1. **Recall is good, and cheap to get.** Annotating a protocol (a dozen
   generics) is enough to find io in every real io word I tried. Nobody
   had to annotate `print`, `.`, `printf` or `file-lines`.
2. **Precision fails at open generic dispatch.** Taking the union over all
   methods of `dispose`, `set-at`, `equal?` and similar generics pulls in
   UI pane streams for any code that touches an assoc. This is not a bug
   in the prototype; it is what a context-insensitive effect analysis does
   with open, extensible dispatch. Factor's generics are everywhere, so
   this is the main obstacle.
3. **Factor uses its stream protocol for pure computation.**
   `alien>string` decodes through an in-memory byte-reader stream.
   Annotating the protocol therefore marks pure decoding as io. Real io
   would have to be annotated at *ports* (`io.ports`, the
   `io.backend`/`io.files` hooks, FFI), not at the protocol, and in-memory
   streams would have to be effect-free.
4. **Putting it together**, something workable would need:
   * leaf annotations on ports, FFI and primitives;
   * declared rows on the stream/assoc/sequence *protocol generics*,
     which method definitions would be checked against (an `M:` may not
     exceed its generic's row), instead of unioning methods;
   * transitive inference for everything else;
   * error-path effects (`throw` → `strerror`) either ignored or kept as a
     separate label.

   That is roughly how Koka and OCaml 5 typed effects handle open
   dispatch: the interface carries the row. In Factor it would mean
   annotating a few hundred protocol generics in core/basis. That is a
   big job, but much smaller than annotating every word, and the
   tool chain here (observer hook, row-witness, cached fixpoint)
   supports doing it incrementally.

Without (4), annotating basis IO is only useful in the "assert at the
leaves, assume pure elsewhere" mode. That mode is precise but unsound.
It is still a reasonable lint for application code that wants to keep
io out of a pure core.
