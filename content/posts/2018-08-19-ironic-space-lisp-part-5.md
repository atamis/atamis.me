---
title: "Ironic Space Lisp Part 5"
date: 2018-08-19T20:44:24-07:00
tags: ["rust", "code", "language"]
projects: ["isl"]
---

Let's talk about environmental bindings. I'm taking the unusual (I think)
approach of sharing environment bindings code between the VM and the interpreter.
Unfortunately, I wrote the environment code at the same time as the VM, and
fit the code a little too closely to the requirements of the VM, and didn't
think enough about what the interpreter would require. In the process of writing
the interpreter, I encountered a strong disconnect between the semantics that I
wanted and the semantics I had. Additionally, the first version of the
environment used `mem::replace`. `mem::replace` is weird, I've used it a couple
of times, but mostly as a sort of band-aid, and I've always ended up refactoring
code away from it. It's ended up being a personal code smell of sorts. Luckily,
the new version doesn't use it.

`mem::replace` can sometimes seem like a way to get around borrow restrictions.
It takes a mutable reference, and a value, and swaps the old value for the new,
returning the old value. It doesn't violate the borrow checker, but it bends it,
and you can feel the `unsafe` blocks lurking in the background. It's based on
the `swap<T>(x: &mut T, y: &mut T)` function, which 

> Swaps the values at two mutable locations, without deinitializing either one.

This is noteworthy because it can do this to types which don't implement `Copy`.
It uses unsafe blocks to bypass the borrow checker. Under normal circumstances,
I think the function would have to take ownership of the values to swap them,
but with `unsafe` blocks, they can be swapped directly.


# The Old Version

```rust
pub struct Environment {
    bindings: HashMap<String, Rc<data::Literal>>,
    parent: Option<Box<Environment>>,
}
```

This looks reasonably normal for lexical scoping (sort of). You have local
bindings in a hashmap of names to values, and a pointer to a parent representing
higher level bindings. That pointer is a `Box`, however, which means only 1
pointer to this parent environment can really exist. `Box` is less a pointer and
more a value in heap memory: cloning the box will clone the inner value and box it.

This value represents a particular environment, so `put` just inserts directly
into the local bindings hashmap.

```rust
  pub fn get(&self, k: &String) -> Result<Rc<data::Literal>> {
      if let Some(v) = self.bindings.get(k) {
          return Ok(Rc::clone(v));
      }

      if let Some(ref p) = self.parent {
          return p.get(k);
      }

      Err(format!("Binding not found for {:}", k).into())
  }

```

