---
title: "Flows the Wrong Way: Streaming into Elixir"
date: 2018-10-10T15:41:01-07:00
draft: false
---

As part of a new and exciting project, I was faced with the task of ingesting a
large amount of more or less homogeneous JSON data into a SQL database for an
associate of mine to do some rudimentary business intelligence analysis on it.
The context complicated things: the bulk data was a bunch of historical social
media data, and in future he would also want to ingest the live API in addition
to this archived historical data. The ratio of data in to cleaned SQL data out
is pretty massive (approx. 20gb into 30mb, but I'll get into this later), so most
of the processing power was dedicated to filtering and paring down the data,
rather than inserting it into the DB, so I figured that the system could
probably absorb a lot of data from a lot of different sources at the same time,
all the time. This mean the system had to be "online", and resilient in the face
of failure, so I decided to write this program in Elixir (taking advantage of
the Flow library) to take advantage of the strong asynchronous IO, concurrent
parallelism, and system resilience.

# The Data

The data is pretty standard: compressed text files with 1 JSON object per line.
The document as a whole isn't really a valid JSON document, rather a whole bunch
of them, but that's okay, the JSON objects can be dealt with independently.
However, between repeated keys, and some repeated values, the data compressed
very readily: the compressed files were between 1 and 3 gigabytes, but over 20gb
when decompressed. I couldn't fit this data set into RAM, but that's okay, this
was always going to be a streaming system. However, the entire relevant archive
was 20 or so files, and I didn't have the disk space to hold them all uncompressed.
It's also worth nothing that streaming compressed data from disk is more
efficient than streaming uncompressed, so you can get higher effective IO by
decompressing the data in memory, and then consuming it with a stream.

# The Basic System

This is what the system looked like so far:

```elixir
File.stream!(name, [], :line)
|> Flow.from_enumerables()
|> Flow.map(&parse_json/1)
|> Flow.filter(&is_map/1)
# ... cleaning ...
|> Flow.each( fn p ->
  post = %Post{}
  changeset = Post.changeset(post, p)
  case Analysis.Repo.insert(changeset) do
    {:ok, _} -> nil
    {:error, reason} -> IO.puts("Encountered error #{inspect(reason)}")
  end
end)
```

Reading in a file (or files) one line at a time, parsing the JSON, filtering it,
cleaning it, and then inserting it into the database. This is pretty efficient
and stable, thanks to the speed of Elixir and backpressure of Flow. In
particular, Flow is a pull system rather than a push system. In Flow, consumers
query up-stream producers (or producer-consumers, as the interstitial steps are
termed), expressing their "demand" for additional data, which the producers
supply. This integrates with Elixir's default IO device types well: files can be
read from line by arbitrary line, feeding the system without overwhelming it.

Elixir's IO device type is pretty interesting: it's a departure from the
traditional Erlang method, and supports pretty rich interaction capable of
supporting this sort of careful IO work. There are a couple of small problems,
and I have a folder full of failed attempts.

# Attempt 0: Streaming compressed data with Erlang

Erlang has a [zlib](http://erlang.org/doc/man/zlib.html) library for dealing
with compressed data, but converting a _stream_ of compressed to a stream of
uncompressed data looks complicated. Also, it supports zip and gzip, but not any
of the compression algorithms the data is actually compressed with, so I'd have
to re-compress the data, so I figured there had to be a better way.

# Attempt 1: Pipes

So we can't read `xz` files directly, but we can read STDIN, and we can pipe the
decompressed data directly into Elixir.

```
xz -k -c -d file.xz | mix run --no-halt
```

So how does Elixir deal with large amounts of data (more than 20gb) of data on
STDIN? Does it read it carefully in chunks in response to backpressure, or does
it just buffer it all? It just buffers it, and the OOM killer got my Elixir
process before it completed. I _think_ this is a flaw in Erlang or Elixir,
because this isn't how most command line programs deal with STDIN. They generally
stream it through much smaller buffers. This might be my fault, but I know that
most of my code doesn't "leak" memory per-record, so if there's a "no-buffer" or
"streaming" mode for STDIN that somehow isn't enabled by
`IO.stream(:stdio, :line) |> Flow.from_enumerable()`, I don't know where it is.

# Attempt 2: Ports

Elixir offers a `Port` library based on a very similar Erlang feature for
calling out to an external program and interacting with it. It has a
"controlling process", and when the Port receives data from the external process,
it sends it as a message to its controlling process in a particular message
format you can match on. However, it does this _constantly_, and you can't stop
it, so I used the Erlang `:queue` library to make an efficient buffer, and
implemented `GenStage`'s `handle_demand/2` so the whole thing could plug into
the existing Flow system. This approach is probably just as flawed as the pipes
approach, because it still doesn't deal with backpressure--the buffer keeps
growing--but at least when lines are consumed, they're removed from the buffer,
and eventually GCed, which didn't seem to be the case for the STDIN buffer. It's
not entirely clear why this didn't work, although my theory is that I didn't
implement `handle_demand/2` properly. The Flow would get 2 or 3 messages from
the `Port`, then shut everything down with no error message, so I suspect I
violated a contract, and should have implemented `handle_demand`, although I'm
not sure how.

# Attempt 2: Unix Sockets

Unix Domain Sockets are like normal IO sockets, but instead of being addressed
with IPs and ports like TCP or UDP, they use filesystem paths, and act like
normal files. You make them, read from them, and write to them. So the plan is
to make a socket, set up the external command to write decompressed data to the
socket, and then get Elixir to read it. How do you access UNIX domain sockets
with Erlang? With `:gen_udp`, of course. So how does `:gen_udp`. Did this work?
Nope, I could never get `:gen_udp` to connect to the socket. I could read
uncompressed data from it with other tools, but I couldn't get Erlang to read
the socket.

# Attempt 3: TCP Connections

So there's this really cool tool called `socat`, which lets you connect 2
sockets of arbitrary type together. The 2 sockets can be anything, including
STDIN, STDOUT, UNIX domain sockets, exec'd external commands, TCP sockets, UDP
sockets, SSH sockets(?), and many others. It can do a number of things with TCP
sockets, and one of those things set up a TCP listening socket, and write data
from the other socket to clients that connect to the right TCP port. This
process has the distinct advantage of having buffers and backpressure built in:
Erlang's `:gen_tcp` library includes a `:passive` mode, where you synchronously
receive data, but also an `{:active, :once}` mode, where the TCP socket sends a
single message when it receives data, and then switches back to `:passive` mode,
and you have to reset it to `{:active, :once}` to get the next message, so
you're never swamped. So why didn't this work? Again, I'm not sure, but I tried
to implement it as a `GenStage`, and if you're noticing a pattern--that I don't
know how to write `GenStage`s--me too.

At this point, I took a break. Okay, actually I gave up, and resigned myself to
inefficiently reading hundreds of gigabytes from disk. After giving myself a
couple of days to think, I came up with a similar, but new solution.

# Attempt 4: TCP Listener

Instead of making the connection ourselves, what if we just listened on a
socket? We accept connections, read data using `{:active, :once}`, and buffer a
small number of messages in an aggregator from all connections, only receiving
more when the buffer is drained. With aggressive use of supervisors, we can
ensure the entire thing never goes down, and continues to feed the Flow.

The system uses a `DynamicSupervisor` to handle the individual sockets:

```Elixir
defmodule Analysis.TcpStream.SocketSupervisor do
  use DynamicSupervisor

  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def start_child do
    spec = %{
      id: Analysis.TcpStream.Socket,
      start: {Analysis.TcpStream.Socket, :start_link, []},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl true
  def init([lsocket]) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [lsocket])
  end
end
```


The `extra_arguments` option to `DynamicSupervisor` lets us parameterize all the
children this supervisor spawns with some argument, which in this case is the
listening socket handle. This is because, [per this post on
erlang-questions][thread], the best way to do this sort of TCP socket listening
is to have the _socket_ call `accept` on the listening socket, and then spawn
another socket when it gets a connection. The listening socket is basically
handed off to successive sockets. This is in contrast to the traditional model
where one process accepts sockets, then spawns or hands off the socket to a
worker. However, this Supervisor doesn't actually create the listening socket,
the overall supervisor does. It's also worth nothing that, like many parts of
this system, it's globally registered under its own module name.

Let's take a look at the socket itself, which isn't globally registed, but
dynamically created and supervised by the above supervisor.

```Elixir
defmodule Analysis.TcpStream.Socket do
  use GenServer

  def start_link(lsocket) do
    GenServer.start_link(__MODULE__, lsocket)
  end

  def init(lsocket) do
    {:ok, %{lsocket: lsocket, buffer: nil}, 0}
  end

  def handle_info(:timeout, %{lsocket: lsocket} = state) do
    {:ok, socket} = :gen_tcp.accept(lsocket)

    Analysis.TcpStream.SocketSupervisor.start_child()
    Analysis.TcpStream.Aggregator.register()

    {:noreply, Map.put(state, :socket, socket)}

  end
  
```

The `Socket` is parameterized by the listen socket, and uses a timeout of 0
to immediately attempt to accept a connect on the socket. It uses a this
`GenServer`-internal timeout system because initialization code for `GenServers` is
expected to return promptly, and can error out if it doesn't.

  
```Elixir
  def handle_info({:tcp, _sock, data}, state) do
    {:noreply,
     %{state |
       buffer: if state[:buffer] do
         state[:buffer] <> data
       else
         data
       end
     }
    }
  end
```

Although the listen socket is in `:line` mode, it sometimes chunks replies,
sending incomplete lines through multiple messages, so we concatenate with the
buffer if it's already present. This may be the source of a bug, which I'll get
to later.

```Elixir
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
```

I think this is the proper way to handle the shutdown of the TCP stream, and the
application has stopped throwing errors when clients disconnect, but I'm
ultimately not sure.


```Elixir
  def handle_call(:get_buffer, _from, %{socket: socket} = state) do
    :inet.setopts(socket, [{:active, :once}])
    {:reply,
    if state[:buffer] do
      {:ok, state[:buffer]}
    else
      {:ok, :empty}
    end,
     %{state | buffer: nil}}
  end

end
```

Reset the TCP socket, and query and reset the internal buffer. This means that
the socket won't read more data than necessary, and effectively passes on the
backpressure gained from `{:active, :once}`.


Let's take a look at the aggregator.

```Elixir
defmodule Analysis.TcpStream.Aggregator do
  use GenServer
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [[]], name: __MODULE__)
  end

  def register do
    GenServer.call(__MODULE__, :register)
  end

  def get_buffer do
    GenServer.call(__MODULE__, :get_buffer, 10000)
  end

  # Callbacks

  def init(_args) do
    {:ok, []}
  end

```

Note that this is globally registered. This allows any other piece of the
application to read data from this socket. This has some caveats.


```Elixir

  def handle_call(:register, {from, _ref}, pids) do
    IO.inspect({"Registration from ", from})
    Process.monitor(from)
    {:reply, :ok, [from | pids]}
  end

  def handle_info({:DOWN, _, :process, from, _} = msg, pids) do
    IO.inspect(msg)
    {:noreply, List.delete(pids, from)}
  end
  
```

Sockets register themselves with the Aggregator, and the Aggregator monitors
them so it can remove them from the list.

```Elixir
  def handle_call(:get_buffer, _from, pids) do
    buffer = Parallel.pmap(pids, fn(pid) ->
      try do
        case GenServer.call(pid, :get_buffer, 1000) do
          {:ok, :empty} -> []
          {:ok, b} -> String.split(b, "\n")
          x ->
            IO.inspect({:unexpected_buffer, x})
            []
        end
      rescue
      _ -> []
      end
    end
    ) |> List.flatten() |> Enum.filter(&(&1 != ""))

    {:reply, buffer, pids}
  end
end
```


This queries all the registered sockets, then manipulates the responses slightly
to make subsequent processing easier. In particular, it splits on newlines
(because sometimes TCP connections don't really fully obey the request only for
full lines, or maybe they ignore the `{:active, :once}`, and the socket naively
concatenates 2 lines), flattens the buffers (so Sockets can return multiple
messages, or you could theoretically chain aggregators, no idea why you'd do
that though), and then filters out empty strings, splitting on newlines under
normal circumstances tends to produce the line and then an empty string from the
other side of the newline. This is reasonably robust, although it's worth noting
that this is called with a timeout of `10000`, and it gives the sockets `1000`
(ms, I think) to respond, so if more than 10 sockets fail to respond, the
Aggregator could itself timeout. Also note that in the case of errors (timeouts
throw exceptions, but many other things do to), the Aggregator does absolutely
nothing, and relies on the Socket to actually crash itself before removing it
from the pid list. Hypothetically, if a Socket crashed but didn't die, it would
sit around in the pid list, taking up 1s of every attempt to get a buffer, until
the program was restarted, so I guess we hope that sockets can't do that.

So given my previous failings to write a correct `GenStage`, how do I actually
use this Aggregator?

```Elixir
Stream.resource(
    fn -> nil end,
    fn _ -> { Analysis.TcpStream.Aggregator.get_buffer(), nil } end,
    fn _ -> nil
end
```

Fun fact, this is actually a spinlock, which means it works, but it's really
really bad. It works though, and ultimately lets you easily stream multiple
different data sources directly over TCP using the same interface, and it'll all
get ingested properly by the flow. You can use whatever compression algorithm
you want, you can write some other program to send other data, you can do
whatever you want, and the flow keeps going.

Because this solution is so obviously bad, and because I'm clearly missing
something about `GenStage`, I'm going to continue to think about this problem,
and ultimately create a better solution. Probably one that still listens on TCP
sockets, but one that doesn't spinlock. Ultimately, my colleague was happy with
the solution, the application worked out of the box, and the universal interface
of plain text JSON objects to a TCP socket was easy for him to understand,
interact with, and even automate (he has no idea how the Flow application works,
but he has shell experience and can assemble `ncat` commands.). Spinlocks are
bad though, and I think throughput can be increased if I write the GenStages right.

[thread]: http://erlang.org/pipermail/erlang-questions/2010-July/052583.html
