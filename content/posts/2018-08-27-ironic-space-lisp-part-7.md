---
title: "Ironic Space Lisp Part 7"
date: 2018-08-27T15:56:11-07:00
---

Let's talk about the VM internals. I've written a compiler for ISL, and
implemented functions at the same time. This is not a mistake or an over-reach,
rather a natural progression. To the VM, what is a function? The VM doesn't have
a strong concept of "functions", or even of procedures. It has the `Call` and
`Return` operations. These operations are the only way to manipulate the frame
stack in a meaningful way: `Call` pushes an address to the frame stack, jumping
to it, while `Return` pops an address, returning to the caller. So the VM has a
concept of blocks of code you can jump to which will do "things" to the data
stack, and then return back to you, maybe.

The data stack is totally unprotected from the callers, with no stack
"blockades" or "breakpoints", although you could imagine a such a system to
prevent stack destruction. This system would only be useful for calling
untrusted bytecode, because a compiler emitting those instructions would be a
bug. There is also no guarantee that your caller will return to you: they could
totally ignore you and enter an infinite loop. The VM is already slow and stupid
enough, I think this sort of security is better addressed at the "OS" or
scheduler level. The VM struct represents a single executing thread, so to
accommodate the planned parallel execution environment, multiple VMs would be
scheduled on OS threads. Launching a new VM/thread would be a normal task, so
extending that system to permit launching restricted VMs without certain
"syscalls", like thread launch, message passing to anybody except the leader, etc.

I had planned to implement these "syscalls" as a table, and adding capabilities
to a VM was just pushing Rust-level function into the table. Rather than use a
separate `Syscall` operation, it's currently implemented as addresses you can
`Call`: the VM hooks the instruction decode step and looks them up. When you add
syscalls to the table, you'd get an address back, and you store the address in
then environment, and can use normal function call semantics. To add more
syscalls to extend the VM's capabilities, you'd push more functions to the
table, and get more addresses back that you then bind to the environment and
continue executing bytecode. That means you can't rely on a stable syscall
interface, you have to reference the environment binding each time. You also
can't do pre-execution optimization to replace function variable references with
address literals because the address literals are VM-instance specific, and
dependent on the _order the syscalls were installed in the VM._ If you were
interested in strongly confounding compilers that _do_ rely on syscall order,
you could randomize the syscall distribution and order, but that seems excessive.

# ISL Bytecode

To make life easier, ISL bytecode is stored in the `Bytecode` class, which is a
vector of `Chunk`s which are vectors of operations. This is largely code-only
memory, with the exception of the `Op::Lit` operation, which holds a
`data::Literal`. The rest of the program's memory is in the data stack and the
environment bindings: no generic contiguous memory allocation or access for this
VM. Normal machine code isn't as segmented as ISL bytecode, and although the
layout depends on compiler, OS, etc., the actual code of the machine code is
generally a single contiguous array.

This `Vec<Vec<Op>>` architecture was designed to make my job as an implementer
easier, but potentially allow more efficient bytecode packing in the future.
Addresses are tuples of `(chunk_index, operation_index)`, so nothing is forcing
the VM and compiler to use chunks, and chunks don't mean anything to do the VM,
so compiler writers can can use them how they wish.

The VM and bytecode do make 2 assumptions. The first is that, after executing a
particular instruction that isn't a jump (not `Jump`, `JumpCond`, or `Call`),
the next instruction to execute can be found at the next _operation index_ in
the _same chunk_. This is easy to understand, basically what you expect, and
matches the efficient execution strategy in accordance with branch prediction
and predictive cache filling for modern CPUs.

The other assumption is how you will want to load additional code into your VM.
I'm planning on allowing ISL to load additional code into its VM at runtime,
either in the form of `eval` compiling the code rather than simply evaluating
it, or loading libraries dynamically, or receiving new code over the wire from
"colleague VMs" and executing it. Currently, this is implemented by copying
chunks from one bytecode to another, adding the new chunks to the end of the
existing chunks, and iterating over all the new operations, adding the new chunk
offset to all the addresses, so the addresses stay locally consistent. This
process returns the address of the first new chunk: by convention, this is the
"main" function for each bytecode. Because the `Call` and `Return` instructions
don't manipulate the environment (compilers have to emit instructions do this
manually), you can use this main function to add name-address bindings to the
global environment.

You can't do this at runtime yet (because I haven't fully built syscalls yet),
but you can do it from Rust, which is how the new REPL works! Yes, real REPL
which compiles to bytecode.

## ISL Function Interface

