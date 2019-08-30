+++
title = "Ironic Space Lisp Part 9"
date = 2019-08-29T14:05:09-07:00
draft = false
tags = ["rust", "code", "language"]
projects = ["isl"]
+++

It's been a long time since I last worked on ISL, mostly because I got
distracted by other projects and languages: things like the
[flows](/projects/flows/) project, or Clojure. Also, writing futures code in
Rust is _painful_. Recently, async-await syntax got released on Rust nightly,
which makes async code much easier to write.

When I was last working on the project, I was working on a local variables
feature. VM operations to allow storing and loading local variables linked to
the frame stack, and later, support in the compiler. I left this unfinished and
riddled with errors, so I branched those changes off and committed them as
broken so I could work on something else.

# The Execution Environment

That something else was a new execution environment. I wrote a preliminary
version an asynchronous execution environment with raw futures before I took the
break, and the code was messy and heavily nested. The new code is a lot nicer
and more straightforward, but I encountered some pretty awkward features.

To start with, Rust doesn't have async traits yet. Trait methods cannot be
asynchronous, but there is a crate to fix this, [async-trait][async-trait]. This
requires that traits and implementations be tagged with a macro, but hopefully
this will be resolved in Rust core later: this seems awkwardly fundamental not
to have, although we aren't entirely async yet.

```rust
/// A trait for interfacing between a [`vm::VM`] and its execution environment.
#[async_trait]
pub trait ExecHandle: Send + Sync + fmt::Debug {
    /// Return the `Pid`, or unique identifier of the exec handle.
    fn get_pid(&mut self) -> data::Pid;
    /// Send a message to a particular `Pid`.
    fn send(&mut self, pid: data::Pid, msg: Literal) -> Result<()>;
    /// Spawn a new `VM`, consuming the `VM` and returning its `Pid`.
    fn spawn(&mut self, vm: vm::VM) -> Result<data::Pid>;
    /// Asynchronously receive a Literal from your inbox.
    async fn receive(&mut self) -> Option<Literal>;
}
```

This trait defines the 4 methods that the VM, or really any Rust code that wants
to interact with the ISL execution environment, can use. Each handle has a
unique PID that is registered with the central router (more on that later), so
you can get your own pid, send a message to another pid, spawn another VM (more
on that later too), and an asynchronous method to maybe receive a message on
your own incoming channel.

This execution environment uses a central router to route incoming messages to
the right PID. Each handle has a single incoming channel (typed as an ISL
`Literal`). This mirrors, at least in functionality, how Erlang works. Each
process has a single incoming mailbox, and all messages between processes are
normal Erlang terms.

of course, the BEAM doesn't use a single central router for this, that would be
slow and stupid, but implementing it in this way made sense for now.

Finally, it's worth noting that the spawn method takes a `VM`. This is because
the core of the execution is a function unhelpfully named `exec_future`, which
takes , which consumes a `VM` and returns a future representing the asynchronous
execution of that VM, and the PID of its router handle. It doesn't schedule it
(depending on context, either the `ExecHandle` or `Exec` itself handles that.)
Of course, because the router handles are pretty generic, more than one kind of
ISL executor could run in the same execution environment seamlessly. So, the
execution environment could be made more generic by instead taking futures
rather than the pieces necessary to make the futures.


The other issue I encountered (specifically with `exec_future`) was in trying to
write a "semi-asynchronous" function. Under normal circumstances, `async`
functions are basically transparent. Here's the implementation of `receive` for
for router handle:

```rust
/// Asynchronously receive a Literal from this channel.
async fn receive(&mut self) -> Option<Literal> {
    self.rx.next().await
}
```

This is when Rust's async await stuff works the best. All `Future` types are
hidden by the compiler, asynchronous method calls only need `.await`, and no
nesting or callbacks or anything. What if, though, I wanted a function that
return 2 values, 1 immediately, and one asynchronously? Well, if you're
returning a value immediately, the function can't be asynchronous, that much is
clear (or if it isn't, then getting the immediate value becomes much more
annoying). So we need to return a value (in this case the PID of the newly
spawned VM), and the VM's actual future. So, we need to actually figure out what
type an asynchronous function literally returns, so we can also return it from
this function. The easy part is making the future, which can be done by
anonymous async closure, which returns a future.