The binding hashmap maps strings to reference counted pointers to data, so we
return a cloned pointer. Additionally, if this environment has a parent (and
therefor isn't the root environment), we delegate to our parent.


```rust
pub fn pop(&mut self) -> Result<()> {
    let parent = mem::replace(&mut self.parent, None);
    let parent = parent.ok_or("Attempted to pop root environment")?;

    *self = *parent;
    Ok(())
}
```

This function first takes ownership of the environment's parent by using
`mem::replace` to replace the parent with `None`, then it sets itself to its
parent with `*self = *parent`. In practical terms, this patterns is unknown to
me. Although the practice of replacing yourself makes sense if you're writing
instance methods on effectively immutable values (like numbers or booleans), I
don't really know if anybody does this with structs. I wasn't even sure this
code would compile.

```rust
pub fn push(&mut self) {
    let n = Environment::new();
    let p = mem::replace(self, n);
    self.parent = Some(Box::new(p));
}
```

This uses `mem::replace` to execute a sort of bait and switch, replacing
ourselves with the new empty parent-less environment, then setting ourselves as
the parent.

This upshot of all this swapping is that the user of this struct sees what
appears to be a normal linked-list type of environment binding, but calling push
and pop swaps the value in place, so the `Environment` struct acts more like a
container for all those nested environments, simultaneously managing the pushing
and popping of the Environments, and the looking up.

This works pretty well for the VM implementation. It only has to keep track of
one environment, and it only pushes and pops the environment stack in response
to instructions: it's someone else's job to push and pop environments at the
right time.

It didn't make quite as much sense for the interpreter. In the `let`
interpretation, the interpreter should make a new environment parented to its
own environment, load the local bindings into the new environment, then evaluate
the body with the new environment. However, pushing and poping those
environments is effectively done on the same struct, it just gets replaced. And
you have to pass the environment as a mutable reference to allow further local
bindings down the AST tree, so the upper levels are holding onto an Environment
that very much isn't for them. If the body of the let pops the environment one
too many times, the entire stack gets screwed. The interpreter also maintains a
global environment, but there's no concept of separation between those
environments, they're treated as the same value, so the global environment gets pushed
down the environment stack, and the struct points to environments evaluating
deep in the AST. As long as the environment doesn't get "overpopped", it won't
_break_, but the substantial difference between these two uses felt like a hint
that I was missing an important difference in my data model.

# The New Version

This particular technique has been on my mind for a while. In the simplest
self-hosting lisp interpreters, environment bindings are implemented with
"assoc" lists: lists of cons of keys and values `((a . 1) (b . 2) (c . 3))`,
or "alists", lists of lists of keys and values `((a 1) (b 2) (c 3))`. As a map
data structure, these have performance on the order of degenerate binary trees:
`O(n)` for search at worst. They do have a couple of useful properties: they're
very easy to implement, because they are lists you can just cons more pairs onto
them, and because of the way cons-lists share data, you can keep track of parent
environments by maintaining a pointer to cons you consider as represents the
head of your environment bindings, and generate child environments by consing
additional pairs on without risking mutating to your pointer and without copying
data needlessly. It also let you keep track of the child environments over the
long term, making lexical lambda bindings very easy to implement.

I obviously want to avoid the `O(n)` lookup times, so I want to stick with
hashmaps for the bindings themselves. I don't want to copy large environments
regularly, so I want to let child environments share parent environments too.
However, environments need to stay mutable to allow parent environments to move
on from evaluating children and add more bindings. Rust basically won't let us
leak memory, and we need to maintain multiple references to the environments, so
we need to use reference counted pointers. `Rc` won't let us mutate its value,
so we need to use a `RefCell` instead. `RefCell` enforces borrowing semantics at
runtime, allowing either 1 mutable reference or multiple immutable references at
one time. We have children pointing to environment, so we can't actually ever
mutate it with `RefCell`. Were we going to replace the parent environment with
another child to continue binding in the global environment? Deeply nested
environments like this steadily lose their performance advantage as you're
forced to check a longer and longer linked list of hash maps. We'd be
introducing a new child binding to be the new global binding with every local
environment, and we'd need to do it at non-local levels too.

This is getting cumbersome, but it's also beginning to remind me of immutable
data structures. Immutable data structures are data structures that implement
mostly normal data structure semantics, but in an immutable way. They are
perhaps best well known for their use in Clojure, where they back almost every
data structure in the language. The immutable data structures allows for hashmap
"mutation" while also allowing you to maintain the old version of the hashmap
unchanged, which is basically exactly what we want for our environments.
There are immutable data structures for many different types of data structures,
and I was planning on making Ironic Space Lisp ultimately backed the rust
implementation of immutable data structures, `im-rs`. I'm not sure if I want ISL
to have cons-lists or just have immutable vectors. While cons-lists are easier
to implement, immutable vectors are already implemented, and probably have
better performance characteristics. Changing this will probably mean changing,
at least slightly, all parts of the program (parser, AST, interpreter, and VM),
but I always envisioned ISL without mutability, in much the same way as Erlang
avoids mutability, and immutable data structures seem like a great way to do that
without being horribly inefficient and copying everything around, or attempting
to implement my own bad versions of existing immutable data structures.

Anyway, back to environments. `im-rs`'s `HashMap` matches the semantics I want
for environments pretty perfectly: hash maps with the option to insert "mutably"
and to produce new hashmaps with new values inserted to use as child
environments. I don't feel any particular need to wrap the `HashMap`, so my new
basic environment data structures is just this:

```rust
pub type Env = HashMap<String, Rc<data::Literal>>;
```

I'm continuing to use reference counted pointers to the bound values, but this
doesn't really agree with my philosophy that `Literal`s should be either easily
clonable or reference counted anyway.

This single type isn't entirely sufficient, though. Although the interpreter
keeps track of nested environments with its rust-level program stack, the VM
doesn't do that. I wasn't particularly eager to implement the environment stack
pushing and popping in the VM directly, so I decided to implement that
functionality in another type in the `environment` module, `EnvStack`:

```rust
pub struct EnvStack{
    envs: Vec<Env>
}
```

`EnvStack` implements many of the old `Environment` methods, like `get`, `put`
(which `Env` calls `insert` or `update` depending on whether you want to update
in place or get a new hashmap), `push`, and `pop`. Although `EnvStack` does own
all the `Env`s, it does let its users borrow the top of the stack with `peek`,
and I couldn't think of a good reason to allow for arbitrary borrowing, so you
can't. Finally, `push` and `pop` are adorably pedestrian compared to their
`mem::replace` ancestors:

```rust
pub fn push(&mut self) {
    let n = match self.envs.last() {
        Some(e) => e.clone(),
        None => Env::new(),
    };

    self.envs.push(n);
}

pub fn pop(&mut self) -> Result<()> {
    self.envs.pop().ok_or("Attempted to pop empty environment stack")?;
    Ok(())
}
```

Because the external interface changed, I had to change the test suite
substantially, and update the VM, but the interpreter was mid-rewrite when I
realized the need for a new environment implementation, so no interpreter code
got commited using the old environment before and the new AST.

In lieu of any serious conclusion, I'll leave you with a mangled proverb: _"In
the land of the borrow checker, the immutable man is king."_