To simplify things for implementers (me), functions are quite simple. Each
function lives in its own chunk. Thus, you can call a function by jumping or
`Call`ing the 0th operation index for that chunk. Currently, it is assumed that
functions themselves will manage their environments, pushing and popping
environments as necessary. Thus, if future optimizations can remove a function's
need for environmental interaction, those operations can be elided directly,
rather than signaling all the call sites that the instructions aren't
necessary.

ISL functions take arguments on the stack, and arity information is not
contained within the bytecode. It's not implemented at all, and would have be be
implemented in an earlier pass. However, most languages like binding arguments
to names and then reusing them, so you can use the `Store` operation to put
arguments in the local environment. Well behaved functions consume all the
arguments passed to them, and leave a single value on the stack (they could
leave multiple values, but that could be messy, difficult for compilers to
utilize, and hopefully not necessary with the addition of better data
structures). Then they pop their environment (if necessary) and call `Return`,
which pops the frame stack and returns control to their caller. This interface
is nicely barebones, and can fit with a number of different programming and
compiler styles.

This does mean that functions aren't really language level values, they're
bytecode in the bytecode-store, rather than in the runtime data-store. Currently
ISL solves this by using data-level addresses to represent functions. You can
load a keyword from the environment, get an address, then call that address with
some arguments, and it'll all work right. Because the address is normal value,
you can reassign it, use it in local bindings, even compose them (maybe), and it
still refers to a chunk of bytecode, in the end.

However, functions aren't closures, and closures are a very important part of
higher-order programming, and Lisp in particular. Closures will need substantial
direct support in the compiler, and because I don't think it can be done
through the existing syscall infrastructure. It could be done as an operation,
but parameterizing it would be difficult: most of the relevant variable data
(precisely which values to close over) exists in the AST and compiler, but is
lost by the time it reaches bytecode. Calling a closure involves pushing an
environment, adding all the new bindings, and then calling the enclosed
function. This could be done at callsite, increasing the size of the bytecode,
or could be done in another chunk which then calls the wrapped function. This
adds another push to the frame stack, but with tail call optimization, that can
be avoided.

# The Current Compiler

The current compiler is dumb and has 3 phases. I'm tempted to name it something
like "failure", but I already use a library called failure, or fuckwit, or
"a disaster in three acts", or something. I'm not exactly proud of it. It works, but
produces some pretty shitty bytecode. This is the bytecode version of `(def x 1)
x`, annotated manually:


```
        (0, 0)  Lit     N(1)
        (0, 1)  Lit     :"x"
        (0, 2)  Store           // Store x = 1
        (0, 3)  Lit     :"x"
        (0, 4)  Load            // load x
        (0, 5)  Pop             // pop x
        (0, 6)  Lit     :"x"
        (0, 7)  Load            // load x
        (0, 8)  Return          // return

```

It stores x, it loads it, it pops it, and it loads it again before returning.
Holy shit.


There are 2 major hurdles to get over when compiling ISL: if and functions. If
is easy in the sense that it directly maps to a known operation, `JumpCond`, but
`JumpCond` takes 2 addresses and a value, and jumps based on the value. But the
compiler doesn't really know where to jump, exactly: from the middle of an AST,
it's hard to know where the code you're writing, so you can't really emit a
literal address. You could maybe emit a literal address, and then update address
values as the bytecode moves around, a little like the bytecode importing I
described above works, but that sounds really complicated, and very bookkeeping
heavy. It does sound pretty generic, so you could build and test it in isolation
and without loss of generality, but I decided to take a different approach. That
different approach is an intermediate representation for operations. This
intermediate pass is comparatively simple, and really only deals with the
difficulties of `JumpCond`.

```rust
pub enum IrOp {
    Lit(Literal),
    Return,
    Call,
    Jump,
    JumpCond {
        pred: Rc<IrChunk>,
        then: Rc<IrChunk>,
        els: Rc<IrChunk>,
    },
    Load,
    Store,
    PushEnv,
    PopEnv,
    Dup,
    Pop,
}
```

This phase of the compiler is implemented as an `ASTVisitor<IrChunk>`. It walks
the AST tree and produces a vector of intermediate operations that may point to
other vectors of intermediate operations. A lot of this phase is just emitting
one or 2 instructions, and then appending the chunks generated from `visit`ing
the AST child nodes. The mapping between `IrOP` and the bytecode native `Op` is
pretty clear, but the packing problem of getting all the `JumpCond` chunks in
the right place is a little tricky, so I wrote a packer to pack it all together.
You can see it [`compiler::pack`][compiler_pack]. It's purpose is to pack an
`IrChunk` into a `Bytecode` starting at a particular chunk and op index. It
returns the final operation index, which allows you to chain pack `IrChunks` into
the same `Chunk`, if the packer thinks they can fit together. The packer "allocates"
subsequent chunk indexes with the naive algorithm of just adding another chunk
to the end and returning its index.

