---
name: xcode-network-engineer
description: "Accumulated Network.framework findings for Swift, covering both the modern structured-concurrency API (NetworkConnection/NetworkListener/NetworkBrowser, iOS/macOS 26+) and the older completion-handler API (NWConnection/NWListener), plus a known EINVAL hosting-bug pattern. Use before starting work on a Network.framework transport layer, choosing between NetworkConnection and NWConnection, investigating a listener-bind failure, or debugging real-network behavior in any Swift app using Network.framework."
---

# Network.framework notes

Accumulated, hard-won knowledge about `Network.framework` for Swift apps that host or join
real network sessions (multiplayer games, peer-to-peer apps, local servers). Not a general
Network.framework tutorial — see Apple's own documentation for the API surface. This is what
tends to bite in practice, and a debugging playbook for the one known nasty issue below.

No published Claude Code skill (checked across local skills, installed marketplaces, and
Apple's own Game Porting Toolkit 4) covers Network.framework/socket-level networking as of
2026 — this fills that gap.

## Which API to use: NetworkConnection/NetworkListener vs. NWConnection/NWListener

As of iOS/macOS 26, Apple shipped a second generation of Network.framework built natively for
Swift structured concurrency: `NetworkConnection`, `NetworkListener`, and `NetworkBrowser`
(WWDC25 session "Use structured concurrency with Network framework"). The older
`NWConnection`/`NWListener`/`NWBrowser` API (completion-handler and `stateUpdateHandler`-based)
remains fully supported — it is not deprecated — and is still the only option when the
deployment target is below iOS/macOS 26.

- **New code targeting iOS/macOS 26+ only:** default to `NetworkConnection`/`NetworkListener`.
  The protocol stack is declared fluently (nesting protocol options like building a SwiftUI
  view tree) instead of assembled via `NWParameters`/`NWProtocolStack`, `send`/`receive` are
  `async` instead of completion-handler-based, and each accepted connection on a listener runs
  in its own automatically-cancelled child task — so tearing down the listener's task tears down
  every live connection for free, without manual bookkeeping.
- **Code that must support pre-26 OS versions, or existing NWConnection/NWListener code that
  isn't actively causing pain:** stay on `NWConnection`/`NWListener`. The two families coexist
  in the same process, so migration can be incremental — there is no forced rewrite.
- **Don't reach for `withCheckedThrowingContinuation` wrappers around `NWConnection`'s
  completion handlers as a substitute for adopting `NetworkConnection`** on iOS/macOS 26+ targets
  — that pattern was a reasonable bridge before the structured-concurrency API existed, but now
  it's reinventing what `NetworkConnection` already does natively, with more room for the wrapper
  itself to leak continuations or double-resume.

Sketch of the modern shape (fill in real message/framing types for the app in question):

```swift
let connection = NetworkConnection(to: .hostPort(host: "example.com", port: 1029)) {
    Coder(GameMessage.self, using: .json) {
        TLS()
    }
}
try await connection.send(GameMessage(...))
for try await (message, _) in connection.messages {
    handleMessage(message)
}
```

`Coder` gives direct `Codable` integration and built-in TLV (type-length-value) framing, so
message boundaries don't need to be hand-rolled on top of a byte stream the way they typically
were with `NWConnection`. On `NetworkListener`, `run()` starts one child task per inbound
connection and hands each to an async handler — cancelling the listener's enclosing task is
sufficient to tear down all of it, which removes a whole class of "did I close every accepted
connection" bugs that `NWListener`'s `newConnectionHandler` made easy to get wrong.

## The network standard: what "real networking" via Network.framework actually looks like

Both API generations are async wrappers over standard TCP/UDP — not a new wire protocol. A
typical real-time multiplayer/client-server app splits into two channels:

- **TCP** (`.tcp` protocol option, tuned via `NWProtocolTCP.Options` under either API) for a
  reliable control channel: handshakes, session events, chat, anything that must arrive exactly
  once and in order.
- **UDP** (`.udp`, `NWProtocolUDP.Options`) for high-frequency, loss-tolerant state: per-tick
  position updates, anything where a dropped packet is fine because the next one supersedes it.
- **IPv4 may need to be forced explicitly** (`NWParameters.requiredInterfaceType` /
  constraining endpoint/host resolution) if dual-stack resolution causes problems on a given
  network. This constraint applies under the older `NWParameters`-based configuration; the
  equivalent on `NetworkConnection` is expressed in its declarative protocol-stack initializer.
- **Optional discovery/lobby pattern**: a separate, persistent TCP connection to a third-party
  matchmaking/tracker server, independent of the peer-to-peer game channels. `NetworkBrowser`
  (iOS/macOS 26+) and Wi-Fi Aware peer discovery are options for local/peer-to-peer discovery
  specifically — verify current API shape against Apple's documentation before depending on
  specifics, since this corner of the framework is newest and most likely to have moved since
  this note was written.
- **LAN discovery via Bonjour/`dnssd`** is a separate, older, and still entirely valid path,
  distinct from `NetworkBrowser`/Wi-Fi Aware — `NWListener.Service`/`NWBrowser` with a
  `.bonjour(type:domain:)` descriptor, or the raw `dnssd`/`NetServiceBrowser` APIs, register and
  discover services on the local network without any of the newer peer-to-peer machinery. An app
  doing NAT/port-mapping work via `dnssd` already has a working local-discovery story; don't
  assume `NetworkBrowser` or Wi-Fi Aware are required just because they're the newest option —
  they solve a different problem (structured-concurrency-native peer discovery, including
  non-Bonjour transports) than "find another instance of this app on my LAN," which Bonjour has
  handled well for a long time.
- **No NAT traversal by default.** `Network.framework` does not do NAT-PMP/UPnP port mapping for
  you, under either API generation — hosting across a NAT needs either manual port forwarding or
  a separate, deliberately chosen traversal library (check its license before adding it).
- **Path/viability monitoring extends to multiplexed/QUIC streams** in the newer API generation,
  which matters if the app needs better-path handoff logic (e.g. Wi-Fi-to-cellular) for anything
  beyond a single plain TCP/UDP connection.

## Known issue: `NWListener` fails with `POSIXErrorCode 22` (EINVAL) on every port

A real, previously-encountered failure mode: `NWListener` construction/start fails with EINVAL
on every port tried, while raw BSD `socket()`/`bind()`/`listen()` on the same ports succeeds
fine on the same machine at the same time. This points at `Network.framework`'s own listener
path specifically, not the underlying kernel socket layer, not app code, and not entitlements.
This was diagnosed against `NWListener`; it has not been re-confirmed against `NetworkListener`
on iOS/macOS 26+, but since both sit on the same underlying framework, the same debugging
checklist below is the right starting point if the symptom recurs there.

**Debugging checklist, in order of what's cheap to rule out:**
1. Reproduce outside the app entirely — a bare standalone Swift binary with no entitlements and
   no sandbox. If it still fails, it's environmental, not app-specific.
2. Check whether it's OS-version-specific: does it reproduce identically on a different
   machine/OS version (stable vs. beta)? If both fail identically, it's not a beta regression.
3. Check code signing / Local Network permission: does switching from ad-hoc signing to a real
   Development identity change anything, and does a Local Network permission prompt ever
   appear? If neither changes the failure, it's not a signing/permission issue.
4. If both of the above are ruled out and the root cause still isn't found: check for
   VPN/firewall/network-extension software on the affected machine, and search Apple Developer
   Forums/Feedback Assistant for the same `EINVAL` signature on the specific OS build in use —
   this has recurred across multiple macOS beta cycles without a public root-cause writeup.
5. **Avoid open-ended re-investigation.** If a session already ruled out 2-3 theories and found
   nothing, that's a strong signal to stop and ship a fallback (below) rather than opening a new
   investigation angle — this is a real escalation-of-commitment trap worth naming explicitly
   when deciding whether to keep digging.

**Mitigation pattern (ship this regardless of whether the root cause is ever found):** on
listener bind failure, fall back to a local-only mode through the *same* code path used for
normal play (same view/session initializer), with a visible, honest on-screen notice — never
fail silently into degraded behavior.

## General Network.framework gotchas

- **On `NWConnection`/`NWListener`:** state updates arrive via `stateUpdateHandler` closures, not
  thrown errors — a successful initializer call does **not** mean the listener/connection is
  bound/ready; wait for `.ready`. `NetworkConnection`/`NetworkListener` replace this with
  `async`/`for try await` sequences over state, which surface readiness and failure through
  normal Swift control flow instead of a side-channel closure — prefer that shape for any code
  that can target iOS/macOS 26+.
- Give one type ownership of a connection's full lifecycle (accept/handshake through the live
  session) rather than splitting it across a connect-scoped helper and a separate live-session
  object — a handshake phase that tears the connection down on return, then hands off to a
  different owner, is a common source of "works once, can't be reused" bugs. Under
  `NetworkListener`, the natural way to express this is one child task per connection owning that
  connection end-to-end; resist the urge to hand a connection off to a task other than the one
  it was accepted into.
