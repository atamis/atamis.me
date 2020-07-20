+++
title = "Nomad on ARM64: Cannot Join Network"
date = 2020-07-20T16:03:35+02:00
draft = false
tags = ["cloud"]
projects = []
+++

I recently got a Raspberry Pi 4 model B, and I wanted to do the usual "deploy
container orchestrator" thing, but I didn't really want to do a full Kubernetes
cluster because that seemed like overkill for such a small computer. I'd lose a
lot of capacity to Kubernetes services even if I used a small distro like
[k3s](https://k3s.io/). For the lower overhead and easier setup, I decided to go
with [Hashicorp Nomad](https://www.nomadproject.io/) instead, targeting a single
node cluster with for now.

I wanted to run Nomad along side Consul to take advantage of the Consul Connect
service mesh architecture. Nomad provides special integrations for Consul
Connect, but it requires the use of `bridge` network mode:

```hcl
network {
  mbits = 10
  mode = "bridge"
}
```

However, I encountered a persistent error while trying to start this job:

```
2020-07-20T14:37:20+02:00  Driver Failure   Failed to start container 3d7d18bb5134cf7acde6f8f3447280a694b09e8c18d31889ccc87bc74656ed58: API error (409): cannot join network of a non running container: e4b1ba72942153111155561eda18ac536b28c8312157bc8acebdcf79f88d0a88`
```

This was after installing the [CNI
plugins](https://github.com/containernetworking/plugins/releases) to
`/opt/cni/bin`, a prerequisite for `bridge` mode. Normal `host` networking
worked just fine, but `bridge` networking failed consistently. I encountered
this error even after reinstalling both Nomad and Docker, and even on 2
different operating systems: Raspberry Pi OS 64bit beta and Manjaro ARM 64bit.
This strongly implied it was something related to the ARM processor that the Pi
used, although I was also concerned that the Linux kernels compiled for both
OSes were somehow missing some feature that was necessary.

Both containers in the group were attempting to connect to this container, and
the container wasn't either of the other containers, and wasn't mentioned at all
in the rest of the Nomad logs. This was pretty confusing.

While debugging the problem (aimlessly, at this point), I ran `docker system prune -af` to try and clean up the environment, and noticed something very
interesting:

```
atamis@zia:~$ docker system prune -af
Deleted Images:
untagged: debian:buster
untagged: debian@sha256:46d659005ca1151087efa997f1039ae45a7bf7a2cbbe2d17d3dcbda632a3ee9a
deleted: sha256:d4e598e8f93560894fc0cab98088e7d888e89f79e29dfdaeb92abbcc82df7b29
deleted: sha256:38c9830b1f76ba335fe93eef5e16bb60e2e940fbb51ba9920030bc7b1d28f4e6
untagged: gcr.io/google_containers/pause-amd64:3.0
untagged: gcr.io/google_containers/pause-amd64@sha256:163ac025575b775d1c0f9bf0bdd0f086883171eb475b5068e7defa4ca9e76516
deleted: sha256:99e59f495ffaa222bfeb67580213e8c28c1e885f1d245ab2bbe3b1b1ec3bd0b2
deleted: sha256:666604249ff52593858b7716232097daa6d721b7b4825aac8bf8a3f45dfba1ce
deleted: sha256:7897c392c5f451552cd2eb20fdeadd1d557c6be8a3cd20d0355fb45c1f151738
deleted: sha256:5f70bf18a086007016e948b04aed3b82103a36bea41755b6cddfaf10ace3c6ef
untagged: registry:2.7.1
untagged: registry@sha256:8be26f81ffea54106bae012c6f349df70f4d5e7e2ec01b143c46e2c03b9e551d
deleted: sha256:1525b096095b7c89c39f47897379a700ca4a56864a18fd60c35dbb46cbf4cb9a
deleted: sha256:7e2d17a428f19c9d33abf121c8e7d84f698601de11174d7bebfe329601cfeb63
deleted: sha256:81a86f0bb282abbd8723da7b9ce336d326d0117f9b12d50a07b58a11dccfe644
deleted: sha256:ca36d536f53602958e19907c5f41f9e40d8b1b9b8d201902fceccb5751f73fa6
deleted: sha256:bbcf1e4270b18796837fe3f3a5e9a32dff0f06f1bd6f4a151b1cbda8cd91172e
deleted: sha256:678a0785e7d29c77c56c1bb0af4b279374e731903506838956f7bc808665a6dd

Total reclaimed space: 133.5MB
```

At this point, I wasn't really sure what the `pause-amd64` container was for,
but based on the name, it would completely fail to run on an ARM platform. So, I
searched the Nomad Github repo for the container name, and found a reference to
it in the docs for the Docker-Nomad integrations. The documentation was for an
option called
[`infra_image`](https://www.nomadproject.io/docs/drivers/docker#infra_image),
which is described like so:

> This is the Docker image to use when creating the parent container necessary
> when sharing network namespaces between tasks. Defaults to
> "gcr.io/google_containers/pause-amd64:3.0".

So it looks like Nomad creates a dummy container for `bridge` networks, then
connects the other containers to it. They use a "pause" container so the dummy
container doesn't do anything, but the pause container they use is hard-coded to
an AMD64-only container. Maybe I missed the error message in the Nomad logs, but
I hadn't seen any reference starting this container, so I feel very lucky to
have accidentally stumbled into this solution.

The solution was pretty easy: find an ARM64 pause container and configure Nomad
to use it instead of the AMD64 one.

I put the following in my Nomad client configuration:

```hcl
plugin "docker" {
  config {
    infra_image = "kubeedge/pause-arm64:3.1"
  }
}
```

and my issue was fixed and my containers started up just fine.
