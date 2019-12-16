+++
title = "\"Interesting\" Clojure Macro Interaction"
date = 2019-12-15T23:01:08+01:00
draft = false
tags = ["code", "clojure"]
projects = []
+++

Clojure's macro system is a little tricky to work with (at least for me), but
it's also quite powerful. Being able to rewrite the languages AST at compile
time is really cool, and the fact that Clojure's syntax is just the
data structures that normal Clojure code operate on makes writing macros a
breeze (at least compared to, say, Rust or Javascript).

Clojure's macro expansion works in dependable way: it keeps apply macros until
there are no more macro calls in the code, then compiles the resulting code.
This means that you can use macros together without worrying (too much) about
the interaction: it should just work. This is reasonable when the macros are
depending to be functions, where they're syntactic sugar on top of a normal
function, or they expand into one or two calls to functions. These macros are
easy to write and easy to understand, and they let you write "functions" that
take their arguments pre-expanded and do interesting things with them.

There are also macros that implement DSLs like [Compojure][compojure_github],
which is a concise HTTP routing DSL. These are usually inflexible and slightly
awkward to use. I've heard it said that DSLs are written to the author's taste,
and you have to learn the author's taste to use their DSL, which can be pretty
awkward.

There's another kind of macro that could be labeled a structural macro. These
are macros that make writing functional code easier. Functional code in Lisp can
be difficult to read, because execution passes from the inside out. Clojure
offers the threading macros to make this easier (see [my
article][threading_article] more more context). Threading macros allow you to
write code that is executed from top to bottom, making it easier to read:

```clojure
(->> vals
     (map inc)
     (filter odd?)
     (reduce +))
```

Expands to:

```clojure
(reduce + (filter odd? (map inc vals)))
```

Which you have to read inside out when it's really better understood as a linear
pipeline.

But what if you're doing some work with the `core.async` libraries?

```clojure
(a/go
  (->> urls
       (map go-make-request)
       (map a/<!)
       (filter success?)))
```

This is another pipeline that reads better with a threading macro, but it's
still equivalent to

```clojure
(a/go
  (filter success?
          (map a/<!
               (map go-make-request urls))))
```

But what's this, we put all the function calls in the pipeline, but left the
call to `a/go` outside. This makes sense, because `a/go` is basically a piece of
syntax for indicating that these expressions are run in a `core.async` context
possibly on another thread. It's like the `fn` or `when` syntax. They're still
expressions that return values, but they also execute multiple expressions and
only return the last one, and tend to have other varied effects on the
execution order and location: they clearly don't operate like normal functions.

None of that matters, however, because Clojure does not differentiate between
them and normal syntax and you can just thread all those expressions together
like this:

```Clojure
(->> urls
     (map go-make-request)
     (map a/<!)
     (filter success?)
     a/go)
```

And it totally works. Want to also return the value from this go block to
non-`core.async` code?

```Clojure
(->> urls
     (map go-make-request)
     (map a/<!)
     (filter success?)
     a/go
     a/<!!)
```

Want to time how long this takes, but still return the value? The `time` macro to
the rescue!

```Clojure
(->> urls
     (map go-make-request)
     (map a/<!)
     (filter success?)
     a/go
     a/<!!
     time)
```

This can get so much worse. What if we only want to go through this pipeline if
we have some urls? As it is currently, we always launch a go block even if that
go block will find that `urls` is empty and immediately return the empty list
after mapping over nothing twice. We can just skip that if we want.

```Clojure
(->> urls
     (map go-make-request)
     (map a/<!)
     (filter success?)
     a/go
     a/<!!
     time
     (when (seq urls)))
```

It also works with other non-macro syntax

```clojure
((->> n
      inc
      (fn [n] (println n)))
 1)
```

Has homoiconicity gone too far?

Yes.

Should Rich Hickey stop?

No.

Should you use this in production?

Yes.

Will your coworkers let you?

No.

[compojure_github]: https://github.com/weavejester/compojure
[threading_article]: /posts/2018-11-3-pipeline-operators/
