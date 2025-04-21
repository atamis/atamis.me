+++
title = "Compiling Forsp Stacklessly"
date = 2025-04-21T10:45:30+02:00
draft = false
tags = ["rust", "code", "language"]
projects = []
math = true
+++

Forsp is fascinating language billed as a combination of Lisp and Forth. It's
stack based, but features easy idiomatic access to a local environment. This
gives you the simplicity of Forth, but offers an "escape hatch" out of stack
hell. Code that would require complicated stack/value shuffling in Forth can
instead name the values and manipulate them in a way more natural to Lisp
programmers. Forsp is also neither call by value nor call by name, but instead
call by push value, though I'm not entirely clear on why this is interesting as
I haven't read the paper yet. Reading the paper wasn't necessary for this project

Forsp was designed (or, in the same way Paul Graham claims McCarthy "discovered" Lisp,
"discovered") by [Anthony Bonkoski](https://xorvoid.com/) in a [blog
post](https://xorvoid.com/forsp.html). That post describes the language, covers
some interesting applications and properites, and links to an
[interpreter](https://github.com/xorvoid/forsp/tree/main) in C.

# Summary of Forsp

I'd highly recommend reading Bonkoski's post on Forsp for greater familiarity,
but I'll cover the basics here.

Forsp is a series of instructions, and it has a stack of values, an
environment binding names to values, and a call stack (implicit in recursive
interpreters and not reified in the language.)

One of the values is a "thunk", a zero-argument function, or computation, that
closes over the environment you can `force` later.

The core language's only values are atoms and thunks, but I added numbers
to make things a little easier. You can quote values to put them directly on the
stack (`'atom'`), and thunks are instructions surrounded by parenthesis, and are
always pushed onto the stack directly.

You can `pop`, which pops a name, then a value, off the stack, and binds the
value to the name in the current environment. Similarly, you can `push`, which
pops a name off the stack, and pushes the value bound to that name in the
current environment onto the stack. I found this terminology a little confusing,
so it's important to remember that it's from the perspective of the _stack_, not
the environment.

You can `force`, which pops a thunk from the stack and calls it. Bonkoski says
that you can understand thunks as single argument functions from `stack ->
stack`, but these thunks frequently take named arguments by popping values from
the stack to the environment immediately, then referring to them later in the
function, so it can also be helpful to understand these thunks as taking
arguments and returning values.

There is some additional syntactic sugar:

| Sugar   | Code              | Commentary                                                                 |
|:--------|:------------------|:---------------------------------------------------------------------------|
| `'atom` | `quote atom`      | Push an atom literal to the stack                                          |
| `$atom` | `quote atom pop`  | See `pop` above, binds a value to `atom`.                                  |
| `^atom` | `quote atom push` | Reference `atom` in the environment, pushing the bound value to the stack. |
| `atom` | `quote atom push force` | Call the `atom` thunk from the environment |

I also added numbers (always literal, also quotable) and `inc`, because I wanted
a built-in function to call on numbers. Bonkoski later adds `cons`, related
functions, `cswap`, etc. I added `println` to make debugging easier

Forsp has no looping construct, but you can Y-combinator with it just fine.

# Compiling Forsp

Compiling is a pretty broad topic, but usually when someone talk about compiling
a language, they frequently mean lowering a high level language all the way to
machine code, and I'm not doing that, I'm compiling to Rust, which is a lot less
impressive. Rust is also a high level language, so writing a compiler from Forsp
to Rust is actually really easy. It's almost as easy as writing an interpreter
in Rust. It's so easy I won't demonstrate it.

However, I'd like to highlight a problem with Forsp's looping. Forsp can only
loop via Y-combinator, but this is infinite recursion, which requires tail call
optimizations to ensure it doesn't blow the stack. I'm pretty sure you can't
really write a tail-call optimized interpreter for Forsp. And Rust lacks
features to guarantee tail-calls (maybe coming soon), so I couldn't get the
compiled Rust code to reliably tail-call optimize, and it blows the stack as
well. "Under what circumstances will Rust/LLVM do TCO" and "why isn't my Rust
code getting TCO'd" are both really annoying questions.

So let's try and fix this.

# Continuation Passing Style

The goal is that every segment of Forsp code should end with a `force` call that
doesn't return. That way, we don't need to keep track of a stack at all. And you
can turn every `force` into a `jump`. I'm not really sure what this style of
compilation is called. I swear I read articles on a compiler written like this in
relation to a Scheme compiler. And I can't find those articles anymore. CHICKEN
compiles to C, but doesn't use this technique. So I guess I'm implementing this
based on hearsay. 

But I do know that continuation passing style helps here. Every function takes a
continuation representing the rest of the program, and every argument is either
a literal or an argument, and each function ends with a call to some other
function, which is the only function call in that function. So if the
continuation to the entire program is just terminating the program, then you
don't need to unwind the stack, and you can just exit.

Implementing CPS for Forsp was a bit of a challenge, as I believe it is novel
work. I referenced the Wikipedia page on CPS, which included a function
converting a simplified version of Scheme to CPS, which I had trouble following
because Forsp is neither Scheme nor Lisp.

I spent a lot of time screwing around with implementations of this that didn't
work before I returned to the Wikipedia page to realize that the conversion
function _took_ the current continuation as an argument. This was very helpful
because it reminded me that you weren't always going to call the "current"
continuation, the continuation of the program might come from somewhere else.

Before we get into it, I ended up adding some new primitives, `forceCC` and
`forceCCBare`. One challenge I faced is that every thunk in CPS'd program needs
to take an argument for the continuation. Thunks don't strictly define
arguments, so we need to be careful not to interfere with the rest of the
program's stack manipulation. The continuation is the first argument, and we
push the right continuation to the stack right before forcing the thunk, which
immediately binds the continuation, so it's just CPS code running and the stack
isn't mangled.

But wait, how do we push the continuation to the stack, then force the thunk we
actually care about? If we have code that looks like 

$$ (code... \quad force) \quad force  $$

And we're trying to just CPS this `force`, how do we actually pass the
continuation? If we put it first, $(code... \quad force) \quad continuation
\quad force$, then we just force the continuation instead of the thunk we care
about. So, can we just put the continuation last, $continuation \quad (code...
\quad force) \quad \quad force$? And the answer is "no", because not all `force`
calls will be immediately preceded by code pushing the thunk to the stack. The
stack is in an arbitrary state, and we need to accommodate that. So we need a new
kind of force: 

$$forceCC=swap \quad force$$

Where `swap` swaps the top elements of the stack. This lets us push the
continuation to the stack immediately before running `forceCC`, but it actually
forces the thunk underneath the continuation, and passing the continuation to it as its first
"argument".

At the end of the CPS process, we won't have any normal `force` instructions
left, but there will be cases where some segment of instructions needs to
continue computation, but won't be forcing any thunks itself. I've introduced
`forceCCBare`, which is just `force`, as a signal that the code has been
processed by CPS, but that no special handling is actually required.

$$forceCCBare = force$$

So we need a function to convert Forsp code to CPS form. It needs to take the
Forsp expressions, and it'll also take a continuation. At the top level, we'll
pass in the entire program, and the continuation will either do nothing (because
nothing happens after the program is done), or terminate the computation if
that's more convenient for us. Each recursive call will take some subset of the
code, representing the "current" of the computation, whatever that may mean at that
point, and the continuation, representing whatever happens after that.

So the CPS function in pseudocode is going to look kind of like

```
fn cps(exprs, cont) -> exprs { 
     ?
}
```

We don't care about instructions that aren't `force`, so they can simply pass
though unchanged:

```
fn cps(exprs, cont) -> exprs { 
     push cps1(expr) in exprs to new_exprs while expr is not force
     ?
}
```

Where `cps1` is a function that handles CPS conversion for single values. The
only value that requires special handling is a thunk.

```
fn cps1(expr) -> expr {
    return expr if expr not thunk
    let thunk_exprs = children of expr
    let cc_name = gensym
    ($cc_name cps(expr.exprs, ^cc))
}
```

This generates a unique name for the continuation, then calls `cps` with that
continuation as the continuation. The continuation is supposed to be some
expressions that puts the continuation on the stack, so this could be a literal
thunk, or an environment reference.

Back to `cps`:


```
fn cps(exprs, cont) -> exprs { 
    let new_exprs = ()
    push cps1(expr) in exprs to new_exprs while expr is not force
    let force, rest = exprs.split
    if rest is empty
        push cont to new_exprs
        push forceCC
    else 
        push (cps(rest, cont)) to new_exprs
        push forceCC
    
    push cont, forceCCBare to new_expr if we didn't force
    
    new_exprs
}
```

If there are no force expressions, then we need to push the current
continuation to the stack, and then force it to continue the computation. We use
`forceCCBare` to signal that this is in CPS even though no swapping is
required. 

If there is a force expression, all the instructions after it are the "rest of
the computation", and need to become the next continuation. After that "happens",
then the current continuation needs to be called, so the current continuation is
this new continuation's continuation. Continuations are thunks, so we wrap the
results in a thunk, then call `forceCC` to force the thunk with that
continuation. 

But if there is no other computation after the force, we can just use the
current continuation. 

The top level continuation could be `()`, a thunk that does nothing, but we want
to be able to terminate the program without unwinding the stack, so the top
level continuation is `(terminate)`, where `terminate` immediately terminates
the computation.

For example, lets consider the program `(1) force inc println`. We put the thunk on the
stack, force it immediately to put 1 on the stack, call `inc`, resulting in 2 on
the stack, then printing it. This can be desugared into `(1) force ^inc force
^println force`.

Here it is in CPS form:

```
($cc-g 1 ^cc-g forceCCbare)
(^inc 
    (^println 
        (terminate) 
    forceCC) 
forceCC)
forceCC
```

Every `force` becomes a `forceCC`, and the continuation directly before it is
either the rest of the computation, or `(terminate)`. `(1)` doesn't force
anything, so it takes a continuation and forces it at the end.

Note that built-in functions like `inc` and `println` have to take continuations
as well, and should be considered different functions like `incCC` and
`printlnCC`. However, because the target is a CPS-only platform, all this is
handled at the language level. Builtins require no modification, but are
separate types of values, and `forceCC` handles them separately by calling the
associated built-in function, then forcing the CC.

# Evaluating or Compiling CPS

With a little finagling, you can evaluate CPS-Forsp code on a normal
interpreter, but, unlike normal Forsp code, it doesn't return and the next
computation is always another stack frame, so instead of loops having problems
blowing the stack, every program blows the stack. Rust has a stack limit of
~3000, so I hope your program doesn't need to force more than 3000 times.

I think the easiest way to compile or evaluate CPS code is to extract all the
thunks to a flat structure, replacing them with references to the thunks. The
closure value is then just a thunk reference and the environment, and every
thunk is just a flat list of instructions ending in a `forceCC`. You can represent
your evaluation state with a simple structure: `(thunk_ref, env, inst_idx)`.
You can step this interpreter instruction by instruction, and easily pause
evaluation, which is always cool. I know CPS is also used for the code -> state
machine conversions that Clojure and Rust use for their async features, and this
resulting interpreter does look like a state machine.

But we're here to compile to Rust. There are a lot of details related to the
runtime environment I won't cover here.

Thunk reference names become enum options in a `ThunkRef` enum.

The core of the compiled code looks like:

```rust
fn top_level(env, stack) {
    let cur_frame = Frame {tr: ThunkRef::Entry, env: env.clone()};
    
    loop {
        match cur_frame.tr {
            ThunkRef::Entry => {
                // Instructions
                // The next thunk, thunk2
                // Continuation (thunk3)
                // ForceCC
            },
            ThunkRef::thunk2 => {
                // More instructions
                // Push the continuation (thunk3)
                // ForceCCBare
            },
            ThunkRef::thunk3 => {
                // Terminate
                break;
            }

        }
    }
}
```

Most of the instructions are self-explanatory.

Thunks have already become `thunkrefs`, and are compiled as 

```
stack.push(Value::Thunk { env: cur_frame.env.clone(), fp: ThunkRef::{tf} });
```

Where `{tf}` is the name assigned to the thunk.

`forceCC` is more complicated:

```rust
// header.rs:
pub fn builtin_force_cc(stack: &mut Stack, cur_frame: &mut Frame) -> Frame {
    let cc = stack.pop().unwrap();
    let th = stack.pop().unwrap();
    match th {
        Value::Thunk { env, fp } => {
            stack.push(cc);
            let nf = Frame {
                env: env.clone(),
                tr: fp,
            };
            return nf;
            // cs.push(nf);
        }
        Value::BuiltIn(f) => {
            f(&mut cur_frame.env, stack);
            if let Value::Thunk {
                env: cc_env,
                fp: cc_fp,
            } = cc
            {
                let nf = Frame {
                    env: cc_env.clone(),
                    tr: cc_fp,
                };
                return nf;
            } else {
                panic!(
                    "Forcing builtin with CC, expected CC to be thunk, got {:?}",
                    cc
                )
            }
        }
        x => panic!("Can't force non-thunk: {:?}", x),
    }
}
```

And the instruction is compiled as:

```rust
cur_frame = builtin_force_cc(stack, &mut cur_frame);
```

Built-ins are a separate type values that contain a Rust function pointer to
their implementation, so `forceCC` handles the continuations itself. So
`builtin` sort of becomes `'builtin do-builtin {cc} forceCCBare`, but this can't
be implemented statically as part of CPS conversion  because `force` never knows
what it's actually forcing. `force`, `push`, and `pop` aren't built-ins, my
current compiler treats them as keyworded instructions, but I think built-ins
have value because the language should probably do something that isn't forcing
thunks and returning atoms. 

The current frame is just a local variable with a reference to the compiled
code, and the `match` is basically just a jump to the compiled code. It's not
quite a jump, but it's pretty close.

# Results

This compiler's output is pleasantly fast and can loop indefinitely without
leaking memory or building up runtime structures per-loop invocation. I haven't
tested it with exceptionally large Forsp programs because suitable examples do
not really exist. Probably the largest Forsp program currently written is
Bonkoski's self-interpreter, which requires some extra language features like
`cons`. CPS programs build their call stacks as continuations, which this
compiler's output stores in its environment, so it's possible that the program
could run into memory issues when dealing with very large programs, though I
think its in-memory representation is reasonably efficient.

You can check out the compiler here: https://github.com/atamis/frospy

I called it Frospy

# Future Work

An interpreter would be easy to implement, but it's also easy to imagine converting
the compiler output from a normal program to a program that can "pause" and
return control to its caller to request input, or something. It seems like it
would be easy to implement asyncronous message calling without reaching for
Rust's `async` features that do the work already.

It's noteworthy how we've converted a recursive expression tree to a flat
representation without losing the call structure of the program. An interpreter
of the CPS for now operates strictly on instructions without any need for
recursion, meaning it can limit how many instructions it processed, and pause
before resuming indefinitely, but the implementation each instruction is nearly
identical to its non-CPS implementation.

It's also worth inspecting whether all environment interactions need to be with
the real environment. If those values are only written to and read from the
current environment, and they aren't referenced in any closures generated by the
code, then it doesn't need to bind to the environment at all, we can compile it
to local variables. But how do we determine whether it's used in the closures?
This turns out to be trickier than expected. Consider the following program:

```
1 'x
(pop         ; thunk 1
    (^x inc) ; thunk 2
 force) 
 force 
 println
```

The pop in thunk 1 is configured entirely by values put on the stack outside the
thunk. Thunk 1's environment has `x` bound to `1`, and thunk 2 closes over that
environment, and and so both has and uses the binding.

But consider a very similar program:

```
1 'y
(pop         ; thunk 1
    (^x inc) ; thunk 2
 force) 
 force 
 println
```

The top level code passes in `y` instead of `x`, so thunk 1's environment will
be different and `x` will be unbound in thunk 2. So not only can we not
statically identify `^x` in thunk 2 as unbound, it's possible for a thunk to not
know what its environment will be unless it takes into account how and where
it's called.

If binding name used by each `pop` and `push` is static, then you can determine
local vs. non-local bindings, but if a series of expressions includes a `push`
or `pop` to a dynamic name, then this optimization has to be disabled for that
thunk and all thunks containing that thunk because they can no longer
definitively say whether their bindings are local or not. I will admit that it's
a little difficult to identify a use-case for dynamic bindings, and might be
able to ban them from the language without much loss of power, though it's
definitely less elegant.

Of course, some more sophisticated data-flow analysis could help this, and expand the
situations where `push` and `pop` operate on static names. For each instruction,
and built-in, you can calculate the number of stack elements it consumes and produces
(call it arity), and infer, based on that, an arity for all thunks Then you can
convert stack operations to "registry" operations in SSA, and thunk arities to
arguments and multiple return values. This is a fairly standard compilation
technique for stack-based languages, because you don't really want a stack, they're
slow.

However, Forsp presents a unique challenge: `force`. What is `force`'s
arity? When does `force` know what its arity is? `force` has no idea what thunk
it's forcing, just the top of the stack. So `force`'s arity is generic over the
arity of the thunk it's forcing, which is _deeply_ inconvenient. I think this
means that doing this data-flow analysis correctly requires also _typing_ the
stack and _typing_ thunks based on their arity, so you can track the type of top
of the stack, and give `force` the right arity. But how do you handle thunks
that push arbitrary numbers of values to the stack. I think it also requires
that conditionals (`cswap`, not mentioned here, but Bonkoski discusses it) have
the same type for their arms, or at least the thunks need identical arities. And
you don't necessarily have the same escape hatch of disabling the optimization
because if you a `force` has multiple possible arities, then the stack can have
multiple different types, and all code afterwards has to type-check for all
possible types. This kind of uncertainty is usually frowned upon in type systems.

Banning these use-cases is probably a good idea anyway? What are you doing with
arbitrary stack sizes? Why are your conditional thunks consuming different
numbers of stack elements? No instruction or built-in requires this, so it would
have to be a feature of user code: the user would have to write thunks that put
arbitrary numbers of values on the stack, and the only meaningful thing they
could do with them is write another function that takes all of them off the
stack for whatever purpose. Or a conditional that _might_ have left an extra
value on the stack, so you need another conditional to remove the extra value
before continuing.

But Forsp _does_ let you do these things. It is dynamic and dynamically typed.
There's no obvious reason to ban them other than that they're probably bad ideas
to use in your program, and they make optimizations hard. The syntax makes it
look like it's possible, so it'd probably be pretty confusing if they weren't.
Bonkoski even articulates the syntax in a way that discourages you from
considering these options (particularly the dynamic environment problem), but
they're totally possible in his interpreter. 

That's kind of the beauty of Forsp. Future work probably isn't applying existing
optimizations to Forsp because it resists existing techniques. That's pretty
cool. 
