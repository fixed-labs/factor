# delimited — working log (angle C: native delimited continuations)

Running log so another agent can resume. Newest at the bottom.

## 2026-10-30 setup
- VM b-53670027948c0e51de5743b9 (factor-master-c11), repo github:fixed-labs/factor @ master (3b4aa6e510), 2 cores.
- `git checkout -b effects/c-native`; started `./build.sh net-bootstrap > ~/build.log 2>&1 </dev/null` (appends `BUILD EXIT n`).
- Read: core/continuations/continuations.factor (callcc = full copy of ds/cs/rs/namestack/catchstack; `recover` is built on `ifcc` so it also copies the call stack),
  basis/threads/threads.factor (green threads use sub-primitives `(start-context)`, `(set-context)`, `(set-context-and-delete)`, `(start-context-and-delete)` from threads.private),
  vm/contexts.cpp (context pool `unused_contexts` capped at 10; new contexts get 3 mmap'd segments; context_object_count = 4: namestack, catchstack, context, in-callback-p — no spare slot),
  basis/bootstrap/assembler/x86.64.factor (jit-set-context / jit-start-context: save ctx, swap RSP + ds/rs regs, push param; O(1)).
  Note: `(start-context-and-delete)` actually *resets the current context* and jumps to a quot; it is not "start new, delete old".
- Decision: design (1) stack switching on existing contexts, no VM changes. See DESIGN.md.
- Current prompt found through a namestack binding (`current-fiber`), because there is no free context-object slot without a VM change.

## build + first prototype
- Build finished OK (`BUILD EXIT 0`, ~15 min wall incl. net-bootstrap download).
- Wrote extra/delimited/delimited.factor, delimited-tests.factor, bench/bench.factor.
- Name clashes found on load: `shift` (math), `resume` (threads), `associate` lives in hashtables, `context` in kernel.private.
  Renamed to `reset0`/`shift0` (accurate anyway: handler runs outside the prompt, k includes it = shift0/reset0) and `resume-k`/`throw-k`.
- Bugs fixed while testing: `case` default branch also receives the case value (discard needed `2drop`);
  `with` + `assoc-find` puts the curried param *between* key and value (broke clause lookup); a test clause dropped k instead of the effect.
- `./factor -run=tools.test delimited </dev/null` -> all pass (incl. 1e6 performs in one handle with flat stack, perform at depth 10,000, gc/compact-gc with 101 suspended fibers, 100k aborted handles without leaking contexts, resume from another green thread).
- First bench: perform via clause table was ~530 ns/op because non-literal `instance?` costs ~400 ns. Replaced with a per-handle class-of -> clause cache (hashtable, `class<=` scan on miss). Now ~160 ns/op. Added `handle-with` (user-written dispatcher) + `unhandled`.
- Bench (`./factor -run=delimited.bench </dev/null`), see NOTES.md for the table.

## GC stress, debug VM, context pool
- Added extra/delimited/stress (N generators via `handle*`, data kept on fiber stacks, nursery churn, `gc` every 5 rounds, `compact-gc` every 13).
  `./factor -young=1 -aging=1 -tenured=16 -run=delimited.stress 10000 </dev/null` -> ok.
- Built a debug VM out of tree: `mkdir ~/dbg; cp -r GNUmakefile vm build.sh ~/dbg; cd ~/dbg; make DEBUG=1 -j2` (~4 min);
  run with `~/dbg/factor -i=/home/dev/repo/factor.image ...`. Tests + stress pass on it with -young=1 -aging=1.
- Bench showed fresh-context creation is 20-35 us (3 mmaps) once the VM's 10-entry pool is empty, and freeing is a munmap.
  Added a library-level pool: finished bodies park their context in `set-context` (`fiber-pool-limit`, default 256); `start-fiber` switches into a parked one.
- BUG (fixed): first pool version had `fiber-main` call itself after parking. Calls to a `( -- * )` word are not tail calls, so each reuse leaked a frame
  (callstack length in a body: 6, 9, 12, ...). Symptom: the 100k-handle leak test went quadratic and looked like a hang (killed by timeout; no Factor bug report). Fixed with `loop`; added a regression test.
- `check-resumable` now also refuses a k whose context alien is `expired?` (saved image); startup hook clears the pool.
- No VM changes were made, so the core/compiler/threads regression suite was not required.
- 33 tests pass (release default heap, release -young=1 -aging=1, debug -young=1 -aging=1). Numbers in NOTES.md.
