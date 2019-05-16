---
title: "Netns socat Trick"
date: 2019-05-16T11:57:15-07:00
---

I mostly use this blog for theories, ideas, and think-pieces. But I
figure I'll return to the _roots_ of blogging, and take the
opportunity to explain a solution to a technical problem I
encountered.


# The Problem

I have a home lab server I built out old gaming PC. I haven't done
anything with its mediocre graphics card (so no exciting machine
learning stuff). I've used it as a file server and a render box
(blender's CPU rendering only), but I've also used it as a VPN client.
After failing on my own[^1], I ended up using the excellent
[namespaced-openvpn](https://github.com/slingamn/namespaced-openvpn)
to set up a Linux net namespace whose only external connection is
through the VPN, and which fails closed should the VPN be interrupted.
This makes using applications of any sort (including console
applications and daemons) very easy, especially compared to other less
robust solutions rooted in syscall interception, or similar. It's
frequently easier to work _with_ the kernel than against it.

User interaction with the net namespaces is pretty easy:

```
ip netns exec vpn bash
```

This launches a root bash shell in the namespace. Any child processes
are also launched in the namespace as well. This namespace technology
is part of the collection of technologies that make containers
possible, and `namespaced-openvpn` implies that it would be possible
to isolate the VPN user further, configuring an entire container to
access the outside world exclusively through the VPN. This is
_interesting_, particularly if it could be extended to Tor, rather
than just a VPN, but that's a project for another time.

However, I wanted to be able to run servers inside the namespace. I
wanted the server to have a VPN only view of the world, but be
accessible normally (on LAN, etc.). This is prevented by normal usage
of network namespaces. Services that listen in the namespace simply
don't listen on open external ports. Search around I found a solution
that involved even more virtual network configuration, but I mostly
have that handled by `namespaced-openvpn`, and messing with
configuration I don't really understand is a great way to open myself
up to security holes.


# The Solution

The solution is `socat`, the Multipurpose Relay. `socat` takes 2 streams
of any sort and connects them. It has a number of useful adaptors that
let you read, listen, connect to, etc. 2 things, and then feed bytes
between them. You can use a command like

```
socat file:~/.profile STDOUT
```

To print a file to standard out (replicating the normal `cat`)
program, but you can also use it as a make-shift reverse proxy. If you
have a local service running on port `3000`, you can "re-listen" it
and proxy it over a UNIX domain socket with this command

```
socat UNIX-LISTEN:/tmp/socat.sock,fork tcp:127.0.0.1:3000
```

This instructs `socat` to listen on a UNIX socket, and upon receiving
a connection, to in turn connect to `127.0.0.1:3000` over TCP. Of
particular note is the `,fork` after the UNIX socket. This tells
`socat` to fork a process for each connection to the socket, and to
continue listening. By default, `socat` will accept one connection, do
its proxying, and then close, refusing other connections. This
behavior is undesirable for this purpose as I'm intending this server
for long term use, and it's web server anyway, and rarey does a web
application need only 1 request: additional assets are usually
required, not to mention the continued interaction.

This proxy command is run inside the namespace so it has access to the
server. However, filesystems and UNIX domain sockets _aren't_
namespaced, so we can run the following command outside the namespace:

```
socat TCP-LISTEN:3003,fork UNIX:/tmp/socat.sock
```

I chose to listen on `:3003` because I used `3000-3002` testing, and
for some reason I couldn't listen on them again. I assume they got
released pretty quickly, but I'm pretty impatient. This is just like
the last command, but the inverse. It listens on TCP, forks those
connections, and proxies them to the socket. This works _perfectly_.
It handles multiple connections (although not efficiently:
process-per-connection should absolutely be avoided in production HTTP
contexts). It's pretty stable. It's transparent. And it's easy!

`socat` is an incredibly flexible tool, and this is just one of its
many uses. It's jam packed full of features, and I highly recommend
its [man page](https://linux.die.net/man/1/socat), [this document of
examples](https://github.com/craSH/socat/blob/master/EXAMPLES), and
this [basic
introduction](https://medium.com/@copyconstruct/socat-29453e9fc8a6). 



[^1]: There are a lot of important details rooted in the internals of
    Linux virtual networking that are easy to miss and compromise your
    security.
    
