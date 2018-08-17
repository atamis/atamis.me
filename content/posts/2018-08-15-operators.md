---
title: "Operators"
date: 2018-08-15T16:21:39-07:00
---

I recently started thinking about operators and math in programming languages.
This is at least partly inspired by the programming language I'm making right
now, but I'll get to that later. It's also inspired, in some sense, by the
tutorials I was reading while trying to successfully parse my programming
language. I didn't find a tutorial specifically for what I was trying to do,
which was fair, but I did find tutorials on parsing other more "normal"
languages or more C-like languages, and it got me thinking.

There's something of a disconnect between the way we use programming languages
and the focus of the syntax and semantics of languages. In particular, languages
put enormous effort into making math, specifically arithmetic, very simple. In
many languages, you can write out mathematical expressions almost in plain text,
and it'll be evaluated properly. `x + 4`, `x/y - 3`, `x**2 + 2x - 4 == 0`. Hmm,
what's up with that last one. `**` is Ruby's exponential operator. In common
math parlance, it would be written `x^2`, or `x²`, if you have some fancy
formatting. However, `^` usually denotes bitwise XOR, and is part of the suite
of slightly less known bitwise operations which also get their own operators.
Java gives you `Math.pow`, and your Java equations start to look a little weird.

My point is that we don't use these mathematical operators very much. They show
up, on occasion, but most of the programs I write don't really rely on long and
complex equations as the main business logic, they mostly do delegation,
symbolic operation, and string manipulation. String manipulation, specifically
concatenation, sometimes uses operators, but just as commonly doesn't, making
string related code somewhat difficult to follow. Even if you are using
operators, unless your readers know the operator precedence hierarchy well, code
that relies on precedence to be correct can be very hard for humans to read and
verify. Programmers frequently add parentheses just for code clarity.

