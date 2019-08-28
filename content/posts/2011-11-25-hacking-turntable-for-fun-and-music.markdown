---
title: "Hacking Turntable for Fun and Music"
date: 2011-11-25T15:12:00-00:00
tags: [code, javascript]
---

Previous Solutions
------------------
[Turntable](http://turntable.fm) is a collaborative DJ website that lets people
play music to an online audience. Turntable, by default, doesn't let you
download the music you hear. If you hover over the track name in the UI, you can
scrobble the track to Last.fm, find it in Spotify or Rdio, etc. Some people
(myself included, but we'll get to that later) wanted to download the files
being played.

So, a Greasemonkey script was created to automatically download songs as
they were played on Turntable. I've never tried this script because
Turntable killed it somehow. This proves that Turntable doesn't like
people messing around with their service in this way.

There is also the manual way. Webkit (Chrome and Safari) and Firebug
include a network activity inspector. When it's open, you can see all
the requests (and files) that the page requests. When Turntable.fm
downloads songs to play, you can see the request in the network
inspector for the music file, and it even says "audio/music" in the file
type. From there, you can get the URL for the file on Turntable (Or
MusicNet, another of Turntable's music sources), and from there you can
download the mp3. You can even download it directly from the network
inspector, but I never got that to work well.

So, if you want to download music from Turntable nowadays, you have to
go through an incredibly manual and annoying process filled with tedium.
At least you have music playing in the background.

I was not happy with this situation.

My Solution
-----------

While walking, I considered the problem. When I was downloading the
songs from Turntable.fm, I'm looking directly (with some parsing, thanks
to Webkit or Firebug) into the HTTP stream, watching as requests and
response go by. I would get my inspector to filter for requests for
"Other" requests, then I would manually watch the incoming requests,
looking for one that was tagged as "audio/media", and that came from
`static.turntable.fm`, or `fp-limelight.musicnet.com`.

I then realized that I could do this much more painfully in Wireshark. I
could watch requests go, packet by packet, and I could then try and save
the packets with audio data and concatenate them somehow, producing a
full audio file. Of course, there was a much simpler way to do this:
Node.js.

Node.js does stream redirection well, and can operate as an HTTP proxy.
It could watch all the http requests flowing in and out of the computer,
scanning each one carefully. I could install my server as the system
proxy, and I'd be able to watch all the requests stream by, and identify
which responses would hold the audio data.

Once I had the idea, implementation was simple. Just watch the request
stream for the important URLs, and redirect the responses (containing
the audio), not only back to the browser but into a file on the hard
drive.

My solution worked perfectly. Occasionally, a song would start playing
and be immediately skipped. This produced a file that, while it had all
the relevant ID3 tags and declared it's length in full, only had a few
seconds of audio. This is essentially unavoidable without completely
reworking the system to capture only download URLs, not to simply
redirect the http stream.

You can find Interceptor [here](https://github.com/atamis/jockey_interceptor).
It contains a more detailed readme, TODO, and the code itself.

Extending Interceptor
---------------------

The music delivery architecture Turntable.fm uses is pretty simple. Make
HTTP requestion, receive music file. When I started looking around, I
noticed this architecture in quite a few places. For instance,
[Soundcloud](http://soundcloud.com/). Soundcloud serves their sound
files on `ak-media.soundcloud.com`, and it was trivial to add another
URL source to Interceptor, having already added the 2 Turntable.fm
sources.

While Interceptor obtained all the files Soundcloud sent, I ran into a
small problem. The files sent by Soundcloud didn't have ID3 tags.
Turntable thoughtfully includes ID3 tags in the majority of the songs
they serve but Soundcloud did not. Files intercepted from Soundcloud are
less useful, and can be hard to identify.

However, the principal remains sound (pun not intended). After a cursory
inspection of Grooveshark and Pandora, I believe they may be
susceptible. Spotify, on the other hand, probably isn't. They use a more
advanced P2P, probably binary protocol that Node would have a harder
time intercepting and a harder time interpreting. It would lots more
work, and might not be possible.

Problems Intercepting
---------------------

My understanding of proxy etiquette is sparse, and there's a good chance
Interceptor doesn't follow the rules. In fact, I know it doesn't.
Dropbox seems unable to sync properly when Interceptor is on and
proxying, and there are occasional hiccups during normal browsing (weird
things like websites failing to load and their URLs duplicating in the
browser address bar.) A little help fixing those things from people who
understand proxies better than I do would be nice.
