---
title: "Flows the Wrong Way, Part 2: The Right Way"
date: 2018-10-13T12:36:21-07:00
tags: ["code", "elixir"]
projects: ["flows"]
---

In my [last post][last_post], I covered my first attempt to implement TCP streaming in
`Flow`, a data flow library for Elixir. My first attempts involved a bunch of
failed Unix sockets, and an attempt to implement a `GenStage` that failed for
reasons I didn't understand. I eventually settled on this:

```Elixir
Stream.resource(
    fn -> nil end,
    fn _ -> { TcpStream.Aggregator.get_buffer(), nil } end,
    fn _ -> nil
end
```

`Stream.resource/3` can be converted into a `Flow` with
`Flow.from_enumerables/2`. This is implemented with the assumption that the
stream is synchronous (I think), and it continuously polls the 2nd function for
new stream items. I'm not entirely sure if you're allowed to block the stream
process, but if you were, you could write something like:

```Elixir
Stream.resource(
    fn -> socket end,
    fn socket -> { :gen_tcp.recv(socket), socket } end,
    fn socket -> nil
end
```

But let's get back to my failure. `TcpStream.Aggregator.get_buffer()`
is a `GenServer` call that polls each `Socket`'s internal buffer, and aggregates
the results, and the stream continuously polls when it wants data, so the entire
system is constantly polling and emptying the socket's internal buffers.

# The Bug

This is actually the bug I mentioned in the last article. Let's discuss
`:gen_tcp`'s behavior, and how it relates to this project. The data sources this
project is dealing with is basically "one JSON object per line, but millions of
lines", which is actually really convenient. Trying to implement or use a
streaming JSON decoder properly would be a real pain for this project, and the
data is obviously too large to hold a single JSON object that large in memory,
so keeping these JSON objects independent from a parsing perspective makes
things much easier: you can just parse each line independently. However, because
each JSON object is pretty large (some are larger than 50,000 characters), the
lines can be really long. They are always newline delimited, however. To that
end, the initial implementation of this project was using files on disk, and
opening those files as streams with the `:line` option, which causes the file to
be read line by line, rather than all at once or in fixed sized binary chunks.  