Here's the real signature:

```rust
fn exec_future(
    mut vm: vm::VM,
    router: &RouterChan,
) -> (
    data::Pid,
    Pin<Box<impl Future<Output = (vm::VM, Result<data::Literal>)>>>,
)
```

So, the future's output is a tuple of the VM (because `exec_future` has to take
ownership of the `VM`), and the result of its execution, which could be an error.
The future is boxed because its size can't be determined properly at compile
time, and it's pinned because I'm not sure why. It wouldn't type check
otherwise, because spawning the future on an executor required it to be pinned.
Luckily, pinning and boxing the future was as easy as `Box::pin(f)`, where f is
the future. I didn't manage to find many helpful resources on this _very_
specific subject (async-await is very new), so hopefully this helps someone.

# Comparison

I want to put a comparison between some old futures code and the new async code.
The first is `exec_future`, the beating heart of asynchronous `VM` execution.

Here's the old version:

```rust
fn exec_future(
    mut vm: vm::VM,
    router: &RouterChan,
) -> (
    data::Pid,
    Box<Future<Item = (vm::VM, data::Literal), Error = failure::Error> + 'static + Send>,
) {
    use vm::VMState;

    let mut handle = RouterHandle::new(router.clone());

    let proc = handle.get_procinfo();

    let pid = proc.pid;

    vm.proc = Some(Box::new(proc));

    handle
        .router
        .try_send(RouterMessage::Send(handle.pid, "dummy-message".into()))
        .unwrap();

    let f = loop_fn((vm, handle), move |(vm, handle)| {
        ok((vm, handle)).and_then(
            |(mut vm, handle)| -> Box<
                Future<
                        Item = Loop<(vm::VM, Literal), (vm::VM, RouterHandle)>,
                        Error = failure::Error,
                    > + Send,
            > {
                vm.state = VMState::RunningUntil(100);
                vm.state_step().unwrap();

                if let VMState::Done(_) = vm.state {
                    let l = { vm.state.get_ret().unwrap() };
                    vm.proc = None;
                    return Box::new(ok(Loop::Break((vm, l))));
                }

                if let VMState::Stopped = vm.state {
                    return Box::new(ok(Loop::Continue((vm, handle))));
                }

                if let VMState::Waiting = vm.state {
                    return Box::new(handle.receive().then(|res| {
                        let (opt_lit, handle) = res.unwrap();
                        vm.answer_waiting(opt_lit).unwrap();
                        Ok(Loop::Continue((vm, handle)))
                    }));
                }

                panic!("VM state not done, stopped, or waiting");
            },
        )
    });

    (pid, Box::new(f))
}
```

Dense, nested, and confusing

```rust
fn exec_future(
    mut vm: vm::VM,
    router: &RouterChan,
) -> (
    data::Pid,
    Pin<Box<impl Future<Output = (vm::VM, Result<data::Literal>)>>>,
) {
    use crate::vm::VMState;

    let handle = RouterHandle::new(router.clone());
    
    let pid = handle.pid;

    vm.proc = Some(Box::new(handle));

    let f = async move || loop {
        vm.state = VMState::RunningUntil(100);

        if let Err(e) = vm.state_step() {
            eprintln!("Encountered error while running vm: {:?} ", e);
            return (vm, Err(e));
        };

        if let VMState::Done(_) = vm.state {
            let l = { vm.state.get_ret().unwrap() };
            vm.proc = None;
            return (vm, Ok(l));
        }

        if let VMState::Waiting = vm.state {
            let opt_lit = vm
                .proc
                .as_mut()
                .map(move |proc| proc.receive())
                .unwrap()
                .await
                .unwrap();
            vm.answer_waiting(opt_lit).unwrap()
        }
    };

    (pid, Box::pin(f()))
}
```

Simpler and cleaner. The control flow in particular is really clear. The entire
asynchronous closure is one big loop that proceeds in the normal fashion, while
the old futures code used the `loop_fn` construct, which took closure which
_returned a loop control value_, and would then loop or stop looping based on
that, making it very confusing, all in all. Like, writing this code wasn't
terribly hard, nor is reading it, but it requires a lot of special knowledge,
and I referred to the futures documentation heavily for writing this fairly
simple looping code. By contrast, to write the async-await code, I merely had to
refer to the Rust control structures I was already familiar with, and if this
function hadn't needed to return the VM, then i would have been able to make
heavy use of the try/`?` macro to make the code even simpler.

