---
title: "The Phantom Rejection"
date: 2018-09-14T17:10:34-07:00
---

I'm unemployed, so I'm constantly applying to jobs, and have posted my resume to
a couple of job boards, attempting to prompt semi-cold calls from recruiters.
And it's worked, to an extent. I haven't got a job, but I've gotten a couple
emails from recruiters.

I also got a rejection email. Not unusual, some companies decide to let me know
that I'm no longer being considered for a position. But I never applied to this
company. I'd never heard of this company, and I wouldn't have applied to the job
because I lack relevant experience.

So what happened? Let's speculate.

# The Bug Conspiracy

Let's say you're a medium sized corporation, and you're hiring pretty much all
the time, so you have an internal recruiting department. Not large, probably 1
team, that interfaces with hiring managers, supplying them with candidates in
the form of resumes to evaluate.

The team screens resumes for specific keywords and general red flags, like Comic
Sans and obvious serial killers. The hiring manager gets cleared resumes, and
evaluates the skills and experience of the candidate with greater specificity,
and either decides to move forward with the interview process, or reject them.

This system sounds pretty resume-centric, but it doesn't have to be: the resumes
could be actual resumes, but they could be some internal standardized format to
make evaluation, storage, and querying easier. PDFs bad, relational DBs good, so
to speak.

So the company has these people all operating on this shared database, but
things are getting a little hectic, so they decide to systematize. They
establish procedure, either with code or bureaucracy, to manage the lifecycle of
applicants: which tests and filters they've been evaluated against, which
people have signed off on them, which interviews they've done, etc. The system
could also keep track of previous applicants. Depending on
a couple of factors, the company may want to encode a substantial amount of
hiring logic in this procedure. They may want to do this to allow their hiring
to scale, so they can hire very large numbers of employees in roughly the same
way. They see these bulk employees as cogs in the machine, and it only makes
sense to these companies to systematize the acquisition of new cogs, so to
speak

That description is unnecessarily dry, however, and some companies may
see the value of systematization in its clarity to both "clients" of the
recruitment process. Clarifying to hiring managers exactly who is applying, and
how many are passing each filter, can give the managers a good view into the
workforce, and might influence them to be more lenient in the face of a
candidate drought (allowing faster hiring), or more selective in the face of a
flood (holding out for the best possible candidate). On the candidate side, some
clarity simply isn't possible: some kinds of feedback open the company to
liability, and can't be provided. However, knowing the length of the process,
how many interviews to expect, who's responsible for the decisions, and most
importantly, which part of the interview process they're in can be very helpful. The system can also
keep track of whether candidates have failed out, and send an email informing
the candidate of that, regardless of how far into the process they got[^0].

So let's say the company discovers public job boards, which would be better
called candidate boards, from the perspective of the company. These boards allow
the company to filter resumes based on a few attributes, like skills and
experience, and then access a large list of resumes. This is a potentially rich
source of talent, but the signal to noise ratio is pretty low, so manually
evaluating each resume would not be particularly profitable. "But we already have
a system in place," the company thinks, "we can load these resumes into the
system, evaluate them with whatever automation we have already in place, and
efficiently find great new talent!"

So what does the system do when someone inevitably fails one of the system's
filters? Should the system send that person an email that they aren't in
consideration for the position? No, but is the emailing component aware of the
fact that this candidate didn't apply themselves? This is a non-standard use of
the system, and it would be understandable if the original programmers didn't
think this would be a problem, and subsequent programmers weren't sufficiently
familiar with the system to notice the issue. Maybe the recruiting team started
loading the job board resumes into the system without telling any programmers,
and without the full knowledge of the system themselves. Maybe they fired the
programmers.

The end result is that the system starts emailing random people from the job
board that they've been rejected from a job they __never applied to__ at a company
__they've never heard of__.

# The Third Party

So let's say you're a third party recruiter. Let's say you're a particularly
_unscrupulous_ third party recruiter. And things aren't going great. You have
access to the same resume list as the first party recruiters, but you don't have
any jobs you're trying to hire for: no company has hired you to recruit on their
behalf. Or maybe you're a low level recruiter in a big recruiting firm, you
have a placement quota, and you're having trouble filling it this month. You're
getting desperate. Time is running out. You don't have time to go through the
rigmarole of the first couple of emails and phone interviews, trying to get a
candidate interested in a position. So you decide on a Hail Mary. You start
grabbing resumes, grabbing job listings, and just jamming them together. You
have to go fast, so you only take a cursory glance at the keywords. You apply to
a lot of different resumes to a lot of different positions, hoping one of them
will stick.

At this point things get a little hazy. The recruiter is going to want credit
for making the match, so they probably put their own email on the application.
So why did I get the email? Perhaps the company picked my email up from my
resume, or maybe this random third party recruiter mistakenly applied with my
email instead of their own.

# Conclusion

So what actually happened? No idea, I never bothered to follow up. There are a
couple of reasons why this happened (including me forgetting that I applied,
which seems unlikely given the positions requirements), and although these
explanations seem _plausible_, actually figuring out what happened would be a
lot of work, and I don't really have the training or experience to do that sort
of investigative journalism.

I'm also not particularly angry at this situation. I've gotten plenty of
rejection letters; the novelty of getting one for a job I didn't apply to made
up for the fact it was another rejection letter. In fact, this article is almost
an apologia for this company, because sending an unprompted rejection letter is
_pretty rude_. Just imagine if, while looking through job listings, I emailed
the company of every listing I didn't apply to.

>Hello, I appreciate the interest your job listing for "Full Stack Developer"
>expressed, but I don't think I'm a great fit for the position. However,

I wouldn't get any emails back, but I'd be roundly mocked by the HR department.

[^0]: I recently received a rejection email from a company I applied to and was
    rejected from __6 months__ after I interviewed and got an email that they
    weren't going to hire me. Their system must have a hard deadline of 6
    months, after which candidates are automatically failed, and the hiring
    manager or recruiting team failed to properly reject me in the system when
    they actually made the decision.
