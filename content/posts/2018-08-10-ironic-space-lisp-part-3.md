---
title: "Ironic Space Lisp Part 3"
date: 2018-08-10T17:09:28-07:00
draft: false
---

Have you ever been working on a project and felt stupid and scared? Not in an
anxious way, and not in an imposter syndrome way, but in a visceral way, like "I
don't really know what I'm doing, and I'm not sure I can do this." Some
languages are so complex and _different_ that, although I know they're full
feature and Turing complete languages, I don't know that I can even write
whatever program I'm trying to make. Or at least that I can't write it idiomatically.

On the one hand, this really doesn't feel good. On the other hand, it's a very
strong sign that I'm actually learning something. Right now, I'm only scared of
2 languages: Rust and Haskell. On this side of the learning curve, I can't say
with total confidence exactly what I'm learning from them, but I'm very much
learning _something_.

Rust's really mind bending parts are mostly the type system differentiating
between stack and heap data, the lifetime system, and the borrow checker.
Luckily, writing a lisp interpreter is a good way of really exploring those
systems. Haskell enforces radical functional purity at a level I haven't really
encountered in any other language, despite my experience with other functional
languages.

Anyway, my practice of having 1000+ tabs open paid of once again when I noticed
Bob Nystrom's book, ["Crafting Interpreters"][book] in my browser. "Hey, that's
what I'm doing," I thought, stupidly. One the book's main points was that
tree-walk interpreters are slow. In retrospect (particularly with the book's
subsequent paragraphs), it's fairly obvious. Modern CPUs are optimized for
fast loops over linear data. One of their main "bottlenecks" is pointers:
dereferencing pointers into uncached memory is really slow (almost guaranteed to
generate a cache miss).

As it turns out, tree walk interpreters dereference pointers constantly. Because
AST trees are inherently recursive, and structs can't be of indeterminant size,
all child nodes in ASTs must be pointers, and usually pointers to heap data,
which in turn point to more heap data.

```rust
pub enum Lisp {
    Num(u32),
    Op(Op),
    List(Rc<Vec<Rc<Lisp>>>),
}
```

A lot of languages make these pointers implicit, like Java, where there are no
value/stack objects, only heap allocated objects, and everything is a reference.
Writing a recursive interpreter over a simple tree structure like this is really
easy, and it's the go to technique for "writing your first interpreter"
tutorials and articles, like ["Write Yourself a Scheme in 48
Hours"][haskell_scheme] (which includes the phrase "you'll have to forget most
of what you already know about programming", which is how you know it's a good
tutorial). Nystrom's book complicates that slightly by employing the visitor
pattern to implement evaluation, but I found his justification for it entirely
convincing, and it really didn't change the performance implications of
tree-walk. Additionally, my interpreter almost never deals with data values
directly, they're almost always wrapped in an `Rc`,

```rust
// from src/frames/if_frame.rs
pub struct IfFrame {
    lisp: Rc<Lisp>,
    predicate: Option<Rc<Lisp>>,
    answer: Option<Rc<Lisp>>,
    state: FState,
}
```

primarily to prevent ownership issues. The AST/data are all treated as
immutable, so reference counting the entire thing and directly sharing data and
code is reasonable semantically speaking (especially for a Lisp), but too much
indirection is inefficient.

It's worth noting that although the Ironic Space Lisp interpreter isn't a normal
tree walk interpreter. The ISL interpreter, as it's implemented on the `master`
branch right now, reifies the stack frames tracking the recursive descent into
the AST to permit preemptive pausing. This really doesn't help the locality
issue, as the AST still lives in arbitrary heap memory. Additionally, although I
thought that reifing the frame stack would assist in implementing Tail Call
Optimization (an important part of the language), I subsequently realized it
wouldn't: it would be mildly easier than in a normal recurse tree-walk
implementation, but still wouldn't be easy.

By contrast, in a bytecode VM, implementing TCO is easy, and can be done both at code
generation and at runtime in the VM. Nystrom also convincingly claims that
bytecode VMs are much faster than treewalk interpreters, and not much harder to
write. I find myself convinced by these arguments (and the ever increasing
complexity of the frame code, see [`if_frame.rs`][if_frame_code]), and I've
restarted work on the stack VM in the ISL repo. It's still in the `old_stack`
branch.

It isn't substantially smaller than the stepped interpreter, but it's a
fair amount simpler, partially because it's just a VM. It does have nested
environments and bindings before the stepped interpreter, but doesn't have
complex data types like _lists_ 🤔. It currently treats bytecode addresses as
normal data, which is something which _might_ change, but exposing those sorts
of externals to the user is something that _might_ have interesting gameplay
implications. It might also be relevant if I want to implement some other type
of language on the bytecode VM, but that seems less likely, particularly because
I've already implemented environment bindings _in the VM_.

In the end, Nystrom baited me: he's completed the section on the tree-walk
interpreter, but his chapter on the bytecode VM ends at compiling
expressions, leaving such topics as "local variables", "calls and functions",
"closures", and "garbage collection" incomplete. I think I'll be alright: I can
see how to implement all of these, although I'm particularly interested in his
approach to closures.

I'm hoping to make closures serializable, or at least transferrable between
different VMs with different environments: possible in Java, difficult in PHP,
involves eval in Ruby, possible in [Erlang][erlang_passing_funs], etc (how crazy is it that
it's possible in _Java_ but not _Ruby_?). In particular, capturing bound values
and passing them over the wire _with_ the function seems doable, but _weird_.
I'm not sure I need to serialize closures all the way to strings and send them
over the network, but copying/moving functions made from and parameterized by
higher order functions from one VM to another seems like a really flexible and
powerful tool for the languages ultimate purpose.

It's worth nothing that [this presentation][scheme_presentation] was very
interesting, although it covers a lot of topics that weren't directly relevant
to this project.

## Addendum: Tests

_Why haven't you written any tests?_

This is a pretty bad look for me: no tests of any of the implementations. To
explain, allow me to draw your attention to the phrase "any of the
implementation". I've written two and a half implementations, and none of them
have reached any sort of completeness. Between uncertainty over language, API,
and implementation, the code is changing so fast that tests would be mostly wasted
effort. I've had very little solid idea of what this project is going to look
like in the end, and without a solid vision, any tests that get written have a
very good chance of being abandoned as that code base becomes obsolete. I've
abandoned the bytecode VM, then picked it up again, but I ended up rewriting it
substantially, so any existing tests would either restrict me unreasonably or be
deleted. Certain design decisions in the stepped interpreter made it harder to
implement the naive tree-walk version, so tests written for that partial
interpreter would also have been thrown out. The stepped interpreter is very
complicated with lots of moving parts, but all the parts are very tightly bound,
which makes testing them independently very difficult, and testing them together
very difficult too. The VM is easier to write tests for, luckily.

[book]: http://craftinginterpreters.com/
[haskell_scheme]: https://en.wikibooks.org/wiki/Write_Yourself_a_Scheme_in_48_Hours
[if_frame_code]: https://github.com/atamis/ironic-space-lisp/blob/6151575b11165807cc256a4198a9aea8fbe95bd2/src/frames/if_frame.rs
[erlang_passing_funs]: http://www.javalimit.com/2010/05/passing-funs-to-other-erlang-nodes.html
[scheme_presentation]: http://www.call-with-current-continuation.org/scheme-implementation-techniques.pdf
