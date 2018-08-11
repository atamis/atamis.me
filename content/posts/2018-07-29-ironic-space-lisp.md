---
title: "Ironic Space Lisp Part 1"
date: 2018-07-29T02:03:01-07:00
---

[Part 1](/posts/2018-07-29-ironic-space-lisp/)

[Part 2](/posts/2018-07-09-ironic-space-lisp-part-2/) 

I recently had a new idea for a space programming game. The idea isn't done,
although the planning document is getting lengthy. Programming games need
programming languages, and based on the game design, I had some pretty
particular specifications for the language.

* Sandboxed
* Concurrent
* Preemptive

Although the design hasn't settled fully, I'm currently planning on executing
code on the server, which means the language needs to be able to be sandboxed in
two senses: it shouldn't be able to access the server outside of approved
channels, and it shouldn't be able to access _other threads_ outside of approved
channels. Most critically, these approved channels are approved (and
potentially modified by light speed restrictions) by _game logic_.

The language's execution environment needed to permit not only this level of
security sandboxing, but also this game logic dictated communication limitations.
In the current design, the potential channels are a message passing style
communication network. The different language environments represent independent
compute units separated by physical space, thus precluding direct access; In
some cases, separated by so much distance that light speed imposes message travel
times dictated by game logic rather than the execution speed of the language
environment.

In the interest of speed, however, I want all these independent and strictly
sandboxed concurrent threads running at the same time on a few raw OS processes.
Also, I want them to be preemptively scheduled, because I think that's neat.
Also I wanted it to be pure functional, because I think that's also neat.

The preemptive requirement ended up being a somewhat defining point: I wanted
the ability to _single step through lisp code_. Writing a normal recursive lisp
interpreter is easy. Writing a stepped lisp interpreter is sort of insane. This
is the point I decided to implement utilize stack machine VM to enable this sort
of stepped interpretation.

Given the slightly mental requirements, it was sort of clear I was going to have
to write my own language. What an amazing opportunity to learn a new and exciting
language! I know I'm going to be running a game alongside the language, and I
don't want to use an implementation language that was to slow, so let's use
Rust, an incredibly complex language that boasts zero-cost abstractions with
C-like speed. I could tell this was a mediocre idea, but I would soon learn it
was even worse than expected.

I spent the first four days reading the [Rust
Book](https://doc.rust-lang.org/book/second-edition/foreword.html). At this
point, I felt ready. Laughable, really.

# The Plan

_[I feel I should stress that I didn't do very much real planning]_

The plan was to write a quick lisp eschewing the normal mutable global state for
immutability. My first idea looked a little like this:

```
    lisp strings -> AST -> simplified AST -> "bytecode" -> VM -> scheduler
```

The plan was to psuedo-compile the the AST into bytecode for a stack VM.
At the time, although the scheduler would likely be the most complex part of
this project, I thought that starting with the VM would be a good idea. The VM
represented a sort of MVP for the entire thing. Who really cares about parsing:
I've done parsing before, I've done AST simplification before, and I couldn't
really convert AST into bytecode before I know what my bytecode was.

# The Stack Machine

So it was the VM first. [You can see this abortive first attempt
here.](https://github.com/atamis/ironic-space-lisp/tree/old_stack). As with all
great lisp interpreters and stack VMs (for they are so similar in this early
stage), you start by adding numbers. I set up the number literal operations, the
addition operator, stuck them in a vector and let it rip.

```rust
match op {
    Op::Lit(l) => frame.stack.push(( l ).clone()),
    Op::PlusOp => {
        let x = frame.stack_pop()?.ensure_number()?;
        let y = frame.stack_pop()?.ensure_number()?;
        let s = x + y;
        frame.stack.push(data::Literal::Number(s));
    }
    Op::ApplyFunction => { /* ... */ },
    Op::ReturnOp => { /* ... */ },
}
```

It's got all the hallmarks: stacks, operations, addition, the works.
Unfortunately, I started to get excited, and implemented functions next. Not any
sort of syntax, just raw-built function literals:


```rust
#[derive(Debug)]
pub struct AddOneFunction;

impl LambdaFunction for AddOneFunction {
    fn get_arity(&self) -> usize {
        1
    }

    fn get_instructions(&self) -> Vec<Op> {
        vec![Op::Lit(data::Literal::Number(1)), Op::PlusOp, Op::ReturnOp]
    }
}
```

This was combined with a "stack frame" that held a set of instructions and its
own personal stack. In a sense, each stack frame was its own stack VM, and
unlike normal stack machines or concatenative languages, each function had its
own stack preloaded with `get_arity()` items from the stack of its caller.
Rather than trusting each function with the full stack, it somewhat pointlessly
isolated them: this simply wouldn't be a concern assuming the AST produced
reasonable bytecode. I was briefly thinking of making players execute untrusted
code for in game reasons which could potentially hurt them in game, but this
level of security somewhat trivializes that threat.

```rust
let function = frame.stack_pop()?;

match function {
    data::Literal::Builtin(f) => {
        f.invoke(&mut frame.stack); /* An earlier and simpler sort of function */
    },
    data::Literal::Lambda(f) => {
        let mut new_stack: Vec<data::Literal> = Vec::new();
        for _ in 0..f.get_arity() {
            new_stack.push(frame.stack_pop()?);
        }
        /* new stack, new instruction set, new everything */
        new_frame = Some(StackFrame::new(f.get_instructions(), new_stack))
    },
    _ => panic!("Attempted to apply non-function"),
}
```

I then ran smack dab into the problem of if statements. I hadn't even considered
them at all: I had no way to represent non-executing chunks of code. I had
functions, but the potential of doing a full function call (with closures in
future) staggered me, and caused me to reconsider this approach. How would I
even represent that in bytecode? Would my bytecode be litered with raw function
literals with more instructions nested within? Where was my nice clean flat
vector of instructions to speedily rush down, pausing only for user defined
functions? Why even bother if it was going to have the same nested format of the
original AST anyway? I was also starting to get worried about the amount of code
in my data and data in my code. At the time, these should have been separate:
code is data in lisp, but this was "bytecode". Those raw function literals would
look like data, but would be filled with bytecode instead.

Looking back now, these problems seem manageable, although they push the
complexity outwards a bit. Maybe with some more bytecode management, more faith
in my functions, it could work.

At the time, I decided to take a different approach: If stepping required that I
not rely on the Rust stack to keep track of evaluation, I would make my own
stack. Find out more next time.
