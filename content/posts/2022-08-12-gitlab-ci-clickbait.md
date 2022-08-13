+++
title = "How I reduced my Gitlab CI Runtime by 80%! (Clickbait!)"
date = 2022-08-13T13:52:29+02:00
draft = true
tags = ["cloud", "linux"]
projects = []
+++

I use Gitlab to host a lot of my repos and I have one particular repo that runs
CI a lot. It's more convenient when it runs fast and it's a lot cheaper on build
minutes. It used to take nearly 4 minutes to run. Now it takes just 40 seconds.
Why did it take so long in the first place, and how did I make it so much faster?

# Previous Approach

This CI pipeline is actually related to a post I made some time ago about my
[Org Setup](/posts/2021/09/15/org-setup/). This workflow involves committing my
org files to a git repo and then running some tools on them, doing tasks and
modifying the org files with the results, and then recommitting the changes. I
used to run these tools manually, but I got tired of that, and decided to
integrate CI. So now the process is that I commit my org files, push them to the
remote repo, which triggers CI, which runs the interaction steps, and finally
commits the new changes.

This is a little awkward as I'll frequently find that CI has committed when I
wasn't expecting, my local and remote repos have diverged, and I need to merge,
but I designed the interaction tools to make merges as painless as possible, so
this is a minor annoyance.

I host this repo on Gitlab, so I used Gitlab CI for this pipeline.

