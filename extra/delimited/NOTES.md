# delimited — results and notes

Machine: Rift VM, 2 cores x86-64, release VM built by `./build.sh net-bootstrap`
from fixed-labs/factor master (3b4aa6e510). **No VM changes.**

## API (extra/delimited)

| word | effect | notes |
|---|---|---|
| `reset0` | `( quot: ( -- obj ) -- obj )` | prompt; body runs on its own context |
| `shift0` | `( quot: ( k -- obj ) -- obj )` | handler runs outside the prompt; k includes it |
| `resume-k` | `( obj k -- obj' )` | deep: returns at the body's end or next suspension |
| `throw-k` | `( error k -- obj' )` | resume by throwing at the suspension point |
| `discard` | `( k -- )` | abort a suspended k (runs its cleanups), free its context |
| `perform` | `( effect -- value )` | |
| `handle` / `handle*` | `( body clauses -- obj )` | clauses: `{ { class [ ( effect k -- obj ) ] } }`; `handle` discards an unresumed k on exit, `handle*` lets k escape (generators) |
| `handle-with` / `handle-with*` | `( body handler: ( effect k -- obj ) -- obj )` | hand-written dispatch; `unhandled ( effect k -- obj )` forwards |
| `fiber-pool-limit` | global, default 256 | parked contexts kept for reuse |

Names: `shift`/`resume` clash with `math`'s `shift` and `threads`' `resume`;
`shift0`/`reset0` is also the accurate name for these semantics.

## Benchmark (`./factor -run=delimited.bench </dev/null`)

depth = real (non-tail) frames between the handler/prompt and the capture.
200,000 ops per fiber cell; 20,000 (2,000 at depth 10,000) per callcc cell.

```
depth    perform  perform-w     shift0   callcc1+cw      recover      reset0     handle
        (ns/op)    (ns/op)    (ns/op)      (ns/op)      (ns/op)    (ns/op)    (ns/op)
     0      170.9      143.3      144.4        578.9        359.6      639.9      599.5
    10      169.6      149.2      129.7        505.4        345.0      592.2      616.2
   100      178.2      131.3      121.3        545.5        454.5      597.2      645.4
  1000      161.8      135.3      134.3       2180.9       1483.3      603.2      616.1
 10000      168.8      138.5      142.8      61866.6      95013.9      592.3      618.5
```

- `perform`: `perform` + clause + `resume-k` through `handle` (clause-table lookup).
- `perform-w`: same through `handle-with` with a compiled `ask?` test.
- `shift0`: `shift0` + `resume-k` through `reset0`.
- `callcc1+cw`: `[ ] callcc1` then `continue-with` it: one capture + one
  restore and no jump to a handler at all, i.e. a *lower bound* for a
  callcc-based effect handler. Depth 0 is not free: it still copies the
  frames below the benchmark (toplevel, `-run` machinery).
- `recover`: `[ ] [ drop ] recover`, for reference. It is built on `ifcc`, so it
  also copies the whole call stack today.
- `reset0`/`handle`: installing a prompt and running an empty body to the end.

**Capture+resume stays flat at ~120–180 ns from depth 0 to 10,000; callcc
grows linearly (0.5 µs → 2.2 µs → 62 µs).** Crossover vs the callcc lower
bound is already at depth 0.

Other costs:

```
handlers between perform and its handler:
    0 skipped:    173.7 ns/op
    1 skipped:    324.4 ns/op
    5 skipped:    875.5 ns/op
   20 skipped:   3574.6 ns/op
fibers kept alive (pool of 10 exhausted):
      10 live: create+suspend  11191.0 ns, discard   3416.0 ns
    1000 live: create+suspend  22497.2 ns, discard  24194.2 ns
   10000 live: create+suspend  35202.8 ns, discard  31382.8 ns
```

- Forwarding through a handler that does not match costs one extra switch pair
  per skipped handler (~170 ns each): linear in handler nesting, not stack depth.
- A context is three mmap'd segments (data 256 KiB, retain 256 KiB, call 1 MiB
  by default, plus guard pages). Installing a prompt is ~600 ns while a context
  is available from a pool; creating one fresh is 20–35 µs (mmap), and
  returning one beyond the pools is a munmap (~25 µs). The VM pool keeps only
  10 unused contexts, so the library keeps its own pool of parked contexts
  (`fiber-pool-limit`, default 256): a finished body parks its context in a
  `set-context` and the next prompt switches straight into it.
