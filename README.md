# omp-ui

A native macOS app for [omp](https://omp.sh): many projects open at once, each
with its own agent, all driven from one window.

The app owns the agents. Every open project gets its own `omp --mode rpc-ui`
process that keeps running for as long as the project is open, so omp holds on
to its session, its queued messages and any background work between UI visits.
The app talks to those processes over omp's RPC protocol — newline-delimited
JSON over stdio — and streams everything they produce into the window.

```
┌──────────────┐   JSON lines over stdio   ┌─────────────────────────────┐
│  omp-ui      │◀──────────────────────────▶│  omp (per open project)     │
│  (SwiftUI)   │                            │  one `omp --mode rpc-ui`    │
└──────────────┘                            └─────────────────────────────┘
```

## Requirements

- macOS 14 or newer.
- [omp](https://omp.sh). If it is not installed, the app says so on first
  launch and installs it with omp's official installer at the press of a
  button, or shows the Homebrew and Bun commands. It finds omp where omp's
  installer, Homebrew and Bun put it; *Choose omp…* points it at one anywhere
  else, and `OMP_UI_OMP_BIN` overrides both.
- A model account for omp. If omp has none, the app asks you to sign in to
  one — in the browser, or by pasting a key — with omp's own sign-in.

## Running it

```sh
sh scripts/swift-check.sh build      # build
sh scripts/swift-check.sh test       # test
sh scripts/build-app.sh              # a .app in dist/
```

Or install the release:

```sh
brew tap akhil-gautam/tap
brew install --cask akhil-gautam/tap/omp-ui
```

The first launch shows an empty state. Use **New project** in the sidebar to
add a project directory; omp then starts on that directory and, if the project
has sessions on disk, the most recent one is resumed.

## What it does

- **Projects.** Each project runs its own omp process, concurrently. The
  sidebar shows every project's live state. The project you were last using is
  reopened on the next launch.
- **Transcripts.** Replies are rendered as markdown: headings, lists, tables,
  task lists, and fenced code with syntax highlighting and a copy button.
  Thinking is always shown — it is the reasoning, not a summary. A tool call
  is a card: the call itself on a line of its own, and the result omp saw
  underneath it.
- **Composer.** Enter sends, Shift+Enter adds a line. While a turn is running
  the composer shows only **Stop**; Enter still sends what you write, as a
  steering message omp reads at its next step — the way Enter works in omp's
  own interface — and the queue is listed above the composer.
- **The + menu.** The button at the start of the composer brings things into
  a message. Every page is searched by a few letters, best match first, and
  worked from the keyboard: ↑ and ↓ move, Return chooses, Escape goes back.
  - *Upload file* attaches images; any other file is named so omp reads it.
  - *Files* and *Directories* list the project — git's own list in a
    repository, the files changed most recently first, with Finder's icons —
    and name the one you pick as `@path`, which omp expands into the file's
    contents or the folder's listing.
  - *Skills* and *Slash commands* are omp's own, with their descriptions and
    the arguments a command takes, and start the message.
  - *Conversations* lists the project's conversations, marks the one that is
    open, switches to another or starts a new one; one omp has not titled is
    named by the first thing said in it.
  - *Git* points at the uncommitted or staged changes, a branch or a commit,
    each commit by its subject, hash and age.
  - *Rules* lists the rules files omp works under — `.omp/rules`, `AGENTS.md`,
    `CLAUDE.md`, `.cursor/rules` and the rest, in the project and your own.
  - *Terminal* runs a command in the project through omp, which keeps the
    output in the conversation for the agent to read; it shows as a card.
  - *Codemaps* asks omp to map a folder or the whole project — entry points,
    flows, key files — as a diagram. omp has no map of its own to show.
- **Session mode.** The chip beside the composer switches between
  *Interactive* — a steer lands on the running turn at once — and *Autopilot*,
  which lets the turn finish first. Either way the messages you send while
  the agent works wait in the queue, and the queue holds all of them: send a
  second and a third and none of them is lost. It drives omp's own steering,
  follow-up and interrupt modes, and the app applies it to omp when a project
  opens.
- **Failed turns say why.** When a provider refuses a turn — out of credits,
  a bad key, a model that is gone — the reason appears under the message it
  answered, and it is still there after a restart.
- **You can see it working.** From the moment a message is sent until the
  turn ends, a row at the foot of the transcript says what omp is doing —
  sending, thinking, running a tool — and for how long.
- **omp is kept running.** If a project's omp has stopped, the next message
  starts it again; opening a project that is already running leaves it alone.
- **Idle agents sleep.** A project whose agent has had nothing to do for ten
  minutes — no turn, no question waiting, nothing queued, no command or
  background work running — has its omp stopped, giving back its memory
  (about 250 MB each). The conversation stays on screen, the project reads
  *asleep*, and your next message starts omp again in the same conversation;
  looking at the project does not. *Settings → Agents* sets the wait, or
  turns it off.
- **Dialogs.** When omp needs a decision — a tool approval, the `ask` tool, an
  extension prompt — the request appears and omp waits for your answer.
- **Twenty themes.** *Settings*, at the foot of the rail, shows each theme as
  a small window in its own colours; choosing one changes the whole
  interface — a ground, a set of greys and one accent. The choice is
  remembered. The default is a white page and a grey rail, the way a
  document is.
- **The model list.** The same models omp lists in Terminal, named the way omp
  names them — `provider/id` — so `anthropic/claude-opus-5-5` on an Anthropic
  login and `openrouter/anthropic/claude-opus-5.5` billed to OpenRouter never
  look alike. Provider by provider, each under its logo, newest first by
  [models.dev](https://models.dev)'s release dates, with each model's maker's
  logo and the month it came out; models.dev's catalog is fetched at most once
  a day and kept, and without it the order falls back to the dates in the
  models' ids. The chip names the provider beside the model, and the list is
  searchable by name, provider or id. Below the models, as in omp's model hub,
  are the providers not signed in yet, each with *Sign in*: signing in is how
  their models are enabled.
- **Your shell's environment.** An app opened from the Dock does not see what
  your shell profile exports, so omp would miss API keys like
  `OPENROUTER_API_KEY` and PATH additions. The app reads your login shell's
  environment at launch and starts omp with it, so omp sees what it sees in
  Terminal.
- **Accounts.** omp's own sign-in, in the window: when omp can use no model
  the app asks you to sign in, and *Settings → Accounts* adds an account or
  signs out of one. Browser sign-ins open the provider's page and finish on
  their own; a provider that wants a key opens the page where you get one and
  takes it in a hidden field.
- **A window that runs to its edges.** The content begins at the top of the
  window with the traffic lights drawn over it, the way a browser's does.
- **Live state.** The plan omp is working through, and the project's status
  in the top bar.
- **Keyboard.** ⌘K focuses the composer, ⌘N adds a project, ⌘1…⌘9 switch
  between projects.

## The shape of the interface

- **The rail.** The projects on top, with a search over them; *Settings* at
  the foot.
- **The project list.** A dot beside each project says whether its agent is
  ready, working or stopped. Hovering a running project shows a stop button,
  which ends that agent and gives its memory back; right-click for the same.
- **The light.** A lamp hangs over the page: bright over an empty one, where
  a headline sits in its light with a few ways to begin and the name set
  enormous beneath them, and faint behind a conversation. Every surface is
  glass lit along its top edge, and labels sit in pills — in all twenty
  themes, drawn from each theme's own colours.
- **The sky.** While an agent works, stars hang over the whole window and
  twinkle, and every so often a shower of falling stars crosses it, over the
  page, the cards and the code alike. *Settings → Sky* sets when it shows —
  while working, always or never — how often showers come, how many stars
  fall in each, their speed, tail, thickness, brightness, direction and
  colour, and how many stars hang in the sky; *Preview* sends a shower at
  once. With Reduce Motion on there is no sky.
- **The top bar.** The project and its agent's status in a pill at the
  centre, with back and forward beside it.
- **The conversation.** What you said is a bubble on the right. The agent's
  thinking follows a *Thinking* pill. Its tool calls are cards, each with an
  icon for its kind, the call on a line of its own and the result beneath it.
- **The composer.** A card that floats over the page with light pooling under
  it, with the model, the mode and the thinking level along its bottom edge,
  and the branch and folder below that.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/OMPCore/RPCConnection.swift` | The client for omp's RPC protocol: framing, request correlation, chunked frames. |
| `Sources/OMPCore/AgentProcess.swift` | One project, and the omp process that works on it. |
| `Sources/OMPCore/SessionState.swift` | The session's state, its queue, its dialogs. |
| `Sources/OMPCore/Markdown.swift` | The markdown reader. |
| `Sources/OMPCore/Project.swift` | The project list, kept in the app's support directory. |
| `Sources/OMPCore/OMPRuntime.swift` | Finding omp, and the sessions a project has. |
| `Sources/OMPCore/ComposerContext.swift` | What the + menu brings into a message: images, `@path` mentions, the project's files, rules, git references, codemaps. |
| `Sources/OMPApp/` | The interface: the shell, the sidebar, the transcript, the composer. |
| `Sources/OMPApp/Theme.swift` | The colours and type the interface is built from. |
| `Sources/OMPApp/Glass.swift` | The light and glass: the lamp, lit surfaces, pills, the wordmark. |
| `Sources/OMPApp/ComposerMenu.swift` | The composer's + menu and its pages. |
| `scripts/build-app.sh` | Assembles the `.app` and signs it. |

## Tests

```sh
sh scripts/swift-check.sh test
```

The tests cover the pieces that are easy to get quietly wrong: the session
buckets omp writes on disk, the branch of a repository, the markdown reader and
the protocol client.
