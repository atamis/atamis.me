+++
title = "Monorepo Compromise"
date = 2019-11-03T20:54:26+01:00
draft = false
tags = ["code"]
projects = []
+++

I have a modest proposal on repository organization. There are 2 primary
archetypes, multiple repositories and the monorepo pattern. In multiple
repositories, you have 1 project per repository, binaries requiring internal
libraries, and use tools to ensure that you have all the necessary repositories
downloaded and up to date (easy with most modern package managers). In a
monorepo, all projects are stored directly in the monorepo, as part of a single
codebase or project, and all internal dependencies are automatically managed.

Each archetype has its own challenges (multi-repository PRs, space
consideration, compartmentalization, CI), but I'd like to propose a third
solution that solves none of these issues and is really dumb

# Hydra Repositories

In git, you can create a branch in a repository with no connection to the
existing history: an orphan branch.

Per [this](https://stackoverflow.com/a/4288660) SO answer,

```
git checkout --orphan newbranch
git rm -rf .
```

And boom, you have a new branch with no connection to the old history of the
repository and no contents. From here you can build an entirely new project
isolated from any other branches.

In the hydra Repository, you maintain separate orphan branches for each of your
projects and libraries. This has all the isolation and lack of easy code sharing
of multiple repos, but in the same repo. Like a monorepo, you can clone every
single project you care about with a single `git clone` command without an easy
way of excluding some parts of the project. Google's famous monorepo includes
specialized tooling for dealing with a single repository that contains _all_
Google code, and you'll be building all that tooling on top of git!. CI is even
harder than in a monorepo, and even less tooling exists for managing this
structure.

Although most dependency management tools is prepared to deal with dependencies specified
by git repo URL and SHA (in order to handle multiple private repositories), are
they read to deal with multiple dependencies that all come from exactly the same
repository? Maybe some of them make some assumption that renders them incapable
of dealing with hydra repositories, and therefor that language or environment
incapable of running in a hydra repository.

By using git worktree, you can "mount" these orphan branches in the working
directories of other branches like so:

```
git worktree add repository/ <SHA>
```

This directory will act like another working directory for the overall git
repository, allowing you to work on multiple branches at the same time.

You can also theoretically merge these repositories easily by just merging the
branches directly, so if you make the horrible and inexplicable decision, you
can resolve the issue by just merging the orphan branches into the same branch.

Luckily, this article is not born of personal experience.
