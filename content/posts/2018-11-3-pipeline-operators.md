---
title: "Pipeline Operators"
date: 2018-11-03T19:28:01-07:00
tags: ["clojure", "elixir", "code", "rust", "language"]
---

Pipeline "operators" or "threading"[^0] constructs are interesting language
constructs. They are an acknowledgement that functional code can be a little
obtuse. They reorient (or rewrite) functional code so it looks more like a
"dataflow". Particularly of Lisps, but also of some other functional languages,
execution moves from the inside of expressions to the outside in a way that's
not particularly natural feeling. It's a real source of the difficulty people
express when reading functional code.

# Clojure

```Clojure
(reduce + (map #(+ % 5) (filter #(= (rem % 2) 0) (range 50))))
```

So what does this do? It's a little hard to say. Allow me to introduce the
threaded macro:

```Clojure
(->>
    (range 50)
    (filter #(= (rem % 2) 0))
    (map #(+ % 5))
    (reduce +))
```

This is the "thread-last" macro, which inserts the last expression as the last
argument to the current statement. It's a macro, so this rewriting is done at
compile time. Clojure also has a "thread-first" macro, which puts the last
expression in the first argument, and most use of these macros is with these 2
macros. This is because the Clojure standard library is carefully written so
that, based on the data type you're dealing with, the operative argument is
always either the first or the last across multiple relevant functions.
`filter`, `map`, and `reduce` are all similar functions, and they all take the
data structure they operate as their last argument.

This can seem a little limiting. Mostly you can just trust the standard library
writers, and the public library authors, and your own code, to fit into this
model pretty well. If you're doing something a little strange, you can use the
`as->` macro to bind a value to a name, and then thread the expressions with the
name in the right argument location, rather than implicit placement of the `->`
macro. The ergonomics isn't as good because that name ends up littering your
pipeline expression, but it's entirely equivalent and quite useful.[^1]

By reorienting/rewriting the expression, you can easily read _from top to
bottom_ the steps the expression takes to build the final value. Clojure also
allows for Java interop in the form of `(.methodName object args...)`. This fits
into the Clojure syntax nicely, and the threading macros let you chain method
calls more easily (although because it calls the method on the object that the
last method call returned, it can't be used to repeatedly call methods on the
same object unless that object is already a method chaining object, like a
Builder pattern object.)

Of course, one can _and should_ question the value of these macros. As macros,
they are _new_ syntax, but the nature of the macros and the **aggressive**
elision of the operant data[^4] can really obscure what threaded code is
actually doing. I think it ultimately produces easier to read code, but it isn't
pure profit: it introduces the mental overhead of knowing at least something
about threaded macros.


Outside of understanding how these macros work, there isn't any extra syntax
because, as a Lisp, Clojure's syntax is so regular.[^2]


# Elixir

Elixir doesn't have a threading macro, but it does have a pipeline operator.
It's still a macro, and still works in the same way, but looks a little
different. It solves the same problems, however.

```Elixir
Enum.reduce(Enum.map(Enum.filter(0..49, &(rem(&1, 2) == 0)), &(&1 + 5)), &+/2)
```

The `Enum` module always takes the collection as the first argument, and
additional parameters after, which makes the pipeline operator easier to use,
but makes this code exceptionally difficult to read. You read the names of the
operations first, then the initial collection, then a bunch of parenthesis,
operators, and commas that express several anonymous functions that get applied
according to the rules of the names you read before, but in reverse order. This
code makes heavy use of an anonymous function shorthand, and a piece of syntax
that is used to capture a named function as a value (`&+/2` captures the 2-arity
`+` operator as a value so you can reduce with it) because it wouldn't fit on
one line otherwise, and indentation will not make this code clearer. Shortened by
the pipeline operator, this code gets a lot more readable.


```Elixir
0..49
|> Enum.filter(&(rem(&1, 2) == 0))
|> Enum.map(&(&1 + 5))
|> Enum.reduce(&+/2)
```

Although much more readable, for reference, this is what the code looks like
without the anonymous function shorthand.

```Elixir
0..49
|> Enum.filter(fn x -> rem(x, 2) == 0 end)
|> Enum.map(fn x -> x + 5 end)
|> Enum.reduce(&+/2)
```

