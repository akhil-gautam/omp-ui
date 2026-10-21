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
- [omp](https://omp.sh) installed and on `PATH` (`omp --version` should work).
  Set `OMP_UI_OMP_BIN` to point at the executable if it lives somewhere else.
- Model credentials for omp (`omp models` should list at least one).

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
  Enter queues a follow-up and ⌘Enter steers into the running turn; the send
  button stays there, so a second and a third message can be queued as well,
  and the queue is listed above the composer. **Stop** aborts the turn.
- **Session mode.** The chip beside the composer switches between
  *Interactive* — a steer lands on the running turn at once — and *Autopilot*,
  which lets the turn finish first. Either way the messages you send while
  the agent works wait in the queue, and the queue holds all of them: send a
  second and a third and none of them is lost. It drives omp's own steering,
  follow-up and interrupt modes, and the app applies it to omp when a project
  opens.
- **Dialogs.** When omp needs a decision — a tool approval, the `ask` tool, an
  extension prompt — the request appears and omp waits for your answer.
- **What the project can do.** The sidebar's *Customizations* list opens the
  project's overview, its tools, its skills, its extensions and its prompts.
- **Twenty themes.** The picker in the top bar changes the whole interface:
  a ground, a set of greys and one accent. The choice is remembered. The
  default is a white page and a grey rail, the way a document is.
- **The model list.** Every model omp offers, labelled by the vendor behind
  it, and searchable by name, by vendor or by the id omp gives it.
- **A window that runs to its edges.** The content begins at the top of the
  window with the traffic lights drawn over it, the way a browser's does.
- **Live state.** The plan omp is working through, context usage, message
  count and the current model.
- **Keyboard.** ⌘K focuses the composer, ⌘N adds a project, ⌘1…⌘9 switch
  between projects.

## The shape of the interface

- **The rail.** The projects on top, with a search over them; the project's
  own pages — its overview, tools, skills, extensions and prompts — at the
  foot.
- **The tab bar.** Every open project is a tab, so the ones that are working
  are all in sight. Closing a tab stops that agent and gives its memory back.
- **The conversation.** What you said is a bubble on the right. The agent's
  thinking is a quiet note. Its tool calls are cards, each with the call on a
  line of its own and the result beneath it.
- **The composer.** A card that floats over the page, with the model, the mode
  and the thinking level along its bottom edge, and the branch and folder
  below that.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/OMPCore/RPCConnection.swift` | The client for omp's RPC protocol: framing, request correlation, chunked frames. |
| `Sources/OMPCore/AgentProcess.swift` | One project, and the omp process that works on it. |
| `Sources/OMPCore/SessionState.swift` | The session's state, its queue, its dialogs. |
| `Sources/OMPCore/Markdown.swift` | The markdown reader. |
| `Sources/OMPCore/Project.swift` | The project list, kept in the app's support directory. |
| `Sources/OMPCore/OMPRuntime.swift` | Finding omp, and the sessions a project has. |
| `Sources/OMPApp/` | The interface: the shell, the sidebar, the transcript, the composer. |
| `Sources/OMPApp/Theme.swift` | The colours and type the interface is built from. |
| `scripts/build-app.sh` | Assembles the `.app` and signs it. |

## Tests

```sh
sh scripts/swift-check.sh test
```

The tests cover the pieces that are easy to get quietly wrong: the session
buckets omp writes on disk, the branch of a repository, the markdown reader and
the protocol client.
