---
title: "Ironic Space Lisp Part 2"
date: 2018-07-29T10:59:40-07:00
---

[Part 1](/posts/2018-07-29-ironic-space-lisp/)

[Part 2](/post/2018/07/29/2018-07-09-ironic-space-lisp-part-2/)

Last time, the conceptual challenges of a the stack VM convinced me it was the
wrong approach. In a normal recursive lisp interpreter, code is data, and you
have a single evaluator function over every value. [Follow along here][git1].

[git1]:https://github.com/atamis/ironic-space-lisp/tree/4ee0904fdc54c876cdd9231ff4f1e49593286280

```rust
/// Omni-datatype. Represents both data and code for the lisp VM.
#[derive(Debug, Clone)]
pub enum Lisp {
    /// Represents a single u32 number.
    Num(u32),
    /// Represents an operation see `Op` for more info.
    Op(Op),
    /// Represents a list of `Lisp` values. Note that this is reference counted.
    List(Rc<Vec<Lisp>>),
}
```

_[that Rc pointer to the Vec should have been a hint something was going to go
wrong.]_

This recursive type mirrors the recursive nature of the language, and can be
easily consumed with a recursive function to evaluate the code into a single
value.

```rust
  #[deprecated]
  pub fn normal_eval<'a>(l: &Lisp) -> Lisp {
      match l {
          Lisp::List(rc) => {
              // Main recursion here:
              let l: Vec<Lisp> = rc.iter().map(normal_eval).collect();
              let op = &l[0];
              let args = &l[1..];

              match op {
                  Lisp::Op(Op::Add) => {
                      // Sum up the args and aggressively panic.
                      let sum = args.iter().fold(0, |sum, i| match i {
                          Lisp::Num(i) => sum + i,
                          _ => panic!("Can't add non-numbers"),
                      });
                      Lisp::Num(sum)
                  }
                  _ => panic!("Not operation, or operation not implemented"),
              }
          }
          x => (*x).clone(),
      }
}
```

This function is quite simple: if it's a normal value, just clone the value and
return it. If it's a list, it's a "function" application which is just the
addition operation right now, so evaluate all the list items, and sum up the
`rest` and return. It's easy to keep track of things in your head, if you add
more data types and operations, it's easy to just add them. Trying to make an
entire evaluator in a single function is a bit much, but it's easy enough to
delegate tasks to other functions that are also `(...arguments) -> Lisp`.

Probably the most important thing to draw your attention to is the state of
borrowing in this function. Very soon, the borrowing would become a real problem
for me, so let's look at this nice simple function and its nice simple borrowing
rules. The function takes an immutable reference to a Lisp value, so it doesn't
take ownership of it. This means that although we can destructure and recur on
it, we can't break it apart: we don't own the value. This seems pretty
reasonable: a lisp evaluator that mangles its code as it runs is pretty weird.

However, in just this simple example alone, we have to _return_ both existing
values in the code, and new values made by executing the code: both literal
values and the summed value. If we want to evaluate to a reference, we have a
problem with the addition. We make a wholly new value for the addition operation
to return, and we need to ensure that value will life long enough. If we return
a reference to it, the value will go out of scope immediately, and won't live
long enough for the reference to it to stay valid, which runs afoul of Rust's
lifetime checker.

On the other hand, if we return the value itself, we end up cloning the data
literals in the code because returning them directly runs afoul of the borrow
checker: they aren't ours to give, we're just borrowing them from our caller.
You can't do any real evaluation with making new values (except in some very
strange languages), so we live with cloning data literals.

# The Next Stage

So normal recursive lisp evaluators are nice and simple, but they can't be
paused: they'll just burn through the AST using the program's stack to keep
track. You can't stop them, and stopping them is exactly what we need to do if
we want a stepped evaluator.

So normal recursive evaluators destructure the AST in place, then call
recursively on the component pieces. They keep track of which part of the tree
they're operating on with a stack and local pointers on the stack.

What if we did that, but instead of using the program stack, we just made our
own stack, and pushed and popped frames to that, and pretended to be recursive
when in fact we're some horrible amalgamation of programming concepts built to
serve a sort of fake purpose? On the plus side, it'll make implementing
wake-on-receive easy.

```
trait Frame: fmt::Debug {
    fn single_step(&mut self, return_val: &mut Option<Lisp>)
      -> Result<FrameStepResult, VmGeneralError>;
}
```

This is one of our stack frames. What's `FrameStepResult`?

```rust
// Controls flow in evaluation.
#[derive(Debug)]
enum FrameStepResult {
    // Don't do anything to the control flow.
    Continue,
    // Indicates that the fragment is done and wants to return a value. Set
    // the return value, and pop the frame stack.
    Return(Lisp),
    // Start to recur on a another piece of lisp code.
    Recur(Lisp),
}
```

Oh boy. Frames need some way to actually call our fake recursive function, and
then they're just in limbo waiting for that function call to complete. Functions
that can be called can return, and this is done by returning
`FrameStepResult::Return(value)` rather than using the mutable pointer to the
return value. That pointer is into the overall VM struct. It allows the function
to access the return values of any function it may have called. Under normal
non-horrible-amalgamation situations, when you push the program counter to the
stack and jump to a new function, and that function returns, the program returns
to right after the function call so you can continue with your function. The
very lack of the capacity is almost why we're in this predicament in the first
place, so these frames have to return fully every time they want to recur or
return, so the frames have to be partially reentrant.