The packer's similarly naive approach to packing `IrOp::JumpCond` into the
bytecode is to just allocate new chunks for the 2 branches of the `JumpCond`,
pack those `IrChunks` with a recursive call to `pack`, and then push jumps back
to the current jump on the end. Thus each `if` expression adds 2 chunks. This
could obviously be a lot smarter, but I'm avoiding premature optimization for
now. Additionally, `JumpCond` could be `JumpIfTrue` instead. Changing that now
wouldn't be too hard, because operation set isn't too integrated into the
project, just in the VM and compiler. It might not even require a change to the
`IrOp` or compiler AST phase, just to the packer.

Anyway, I consider the AST compiler one phase, and the packer the second phase.
The third phase is the phase that implements functions. This whole article is
written a little backwards. The above explanation of the bytecode, the function
interface, etc. were all developed alongside this third pass, so before I wrote
this pass, I had no idea how functions were going to be compiled. Phase 1 errors
out on lambdas. It still does, to be fair, but Phase 3 now replaces all lambdas
with something else.

As part of my plan to not read very much literature and just see what happens,
I've named Phase 3 "Function Lifting". As it turns out, [lifting][lifting] is
something different, and I may have made a big mistake, and may have to rename
it. Oh well.

The [`ast::passes::function_lifting`][isl_lifter] module is an AST pass (it implements
`ASTVisitor`) to produce a `LiftedAST`, which is an AST with all the functions
removed, placed into a `FunctionRegistry`, and replaced in the AST with an
address in the form `(registry index, 0)`. This implementation is tightly bound
to the compiler, and any compiler that consumes `LiftedAST`s (usually called
`last` in the code base and damn the consequences) needs to place the functions
at that address, or they'll have to adjust all the address literals in all the
ASTs. It would probably be easier to simply rewrite the lifter, but at least you
can guarantee that every address literal will need to be adjusted, because
there's no other way to produce an address literal: the parser can't emit them,
and the AST parser might error out if it encounters them.

The lifter extracts functions as a list of keyword argument names and an AST
body. Right now, the first function is a dummy function that gets replaced by
the compiler, usually with the root AST. The lifter should probably just put the
root AST there, but whatever.

The compiler has a separate function that compiles and packs lifted ASTs in one
go called `compiler::pack_compile_lifted`. It reallocates chunks for all the
functions, then compiles and packs the `IrOp` in, adding code to store arguments
and to push and pop environments. Then it compiles the root and puts it in the
same place as the dummy function. Recall that packing each `IrChunk` can result
in multiple real `Chunk`s. By pre-allocating chunks for the functions, we can
ensure that any extra chunks don't take a function's assigned spot, and don't
get overwritten. 

## TCO

This is how Tail Call Optimization is implemented in the current compiler.


```rust
fn tail_call_optimization(chunk: &mut IrChunk) {
    let len = chunk.len();
    if len >= 3
        && chunk[len - 3] == IrOp::Call
        && chunk[len - 2] == IrOp::PopEnv
        && chunk[len - 1] == IrOp::Return
    {
        chunk[len - 3] = IrOp::PopEnv;
        chunk[len - 2] = IrOp::Jump;
    }
}
```

It works, but is very tightly bound to the compiler implementation, and if the
compiler ever gains the ability to elide environments, this will break.

# Benching

I tried benchmarking the VM, but for whatever reason, the executing time is
pretty unreliable, with variance of between 5 and 15%. I haven't tried
benchmarking the parser-compiler: I suspect it will be very slow, because,
instead of a much vaunted "no-copy architecture", I implemented a "copy-everything
architecture", where data from each intermediate phase isn't consumed by the
next phase, but entirely new data is produced each time. This allows you to
reuse the intermediate data, a feature I have never used and have no particular
plans to, outside of the obvious reuse of bytecode in the VM.

# Looking Forward

After I add closures, I'll be pretty happy with this toolchain, and will likely
start to work on the standard library. I could also work on the scheduler, but
being able to implement the runtime access to the scheduler alongside the
scheduler will likely be useful.

I'm also thinking about a different kind of VM, one that doesn't use bytecode
chunks like current one, and deals with "first class value functions" in a more
literal way.

[compiler_pack]: https://github.com/atamis/ironic-space-lisp/blob/be888b130d781a70af42e9bf50f9c13d776c9be7/src/compiler.rs#L239
[isl_lifter]: https://github.com/atamis/ironic-space-lisp/blob/be888b130d781a70af42e9bf50f9c13d776c9be7/src/ast/passes/function_lifter.rs
[lifting]: https://wiki.haskell.org/Lifting