Elixir is not object oriented and does not have methods, but almost all APIs
obey the rule that the first argument is the "method receiver", so to speak.
This is adhered to almost to absurdity as seen in `Map.merge/2`, which takes 2
arguments, and merges the _second_ map into the _first_, giving the _second_
map's keys precedence in the merged map. I think that _first_ into _second_
would be a little more reasonable, but that's the decision they made
(`Enum.into/2` can do this, but I digress).

In practice, Elixir code is mostly function calls like above, but not always.
Elixir also has structs, which are some sugar on top of maps, but which provide
attribute access with method-like calls, so `struct.field` would index into the
struct. Elixir also, of course, has binary operators, which break the usual rule
of function syntax and just exist as `operand + operand` in the code (see my
[article][operator_article] for further discussion.)

How do these syntax aberrations fit into the pipeline operator? Very poorly. They
just don't at all, and the accepted method of, say, indexing into a struct is
with an anonymous function:

```Elixir
id
|> Database.lookup()
#|> &(&1.field).()
|> fn struct -> struct.field end.()
|> Enum.map(...)
```

Even when using the shorthand (commented out in the above), this introduces
substantial line noise, and because function values can't be invoked normally,
they have to to be called with `function.()`, even more extraneous syntax is
required. Elixir, like Clojure, does have a shorthand for single arity functions
that let you elide the ending parentheses, _it doesn't work on anonymous
functions_, so any time you want to do anything other than just calling
functions that share first arguments, you introduce a bunch of extra syntax.

It's usually easier to use assignment pattern matching, which breaks you out of
the pipeline operator mode, which is kind of the whole point, but it also puts
the assignment matching _at the start of the pipeline expression_, while the
function that produces the value you're destructuring is all the way at the end.

# `let`

Sometimes threading macros and pipeline operators are just too much work, and
too much mental overhead. Luckily, we can just return to normal programming. I
don't see code that looks like this very much, but it's much more flexible:

```Clojure
(let [coll (range 50)
      filtered (filter #(= (rem % 2) coll)
      plus-five (map #(+ % 5) filtered)
      sum (reduce + plus-five)]
    sum)
```

`let` will let you reference any previous arbitrary step, let you rebind names,
and will let you destructure and match at any step. Elixir's variable
definitions let you do all of this too (Erlang disallows name rebinding, but
Elixir permits it.)[^5]

This does require you to name your intermediate steps which might be a
showstopper for some people, but if your code is that complex, names will help
whoever has to understand the code next.

It is worth noting that there are a couple of libraries in Elixir that do
`monadic` programming, in that they define a monadic type like `{:ok, value} |
{:error, message}` to indicate success or failure (like a `Result` type). This
is a known type, but there isn't huge support for it in the standard library,
and the pipeline operator can't deal with it. So, a collection of several
different libraries implementing monadic bind and pipeline operators, in
addition to some Haskell style `do` syntax for the full naming and destructuring
environment, have sprouted up, like [OK][ok_link]. These are all similar but
slightly different, and there isn't a clear winner, so the whole thing is sort
of a mess. It's very useful to be able to pipeline failable operations together
while avoiding exceptions, but these libraries generally aren't substantially
easier to use with the above issues.

# Rust

Rust has all the extra syntax of Elixir with the addition of method calls.
Because it has method calls, you can build chaining APIs in Rust, which is sort
of the goal of this whole exercise. Just repeatedly call methods on whatever got
returned last to do what you want, and you always have normal assignments to
fall back on. Of course, someone did write a pipeline crate, and this is what it
looks like:

```Rust
// takes a string length, doubles it and converts it back into a string
let length = pipe!(
    "abcd"
    => [len]
    => (as u32)
    => times(2)
    => [to_string]
);
```
[^3]

The names in brackets are method calls on the value, `times(2)` is a function
that multiplies 2 values together, and `(as u32)` uses the `as` operator to
convert to an unsigned 32 bit integer. Because of diversity of syntax you can
use in Rust, to fully express the language in a pipelined fashion, you need a
lot of attendant syntax to make yourself clear.

You can use `pipeline.rs` in a monadic style, like in the following snippet:

```Rust
let result = pipe_res!("http://rust-lang.org" => download => parse => get_links)
```

