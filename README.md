# One Brain: the memory Claude Code is missing

Every session starts from zero and forgets it all on close. One Brain gives Claude Code
permanent memory, shared by the whole team. What one person records, everyone has, with the
name and the date still attached.

[Create your brain](https://onebrain.prophet.lat) · Free during the open beta ·
[Leer en español](ONBOARDING.md)

## What it looks like

Someone asks their Claude about a service they didn't build:

> **why does the payments worker stop retrying after 2 attempts?**
>
> That cap is deliberate, not a leftover. It was set after the duplicate-charge incident
> in March.
>
> *"Two retries on payments, hard stop. At five we double-charged 40 customers in one
> night. If a queue genuinely needs more, it comes through me."*
> Priya Raman · Platform · Mar 12

The answer came out of a teammate's session six months earlier. Nobody wrote a document
for it.

## Why it's different

Nobody writes documents. Memory gets recorded when you close a topic, so there is no form
to fill in and no wiki to keep alive.

Every answer has a name and a date on it, which means you stop reconstructing intent from
commit messages a year later.

Every service, client or person is a tag. Ask about one and you get everything the team
wrote about it, whichever teammate wrote it.

The server itself doesn't run any model. It stores and retrieves, and the judgment stays in
your Claude, on your machine.

## Getting in

You need Claude Code installed first ([how to install it](https://code.claude.com/docs/en/setup)).
The command below checks for it, and if it's missing it stops and you have to ask for a new one.

1. Go to [onebrain.prophet.lat](https://onebrain.prophet.lat) and sign in with Google, or with
   your email and a password if a teammate invited you. Your brain exists immediately, with
   no form to fill in and nothing to approve.
2. Pick **"Uso Claude Code"** (I use Claude Code). The panel shows a one-line command. Paste
   it in your terminal (on Windows, in Git Bash). It installs the plugin, saves your access
   key and writes the One Brain rules to `~/.claude/CLAUDE.md`. The command works once and
   expires after 15 minutes; if it does, ask the panel for a new one.
3. Open Claude Code in any folder and ask it "what does my company's brain know?". The panel
   shows when the first query arrives.

There are no tokens to copy and no extra restarts. Just open Claude Code after the command
has finished: a session that was already open won't see it.

To connect another computer, open **Ajustes → Mis computadoras** in the panel and run the
command it gives you on that machine.

## Daily use

Most of the time you do nothing. The team's context arrives when the session starts, and
your Claude records what you close.

When you want to be explicit:

- `brain_save`, or just tell Claude "save this in One Brain"
- `brain_search` for "what did we decide about X?" or "where is client Y at?"
- `/one-brain:handoff` to hand off state to your future self or a teammate
- `/one-brain:resume` to pick up where the last session left off
- `/one-brain:doctor` when something isn't working

## Requirements

You need Claude Code already running, either the terminal or the desktop app. One Brain
doesn't replace it. It gives it memory.

It also needs a POSIX environment. macOS and Linux already are one; on Windows, use Git
Bash or WSL. `jq` is optional, since the plugin falls back to `python3` and then `perl`.

Working in Codex instead? There's a [Codex build](https://github.com/Prophet-git/one-brain-codex)
of the same brain.

## Your data

One Brain stores what your team decides and learns, not your repository. It doesn't read
your source code. Every brain is isolated from every other one, you can see and edit every
entry, and you can export the whole thing whenever you want without asking anyone.

More on the [security](https://onebrain.prophet.lat/seguridad) and
[privacy](https://onebrain.prophet.lat/privacy) pages.

## Support

[bautista@prophet.lat](mailto:bautista@prophet.lat) · Built by [Prophet](https://prophet.lat)

## License

Source-available, not open source: see [LICENSE](LICENSE). You can read and audit every
line before installing it, and run it against the One Brain service. You can't redistribute
it or point it at a different service.