`:gen_tcp` also offers a `:line` option, but also offers a `:buffer` option for
configuring the size of the socket's internal buffer, and the `{:active,
:once}` feature for controlling backpressure and ensuring GenServer
responsiveness. These 3 options interact in an interesting way. The socket wants
to report lines, and it only wants to report one line at a time, and because
`:active`, it reports them by sending messages to its controlling process.
However, it has an internal buffer, so what it does is chunk the messages. It
reads to the end of the line, or then end of its buffer, and sends the buffer to
the controlling process, then it repeats until it reaches the end of the line,
where it stops, waiting for the `{:active, :once}` to be reset so it can
continue reading.

This means that, even if you have `{:active, :once}` set, you can receive
multiple messages from your socket while in `:line` mode. You won't be
overwhelmed with data (except in pathological cases), but you might receive a
couple more messages than you expect. Reconstructing the message is easy, you
just concatenate the buffers you receive. When someone empties your buffer, you
can reset `{:active, :once}`, and fill your buffer again. Based on your
knowledge of the rest of the system, can you see the bug yet?

Here's the bug: `Stream.resource/3` continuously polls the Aggregator, and the
Aggregator in turn polls the sockets directly. It does this constantly, because
it's a spinlock. So what happens if a Socket gets polled in the middle of a
line? That is, what happens with `:gen_tcp` has sent one part of a line to a
`Socket`, but not the other, and the `Socket` gets polled? It returns a partial
buffer, and the rest of the buffer ends up divorced, and _neither of them are
valid JSON objects_, so the entire line would be lost.

We initially thought this bug was a buffer size issue: that `:gen_tcp` simply
truncated lines that were too long. This is tantalizingly close to how it works
(because shorter lines are never split like this), but we should have known
better. However, when looking at the data that was getting truncated and
dropped, we didn't see data that wasn't going to be dropped elsewhere, as we
were primarily concerned with shorter posts. Fun fact (actually this time), most
of the posts that got dropped due to length were either very long link heavy
posts (heavily researched articles, long lists of deals with links to store
pages) because the links got encoded with escape sequences to fit into JSON
strings without breaking. Other posts that got dropped were a genre we code named
"Unicode fuckery", which were either posts with huge numbers of emoji, or
[Zalgo-esque][zalgo] spaghetti nightmare posts that caused mobile browsers and
clients to crash under the strain, except instead of a steady degradation into
unreadability, they were just solid walls of character noise. Both of these
presented problems due to the way they were encoded in JSON: as `"\uXXXX"`
characters. They also tended to be compound Unicode characters, so each
"character" would be multiple escape sequences so although the site had a limit
on the size of its content, the JSON representation could be up to 8 times
larger thanks to this sort of encoding. 

The fix in this context is easy: maintain a shadow buffer of the partial line,
and only fill the real buffer when you know you have a real line. Really though,
polling your buffers is a bad idea, so I set out to fix the whole issue

# The Right Way

`GenStage` is pretty cool, and from an user side, it's pretty slick and simple,
because the details of demand and backpressure are _mostly_ hidden from you,
unless you get into manual implementation of `ProducerConsumers`. Luckily, we're
only concerned with `Producers`, as all our `ProducerConsumers` are pretty
generic, and implemented by `Flow` already. However, the use case of "Listen on
a TCP port and feed all the lines into a `Flow`" stage didn't seem to be
covered, so I wrote the `Stream` hack. That's an obvious hack though, so I
wanted to write a real `GenStage`, but having already failed 2 times, I had
obviously missed something.

Here's what I missed. The fundamental feature of `GenStage`s is an additional
field in the return value. While `GenServers` return values in the form of 
`{:reply, message, new_state}`, or `{:noreply, new_state}`, `GenStage` adds
another return value, `{:noreply, [events], new_state}`, allowing `GenStages` to
emit new events at any time.

However, this feature isn't strongly represented in the documentation or example
`GenStages`. In general, examples emit events immediately. Sample
`handle_demand/2` implementations simply returns all the requested items, and
`handle_events/3` map over the incoming events, returning them directly.

It doesn't have to be that way, however. Allow me to quote from the
documentation on `handle_demand/2`

>This callback is invoked on `:producer` stages with the demand from
>consumers/dispatcher. The producer that implements this callback must either
>store the demand, or return the amount of requested events. 

This is a slightly odd phrase:

> store the demand

However, you can interpret this to mean that, as a producer, you need to keep
track of the number of events requested from you, and if you don't directly
return those events, you have to keep emitting them somehow. As it turns out,
this is exactly how it works, and it works great[^0].

# The Implementation

Although not strictly speaking necessary, I decided to remove essentially all
polling from the system, rather than simply the worst offenders. This made the
fix for the bug mentioned above easy, and improved the system's efficiency. The
overall structure is the same (sockets accept connections and are supervised
dynamically, aggregator unifies the data for the public interface), but the
control has been inverted somewhat.

Previously, the aggregator only maintained a list of sockets, and polled them on
command. Now, the aggregator is a full `GenStage`, so in addition to keeping
track of sockets, it also keeps track of demand and buffers events.

Sockets accept on the listening socket, and when accepted, they register with
the aggregator and start the next Socket for more accepts. The socket relies on
outside actors to set its `{:active, :once}` trigger properly, which can be done
in 2 ways. The first is a standard `GenServer` call. The Socket also keeps track
of and shadow buffers lines until it has a full lines, whereupon it pushes the
lines to the aggregator (although without newlines). When the aggregator
receives a message push, it informs the socket of whether there is additional
demand, and whether the Socket should continue receiving.

Meanwhile, the aggregator buffers the lines, and emits events, keeping track of
remaining demand. 

Here's the `Socket`:

```Elixir
defmodule TcpStage.Socket do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # Pass in both the listening socket and the aggregator
  def init([ lsocket, agg ]) do
    {:ok, %{lsocket: lsocket, agg: agg, buffer: nil}, 0}
  end

  def handle_info(:timeout, %{lsocket: lsocket, agg: agg} = state) do
    {:ok, socket} = :gen_tcp.accept(lsocket)

    # Start the next socket acceptor.
    {:ok, _} = TcpStage.SocketSupervisor.start_child()

    # Register with the aggregator, which will monitor us
    :ok = GenServer.call(agg, :register)

    {:noreply, Map.put(state, :socket, socket)}
  end

  # Add data to the buffer, then check to see if we need to emit lines.
  def handle_info({:tcp, _sock, data}, %{buffer: buf, agg: agg, socket: socket} = state) do
    data = if buf != nil do
      buf <> data
    else
      data
    end

    lines = String.split(data, "\n")
    {messages, buf} = extract_data(lines)

    if messages != [] do
      if GenServer.call(agg, {:messages, messages}) == :continue do
        # If the aggregator wants more lines, reset the socket
        :inet.setopts(socket, [{:active, :once}])
      end
    end


    {:noreply, %{state | buffer: buf}}
  end

  # Allow an external process (probably the aggregator) to reset our socket.
  # Note that resetting an already reset socket is just fine.
  def handle_cast(:reset_socket, %{socket: socket} = state) do
    :inet.setopts(socket, [{:active, :once}])
    {:noreply, state}
  end


  def handle_info({:tcp_closed, _sock}, state) do
    {:stop, {:shutdown, :tcp_closed}, state}
  end

  def handle_info({:tcp_error, _sock, reason}, state) do
    {:stop, reason, state}
  end


  def terminate(_reason, state) do
    if state[:socket] do
      :gen_tcp.close(state[:socket])
    end
  end

  # Takes a list of strings from a buffer being split,
  # and returns {full_lines, remaining_buffer}.
  # If the buffer ends in a newline (for example), the last
  # element will be the empty string, so we know the second to
  # last line is a full line. If it isn't then this is the truncated
  # first part of a line, and it needs to go back in the buffer.
  def extract_data(lines) when is_list(lines) do
    extract_data_internal(lines, [])
  end

  defp extract_data_internal([f | rest] = lines, out) do
    if length(rest) == 0 do
      out = Enum.reverse(out)
      if f == "" do
        {out, nil}
      else
        {out, f}
      end
    else
      extract_data_internal(rest, [f | out])
    end
  end