So what did this pipeline actually look like? It turns out that committing to
the same Gitlab repo that CI is running is not a novel problem, and I found an
informative
[article](https://www.benjaminrancourt.ca/how-to-push-to-a-git-repository-from-a-gitlab-ci-pipeline/)
on the subject. The article includes all the useful details on how to clone
the repo, how to check if changes have been made, how to push without trigger CI
again, etc.. It also included the vital tidbit that Gitlab CI's default repo
clone is not suitable for actually committing and pushing, so it instead
re-clones the repo to a separate directory.

Benjamin's approach makes use of a Gitlab CI feature that acts like a template
for build steps. You can define many parts of a build step, like scripts for
before and after the main step, as well as image and entrypoint. Then you can
make any number of other concrete build steps that `extend` the original build
step, copying the template and customizing the build step from there. Benjamin's
`git` step cloned the repo and configured the commit user, ran the main steps
interaction script, then committed the changes, all in a `git` specific
container.

So here's a heavy paraphrase of what his setup looked like:

```yaml
.git:push:
  before_script: |-
    git clone "https://${GITLAB_USERNAME}:${GITLAB_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" "${CI_COMMIT_SHA}"
    # Set the displayed user with the commits that are about to be made
  after_script: |-
    cd "${CI_COMMIT_SHA}"
    # check if there are changes and commit them
  image:
    entrypoint: [""]
    name: alpine/git:${GIT_VERSION}

deploy:
  extends: .git:push
  script:
    # Move some generated files
    - mv built/*.jpg "${CI_COMMIT_SHA}"
```

This presented some problems to my. My interaction programs are private
obviously weren't included in a public `git` oriented container image. I also
had more than one interaction, each running in their own container. So I needed
a different approach.

One interesting foible of Gitlab CI is that build steps don't share workspaces:
each step runs separately, close a separate copy of the repo, and then does
whatever it wants to do. If you want to transfer the output of one build step to
another build step, you can use a feature called `artifacts`: select a path and
the build worker will upload it to object storage and subsequent build steps will
download it to the same path.

So here's a paraphrase of my build:

```yaml
stages:
  - commit-prep
  - interaction
  - commit-push

.git:config:
  before_script:
    # Set the displayed user with the commits that are about to be made
    - git config --global user.email "${GIT_USER_EMAIL:-$GITLAB_USER_EMAIL}"
    - git config --global user.name "${GIT_USER_NAME:-$GITLAB_USER_NAME}"

git:prep:
  extends: .git:config
  script:
    # Clone the repository via HTTPS inside a new directory
    - git clone "https://${GITLAB_USERNAME}:${GITLAB_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" "${CI_COMMIT_SHA}"
  stage: commit-prep
  image:
    entrypoint: [""]
    name: alpine/git
  artifacts:
    expire_in: 10 minutes
    paths:
      - "${CI_COMMIT_SHA}"

interaction1:
  stage: interaction
  image:
    entrypoint: [""]
    name: registry.gitlab.com/azrea/interaction1:main
  script:
    - cd "${CI_COMMIT_SHA}"
    -  # do interaction 1
    - cd ..
  artifacts:
    expire_in: 10 minutes
    paths:
      - "${CI_COMMIT_SHA}"

interaction2:
  stage: interaction
  needs: ["interaction1"]
  allow_failure: true
  image:
    entrypoint: [""]
    name: registry.gitlab.com/azrea/interaction2:main
  script:
    - cd "${CI_COMMIT_SHA}"
    -  # do interaction 2
    - cd ..
  artifacts:
    expire_in: 10 minutes
    paths:
      - "${CI_COMMIT_SHA}"

git:push:
  stage: commit-push
  extends: .git:config
  script:
    - cd "${CI_COMMIT_SHA}"
    -  # Commit changes if any
  image:
    entrypoint: [""]
    name: alpine/git
```

So we have 3 different stages in strict order, but also note that the
`interaction2` step depends on the `interaction1` step. This is because, if they
run in parallel, they both will produce artifacts for the same path based on the
artifacts of the `git:prep` stage, and then one of their artifacts "wins" (gets
downloaded second) and makes it to the `git:push` step and actually gets
committed. So `interaction2` runs second (via the `needs` directive) and runs in
serial so that it can receive artifacts from `interaction1` and so its artifacts
include changes from both interaction steps. Even better, `interaction2` is
marked as `allow_failure` (it's not the most reliable program), but even if it
does fail, `interaction1`s artifacts are still committed correctly.

# What Was Slow

So this is pretty unwieldy, but it works great! It's quite reliable, and it's
not even that slow. Well, it takes about 4 minutes, and that's kinda slow. For
context, the interaction programs run in just a handful of seconds each, and
`git` is very fast and the interactions don't produce any substantial amount of
changes, so the `git push` was also quite fast.

So the slowness is somewhere else.

Profiling this kind of stuff can be difficult. None of the commands I'm running
take any real time compared to the overall runtime, which means the culprit is
outside my scripts. I'm left just watching the pipeline run, and seeing where it
spends its time.[^1] Luckily, it's pretty obvious where it spends its time. Each
Gitlab build step imposes a certain amount of overhead. They all have download
their iamge, then clone the repo, then start executing, then do cleanup. It
seems like Gitlab intends their build steps to represent quite large chunks of
work, but this is especially awkward when you're running several small build
steps in a tool-per-container. Containers are supposed to be small and
self-contained, but Gitlab's approach wants big chunky build steps with almost
omnibus container images. It would not be unreasonable for your build steps to
start with a base image, install all the tools you need, and then do whatever it
needed to do.

I was yet again doing something my tools weren't designed to do. Let's build
some new tools, shall we?

# New Approach

In the end, we're going to have to compromise on a design goal. That's okay, the
design goal probably wasn't too important anyway, and we'll figure out a
workaround. We will no longer be running tools in Docker containers. Or at
least, not more than one.

The necessity of running interactions-as-containers requires substantial
contortion. Separate git clone and git push steps. Artifacts, and their
discontents. All these slow features.

In the brave new world, there will be one container and it will run in one step
and it will do _everything_.

And we're gonna do it in Alpine, baybee. The hard way. The fun way.

## Repackaging Interactions

The easy way out would be just combining the Dockerfiles for the existing
interaction tools. The existing interaction tools are written in Rust, so their
Dockerfiles are pretty straightforward, and you can build together something
like this:

```Dockerfile
FROM rust:1.60-alpine as builder1

RUN apk add --no-cache musl-dev openssl-dev
WORKDIR /app
ADD interaction1 ./
RUN cargo build --release

FROM rust:1.60-alpine as builder2

RUN apk add --no-cache musl-dev openssl-dev
WORKDIR /app
ADD interaction2 ./
RUN cargo build --release

FROM alpine:latest

ENV TZ=Etc/UTC
RUN apk add --no-cache openssl libgcc git pandoc
COPY --from=builder1 /app/target/release/interaction1 /
COPY --from=builder2 /app/target/release/interaction2 /
WORKDIR /work

CMD ["sh"]
```

If you use Docker's new BuildKit, it'll build these in parallel: pretty solid.
There are some logistical issues actually building this Docker container: the
interaction tools live in separate repos, so it's not exactly clear where this
Dockerfile would run or what kind of access it would need, those are solvable
issues. What isn't a solvable issue is that this is boring.

## What are we actually doing here

The impetus for actually fixing this problem wasn't really the slow pipeline
(though that was an issue), it was finding
[melange](https://github.com/chainguard-dev/melange) and
[apko](https://github.com/chainguard-dev/apko). Both are part of the
[Chainguard](https://github.com/chainguard-dev) organizing focused on securing
software and infrastructure by defending against supply chain attacks, an aspect
that is largely irrelevant to this project. Melange is tool for declaratively
building APK packages. It kind of looks like a Dockerfile: you describe the
package, your build environment, and then the steps necessary to acquire the
packages's source, build it, and then install it into a destination. and then
Melange takes care of packaging it up into an APK and will even detect some
runtime dependencies automatically.

apko is another declarative tool, this one for building reproducible container images. It
takes an approach somewhat similar to `distroless`, but with APK and Alpine
instead of Debian. It lets you define a series of Alpine registries, trusted
keys, and APK packages, and it'd produce a single layer Docker container with
those packages installed (Alpine base system optional). You can also define the
entrypoint, environment variables, and running services. It's also quite fast.

So, I used Melange to build my Rust applications into APK packages, hosted them
in a private Alpine repository[^2], hooked up the private repo and its key to
apko, and built the omnibus image containing every tool necessary to clone the
repo, run the interaction, and push the results. This images builds in Gitlab in
about a 1:40m. It runs in 40s.

I could replace the old build pipeline with building this image then using it,
and it would still be faster than the original pipeline, but the omnibus image
rarely changes, so can do even better and just run.

I'd previously bounced off the Alpine packaging system, but tools like Melange
and apko make dealing with it a lot easier, and sand off a lot of the rough
edges (while adding a few of their own.) I'm looking forward to engaging with
these tools and techniques, and I'm hoping to see many more developments in this
space going forward.

[^1]:
    I could maybe boot my own Gitlab runner and profile like that, but that
    would prove to be overkill.

[^2]: Easier than it sounds, barely even worth a blog post.
