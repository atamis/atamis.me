---
title: "Ironic Space Lisp Part 6"
date: 2018-08-22T01:56:10-07:00
---

Since last time, I did two things: switched from `error_chain` to `failure`, and
refactored with the visitor pattern. They took about the same amount of time, 
and the refactor is much more interesting. I briefly touch on an issue I
encountered with `failure`, but I'd rather discuss the refactor.

# The Visitor Pattern

Calling this the visitor pattern is a bit grand. The visitor pattern has
intricacies that aren't entirely relevant in this situation, but I can describe
how this visitor works, and why I decided on it.

```rust
pub enum AST {
    Value(Literal),
    If {
        pred: Rc<AST>,
        then: Rc<AST>,
        els: Rc<AST>,
    },
    Def(Rc<Def>),
    Let {
        defs: Vec<Def>,
        body: Rc<AST>,
    },
    Do(Vec<AST>),
    Lambda {
        args: Vec<Keyword>,
        body: Rc<AST>,
    },
    Var(Keyword),
    Application {
        f: Rc<AST>,
        args: Vec<AST>,
    },
}
```

This is my full AST as it stands now. It's missing quote, quasiquote, and some
others, but this is a pretty good basis. It has important and hard bits, like
local bindings and functions. Like all ASTs, it's inherently recursive, and so
operating over it can be somewhat tedious. Consider the interpreter:

```rust
pub fn env_eval(&self, a: &AST, env: &mut Env) -> Result<Literal> {
    match a {
        AST::Value(l) => ...,
        AST::Var(k) => ...,
        AST::If { pred, then, els } => ...,
        AST::Def(ref def) => ...,
        AST::Let { defs, body } => ...,
        AST::Do(asts) => ...,
        _ => Err(err_msg("Not implemented")),
    }
}
```

Each branch can get really quite large, given the complexity of implementing,
say, `let`, and each branch of the match has to return a value for `Result`. As
you can see [here][old_interpreter], even a relatively simple interpreter can
get unwieldy. Additionally, there's error context to consider. It would be
convenient to be able to add context to every error that you might encounter
while recurring down the AST. Sometimes while evaluating you want to return an
error about your specific problem, but you also want to evaluate child ASTs from
your node, and you want to tag those with your context too. Breaking every match
branch into its own function is a convenient way of easily tagging all those
errors properly. Although the VM doesn't recur down an AST, it uses this error
handling approach:

```rust
match op {
    Op::Lit(l) => self.op_lit(l).context("Executing operation literal"),
    Op::Return => self.op_return().context("Executing operation return"),
    ...
    Op::PopEnv => self.op_popenv().context("Executing operation popenv"),
    Op::Dup => self.op_dup().context("Executing operation dup"),
}
```

I encountered a small issue when using `failure`, however. With `error_chain`, I
could use the `chain_err` function on `Result` to add context to an error and
then return it directly. For reasons I don't fully understand, I can't return a
context error from my functions. But if use the `?` operator, it works. The
above code is what I would like it to look like, with the type of the match
being `Result<()>` just like the function, but this is what I have to use instead.

```rust
Ok(match op {
    Op::Lit(l) => self.op_lit(l).context("Executing operation literal")?,
    Op::Return => self.op_return().context("Executing operation return")?,
    ...
    Op::PopEnv => self.op_popenv().context("Executing operation popenv")?,
    Op::Dup => self.op_dup().context("Executing operation dup")?,
})
```

The type of the match is actually `()`, because the match threatens to return
early if the result of the function call isn't `Ok`, then I rewrap it in `Ok`
immediately after calling. [Someone][failure_issue] encountered this problem
too, although he didn't think it was as important.

Anyway, while thinking about iterating over ASTs for various purposes (AST
passes, code generation, etc), I began to think about more complex error
handling. I'm currently using strings for all my errors, which is usually cited
as an "okay" idea for prototype projects and applications, but for libraries,
you should really use more complex error types to make it easier to match on
failure sand respond correctly. Of course, complex error types are also useful
for holding information. If I encounter an error while processing an AST, having
each recursion level tag the error can produce a neat little backtrace for the
AST, but being able to produce errors with the AST copied into them, showing
directly in the AST where the error occured would be very useful, and having
errors using both the AST and potentially line and character numbers could
enable some very nice error messages, which are always important for a
programming language.

