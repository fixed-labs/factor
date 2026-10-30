# effects (angle A: handlers as a pure Factor library) -- working log

Agent A. Branch `effects/a-library`. VM checkout `/home/dev/repo`.
Sibling agents: B = static effect typing in stack checker, C = native VM
delimited continuations. This work uses only existing Factor primitives.

## 2026-10-30

- Created VM, `git checkout -b effects/a-library`.
- Started build: `./build.sh net-bootstrap > ~/build.log 2>&1 </dev/null`
  (appends `BUILD EXIT n` to ~/build.log when done).
- Read core/continuations, extra/coroutines, extra/generators,
  extra/partial-continuations (Filinski-style shift/reset with a box).

### Design (decided before writing code)

Factor's callcc captures *everything*: datastack, callstack, retainstack,
namestack, catchstack. So delimited control is built Filinski-style: each
`handle` captures its own continuation R (the "handle site"), and every way
out of the delimited region (normal return, error, perform) is an *abort*:
`msg R continue-with`. The stale bottom of a captured stack is therefore
never returned into.

- Where does R live? In a fresh hashtable H pushed on the **namestack** by
  `handle` (key: private symbol `current-prompt`). Being in the namestack
  gives per-thread behaviour and correct restoration on non-local exits
  (`with-return`, coroutines, catching) for free.
- Messages to R: `return(v)`, `raised(error)`, `performed(op, k)`.
- `perform` = callcc1 to capture k (perform site), abort to R with
  `performed`. The handler clause then runs **at the handle site**
  (handle-site namestack/catchstack), not on top of the perform site.
- `resume ( v k -- obj )` = run a new `handle` (new R') whose body is
  "continue-with k". When perform's callcc1 returns, it **mutates H in
  place** so H's prompt = R'. (Replacing H instead of mutating would be
  wrong: the region's `recover` frame restores the old namestack copy
  on errors.)
- Errors in the region are caught by a `recover` in the region wrapper
  and aborted to R as `raised`, then rethrown at the handle site.
- Unhandled ops are forwarded: the inner handle re-performs at its own
  site (outside its region) and resumes its k with the answer.
- Deep handlers. Multi-shot is allowed (callcc copies). `discontinue`
  resumes k by throwing at the perform site so cleanups run.

### Implementation log

- NOTE: vocab is `algebraic-effects` (dir `extra/algebraic-effects/`),
  not `effects`: `core/effects` (stack effects) already owns that name and
  core wins the vocab-root search. Test with
  `./factor -run=tools.test algebraic-effects </dev/null`.
- Build finished OK (~10 min, `BUILD EXIT 0` in ~/build.log).
- Scratch experiments go in `~/repo/scratch.factor` (untracked), run with
  `./factor scratch.factor </dev/null`.
- Bugs hit while bringing it up:
  - `[ drop instance? ] with assoc-find`: `with` puts the curried value
    *between* key and value (`key op value`), so it is
    `[ drop swap instance? ] with`.
  - `resume`: `2curry` grabbed k+handler instead of value+k; fixed with
    `[ [ ... ] 2curry ] dip (handle)`.
- Core tests (24) pass: tail/non-tail/zero-shot/multi-shot, forwarding,
  shadowing, clause performs go outward, errors in body/clause/after
  resume, recover inside body across resume, discontinue runs `finally`,
  escaped resumptions, dynamic variables, 10000-op loop.
- PERF PITFALL 1: `run-state!` written with `::` locals was quadratic:
  a clause closing over a local compiles to `... resume 1 drop-locals`,
  so `resume` is not a tail call; each op leaves frames on the handle-site
  callstack, and each perform copies the callstack. Rewrote with an
  explicit mutable tuple + `curry`.
- PERF PITFALL 2: pure `run-state` was quadratic too (1000 iters 0.35 s,
  4000 iters 25 s). Probed callstack depth at the handle site: +18
  frames/op and +8 retainstack/op. Cause: `call( s -- r s )` *inside a
  curried quotation literal*. Such quotations run in the non-optimizing
  JIT, where `call(` is the checking `call-effect` (calls, then checks
  the datastack) -- not a tail call. Same `call(` in a named (optimized)
  word is a tail call (verified with a curry/call( loop: depth constant).
  Fix: move the step into named words `get-step`/`put-step`.
  After: 4000 iters (8000 ops) in ~24 ms, depth constant (42).
- Milestone 1 committed + pushed (core + state, all tests pass).
- Added examples: `algebraic-effects.generators` (push `collect`, pull
  `<gen>`/`gen-next` with escaped resumptions), `.restarts` (resumable
  exceptions: default / strict via discontinue / ask-outer),
  `.console` (input-line/output-line effects, real vs mock handler).
- Bug of my own worth remembering: in a clause, `invalid-number boa`
  *executes* the ERROR: word (throws immediately from the clause), so the
  error never went through `discontinue` and cleanups never ran. Must be
  `\ invalid-number boa`. Same trap applies to EFFECT: classes.
- Other test-writing traps: integers are not sequences (`4 [ ] map` fails,
  use `replicate`/`<iota>`); body quotations must be exactly ( -- obj ),
  checked at runtime by `call(`.
- All tests pass: `./factor -run=tools.test algebraic-effects` EXIT 0.
