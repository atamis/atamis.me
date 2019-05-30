---
title: "Clojure's Looping Syntax is Surprising"
date: 2019-05-30T11:52:59-07:00
---

They aren't _super_ popular, but Clojure has a rich set of high level looping
macros. You have `for` for list comprehensions, `doseq` for imperative looping
over sequences, `dotimes` for an even simpler integer loop, `while` for raw
predicate looping, and `loop` for any kind of arbitrary recursion-style looping
you want to do. However, I'm not a huge fan of the exact syntax some of these
macros use.

Let's talk about `let`, which looks like this:

```Clojure
=> (let [x 10
         y :asdf
         z (range 10)]
     (vector x y z))
[10 :asdf (0 1 2 3 4 5 6 7 8 9)]
```

`let` binds the values to names in order, then executes the body in that lexical
context. Although they're bound in a particular order, they get bound once, then
the body is executed once, as you'd expect.

So, how does `for` work? Here's a basic example:

```Clojure
=> (for [x (range 5)]
     x)
(0 1 2 3 4)
```

As a "list comprehension", `for` binds the values in sequence, then constructs a
list based on the value of the body. `x` gets re-bound to the next item in the
sequence (which is `(range 5)` here) and the body gets re-executed for as long
as the sequence has items remaining.

So imagine you're learning Clojure. Based on how `let` binds its values, how
would you expect this to work:

```Clojure
=> (for [x (range 5)
         y (range 5)]
     [x y])
```

Would you expect it to work like this?

```Clojure
([0 0] [1 1] [2 2] [3 3] [4 4])
```

The 2 sequences get iterated over together, in lock step. This is not how it
works, however:

```Clojure
([0 0] [0 1] [0 2] [0 3] [0 4]
 [1 0] [1 1] [1 2] [1 3] [1 4]
 [2 0] [2 1] [2 2] [2 3] [2 4]
 [3 0] [3 1] [3 2] [3 3] [3 4]
 [4 0] [4 1] [4 2] [4 3] [4 4])
```

It iterates over the entirety of the second sequence _for each value in the
first sequence_, and this generalizes over any number of sequences. `doseq`
works the same way, but it doesn't construct a list, and it's eager (where `for`
is lazy).

So what would you do if you _did_ want to iterate over 2 sequences together?

```Clojure
=> (for [[x y] (map vector (range 5)
                           (range 5))]
     [x y])
([0 0] [1 1] [2 2] [3 3] [4 4])
```

This uses `map` to construct series of intermediate vectors (because `map` deals
with multiple sequences by mapping over them together), then uses the binding
syntax to deconstruct the vector into `x` and `y` to keep the variable names the
same as the above examples, then returns the vector of `[x y]` we're actually
looking for. And what if you didn't want to make the intermediate vectors? Well, then you're back to using `loop`:

```Clojure
=> (loop [x (range 5)
          y (range 5)]
     (when (not (empty? x))
       (println [(first x) (first y)])
       (recur (rest x) (rest y))))
[0 0]
[1 1]
[2 2]
[3 3]
[4 4]
nil
```

This binds `x` and `y` to the range sequences initially (and they get rebound
together each loop), prints their first element, then recurses on the rest of
both. When `x` is empty it returns nil, and it doesn't particularly deal with
sequences of unequal length.

This is pretty inconvenient to do with any regularity. `loop` is really powerful
and _very_ performant, but you have to do almost everything by hand.

For me, at least, this iteration pattern violates the principal of least
surprise. I learned Racket before Clojure, and this is exactly how Racket works.

```Racket
> (for/list [[x (range 5)]
             [y (range 5)]]
    (list x y))
'((0 0) (1 1) (2 2) (3 3) (4 4))
```

I really honestly expected, based on how `let` works and how Racket works, that
`for` would loop together. The worst part is that, for newer users, `(map
vector)` is not particularly intuitive, and if you want to iterate like that,
it's much more natural to nest your loops _syntactically_ rather than implicitly:

```Clojure
=> (for [x (range 5)]
     (for [y (range 5)]
       [x y]))
(([0 0] [0 1] [0 2] [0 3] [0 4])
 ([1 0] [1 1] [1 2] [1 3] [1 4])
 ([2 0] [2 1] [2 2] [2 3] [2 4])
 ([3 0] [3 1] [3 2] [3 3] [3 4])
 ([4 0] [4 1] [4 2] [4 3] [4 4]))
```

Nested for loops even handle predicates just fine:

```Clojure
=> (for [x (range 5)]
     (for [y (range 5)
           :when (< x y)]
       [x y]))
(([0 1] [0 2] [0 3] [0 4])
([1 2] [1 3] [1 4])
([2 3] [2 4])
([3 4])
())
```


The astute among you will notice that this produces a different value, namely
that the inner loop produces sequences, which the outer loop put into another
sequence with no flatten, so this is a list of list of vectors instead of just a
list of vectors. This is a pretty normal problem for Clojurians to solve, so it
doesn't seem insurmountable. Additionally, a version of `for` that flattens or
appends bodies, and therefore produces the same value would also not be hard to
develop or understand. This pattern is flawlessly applicable to `doseq` use
cases, for example.[^2] This is also exactly how non-lisp languages solve these
problems.

```Rust
for x in 0..5 {
    for y in 0..5 {
        println!("{:?}", vec![x, y]);
    }
}

[0, 0]
[0, 1]
[0, 2]

...

[4, 1]
[4, 2]
[4, 3]
[4, 4]
```

What about Common Lisp?

>LOOP provides what is essentially a special-purpose language just for writing
>iteration constructs.[^1]

Well alright then.

So that's my basic objection to this particular syntax choice in `for`. It
violates the principal set up by let, it's convenient for a scenario that isn't
particularly common and which has an easy solution (nested looping) while
forcing you to use obscure idioms for the other situation (synchronous looping).
You could argue that the synchronous looping has some pitfalls, such as "what to
do when the sequences are of different length," and that perhaps the language
designers didn't want to force a core looping construct into either option, but
in fact, the designers already decided on how the language would operate in a
similar situation, `map`, which stops when the first sequence stops.

I'm sure that Rich Hickey discussed this decision somewhere online, and
being Rich Hickey, he probably has good reasons, and it's too late now, but I
couldn't find it, so I'm doing what any good netizen would do: complaining on my
blog.

[^1]: [LOOP for Black Belts](
    http://www.gigamonkeys.com/book/loop-for-black-belts.html) by Peter
    Seibel, 2005. Accessed 2019.
[^2]: `dotimes`, which I mentioned earlier, allows exactly 1 binding per
    expression, so the question of how to handle multiple bindings is
    sidestepped.
