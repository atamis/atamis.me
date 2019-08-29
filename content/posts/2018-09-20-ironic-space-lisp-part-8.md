---
title: "Ironic Space Lisp Part 8"
date: 2018-09-20T13:21:53-07:00
tags: ["rust", "code", "language"]
projects: ["isl"]
---

It's been a while since I posted progress on ISL, and that is mostly my fault.
Most of this time was spent making maintenance, like documentation, but also
trying to get the self hosted interpreter working and self hosting. That was a
challenge, and also my fault.
<!--more-->
# "Closures"

So, I had a problem. I'm really used to having checks to make sure the code I
write is correct. I don't ask for much, but arity checks are nice, and pretty
much every language offers them, either at compile or runtime. Unfortunately, I
had a problem. The ISL compiler destroys arity information, replacing it with a
simple pointer to function memory. This meant that after code was compiled, I
couldn't check subsequent code against existing code for arity agreement. But at
runtime, not only do functions not have arity information, the VM is a stack
machine, so there isn't even an indication of how many items a function is going
to take off the stack, making arity double impossible. It's theoretically
possible for the `function_lifter` pass or the compiler to arity check new code
against itself, but not against old code. 

As far as I can tell, most VMs don't store bytecode like the ISL compiler
does, and instead keep track of more runtime information so you can arity and
type check. When the ISL VM didn't, it failed silently, and consumed the
arguments _from the next function call_, resulting in runtime type errors if
you're lucky, stack popping errors far from the actual error if you aren't.

So I added a new system for functions. I added a new data type, `Closure`, which
stores function arity and an address. The `function_lifter` pass, which does
have access to arity information, now replaces functions with `Closures` rather
than raw addresses. At call sites, the compiler does have access to calling
arity information, but previously threw it away. It now emits a new instruction,
`CallArity`, which includes the arity of the call. The VM can now notice that
the `CallArity` call is to a closure, and check the arity of the closure against
the arity of the instruction. It doesn't verify that the function actually has
this arity, but this system is primarily support for a properly written compiler
rather than security. It's worth noting that both `Call` and `CallArity` will
work properly with either addresses or closures. `Call` never checks arity, and
`CallArity` only checks arity with closures, and acts just like `Call` when
passed a raw address. This is to permit strict arity code to interact with less
strictly compiled code, although this doesn't have a use case yet.

Syscalls have been updated to work with arities where possible[^0].

# A new parser