end
```

Erlang offers a nice double ended queue with nice performance characteristics in
the `:queue`, but its API isn't quite as friendly, so this uses normal lists.
This could be a problem if those lists get very long, but this shouldn't happen,
as the Socket will automatically push lines to the aggregator, who must accept
them, and although there are no hard limits on how long lines can be, lines long
enough to seriously impact the performance of this socket are very rare, even in
weird data sets like ours.

Let's look at the aggregator `GenStage`

```Elixir
defmodule TcpStage do
  use GenStage

  # Fixes a deadlock where a Socket doesn't get triggered,
  # but demand remains
  @timeout 10000

  def start_link(args) do
    GenStage.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init([]) do

    set_timer()

    # Maybe change buffer to :queue for speed
    {:producer, %{pids: [], buffer: [], demand: 0}}
  end

  def handle_call(:register, {pid, _ref}, %{pids: pids} = state) do
    IO.inspect({:registration, pid})
    Process.monitor(pid)

    # Mutual GenServer calls aren't allowed, so this blocks
    # another process until we return.
    spawn fn -> GenServer.cast(pid, :reset_socket)  end

    {:reply, :ok, [], %{state | pids: [pid | pids]}}
  end

  # Delegates to deliver_messages, but informs callers whether there is
  # more demand.
  def handle_call({:messages, messages}, _from, state) do
    {_, ans, state} = deliver_messages(state, messages)


    reply = if state[:demand] > 0 do
      :continue
    else
      :stop
    end

    {:reply, reply, ans, state}
  end

  def handle_info({:DOWN, _, :process, from, _} = msg, %{pids: pids} = state) do
    IO.inspect({:mon_down, msg })
    {:noreply, [], %{state | pids: List.delete(pids, from)}}
  end

  # I had an issue where the system hung with sockets no reset despite demand
  # remaining. This automatically triggers sockets if there is demand. See set_timer/0.
  def handle_info(:timeout, %{pids: pids, demand: demand} = state) do
    if demand > 0 do
      reset_all(pids)
    end
    set_timer()
    {:noreply, [], state}
  end


  # Delegates to deliver_messages
  def handle_demand(demand, %{demand: old_demand, pids: pids} = state) when demand > 0 do
    reset_all(pids)

    deliver_messages(%{state | demand: old_demand + demand}, [])
  end

  # Sends :timeout to itself arter @timeout milliseconds.
  # This is necessary to fix a deadlock bug, but also because GenStage
  # doesn't expose the timeout option that GenServer has, and which Socket uses.
  def set_timer do
    :erlang.send_after(@timeout, self(), :timeout)
  end

  # This doesn't really need to be syncronous.
  def reset_all(pids) do
    Parallel.pmap(pids, fn pid ->
      GenServer.cast(pid, :reset_socket)
    end)
  end

  # Handles the heavy lifting of splitting, buffering, and demand.
  def deliver_messages(%{demand: demand, buffer: buffer} = state, messages) do
    # This could be inefficient, but using :queue can fix that.
    buffer = buffer ++ messages

    # Demand is usually much higher, so rest is usually []
    {ans, rest} = Enum.split(buffer, demand)

    # This could also be inefficient, but requires more work than just :queue
    # to make efficient.
    new_demand = max(demand - length(ans), 0)

    # 2nd argument emits events
    {:noreply, ans, %{state | buffer: rest, demand: new_demand}}
  end
end
```

And that's it. I've omitted the supervisors, because they're nearly identical to
the last ones. I don't have empirical data saying this is faster, but at least
it's not a spinlock. From the vocabulary and structure of the Socket, you might
be thinking that it looks a lot like a `GenStage`. It emits events, and responds
to back pressure. In fact `{:active, :once}` isn't the only limiting mode
possible, you can configure `:gen_tcp` to give you _several_ buffers worth of
data, rather than just one, before needing to be reset. However, it wasn't clear
how to integrate `Flow` with _multiple dynamically spawning and dying_
`GenStages`: the API seems to support static stages only. I could be missing
something, but implementing your own dynamic stage wouldn't be too hard, but
that's for another post, I think.

So why was this so hard? This is basically a "me" problem, because the
documentation probably mentions this particular detail somewhere, and I never
noticed, but I think maybe an example that uses this technique might also be
good. In retrospect, it should have been obvious, but the example code samples
were limited, and didn't really express _when_ you could emit events. Having
written a good `GenStage`, I'm confident I can write more good stages.

Thanks for reading, and I hope I helped someone with the same revelations I
needed.


[^0]: Before I realized this, I thought that `handle_demand/2` had to
    effectively be synchronous, and I thought that was insane, because
    synchronously waiting for the next TCP line (with `gen_tcp:recv`) would
    obviously cause timeouts in `handle_demand/2`.

[last_post]: /posts/2018-10-10-flows-the-wrong-way/
[zalgo]: https://stackoverflow.com/a/1732454
