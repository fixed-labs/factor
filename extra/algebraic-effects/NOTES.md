# algebraic-effects: notes

Algebraic effects with deep handlers for Factor, as a plain library on top
of `continuations` (callcc0/callcc1/continue-with) and `namespaces`. No VM
or compiler changes.

(The vocabulary is `algebraic-effects`, not `effects`: `core/effects` is
Factor's stack-effect vocabulary and wins the vocab-root search.)

## API

```factor
USING: algebraic-effects ;

EFFECT: ask ;               ! tuple class `ask` + word ask ( -- result )
EFFECT: tell value ;        ! tuple class with slot `value`, word ( value -- result )

perform      ( op -- result )                    ! what EFFECT: words call
handle       ( body: ( -- obj ) clauses -- obj )
handle-with  ( body clauses return: ( obj -- obj' ) -- obj' )
resume       ( value resumption -- obj )          ! re-enter with the same handler
resume-with  ( value resumption handler -- obj )  ! re-enter with another handler
discontinue  ( error resumption -- obj )          ! re-enter by throwing at the perform site
<handler>    ( clauses return -- handler )
unhandled-effect                                  ! thrown at a perform with no handler
```

`clauses` is an assoc `{ { class quot } ... }`; the first entry whose class
the op is an instance of wins. A clause is `( op resumption -- obj )`; its
result is the result of the `handle`.

```factor
[ ask 1 + ] { { ask [ nip 10 swap resume ] } } handle   ! => 11
```

Examples (each with tests):

- `algebraic-effects.state`: `get-state`/`put-state`; `run-state` is the
  textbook pure state-passing handler (non-tail resumes), `run-state!` keeps
  the state in a mutable cell (tail resumes).
- `algebraic-effects.generators`: `yield-value`; push-style `collect`, and
  pull-style `<gen>`/`gen-next`/`gen-take` where the clause does *not*
  resume but returns the resumption, which is resumed later after the
  `handle` has returned (escaped one-shot resumptions; infinite generators).
- `algebraic-effects.restarts`: resumable exceptions. `malformed-number`
  is signalled by `parse-number`; policies `with-default` (resume with a
  value), `with-strict` (discontinue: becomes a real `invalid-number` error
  at the signal site, cleanups run), `with-asking` (forwards a question to
  an outer handler).
- `algebraic-effects.console`: `input-line`/`output-line`. `with-console`
  uses the real streams; `with-mock-console` scripts input and collects
  output, so `greet` is tested without any IO.
- `algebraic-effects.benchmark`: `./factor -run=algebraic-effects.benchmark`.

Tests: `./factor -run=tools.test algebraic-effects </dev/null` runs 55
tests across the five vocabularies, all passing.

## How it works

Factor's `callcc` captures the *whole* context: datastack, callstack,
retainstack, namestack and catchstack, all copied. There is no delimited
capture, so delimited control is simulated the Filinski way: each `handle`
captures its own continuation R (the *handle site*, a prompt), and every
way out of the delimited region is an **abort** to R
(`msg R continue-with`):

| leaving the region by | message to R      | at the handle site            |
|-----------------------|-------------------|-------------------------------|
| body returns v        | `returned v`      | run return clause on v        |
| body throws e         | `raised e`        | `rethrow e`                   |
| `perform op`          | `performed op k`  | run the clause with op, k     |

`perform` captures k (the perform site) with `callcc1` and aborts. Since
the region is always left by an abort, the stale bottom of a captured stack
(the frames below the original `handle`) is never returned into.

`resume v k` runs a *new* handle (new prompt R') whose body is
`v R' k continue-with`. When `perform`'s `callcc1` returns, it installs R'
as the live prompt for the resumed region and returns v.

**Where the prompt lives.** In a mutable `prompt-cell` bound in the
namestack by `handle` (a fresh one-entry hashtable pushed with
`with-variables`). Putting it in the namestack, rather than in a global,
means non-local exits that restore an older namestack (`with-return`,
coroutines, an outer `recover`) automatically restore the right prompt, and
each thread has its own. On resume the cell is **mutated** (not replaced):
the region's own `recover` frame restores the namestack *captured at region
entry*, so a replaced cell would send errors raised after a resume to the
dead original prompt; with mutation every copy of the namestack sees the
live prompt. The cell also records its owning thread (see threads below).

**Forwarding.** Every perform aborts to the innermost handle. If no clause
matches, that handle re-performs the op at its own handle site (outside its
region, so the next handler out sees it) and resumes its k with the answer.
This is the standard forwarding semantics for deep handlers; it costs one
extra perform/resume per handler skipped (see numbers).

## Semantic decisions

- **Deep handlers.** `resume` reinstalls the same handler around the rest
  of the computation, and `handle-with`'s return clause also applies to
  results that come back through `resume` (as in OCaml/Koka). Shallow
  patterns are available through `resume-with`, which re-enters under a
  handler the clause chooses (tested: switching handler after the first
  op).
- **Clauses run at the handle site**, not on top of the perform site: with
  the handle site's namestack, catchstack and stacks. A clause's own
  performs go to the *outer* handlers; an error in a clause propagates out
  of the `handle`, not into the body. This is why the abort happens before
  the clause runs, instead of running the clause inside callcc1's quotation
  (which would run it with the perform site's dynamic environment).
- **Zero, one or many resumptions.** All allowed. Zero-shot = the clause
  returns without resuming (exceptions). One-shot is the common case.
  Multi-shot works because callcc copies the stacks: nondeterminism
  (`flip` resumed with t and with f, collecting all outcomes) is tested,
  including datastack values below the perform site. Resumptions can
  escape and be resumed after their `handle` returned (pull generators).
  There is no one-shot enforcement.
- **`discontinue`** (from OCaml) re-enters the region by *throwing* at the
  perform site, so `finally`, `cleanup` and `with-destructors` inside the
  body run; the error then propagates out of the clause's `discontinue`
  call. Tested with `finally` and with `with-destructors` + `&dispose`.
- **Body and results are single values.** A body is `( -- obj )`, an op
  returns one value, a clause returns one value. Arbitrary stack effects
  through a handle could be done by passing datastack arrays but are not.
- **Unhandled ops** throw `unhandled-effect` at the perform site, so they
  are catchable inside the body.

## Interaction with the rest of Factor

- **Dynamic variables.** The region carries its namestack in the
  continuation. After a resume the body sees the bindings it had at the
  perform (tested), and the clause sees the handle site's. For an escaped
  resumption (a pull generator resumed from elsewhere) the body keeps the
  dynamic environment of where it *started*, but effects it performs are
  forwarded to the handlers around the *resume* (tested: a generator body
  using `get-state` is served by the `run-state!` around `gen-next`).
  Bindings are shared, not copied, between multi-shot resumptions: the
  namespaces are hashtables and `get-namestack` only copies the vector, so
  a `set` in one shot is visible in the other.
- **`with-destructors`, `finally`, `cleanup`.** A zero-shot clause simply
  abandons the perform site: **cleanups in the body do not run** (tested,
  a `&dispose`d object stays undisposed). Use `discontinue` to unwind.
  Multi-shot plus destructors is unsafe: both shots share the same
  destructor vector, so the first shot to finish disposes resources the
  second shot is still using.
- **Errors.** Errors inside the region are caught by the region's `recover`
  and rethrown at the handle site, so they come out of `handle` (or out of
  the `resume` call in the clause, after a resume). `recover` inside the
  body works across resumes (tested). `rethrow` preserves the error but
  the debugger's error continuation is that of the handle site.
- **Threads.** Factor threads *inherit* the parent's namestack. Without a
  guard, a child thread spawned inside a `handle` that performs an op
  would continue-with the *parent's* handle-site continuation inside the
  child thread: the child then ran the rest of the parent's code (observed
  before the fix). The prompt cell now records its owning thread; a
  perform whose innermost prompt belongs to another thread throws
  `unhandled-effect` (tested). Resuming a resumption from a different
  thread rebinds the cell to the resuming thread; that path is untested.
- **Coroutines/raw continuations inside a region.** Fine as long as they
  stay inside one region instance. Re-entering a region by any means other
  than `resume`/`discontinue` (e.g. a raw continuation captured inside the
  region and invoked after a *different* shot of the same region was
  resumed) finds the cell pointing at the other shot's prompt and aborts
  to the wrong handle site. Single-shot use cannot hit this.
- **Static checking.** `perform` is `( op -- result )` to the stack
  checker; nothing tracks which effects a word may perform (that is
  sibling angle B's subject).

## What broke, and Factor surprises

1. **Tail position is load-bearing.** Each perform copies the whole
   callstack, so anything that makes the handle-site stack grow per op
   turns a loop of n ops into O(n^2). Two non-obvious ways this happens:
   - A clause written inside `::` that closes over a local compiles to
     `... resume 1 drop-locals`: `resume` is no longer a tail call.
     `run-state!` was rewritten with an explicit mutable tuple + `curry`.
   - `call(` inside a *curried quotation literal* runs in the non-optimizing
     JIT, where `call(` is the checking `call-effect` (calls, then checks
     the datastack height), which is not a tail call. The pure `run-state`
     took 25 s for 4000 iterations (+18 callstack frames and +8 retainstack
     entries per op at the handle site). Moving the step into named words
     (`get-step`/`put-step`), where `call(` compiles to a tail call, gave
     ~24 ms with constant depth. The same `call(` in an optimized word is a
     tail call even with a fresh curry each time (checked separately).
2. Callcc copies the **whole** stack, not just the delimited part, so the
   cost of every perform grows with total stack depth, including frames
   *below* the handle. Native delimited continuations (sibling angle C)
   would copy only the segment between handle and perform.
3. Small traps: `with` places its curried argument between the two inputs
   of an assoc quotation (`key op value`); `invalid-number boa` inside a
   quotation *executes* the ERROR: word (throws on the spot), it must be
   `\ invalid-number boa` (same for EFFECT: classes); `threads` also exports
   a word named `resume` (use `FROM: threads => spawn ;`); integers are not
   sequences (`4 [ ] map` fails).

## Numbers

`./factor -run=algebraic-effects.benchmark`, 2-core Intel Xeon @ 2.30GHz
VM, 3 runs (min / max), ns per operation:

| operation                                   | ns/op (min-max)  |
|---------------------------------------------|------------------|
| plain word call (loop of `plain-word +`)    | 7 - 12           |
| raw `callcc1` + `continue-with` round trip  | 440 - 580        |
| `throw` + `recover`                         | 920 - 1240       |
| `handle` with no perform                    | 930 - 1060       |
| **perform + resume (tail-resumptive)**      | **2640 - 3280**  |
| perform + resume, +10 frames under handle   | 2650 - 2710      |
| perform + resume, +100 frames               | 2690 - 2800      |
| perform + resume, +1000 frames              | 4760 - 5420      |
| perform through 1 non-matching handler      | 5210 - 5670      |
| perform through 4 non-matching handlers     | 13470 - 14650    |
| perform through 16 non-matching handlers    | 53790 - 57080    |

So a perform+resume is ~300x a word call, ~2.5-3x a throw/recover, and
~5x a bare callcc round trip (it does two captures, two restores, a
`recover`, a namespace push and a few allocations). Callstack depth adds
roughly 2 ns per frame per perform. Forwarding is linear, ~3.3 us per
skipped handler. State example: 8000 ops through `run-state!` or the
fixed `run-state` take ~25 ms (~3 us/op).

Obvious next steps if this were to be made fast: skip non-matching handlers
by searching a handler list before capturing (one abort straight to the
right prompt, re-installing the skipped handlers on resume); a fast path
for tail-resumptive clauses that avoids capturing R'; and, fundamentally,
a delimited capture in the VM so cost is proportional to the delimited
segment instead of the whole callstack.