Let's look at the `ApplicationFrame`. The structs for frames represent their
"local variables", so `ApplicationFrame` holds a vector of lisp terms waiting to
be evaluated, and a vector of already evaluated terms. Let's look at just that
process of evaluating those terms (This code refers to them as fragments.
Fragments of _what_, I'm not sure.)

```rust
// Extract the result of the last fragment we recurred on.
if let Some(_) = return_val {
    if let Some(myr) = mem::replace(return_val, None) {
        self.vals.push(myr);
    }
}

// We've evaled all the arg fragments, so it's time to actually
// apply the args to the operation.
if self.list.len() == 0 {
  /* dragons */
} else {
    // We're still evaling arguments.
    let l = self.list.remove(0); // TODO: use pop and reverse arg list

    // Indicate to the evaler that we want to recur on the next arg
    // fragment.
    return Ok(FrameStepResult::Recur(l));
}
```

First, the frame checks to see if there is a return value. This would indicate
that this isn't the first time this frame has been invoked (because the
`Evaler` resets it before recursive calls), and that the return value is the
result of evaluating one of our terms. So we want to extract that value and push
it to our value list. However, the `Evaler` struct owns the value, so we have to
steal it with `mem::replace`. This should be setting alarm bells off: something
is going wrong. To be clear, alarm bells were going off: the documentation does
say it outright, but implies `mem::replace` is something of a hack. It "breaks"
borrow rules in a safe and structured way, but it's still worrisome.

Next we check if we still need to evaluate more terms, and if so, we pop one off
and pass it off for recursion. The fact that we can do this implies this frame
__owns__ those lisp values. The recursive call will do whatever with those
values, never return them, and those lisp values are now lost? This evaluator is
destructuring the values recursively, but then throwing the code away. The
`Evaler` takes ownership of the code, passes it along to its frames, and then
the code is just gone: the `Evaler` quite literally consumes it. This means you
can't reexecute code: the code is gone.

This fact didn't really occur to me. Or didn't concern me. It soon would.

I draw your attention to the small note below the listing for the data type at
the top of this article, and the particular detail that a `Lisp::List` is a
reference counted pointer to a vector. `Lisp` is an enum, so all its members
must be `Sized`, which is a fancy Rust way of saying you have to know their size
at compile time. `u32` and `Op` both have known sizes, but because vectors can
and will grow dynamically, their size isn't known, so you need to heap allocate
them.

The first pointer you reach for is `Box`, which is a heap allocated value
that mirrors the normal value semantics: when you `clone` a `Box`, the internal
value must be clonable, because `Box` clones both itself and the internal value.
You get a whole new value and box. I wasn't a huge fan: cloning large data
structures regularly takes of lot of CPU time and massively increases memory
usage. So instead of using `Box`, you can use `Rc`.

`Rc` is reference counted, and when you clone an `Rc`, you get a new pointer to
the same object in memory. It's still an immutable pointer: Rust guarantees that
immutable pointers are actually immutable, the value won't just change on you.
In particular, it guarantees that there are no mutable pointers lying around to
change the value your immutable pointer is pointing to. `Rc` guarantees the same
thing: you can have multiple immutable pointers, or 1 mutable one.

Allow me to draw your attention to `ApplicationFrame`, which _consumes_ its lisp
terms. It must own them, and then pass them on to the next frame. If it receives
a `Lisp::List`, the values are hidden behind an `Rc`, which owns the values. So
`ApplicationFrame` takes them from the `Rc`.

That resulted in this delightful piece of code:

```rust
// TODO: maybe don't do this.
let list = Rc::try_unwrap(l).unwrap();
```

This code attempts to take ownership the value from `Rc` in full, and then
panics if it can't. I love that comment. I put it there right after writing the
line of code. I was so close to realizing what an awful idea this model was.

I wouldn't realize it for a long time.

# Things are going to get worse before they get better.

At this point, the code actually works. It consumes code so it can't be
reexecuted, but the code does work.

This next part isn't reflected well in the commit history. I'm not entirely sure
what prompted this change, but I was having trouble implementing `if`. During
that process, I came to the realization of just what the code was doing, and
that __consuming__ code datums shouldn't be this literal.

So my next step was to replace all the full value passing with internal
refernces. I figured that the `Evaler` would hold the code struct, and I'd just
pass references to it to the frames. Easy. Nope.

This is what I was trying to do:

```rust
#[derive(Debug)]
enum Lisp {
    Data(u32),
    Pointer(&Lisp)
}

#[derive(Debug)]
struct Evaler {
    data: Lisp,
    stack: Vec<Frame>,
}
```

This does not work. The pointer in `Lisp` needs a lifetime tag. The lifetime
checker in Rust needs a guarantee that the value the pointer is pointing at will
live at least as long as itself, and there is no way to guarantee that. Thinking
logically, you can more or less prove that this won't cause problems to
yourself, so you could write a C program that worked this way (just never free
the code, and free the frames in reverse order), but you can't prove it to Rust,
so this isn't a valid Rust program. Rust sees that the `Evaler` owns the data,
and that the frames might be moved out of the `Evaler`, and then the `Evaler`
freed, and then the frames would have null pointers, and null pointers are a
compile time error in Rust.

Luckily, the solution is `Rc`. `Rc`s everywhere. Shockingly, it just now occurs
to me that _maybe_ this traditionally garbage collected language of lisp _might_
want to at least use reference counted pointers in its evaluation process.

[Witness the carnage.](https://github.com/atamis/ironic-space-lisp/commit/7c5fcaad153be67345a25e46901e8deb72ae0489)

_[The stepped implementation is 340 lines long. It doesn't have any more features
than the recursive implementation at the top of the article.]_

That's all for now. I'm a little worried this crazy plan won't end up working.
Or that the insane way frames have to be written is just untenable. Maybe I can
solve those with state machines. Maybe I should revisit stacks.