However, if I had to rewrite this error handling code for each AST pass I wanted
to write, I would invariably not do this error handling code at all, because no
one pass was so important that it needed this extra effort. If I could abstract
that away, however, and write the code once, I could get it almost for free in
many different places. Plus, as I planned out AST passes like checking for
unbound variables, and comparing them in my head to the current AST passes I had
(interpretation), the similarities were obvious at a relatively high level, and I
could express each as a effectively a reentrant pseudo-map reduce function.

I wouldn't call this full map reduce. There is no particular reduce function,
and not every application needs to map over the entire AST, some can short circuit.

```rust
pub trait ASTVisitor<R> {
    fn value_expr(...) -> Result<R>;
    fn if_expr(...) -> Result<R>;
    fn def_expr(...) -> Result<R>;
    fn let_expr(...) -> Result<R>;
    fn do_expr(...) -> Result<R>;
    fn lambda_expr(&mut self, args: &Vec<Keyword>, body: &Rc<AST>) -> Result<R>;
    fn var_expr(...) -> Result<R>;
    fn application_expr(...) -> Result<R>;
}
```



It also implements a very familiar function `visit` to dispatch an `AST` to the
right method.This is how the interpreter `visit` an `do` expression.

```rust
fn do_expr(&mut self, exprs: &Vec<AST>) -> Result<Literal> {
    let mut vals: Vec<Literal> = exprs
        .iter()
        .map(|e| self.visit(e))
        .collect::<Result<_>>()
        .context("Evaluating do sub-expressions")?;
    Ok(vals.pop().ok_or(err_msg("do expressions can't be empty"))?)
}
```

Note that the recursive call is `self.visit(e)`. This is because `ASTVisitor` is
a trait to be implemented on a particular type that is neither `AST` nor `R`,
and it forms a sort of second generic type argument. This probably makes sense
from an object oriented view, but can lead to some semantically confusing
implementations.

For example, the interpreter implements `ASTVisitor` on `Env`. `Env` holds
lexical bindings, but it's very strange to say "Env visits each AST node to
evaluate the expression". The idea that the environment binding is taking the
action "visit" on the AST is sort of alien: it doesn't make semantic sense, even
if the code works. What makes it particularly strange is that the `Env` value
_changes_. While evaluating some ASTs, we have to introduce limited local
environment bindings, so we make a new `Env` with the old `Env` as a parent, add
our bindings, _then have that `Env` visit the body `AST`s_ . I'm not entirely
sure how the visitor pattern is _supposed_ to work, but swapping out or "object"
mid-flight is very strange from an object oriented point of view. To solve this
conceptual issue, I considered making `ASTVisitor` to have two type arguments.
The implementer type would be assumed to be a dummy at best, and then have each
function take both a `self` and a generic argument. I ultimately decided against
this, because the implementing type basically is another generic argument, even
if it's weird to think about it that way. Maybe it isn't that weird to think
about, making I'm taking an excessively object oriented approach to this.

After making this pattern, I reimplemented the interpreter as an `ASTVisitor`
over `Env`, and proved it worked with the existing tests. I then wrote an AST
pass to find unbound variables, which worked quite well. I certainly hope that
`ASTVisitor` proves to be robust enough to build a full compiler with it.

Speaking of the compiler, I'm trying to decide if I should do research on how to
write compilers. That may sound like a silly question, but I'm interested in
just trying to write a compiler and see how far I get without professional help.
I can't say I wrote this code alone so far; I've learned programming language
implementation in an academic setting before, but I haven't learned compilers in
the same way. I guess I'm interested in seeing what a compiler written by an
"outside" would like like compared to a traditional compiler. That is, my plan
is to write the compiler in isolation, then compare notes with a textbook. That
might be too ambitious, however. I might get half way through the compiler and
realize that I missed some critical piece early in the processing, my work has
been built on a shoddy foundation, and I was going to have to start over again
from scratch, or even worse, I couldn't think of where to go next. At that
point, I might turn to a compiler text book in despair, having been beaten by
the task.

Simply reading the books is probably the easiest solution, but maybe important
insight can be gleaned from simply throwing myself into the problem. Then I can
post the insight on my blog.


[old_interpreter]: https://github.com/atamis/ironic-space-lisp/blob/fa0b02f7a8ba2562f3b0338289460c5de08261b1/src/interpreter.rs#L39
[failure_issue]: https://users.rust-lang.org/t/announcing-failure/13895/18
