# omp-ui

A desktop front end for [omp](https://omp.sh): many projects open at once, each
with its own agent, all driven from one window.

The app owns the agents. Every open project gets its own
`omp --mode rpc-ui` process that keeps running for as long as the project is
open, so omp holds on to its session, its queued messages and any background
work between UI visits. The app talks to those processes over omp's RPC
protocol and streams everything they produce into the window.

```
┌──────────────┐        omp://event        ┌─────────────────────────────┐
│  omp-ui UI   │◀───────────────────────────│  omp-ui backend (Rust)     │
│  (webview)   │                            │                             │
└──────┬───────┘                            │  one `omp --mode rpc-ui`    │
       │ invoke                             │  process per open project   │
       ▼                                    └──────────────┬──────────────┘
┌──────────────┐   JSON lines over stdio                    │
│  omp (Rust   │◀───────────────────────────────────────────▶│
│  + Bun)      │                                            │
└──────────────┘                                            │
```

## Requirements

- [omp](https://omp.sh) installed and on `PATH` (`omp --version` should work).
  Set `OMP_UI_OMP_BIN` to point at the executable if it lives somewhere else.
- Rust 1.87 or newer, and Node 20 or newer.
- Model credentials for omp (`omp models` should list at least one).

## Running it

```sh
npm install
npm run tauri dev      # development, with hot reload
npm run tauri build    # a .app / .dmg in src-tauri/target/release/bundle
```

Or install the release:

```sh
brew tap akhil-gautam/tap
brew install --cask akhil-gautam/tap/omp-ui
```

The first launch shows an empty state. Use **New** in the sidebar to add a
project directory; omp then starts on that directory and, if the project has
sessions on disk, the most recent one is resumed.

## What it does

- **Projects.** Each project runs its own omp process, concurrently. The
  sidebar shows every project's live state. The project you were last using is
  reopened on the next launch.
- **Transcripts.** Replies are rendered as markdown: headings, lists, tables,
  task lists, links, and fenced code with syntax highlighting and a copy
  button. Thinking is folded away; runs of tool calls collapse into one row
  that expands into the exact arguments and results omp saw.
- **Composer.** Enter sends, Shift+Enter adds a line. While a turn is running
  Enter queues a follow-up and ⌘Enter steers into the running turn; **Stop**
  aborts it. Typing `/` offers omp's own command catalogue, with each
  command's arguments and where it comes from.
- **Session mode.** The chip beside the composer switches between
  *Interactive* — one message at a time, and you can steer straight away — and
  *Autopilot*, which lets omp queue everything and finish what it started
  before taking its next turn. It drives omp's own steering, follow-up and
  interrupt modes.
- **Dialogs.** When omp needs a decision — a tool approval, the `ask` tool, an
  extension prompt, a login link — the request appears as a modal and omp
  waits for your answer.
- **Controls.** The model, the thinking level, the session mode and the
  context balance sit in the composer; the top bar starts a new session,
  stops the project's omp, and steps back and forth through the project's
  session history.
- **What the project can do.** The sidebar's *Customizations* list opens the
  project's overview, its tools, its skills, its extensions and its prompts —
  all read from the running omp.
- **Live state.** The plan omp is working through, context usage, message
  count, tokens per second, queued messages, and subagent activity.
- **Keyboard.** ⌘K focuses the composer, ⌘N adds a project, ⌘1…⌘9 switch
  between projects.
- **Themes.** Dark by default, with a toggle at the foot of the icon rail.

## Memory

The app shell is small: a release build is a few tens of megabytes, plus the
system webview. The real cost is omp itself — one `omp` process per open
project, roughly 200 MB each. The stop button in the top bar ends a
project's omp process and gives that memory back; opening the project again
resumes its session from disk.

## Layout

| Path | What it is |
| --- | --- |
| `src-tauri/src/manager.rs` | Owns the projects and their omp processes; the commands the UI calls. |
| `src-tauri/src/protocol.rs` | Translates omp's RPC frames into the UI's event vocabulary. |
| `src-tauri/src/sessions.rs` | Finds the session files that belong to a project. |
| `src-tauri/src/omp_bin.rs` | Finds the `omp` executable and builds a PATH that can run it. |
| `src-tauri/src/project.rs` | The facts the chrome shows about a project: its git branch, the user, omp's approval mode. |
| `src-tauri/capabilities/` | What the window is allowed to do: listen for events, open the folder picker, open a login link. |
| `src/markdown.ts` | Markdown, syntax highlighting and sanitisation for replies. |
| `src/commands.ts` | Matching for the composer's slash-command menu. |
| `src/blocks.ts` | Folding runs of tool calls into one row. |
| `src/schema.ts` | The contract between the backend and the webview, as Zod schemas. |
| `src/store.ts` | The reducer that keeps the UI in sync with omp's events. |
| `src/components/` | The webview: transcript, composer, pickers, dialogs. |
| `scripts/make-icon.py` | Draws the source app icon. |
| `scripts/sync-vendor.sh` | Refreshes the vendored `omp-rpc`. |
| `vendor/omp-rpc` | The official Rust client for omp's RPC protocol (vendored). |

## The wire between the two halves

omp's RPC protocol is the real contract with omp; the one between the Rust
backend and the webview is this app's own, and it is deliberately small:

- The backend normalises omp's frames into `UiEvent`s — status, message
  deltas, tool cards, queue state, dialogs — and pushes them on
  `omp://event`. The webview never sees an omp frame.
- The webview calls the backend with `invoke`: send a message, abort, switch
  model, answer a dialog.
- Every payload crossing that boundary is parsed with a Zod schema
  (`src/schema.ts`); a payload that does not match is dropped rather than
  allowed to corrupt the UI.

## Vendored omp-rpc

`vendor/omp-rpc` is a copy of the official Rust client from
[oh-my-pi](https://github.com/can1357/oh-my-pi) (`sdk/rust/omp-rpc`). It is
vendored because it is not published to crates.io and because pinning it keeps
builds reproducible.

Two small changes were made to it for Rust 1.87; see
[`vendor/README.md`](vendor/README.md) for how to refresh it from upstream.

## Tests

```sh
npm test                   # the webview: reducer, markdown, dialogs, commands
cargo test                 # spawns a real omp; no model credentials needed
cargo test -- --ignored    # additionally sends a prompt and checks the reply
```

The Rust tests start real omp processes and check that projects open, that
each gets its own session, that two projects can run at once, that stopping a
project ends its omp, and that the project list round-trips. The ignored test
needs a working model and network. The webview tests cover the reducer that
turns omp's events into the transcript, the markdown pipeline, the slash
command menu, and the dialogs.