It is worth noting that this code has a lot of raw `unwrap`s, which are
dangerous, and I'll replace it with real error handling code later.

Let's take a look at the router. Here's the old:

```rust
/// Spawn a router on the runtime.
///
/// Routers respond to router messages sent on the sender channel this function returns.
pub fn router(runtime: &mut Runtime) -> mpsc::Sender<RouterMessage> {
    let (tx, rx) = mpsc::channel::<RouterMessage>(10);

    let f = rx
        .fold(RouterState::new(), |mut state, msg| {
            match msg {
                RouterMessage::Close(p) => {
                    state.remove(&p);
                }
                RouterMessage::Register(p, tx) => {
                    state.insert(p, tx);
                }
                RouterMessage::Send(p, l) => state.get_mut(&p).unwrap().try_send(l).unwrap(),
            };
            ok(state)
        })
        .then(|x| {
            println!("Router exited: {:?}", x);
            ok::<(), ()>(())
        });

    runtime.spawn(f);

    tx
}
```

And here's the new:

```rust
/// Spawn a router on the runtime.
///
/// Routers respond to router messages sent on the sender channel this function returns.
pub fn router(runtime: &mut Runtime) -> mpsc::Sender<RouterMessage> {
    let (tx, rx) = mpsc::channel::<RouterMessage>(10);

    let f = async move || {
        let mut rx = rx;
        let mut state = RouterState::new();
        let mut quitting = false;

        loop {
            if quitting && state.is_empty() {
                break;
            }

            let msg = rx.next().await;

            match msg {
                None => break,
                Some(RouterMessage::Close(p)) => {
                    state.remove(&p);
                }
                Some(RouterMessage::Register(p, tx)) => {
                    state.insert(p, tx);
                }
                Some(RouterMessage::Send(p, l)) => {
                    if let Some(chan) = state.get_mut(&p) {
                        if let Err(e) = chan.try_send(l) {
                            eprintln!("Attempted to send on closed channel"
                            + " {:?}, but encountered error: {:?}", p, e);
                            state.remove(&p);
                        }
                    } else {
                        eprintln!("Attempted to send to non-existant pid {:?}: {:?}", p, l)
                    }
                }
                Some(RouterMessage::Quit) => quitting = true,
            };
        }

        ()
    };

    runtime.spawn(f());

    tx
}
```

So, we can immediately see that the new code is longer and more complex than the
old code. However, the old version used a very compact but frankly rather
confusing technique of `fold`ing over stream, a concept that _sort of_ makes
sense in this context, only then to basically ignore the return value? Why were
we folding over this stream in the first place? The answer to that is that I
really didn't want to write more code with the `loop_fn` function, and decided
to save myself some effort by repurposing a similar but unrelated concept. I
don't think this code is particularly easy to understand, and it's quite
brittle. Also, you might have to think about how exactly `fold` will handle
errors? If I return an error, what will happen? Maybe I should sidestep the
issue and just `unwrap` everything. Also, `fold` ends its processing immediately
when the channel closes and drains. This is pretty awkward because it means that
sometimes the router will shut down before all the handles are done sending
messages, leading to, in my specific case, tests that _sometimes_ fail, and
sometimes don't, and that _never fail when backtraces are enabled._

So, the new code will still immediately stop if its router control channel is
closed, but that's no longer the recommended way of stopping the router.
Instead, you send it the quit message, which will cause it to enter a shutdown
mode, where it will wait for all existing handles to drop before stopping. I
don't think this is possible in the old implementation because the `fold` method
doesn't let you terminate early except in the case of channel closure.

Additionally, the new trades obscure futures-based control flow for bog standard
Rust control flow in an async anonymous closure, just like `exec_future`,
meaning that it's much more readable. Plus, receiving the next message is
literally just `rx.next().await`: no callbacks, no messiness.

[async-trait]: https://github.com/dtolnay/async-trait
