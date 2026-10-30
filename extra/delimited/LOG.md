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
