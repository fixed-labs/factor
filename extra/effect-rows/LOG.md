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
