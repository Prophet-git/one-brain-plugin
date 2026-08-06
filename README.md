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

1. Sign in with Google at [onebrain.prophet.lat](https://onebrain.prophet.lat). Your brain
   exists immediately, with no form to fill in and nothing to approve.
2. Install the plugin in Claude Code:

   ```
   /plugin marketplace add Prophet-git/one-brain-plugin
   /plugin install one-brain@prophet
   ```

   Then close Claude Code and open it again, so the skills load.
3. Connect the token the signup gives you:

   ```
   /one-brain:connect <your-token>
   ```

   Close and reopen once more, then run `/one-brain:status` to confirm.

Do the restarts. While the process is alive it keeps using the old copy, and `/clear` won't
help, because that resets the conversation and not the process.

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

MIT, see [LICENSE](LICENSE). The plugin is open. The hosted brain it talks to is a service.