This only calls the next pipe expression if the previous one returned
`Ok(value)` and not `Err(error)`, and calling the next pipe expression with the
value rather than the value in its monadic wrapper. This sort of monadic
programming is usually seen in rust through the `?` macro, which is used on
expressions which return `Result`s, and it expands to an expression that either
returns the wrapped value directly, or does returns from the function early with
the error value. It can't be used in functions which don't return `Result`s, but
it's a very idiomatic method of handling multiple failable operations in sequence.
You could write the above code using the `?` like this:

```Rust
get_links(parse(download("http://rust-lang.org")?)?)?
```

Which doesn't really solve the readability problem, to be fair. However,
`Result` does have method chaining API which can be used like so:

```Rust
Ok("http://rust-lang.org")
    .and_then(download)
    .and_then(parse)
    .and_then(get_links)
```

`Result.and_then` applies a function to the value a `Result` wraps if and only if the
result is `Ok(value)`, and expects that function to return another `Result<U, E>`, but
`U` and `E` can be unrelated to the types of the original `Result`.

Ultimately, Rust is a distinctly imperative language that just doesn't suffer
from the same ordering-comprehension issues that Elixir and Clojure do. It has a
number of existing tools for managing control flow, but even if you want to use
a pipeline macro or similar, thanks to Rust's powerful ahead of time compiler,
you can be sure it won't have a runtime performance cost.

# Haskell

I don't really know Haskell, but they generally solve this problem with
currying, which is a much broader and more powerful concept, but tends to be
opt-in in most languages, and usually not worth the effort or overhead to
"opt-in". Haskell also has a much broader understanding and use of Monads, and
has an explicit `do` syntax in the language, which is used extensively for
similar purposes.

# Conclusion

Although confusing at first, threaded-style code can bring much needed clarity
to complex nested functional code. However, because it's a syntax
transformation, it works best in contexts with simple and straightforward
syntax where the syntax transformation is easy to implement and easy to
understand, like Clojure.

In more complicated syntactic contexts, like Elixir and Rust, it can be useful,
but the additional syntax can make it much harder to understand, and macros
quirks must either be learned or worked around.

Rust has enough extra moving pieces that it can accommodate not having a pipeline
operator, but Elixir doesn't, and might need more intricate macros to support
better ergonomics.


[^0]: I can see why they chose this name (you're threading the expressions
    together, or you're threading the data through the expressions), but it
    clashes with the threads used for parallelism so badly that it makes
    researching this topic difficult. For reference, you can find the [Clojure
    docs here][clojure_docs] and the [Racket docs here.][racket_docs] 

[^1]: Racket doesn't let you bind to names like `as->`, but in both first and
    last threading macros, offers the opportunity to override the default
    argument position behavior by inserting a `_` symbol in the code (like a
    variable reference) to serve as the insertion point for the last expression.
    Clojure will let you match/destructure with `as->`, and end up with several
    different bound names, but the names get rebound _with every expression_, so
    it's a little hard to imagine a situation where this wouldn't get very confusing.
    
[^2]: It is worth noting that, in Clojure, you can "call" a keyword with a map as
      its argument, and index into a map, like so `(:key map)`, and that this works
      perfectly fine when used in a threaded macro, so `(-> map :key)` is
      equivalent. This is part of a special feature of the threading macros that
      let you elide the parenthesis around 1-arity calls, so this is also
      equivalent to `(-> map (:key))`.

[^3]: From [pipeline.rs](https://github.com/johannhof/pipeline.rs#examples).

[^4]: This is not helped by some functions producing transducers when called
    with only 1 argument, like `(map #(+ % 5))` outside a thread macro is a
    valid function call and produces a transducer. Transducers are composed like
    functions with `comp`, so if you aren't entirely familiar with the threaded
    macro, you might think you were looking at transducer code rather than
    threaded code.

[^5]: The Elixir version of the `let` example would be something like this:
      ```Elixir
      coll = 0..49
      filtered = Enum.filter(coll, &(rem(&1, 2) == 0))
      plus_five = Enum.map(filtered, &(&1 + 5))
      sum = Enum.reduce(plus-five, &+/2)
      ```

[clojure_docs]: https://clojure.org/guides/threading_macros
[racket_docs]: https://docs.racket-lang.org/threading/index.html
[operator_article]: /posts/2018-08-15-operators/
[ok_link]: https://hexdocs.pm/ok/OK.html
