---
title: "Ironic Space Lisp Part 4"
date: 2018-08-12T00:41:11-07:00
tags: ["rust", "code", "language"]
projects: ["isl"]
---

This update is all about parsing, and this ended up being really difficult. Not
in a good way though. In my [last post][last_post], I talked about using
languages so difficult and alien that the difficulty clearly signified that
there was something important you could learn from mastering them. I didn't find
this was the case during this phase of the project.

<!--more-->

```
$ cargo run
   Compiling ironic-space-lisp v0.1.0 (file:///home/andrew/src/rust/ironic-space-lisp)                                                                                                                                                       
error: no rules expected the token `,`
  --> src/parser.rs:21:5
   |
21 | /     delimited!("(",
22 | |                alpha,
23 | |                ")");
   | |____________________^
   |
   = note: this error originates in a macro outside of the current crate (in Nightly builds, run with -Z external-macro-backtrace for more info)

error: aborting due to previous error

error: Could not compile `ironic-space-lisp`.

To learn more, run the command again with --verbose.
```


Thanks, rust. The `external-macro-backtrace`, once I had got it working, did not
help my comprehension. By the time I figured out what was wrong with this code,
I had abandoned this parsing framework.

The AST I was targeting was quite simple, eschewing (for now) any
differentiation for special forms, quoting, quasiquoting, booleans, etc. I
didn't write the AST down explicitly, rather, when approaching a new parsing
framework, I would try to write a parser for `keywords` first, before moving
onto numbers and ultimately nested lists. I also didn't want to involve the
existing data structures to avoid initial complexity, so I started with parsing
to strings and vectors, then parser-internal ASTs.

I didn't keep a good record of my attempts, so I can't explain, in detail, where
I went wrong. I suspect that my issues were comparatively minor, and easily
fixed with a little outside help, but I'm an impatient man, and figured I'd
solve my own issues. I also figured that if I needed help as early in these
parsers, advice capable of getting me over whatever issue I was dealing with
at the moment would not be sufficient to carry me through the entire parser.

# [`nom`][nom_link]

`nom` is a parser-combinator language aimed at bit-level context-sensitive data
formats. I was dealing with valid utf8 strings, which Nom handled with aplomb,
but my AST was actually context-free, making `nom` somewhat overkill. `nom`, as
a library, is pretty much all macros for generating custom parser combinators
out of smaller combinators. The whole parser has a type signature roughly like
`&str -> AST`, plus or minus a result type. Because of the heavy use of macros,
the typing of everything was reasonably easy, but unfortunately, it ended up
being hard to understand exactly how to use the macros together, and there were
a large number of functions, some of which returned parsers, and some of which
didn't.

`nom` also has an issue codified in [Incomplete vs end of input][nom_issue]. The
gist of it is that, because `nom` is designed to produce parsers capable of
working on input of both flat string and stream types, it had a tendency to
"over-consume", sort of. It wouldn't see the end of an input string as the end of
an input: if you were in the middle of consuming a some letters for a keyword,
perhaps consuming until you encountered a non-letter, and reached the end of the
string, `nom` would treat this not as a completed keyword, but as an incomplete
token. This is _sort of_ reasonable: this string could be a fragment of a larger
document or stream, the token could be continued in the next string, but the
solution to the problem was more than a little unclear to me. There is a
`CompleteString` type, but that ensures that the parser won't work on streams. I
didn't really find a good solution to this problem?

I also tried to separate lexing and parsing, but couldn't figure out how to
parse non-string data with `nom`: there seemed to be a lot of traits to
implement, and it wasn't abundantly clear why they weren't already implemented
for a simple `Vec` if I was supposed to be able to do this.

Also, error messages tended to be pretty impenetrable because everything was
macros. That error at the start of the article? I got that error because `alpha`
is actually a function, and to get a parser from it, you needed to call it.
Absolutely amazing error message though. Absolutely stumped me. Also, some of
`nom`'s documentation is a little sparse and difficult to understand. None of it
is _undocumented_, _per se_, but I found understanding somewhat difficult to
grasp. `nom` is clearly popular and powerful: the list of projects using it is
quite large, but those projects were mature pieces of software with complex
parsers for formats I didn't fully understand, so reading them to learn how to
use `nom` was not useful.

I expect I'll return to `nom`, as I'm not entirely happy with with my current
choice, but I put several hours into my attempt to get even the most basic
parser out of `nom`, and was thoroughly rebuffed.

# [`combine`][combine_link]

Combine was another parser combinator, but this time with much fewer macros, and
many more functions, types, traits, and more. `combine` types could get
thoroughly overwhelming, with type signatures in error messages easy wrapping my
terminal. Parsing what was actually going wrong from the type signatures was
really hard. I was clearing not using the parser pieces in the right way, and
failing to understand why examples were written exactly the way they were, and
the signature heavy error messages didn't not clarify for me. Although I'm not
entirely familiar with the issue, `combine` encoded the parsing tree into its
complex types, but types cannot be infinite, so recursive parsing was achieved
through a thoroughly baffling macro called `parser!`, which "Declares a named
parser which can easily be reused".

At least part of these problems is my unfamiliarity with parser combinators. I'm
familiar with some of the theory, but adapting that to real world use, and to
the unique syntax and interface of these parsers, is very difficult. The premier
parser combinator is Haskell's Parsec, so perhaps a deep study of Parsec would
help me with this issue. For now, I still need a parser.

# [`lalrpop`][lalrpop_link]

`lalrpop` is a much more traditional parser: it's a compile time parser
generator for context-free grammars. It hooks the cargo build process to
generate Rust code from a custom grammar file, a little like a gigantic macro.
Unlike `nom`, its error messages seem custom generated, and in fact, its grammar
file is defined not in terms of Rust macros but with a grammar itself, making
the entire thing self hosting (or at least self parsing).

It's context-free, so it's arguably less powerful that either `nom` or
`combine`, but its grammar files are succinct and expressive, and I managed to
complete a grammar and a test suite (longer than the grammar) in an amazingly
short time.

It does have fewer examples, and less documentation, but the tutorial was clear
enough that I feel pretty confident I could produce similar parsers, and modify
this parser, quite easily.

# Thoughts

This experience was striking. I'm not happy about my performance with `nom` or
`combine`. I had real trouble understanding and using both of their interfaces,
and I'm hesitant to blame it on the frameworks over myself. Developer
productivity can't be denied, but I can't help but feel I could have been better
and could be better in the future.

I think I'm going to write a few AST mutating phases, then implement a
tree-walk interpreter for the new AST before beginning on code generation. I'm
hoping to reuse the VM's environment code and builtin functions for simplicity.
Ultimately, I can use the interpreter to test the code generation, but because
the bytecode VM is the ultimate goal, I may end up modifying the interpreter to
better fit the semantics of the VM. Modifications to syntax can be implemented
as AST modification stages, as those should be semantic neutral.

The project is really coming together, and starting with the parser, I've begun
building a test suite. I've also had time to think on the bytecode VM, and I
think I'm happy with its current state and semantics, and ready to write a test
suite for it too. The runtime scheduler is a ways off.

[last_post]: /posts/2018-08-10-ironic-space-lisp-part-3/
[nom_link]: https://github.com/Geal/nom
[nom_issue]: https://github.com/Geal/nom/issues/271
[combine_link]: https://github.com/Marwes/combine
[lalrpop_link]: https://github.com/lalrpop/lalrpop