I was having an issue where `cargo` was printing compilation errors twice. I
thought it was related to `lalrpop`, the parser generator I was using. Also, I
had had some time away from it, so I wanted to try `nom` again. It turns out
that printing error messages twice is intended behavior, or at least it's
unrelated to `lalrpop`. Also, `nom` was very frustrating and hard to use. I got
the parser working, but couldn't for the life of me figure out how to properly
parse comments, and my attempts broke in ways I simply didn't understand, and it
made me question my sanity and parsers in general. I wanted the parser to error
out when it couldn't parse something, but but `nom` kept partially consuming
input strings, and silently leaving the string unparsed. I couldn't, for the
life of me, figure out how to make `nom` treat it as an error (apparently
`complete!` refers to some other issue, and using `CompleteStr` everywhere
didn't help either), so I had to write a wrapper function to do this properly.

```rust
/// Parses a string to a vector of `data::Literal`s.
pub fn parse(input: &str) -> Result<Vec<data::Literal>> {
    let mut input = CompleteStr(input);
    let mut lits = vec![];

    while input != CompleteStr("") {
        match tagged_expr(input) {
            Ok((rem, l)) => {
                lits.push(l);
                input = rem;
            }
            e => return Err(format_err!("Parse error: {:?}", e)),
        }
    }

    Ok(lits)
}
```

Note that this code manually parses single exprs out until the string is empty,
and totally ignores the `many!` macro that is supposed to help in this situation.

I'm thinking of rewriting the parser by hand for better error reporting, but the
whole string parser and AST parser suffer very poor usability, mostly because
they're blind to file locations, so they can't report targeted errors. That's
why AST parser error messages contain context information like "While parsing
multi expression 3", so you have to _count by hand_ down your `do` expression or
whatever.

I don't think Rust has a really strong language grammar parser that really
closely fits my needs, but I'm not sure if I want to invest more time here. To
me, it's not the interesting part of the project, and it's "good enough", in the
sense that it no longer silently eats errors.

# The self hosted interpreter.

The good news is that the self hosted interpreter can interpret itself fully,
and can easily be extended to support new language features. It's obviously very
slow, but there are some _very_ obvious inefficiencies in the implementation,
like the use of [assoc lists][cmu_assoc] for environment bindings, full
structural recursion, and the manual implementations of `map`, `foldl`, and
`filter` (although higher order sycalls are still an unsolved problem).

First, a note on tool quality. I didn't want to learn how to write language
modes in emacs (and every other tool), so I was using `clojure-mode` for syntax
highlighting and indentation. From [`d9dfc3a`][cloj_commit]'s commit message,

>I also discovered that `clojure-mode` in emacs is the best way to format ISL
>code, but that it's very particular in its indenting. If `let` bindings aren't
>in brackets, it doesn't indent correctly, so I added brackets to the list of
>acceptable delimiters. Also, `lambda` doesn't exist in Clojure, it uses `fn`,
>and `clojure-mode` formats `fn` differently from other function applications, so
>I aliased `fn` in the _AST_ parser. Nowhere else though.

It's really not my intent to imitate Clojure so much. Although it's a major
inspiration, and I'm a big Clojure fan, ISL has very different goals. These are
good changes, I was going to add more permitted delimiters, and Rich Hickey has
great ideas,  but I don't want to look like a stalker fanboy.

After mostly implementing the interpreter, and testing it on a few small code
chunks, I decided to throw the entire itself at itself, just to see what would
happened. I meant it as a joke, but I then seriously attempted to debug the
interpreter while it was running its own code, and without fully verifying it
worked.

The main problem was that the interpreter was fundamentally broken, and did
_hilariously_ wrong things, but I didn't write enough tests to figure that out.
Instead, I would observe that the output of the VM's tests and the self-hosted
interpreter differed, and then I would have trouble figuring out which layer the
error originated at. Was the VM-hosted interpreter erroring out because I wrote
the ancillary code wrong, or was the interpreter-hosted interpreter erroring out
because its attempt to _interpret_ the ancillary code was broken. This was
raised to absurd levels when the interpreter was erroring out on itself, and not
even print statements could help. The self hosted interpreter didn't have any
back tracing, and when the interpreter-hosted interpreter failed, the frame
stack for the VM was from the interpreter one layer up, where it was doing very
boring things. This is like finding a bug in the VM, looking at the Rust
stacktrace, and observing that the error happened while executing an instruction
in the VM. It's not even relevant which instruction, the relevant debug
information is stored in the application state, and the interpreter offered no
way to inspect it directly, only through print expressions, _which themselves
sometimes broke_. Early in the process, I began tagging all interpreter-hosted
print expressions as triggered by the interpreted code, but sometimes I would
accidentally pass a really big environment to `print` instead of a smaller
value, and massive `sexprs` would vomit onto my terminal. It turns out sticking
an entire interpreter and all its supporting functions (see
[`examples/lisp.isl`][lisp_isl] to see all the "library" functions and "structs"
I had to implement by hand) results in a lot of code heavily nested and entirely
unreadable `sexprs`.

Although verifying the several different language implementations with a strict
suite of test cases would be a good idea (and fixing the Rust interpreter in
turn), and would reveal vagaries in the existing language design (and just how
bad the environment code is in the bytecode VM.) I think the multicore code
would be interesting and rewarding, but I can't implement that on top of any ISL
implementation other than the VM, but it's one of the harder implementations to
ensure is correct. I think the Rust-based interpreter will be easiest to make
correct, and then using it to ensure the ISL interpreter is correct, and then
finally working on the VM. Almost all the implementations make certain
assumptions about how environment bindings work that the absolutely shouldn't,
and although I think fixing them in the interpreter will be easiest, I think the
VM will require some major changes.


# Language Leverage

The `data` module was probably the first code I wrote in this project, as befits
a data oriented programming style. Since that day, I've been writing code like
this:

```rust
// (eval (quote (do *lits)) '())
let caller = data::list(vec![
    data::Literal::Keyword("eval".to_string()),
    data::list(vec![
        data::Literal::Keyword("quote".to_string()),
        data::list(d),
    ]),
    data::list(vec![
        data::Literal::Keyword("quote".to_string()),
        data::list(vec![]),
    ]),
]);
```

This code is building nested data literals out of raw Rust struct constructors,
and man is it wordy. This code is particularly bad because it has to preface all
the structs with the module name, but this is by no means the biggest data
literal in the codebase. Although much of this code was in tests, it made the
tests _very_ difficult to read, and difficult to read means difficult to verify.

I eventually remembered that you can implement `From` to allow for
near-automatic type conversion, and decided to implement a bunch of them for the
single field `Literal` structs. It was a pretty boilerplate chunk of code, but
it makes it that much easier. For example, 

```rust
impl From<u32> for Literal {
    fn from(n: u32) -> Literal {
        Literal::Number(n)
    }
}
```

Of course, Rust vectors can't be heterogeneously typed, so you can't do
something like  `vec!["keyword", 1, true].into()`, the vector can't be
represented in Rust, so you can't write a `From` implementation to convert it.
You would have to do `vec!["keyword".into(), 1.into(), true.into()].into()`,
which is still pretty cumbersome. How to solve this? The `list_lit` macro. A
macro can take heterogeneously typed lists like this, ensure they each get
converted properly, and then wrap the entire list properly.

```rust
#[macro_export]
macro_rules! list_lit {
    () => {
       $crate::data::Literal::List($crate::data::Vector::new())
    };

    ( $($x:expr),* ) => {{
        let mut v = $crate::data::Vector::new();
        $(
            v.push_back($x.into());
        )*
        let l: $crate::data::Literal = v.into();
        l
    }};

    ( $($x:expr, )* ) => {{
        let mut v = $crate::data::Vector::new();
        $(
            v.push_back($x.into());
        )*
            let l: $crate::data::Literal = v.into();
        l
    }};
}
```

The implementation initially relied on the `vector![]` macro from the `im` crate
(which is the container that backs `data::Literal::List` values), but I had real
trouble gaining access to the macro from crates that imported
`ironic_space_lisp` but not `im`. It doesn't seem to be directly possible, and I
couldn't even get reasonable access to `Vector`, a normal struct type, so I had
to reexport it from the `data` module with 

```rust
#[doc(hidden)]
pub use im::vector::Vector;
```

The rest of the implementation is inspired by the implementation details of
`vector![]`. I also had trouble figuring out how to trigger Rust's type
inference to make `into()` work properly, which is why it has so many reassignments.

[^0]: Some syscalls are "stack" syscalls which don't specify an arity and push
    and pop the stack as they please. There are none of them right now, but if
    there were, they wouldn't have defined arities, so you couldn't check their arity.
[cmu_assoc]: https://www.cs.cmu.edu/Groups/AI/html/cltl/clm/node153.html
[cloj_commit]: https://github.com/atamis/ironic-space-lisp/commit/d9dfc3afc1ef689bf83b6da2c8f2292c3bb5b0d7#diff-c15ada9c0ecb840fd46058dd72987586
[lisp_isl]: https://github.com/atamis/ironic-space-lisp/blob/2ee301cf23103b1c796e5b03828ff6a2c42457e0/examples/lisp.isl