- If porting an existing app's networking code onto `Network.framework` from raw POSIX sockets,
  port the *observable wire protocol/byte sequence*, not the POSIX mechanics
  (`accept()`/`select()`/threading glue) — those aren't meaningfully portable or worth
  preserving bug-for-bug; either API generation's async model replaces them cleanly.
- **If the wire protocol must stay byte-for-byte compatible with a live third-party
  implementation** (an existing tracker/server ecosystem, other clients/peers already deployed,
  or a reference/oracle codebase the port is being validated against) — as opposed to a wire
  protocol this app fully owns and can freely change — treat every framing and encoding decision
  as a compatibility constraint, not a style choice. Concretely: don't reach for `Coder`'s
  built-in TLV framing or `Codable`-driven encoding on `NetworkConnection` unless the existing
  protocol's on-the-wire byte layout already *is* that TLV/Codable shape — bytes have to match
  exactly, not just "represent the same information." Hand-write the codec against the actual
  byte layout (as validated against the reference implementation) in either API generation, and
  only reach for `Coder`/`Codable` conveniences when starting a wire protocol from scratch with
  no compatibility target to match.
- **Swift 6 strict concurrency / `Sendable`:** any message or framing type crossing into
  `send`/`receive` (either API) or captured by a `stateUpdateHandler`/handler closure needs to be
  `Sendable` — under Swift 6's strict concurrency checking this is enforced at compile time, not
  discovered at runtime. Prefer plain `Sendable` value types (structs/enums conforming to
  `Codable` for use with `Coder`) for wire messages rather than reference types with mutable
  state; a class that must cross the boundary needs its internal state made safe (immutable
  after init, or protected by an actor) to conform honestly rather than via `@unchecked
  Sendable` as a first resort.
- Don't reintroduce a `DispatchQueue` callback queue plus manual `Task`/continuation bridging for
  `NWConnection` on a codebase that has otherwise adopted Swift 6 structured concurrency
  throughout — that combination tends to be where actor-isolation and Sendable-checking
  complaints pile up. If the queue-based bridging is already extensive and working, it's often
  not worth ripping out solely to satisfy the type-checker; but new networking code in a
  strict-concurrency target is a good candidate for `NetworkConnection` specifically because it
  avoids the bridging problem entirely.