- `discard` of a fiber with a live pool context is ~3 µs, dominated by the
  `throw` of `fiber-aborted` that unwinds the body.

## Tests (`./factor -run=tools.test delimited </dev/null`)

33 tests, all passing, on both the release VM and a `make DEBUG=1` VM
(`-DFACTOR_DEBUG`), with default heap and with `-young=1 -aging=1`. Covered:
reset0/shift0 abort, resume, two shifts, nested prompts, one-shot enforcement,
no-prompt; reader/generator/state effects; 1,000,000 performs in one handle
with no stack growth; perform at depth 1,000 and 10,000; forwarding through
inner handlers (clause table and `handle-with`); superclass/`object` clauses;
unhandled effect; errors out of body, out of `resume-k` into a clause
`recover`, `recover` around `perform` in the body, `throw-k`, errors in
clauses; `discard` running `finally` cleanup and `handle`'s auto-discard;
dynamic variables (body sees prompt-time bindings, clause sees its own,
`set` stays local); `gc`/`compact-gc` with a suspended fiber and with 101
suspended fibers; green threads (`yield`/`sleep` in a body, resuming k from
another thread); 100,000 aborted handles (no context leak); reused contexts
do not accumulate frames.

## GC stress (`extra/delimited/stress`)

`./factor -young=1 -aging=1 -tenured=16 -run=delimited.stress N </dev/null`:
N generators (`handle*`, k escapes) stepped round-robin for 40 steps; each keeps
an array per step alive on its own stack across suspensions and verifies it at
the end; the driver churns the nursery, runs `gc` every 5 rounds and
`compact-gc` every 13.

| VM | heap | N | result |
|---|---|---|---|
| release | default | 2,000 | ok, 4.1 s, 217 MB max RSS |
| release | default | 10,000 | ok, 6.8 s, 349 MB max RSS |
| release | young=1 aging=1 tenured=16 | 2,000 | ok, 4.2 s |
| release | young=1 aging=1 tenured=16 | 10,000 | ok, 7.5 s |
| debug (FACTOR_DEBUG) | young=1 aging=1 | 1,000 | ok, 20.3 s |

Time is dominated by the full GCs/compactions, not by switches (N=200 also
takes ~3.7 s). 10,000 simultaneously suspended fibers is ~15 GB of *virtual*
stack reservations; RSS stays small because untouched stack pages are never
committed. `vm.max_map_count` is 1,048,576 on this box; on a default Linux
(65,530) each context's ~9 mappings would cap live fibers near 7,000.

## Crashes and bugs found

No VM crash ("You have triggered a bug in Factor") in any run.

Library bugs found while testing, all fixed:
- First pool version made `fiber-main` call itself after parking. A call to a
  `( -- * )` word is **not compiled as a tail call**, so every reuse of a
  context leaked a frame (callstack depth inside a body grew 6, 9, 12, ...),
  and 100,000 handles went quadratic (looked like a hang in the test run).
  Fixed with an explicit `loop`; regression test added.
- Non-literal `instance?` costs ~400 ns (a literal class folds to ~2 ns), which
  made clause-table dispatch 3x slower than the switch itself; replaced by a
  per-handle `class-of` cache.
- Factor-isms: `case`'s default branch also gets the case value; `with` over a
  two-argument `assoc-find` quotation puts the curried value *between* key and
  value.

## Limitations / future work

- One-shot only. Multi-shot needs copying the fiber's stacks (design 2).
- A k abandoned outside `handle` (or after a clause throws) holds its context
  until `discard`ed; aliens have no finalizers. `handle` covers the common case.
- Dynamic bindings made around a later `resume-k` site are not visible to the
  resumed body (it keeps the bindings from when the prompt was installed).
- `current-fiber` is found through a namestack binding (`assoc-stack` walk).
  A 5th context-object slot in the VM would make it O(1); the walk is cheap
  for normal binding depths, so it was not worth a VM change.
- Prompt installation (~600 ns) is dominated by `recover` (a callcc of the
  fiber's short stack), the namestack clone and the bind frame; a reusable
  catch continuation per parked context could cut it.
- A suspended k in a saved image should be refused on resume (its alien is
  expired; untested), and the pool is cleared by a startup hook.
- A body that calls `stop` (exits its thread) or returns from an alien
  callback across a fiber boundary is unsupported.