However, operators influence interpreter and compiler design pretty heavily.
Operators break the normal rules of the language pretty substantially, and these
programs have to deal with that, somewhere. To start with, they don't look like
any other syntax the language uses, so lexers and parsers have to understand
operators as a separate class, and parse them accordingly. What's more, operator
precedence is really important. Operator precedence is the difference between
your mathematical equation producing the expected and meaningful answers and it
totally failing. Assuming you notice, it's the difference between your equations
looking clean and nice (a major selling point for operators) and your equations
looking like parenthesis hell (a little like lisp, but we'll get to that later).

So not only does your parser have to know about and understand the fundamental
nature of operators, it also has to understand their precedence _at parse time_.
If you don't handle precedence at parse time, you push the problem down the road
and handle it at some other step. One could imagine an algorithm for operator
precedence working on and modifying AST trees, but that sounds _quite_ hairy.
Once operators are in your AST, they mostly stay there. You could use AST
transformation to turn them into pseudo function calls, making the rest of the
toolchain operation agnostic. You might want to make optimizations later in the
toolchain easier, so you leave them in until you hit code generation to make
selection of the right operations easy.

# Custom Operators

One of the main goals of operators is making equations clearer by representing
simple operations with simple single character operators. Most of the time,
however, even if we are using math as a direct part of the program, we aren't
dealing with single values, we're dealing with multiple values, either a vector
of values or a struct of named values. Being able to use operators on these data
structures could be very useful, although it does have the function of making
code less transparent, potentially invoking a cascade of complex operations and
even memory allocations from a simple `+`. Of course custom operators bring the
standard complexity of operators to classes, or traits, or functions, or however
organize code. Python uses magic methods like `__add__` and `__eq__`, C++
prepends its operator methods with `operator` so `operator+` `operator==`, Ruby
just allows methods with operators for names, and Rust has traits for all the
operations you can implement.

Java, however, doesn't allow operator overloading, and strictly delineates
between values and objects, so you have to write code like
`vector1.add(vector2).minus(vector3)` and regularly have to overload `.equals`
to get reasonable definitions of equality. Java does define `+` on strings, but
it compiles to efficient string concatenation code, bypassing the usual
immutability of the `String` class with `StringBuilder`, but doesn't expose this
functionality to normal users. It does expose that functionality to JVM compiler
writers (obviously, how would it preclude it), so Scala and Clojure both allow
operator overloading (although Clojure doesn't necessarily make it easy).

Haskell takes things a step further by allowing fully custom operators, and lets
you set their precedence in its existing operator hierarchy. I'm not
particularly familiar with Haskell or its implementations and compilers, so I'll
leave you with [this article][haskell_operators].

# Languages without operators

There are a couple of language families that don't do operator precedence at
all. One of these is Smalltalk: because it is concerned entirely with objects
and sending messages to them (but not in an Erlang way), operators are messages
with left associativity, so `1 + 2` sends the `+` message to `1` with the `2`
argument. This is roughly equivalent to `1.add(2)` in Java parlance, so it's a
little like every method is an infix operator (although methods with more than
one argument look a little strange). Smalltalk doesn't do any operator
precedence, however, and just sends the messages with their arguments left to
right, so `1 + 2 * 3` is `9`, not `7`, as normal precedence dictates.

Another example is Lisp, which uses prefix function application. It treats
operators as normal functions, semantically (if not literally), so `(+ 1 (* 2
3))` is `7`, but `(* (+ 1 2) 3)` is `9`. `1 + 2 * 3` is not syntactically valid
outside of quoted lists and macros. Because operators are (semantically)
functions so they can easily take multiple arguments, like `(+ 1 2 3 4)`, and
they are almost always variadic. Arguments are always grouped parentheses, so
there is no need for additional parentheses for grouping, but variadic functions
can reduce the cognitive and text load instead. Lisp does have real operators in
`'`, ``` `  ```, and `,`, which represent `quote`, `quasiquote`, and `unquote`.
Some Lisps introduce quite a few different `unquote` variants. However, in
normal usage, these operators are essentially unambiguous and unary, so their
implementation is comparatively simple.

Stack based languages like Forth and its ilk are the same, except prefix, so `2
3 * 1 +` is `7`, and `1 2 + 3 *`. `1 + 2 * 3` is syntactically valid, does
something very different: it adds 1 to the top of the stack, then multiplies it
by 2, then pushes a `3` onto the stack, leaving a stack of `[2 3]`. Because the
syntax lacks an easy way to specify variadicy, functions in these languages have
fixed arities, so operators are almost always unary or binary.

# Conclusion

I find myself unwilling to take a definitive position on this issue, nor do I
think a definitive position is really necessary. At this stage,
using operators and operator precedence is, essentially, the default position.
If your new language isn't in one of the language families above, it almost
certainly has operators. This isn't really a _problem_: large parts of your
compiler or interpreter have to know about operators, but we have a lot of
experience dealing with it, and multiple tools and techniques to simplify the
problem.

The languages that choose not to have operators seem to be languages
that have some fundamental priority or goal. Operators can efficiently represent
mathematical equations, but some languages feel that something else is more
important. Lisp, for example, thinks that aggressively unifying its syntax into
the absolute minimum state is more important than operators. Lisp's simple
syntax makes it a breeze to implement, which lets you focus on other parts of
the language, innovating on control flow, adding macros with your
homoiconography, etc.. Forth has a long heritage in RPN calculators, so I'm not
sure I can speculate on exactly _what_ Forth's is, but it seems to be ease of
implementation: thanks to the stack, implementation is both straightforward and
performant. The lack of operators and operator precedence is a natural
conclusion of building a stack based language.

Smalltalk decided to take object oriented programming to its logical conclusion
by making everything an object and making every thing you might do in the
language a method call on some object. However, this is also the semantic
approach Ruby took as well, and Ruby has operators and operator precedence. I
somewhat suspect that Smalltalk's lack of operators is a syntax issue: operator
precedence might have been difficult to parse properly when Smalltalk was being
invented, so they decided to make a syntax that didn't need it, but which could
express any mathematical expression with enough parentheses. Now that the decision
has been made, and legacy code relies on this admittedly straightforward
interpretation, it can't very well be changed. Not everybody has comprehensive
unit tests and a strong desire to translate equations from one operator
precedence to another.

I hope I've at least raised some questions in your mind. Operators are clearly
valuable, but their implementation is fraught and can be hampered in pursuit of
simplicity, and ultimately they aren't necessary. It's perfectly possible to
construct languages that don't need operators, just as it is possible to invent
languages that let programmers add as many operators as humanly possible.
Programmers will likely continue to expect operators in their languages: I know
I was floored the first time I saw how Lisp did math. I got over it though.

[haskell_operators]: https://csinaction.com/2015/03/31/custom-infix-operators-in-haskell/
