# effect-rows work log (agent B: effects in the static stack-effect system)

Branch: `effects/b-static` (from `master`). VM checkout: /home/dev/repo.

## 2026-10-30

- Created VM, started `./build.sh net-bootstrap > ~/build.log` (foreground
  command, long timeout; Rift commands each have their own PID namespace so
  backgrounding with `&` is not safe).
- Read `core/effects`, `core/effects/parser`, `basis/stack-checker/{state,
  backend,values,inlining,known-words,row-polymorphism}` and
  `basis/compiler/tree/builder`. Key findings:
  - Every word application goes through `M: word apply-object`
    (inlining.factor); inline words are inferred in place.
  - Inline combinators' quotation inputs are wrapped as `declared-effect`
    knowns by `declare-input-effects`; calling one goes through
    `M: declared-effect infer-call*` (known-words.factor), which knows both
    the combinator word and the declared quotation effect. This is the
    natural hook for handlers.
  - This fork lets non-inline words call monomorphic quotation params
    (`runtime-effect`, set up by `declare-runtime-effects` in the tree
    builder); they go through `M: runtime-effect infer-call*`.
- Wrote DESIGN.md (syntax `( in -- out | labels ..var )`, `E:` / `HANDLER:` /
  `EFFECTFUL:` / `EFFECT:`; row-effect subclass of effect; observer hook).
- Decided on a minimal opt-in hook in basis (variable `inference-observer`,
  f by default, 3 generic hooks) rather than redefining stack-checker
  methods from extra/ (monkey-patching would change global behaviour when
  the vocab loads). (Applied with a throwaway perl script; see the git diff of basis/stack-checker.)
- Wrote extra/effect-rows/{effect-rows.factor, state/, io/, tests}.
- Waiting for the build to finish before applying the basis patch (the
  bootstrap loads basis from source while it runs).
- Build finished (BUILD EXIT 0). Saved the unpatched image as ~/clean.image.
  Applied the basis patch, then `./factor -e='USING: vocabs.refresh memory ;
  refresh-all "factor.image" save-image'` (clean, no errors).
- `extra/effect-rows/run-tests.sh` loads effect-rows and runs its tests
  (log: ~/er-test.log). First run: all but one test passed. The failure
  was the unknown-label test: `search` returned f; switched to
  `parse-word` (gives a proper no-word error with restarts) and taught
  the test's `unwrap` to strip both `lexer-error` and `condition`.
  Second run: 0 failures.
- Started `./factor -run=tools.test resource:core compiler` on the patched
  image (log: ~/core-tests.log) and `tools.test stack-checker`
  (~/sc-tests.log: 159 tests, 0 failures).
- Added opt-in *transitive rows* (`transitive-rows?`, `with-transitive-rows`):
  rows of unannotated non-inline words are inferred from their bodies via
  `build-tree`; a generic's row is the union of its methods' rows; cached
  globally, cache dropped by a definition observer on any redefinition;
  recursion (incl. mutual and through dispatch) handled by re-running the
  root until no cached row changes, then marking reached rows final.
  (Spliced in with a throwaway perl script.) Added `effect-rows.streams`
  asserting a `stream-io` label on the io stream-protocol generics.
- Tests: 44 tests, 0 failures (incl. recursion, mutual recursion, generic
  union, and an `E:` word rejected in transitive mode through a helper).
- Scaling experiment `./factor extra/effect-rows/scaling.factor` (log:
  ~/scaling.log). Bugs found on the way:
  1. My definition observer cleared the row cache *during* inference,
     because macro expansion finishes nested compilation units
     (define-temp). Fixed: invalidate only if a changed definition is a
     cached or annotated word.
  2. The script used `set` inside `with-variable`, so the value was lost
     (rows printed as {}). Switched to set-global.
- Added call-edge recording (`seen` slot of the observer, `row-callees`)
  and `row-witness`. Results (only the stream protocol annotated):
    -- cold cache: a fresh fixpoint for the first root --
    [ "x" print ]                                        10587 ms  row: {stream-io}  inferred 22920 words, 55 failed
    [ 3 . ]                                                  0 ms  row: {stream-io}  inferred 22922 words, 55 failed
    [ 1 2 3 "%d %d %d\n" printf ]                            3 ms  row: {stream-io}  inferred 22925 words, 58 failed
    [ "/tmp/x" utf8 file-lines drop ]                        0 ms  row: {stream-io}  inferred 22925 words, 58 failed
    [ 1 2 + drop ]                                           0 ms  row: {}  inferred 22925 words, 58 failed
    [ { 3 1 2 } sort drop ]                                  8 ms  row: {stream-io}  inferred 22927 words, 58 failed
    [ "a" "b" append drop ]                                  0 ms  row: {stream-io}  inferred 22927 words, 58 failed
    [ H{ } clone [ 1 2 ] dip set-at ]                        0 ms  row: {stream-io}  inferred 22927 words, 58 failed
    [ now drop ]                                             9 ms  row: {stream-io}  inferred 22969 words, 58 failed
    -- why is stream-io in these rows? shortest call chain to an annotated word --
    set-at: set-at -> linked-assoc=>set-at -> delete-at -> cache-assoc=>delete-at -> dispose -> pane-stream=>dispose -> write-gadget -> object=>write-gadget -> stream-write
    sort: sort -> equal? -> persistent-hash=>equal? -> assoc= -> assoc-subset? -> >alist -> mirror=>>alist -> set-at -> linked-assoc=>set-at -> delete-at -> cache-assoc=>delete-at -> dispose -> pane-stream=>dispose -> write-gadget -> object=>write-gadget -> stream-write
    now: now -> now-gmt -> unix=>now-gmt -> io-error -> throw-errno -> (throw-errno) -> strerror -> linux=>strerror -> alien>string -> c-ptr=>alien>string -> stream-read-until
    assoc-union: assoc-union -> assoc-union-as -> set-at -> linked-assoc=>set-at -> delete-at -> cache-assoc=>delete-at -> dispose -> pane-stream=>dispose -> write-gadget -> object=>write-gadget -> stream-write
    -- after reset, each root cold (reset before each) --
    [ 1 2 + drop ]                                        9474 ms  row: {}  inferred 18905 words, 55 failed
    [ now drop ]                                         10306 ms  row: {stream-io}  inferred 22812 words, 55 failed
    [ { 3 1 2 } sort drop ]                               9923 ms  row: {stream-io}  inferred 22692 words, 55 failed
- Wrote NOTES.md (what worked, what was easy/hard, scaling verdict).
- Final: effect-rows tests 44/44 pass; core+compiler 7,955 test forms,
  0 failures (basis unchanged since that run; only extra/ changed after).
