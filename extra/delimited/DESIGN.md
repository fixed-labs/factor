# delimited: one-shot delimited continuations on Factor contexts

Angle C of the effects experiment: runtime-level support for cheap delimited
continuations, as a substrate for effect handlers.

## The problem with `callcc`

`callcc0`/`callcc1` (core `continuations`) build a `continuation` tuple from
`get-datastack get-callstack get-retainstack get-namestack get-catchstack`.
`get-callstack` memcpy's the *entire* call stack of the current context into a
heap `callstack` object, and `continue-with` memcpy's it back with
`set-callstack`. An effect handler built on it pays O(total stack depth) on
both capture and resume, plus the GC cost of the copied stack objects. (Note
that `recover` is itself built on `ifcc`, so every `recover` also copies the
whole call stack today.)

## Candidates

1. **Stack switching (fibers, OCaml 5 style).** Run every `reset`/handler body
   in a fresh VM `context`. A capture is "switch back to the context that is
   waiting for us"; resume is "switch to the suspended context". Nothing is
   copied, so capture and resume are O(1) whatever the depth between handler
   and `perform`. Continuations are naturally one-shot (a context's stack
   can only be resumed once from a given point).
2. **Copy to the nearest prompt.** Push a marker frame at `reset`, and at
   `shift` copy only the frames above it. Cost is O(depth to prompt), not
   O(total depth); multi-shot is possible. Needs a new VM primitive (walk the
   call stack to a marker, copy a slice into a `callstack` object, splice it
   back on resume with the return address fixed up) and care with the GC's
   frame walker, the catchstack (which holds full continuations) and the
   namestack.

## Choice: (1), with **no VM changes**

Reading `vm/contexts.cpp` and `basis/bootstrap/assembler/x86.64.factor`
shows that the VM already has everything (1) needs, exposed as the
sub-primitives green threads use (`threads.private`):

- `(start-context) ( obj quot -- obj' )` — `new_context()` (from a pool of up
  to 10 recycled contexts, else three fresh mmap'd segments), save the current
  context, switch stack pointer + ds/rs registers, push `obj`, jump to `quot`.
  The caller is left suspended *inside* the primitive; when someone later
  switches back to it, the primitive "returns" the value passed.
- `(set-context) ( obj context -- obj' )` — save current context, switch to
  `context`, push `obj` there. A handful of instructions.
- `(set-context-and-delete) ( obj context -- * )` — same, but first returns the
  current context to the pool (used when a fiber's body finishes).
- `context ( -- alien )` — the current context.

Every context has its own data, retain and call stack segments and its own
context objects (namestack, catchstack). Suspended contexts stay in the VM's
`active_contexts` set, so the GC scans their stacks and fixes return addresses
on code-heap compaction exactly as it does for sleeping threads.

So the whole mechanism is a Factor library:

- A `fiber` tuple: its context alien, the context currently waiting on it
  (`parent`), a state (`running` / `suspended` / `dead`), and the prompt's
  handler.
- `reset` creates a fiber with `start-context`. Its body runs on the new
  stacks; `shift`/`perform` sends a message to `parent` with `set-context`;
  the parent dispatches. On finish the fiber sends `done`/`failed` with
  `set-context-and-delete`.
- `resume ( obj k -- obj' )` records the *resumer's* context as the new parent
  and switches into k. This gives deep-handler semantics: `resume` returns when
  the body finishes or suspends again, i.e. resume = reset around k.

### Semantics and decisions

- **Values across the boundary**: one object each way (`reset ( quot: ( -- obj
  ) -- obj )`). The body starts on an empty data stack; values are passed in
  the closure. This keeps a switch O(1); copying data stacks would make it
  O(datastack depth).
- **Finding the nearest prompt**: the fiber's namestack is a clone of the
  creator's plus one frame binding `current-fiber`. Each context has its own
  namestack, so nesting and handler code (which runs in the parent's context)
  see the right prompt automatically. Cost: an `assoc-stack` walk over the
  body's dynamic frames. (A VM change adding a 5th context-object slot would
  make it O(1); not needed for the prototype.)
- **Dynamic variables**: the body sees the bindings live at `reset`/`handle`
  time plus its own; it does *not* see bindings made around a later `resume`
  site. Handler clauses run in the handler's context and see the handler's
  bindings. Same model as OCaml 5 fibers with domain-local state, and the
  obvious one for contexts.
- **Errors**: the body's top level is wrapped in `recover`; an error is sent to
  the current parent as `failed` and `rethrow`n there, i.e. it propagates out
  of the `reset`, or out of the `resume` call that was running the body. The
  catchstack is per context, so `recover` inside the body only copies the
  fiber's own (short) call stack.
- **Prompt tags / forwarding**: `shift` and `perform` messages are distinct
  types. A prompt that does not handle a message re-sends it outward from its
  parent context and resumes k with the answer (standard deep-handler
  forwarding; one extra switch pair per skipped prompt).
- **One-shot**: resuming a running or dead fiber throws
  `continuation-not-resumable` instead of jumping to a dead or recycled
  context (the VM reuses context structs, so a stale alien could point to an
  unrelated live context — the state check is what makes this safe).
- **Abandoned continuations**: a suspended fiber holds a VM context (and its
  stacks are GC roots) until resumed or `discard`ed. `discard` resumes it with
  an abort token that throws `fiber-aborted` inside the body, so `finally` /
  `[ ] cleanup` blocks run, then frees the context. There are no finalizers on
  aliens, so an un-discarded fiber is leaked. `handle`/`handle-with` discard
  the fiber when they return if it is still suspended (no clause resumed it);
  this is done once per handler, *not* after every clause, so clauses still
  resume in tail position and a long-running handler's stack stays flat.
  `handle*`/`handle-with*` skip it, for uses where k escapes (generators).
- **Context reuse**: the VM's own pool keeps only 10 unused contexts; beyond
  that a context costs three mmaps to create and three munmaps to free
  (20-35 us each way). A finished body therefore parks its context in a
  library-level pool (`fiber-pool-limit`, default 256) by waiting in
  `set-context`, and the next prompt switches straight into it instead of
  calling `(start-context)`. The pool is cleared by a startup hook because
  context aliens do not survive `save-image`.
- **Green threads**: a body can `yield`/`sleep`; the scheduler boxes whatever
  context is current (the fiber) and switches back to it later. A k may even
  be resumed from a different thread (its parent becomes that thread's
  context).

### What this does not do

- Multi-shot continuations (would need (2) or a stack copy of the fiber).
- Bodies that exit their thread with `stop`, or callbacks that return across a
  fiber boundary, are unsupported.

## As built

Names: `reset0`/`shift0` (the handler runs outside the prompt and k includes
it, i.e. shift0 semantics; plain `shift` and `resume` also clash with `math`
and `threads`), `resume-k`, `throw-k`, `discard`, `perform`,
`handle`/`handle*` (class => clause tables) and `handle-with`/`handle-with*`
(hand-written dispatch, `unhandled` to forward). Results are in NOTES.md, the
working log in LOG.md.
