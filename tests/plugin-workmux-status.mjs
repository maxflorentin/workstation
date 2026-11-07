#!/usr/bin/env node
// Behavior test for the workmux-status OpenCode plugin.
//
// It copies the real plugin into a sandbox, puts a fake `workmux` on PATH that
// records every call, feeds synthetic OpenCode events, and asserts the status
// sequence. No OpenCode server, tmux, or network required.
//
// Run: node tests/plugin-workmux-status.mjs

import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const pluginSource = join(root, "opencode/plugins/workmux-status/server.ts")
const sharedModules = join(process.env.HOME, ".config/opencode/node_modules")

const sandbox = mkdtempSync(join(tmpdir(), "workmux-status-test-"))
const binDir = join(sandbox, "bin")
const appDir = join(sandbox, "app")
const callsLog = join(sandbox, "calls.log")

let failures = 0
const ok = (label) => console.log(`ok   ${label}`)
const fail = (label, detail) => {
  failures += 1
  console.log(`fail ${label}${detail ? `\n     ${detail}` : ""}`)
}

function setupSandbox() {
  mkdirSync(binDir)
  mkdirSync(appDir)
  cpSync(pluginSource, join(appDir, "index.ts"))
  writeFileSync(join(appDir, "package.json"), '{"type":"module"}\n')
  symlinkSync(sharedModules, join(appDir, "node_modules"), "dir")

  const fakeWorkmux = join(binDir, "workmux")
  writeFileSync(
    fakeWorkmux,
    [
      "#!/bin/sh",
      'printf "%s\\n" "$*" >> "$WORKMUX_LOG"',
      'if [ -n "${WORKMUX_FAIL:-}" ]; then',
      '  echo "fake workmux failure" >&2',
      "  exit 1",
      "fi",
      "exit 0",
      "",
    ].join("\n"),
  )
  chmodSync(fakeWorkmux, 0o755)

  process.env.PATH = `${binDir}:${process.env.PATH}`
  process.env.WORKMUX_LOG = callsLog
}

function readCalls() {
  if (!existsSync(callsLog)) return []
  return readFileSync(callsLog, "utf8").trim().split("\n").filter(Boolean)
}

function resetCalls() {
  writeFileSync(callsLog, "")
}

function createFeed() {
  const buffer = []
  let resolveNext
  let closed = false
  return {
    push(event) {
      const deliver = (value) => ({ value, done: false })
      if (resolveNext) {
        const resolve = resolveNext
        resolveNext = undefined
        resolve(deliver(event))
      } else {
        buffer.push(event)
      }
    },
    close() {
      closed = true
      if (resolveNext) {
        const resolve = resolveNext
        resolveNext = undefined
        resolve({ value: undefined, done: true })
      }
    },
    async *iterate(signal) {
      while (true) {
        if (signal?.aborted) return
        if (buffer.length > 0) {
          yield buffer.shift()
          continue
        }
        if (closed) return
        const next = await new Promise((resolve) => {
          resolveNext = resolve
          // Match the real subscription contract: abort ends the stream.
          signal?.addEventListener("abort", () => resolve({ value: undefined, done: true }), { once: true })
        })
        if (signal?.aborted || next.done) return
        yield next.value
      }
    },
  }
}

async function waitForCalls(count, timeoutMs = 2_000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (readCalls().length >= count) return
    await new Promise((resolve) => setTimeout(resolve, 10))
  }
  throw new Error(`timed out waiting for ${count} calls; got ${JSON.stringify(readCalls())}`)
}

function assertCalls(expected, label) {
  const actual = readCalls()
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    ok(label)
  } else {
    fail(label, `expected ${JSON.stringify(expected)}\n     actual   ${JSON.stringify(actual)}`)
  }
}

async function loadPlugin(cacheBust) {
  const url = `${pathToFileURL(join(appDir, "index.ts")).href}?v=${cacheBust}`
  const module = await import(url)
  return module.default
}

async function runMainScenario() {
  resetCalls()
  delete process.env.WORKMUX_FAIL

  const plugin = await loadPlugin(Date.now())
  const feed = createFeed()
  const cleanup = await plugin.setup({
    event: { subscribe: ({ signal }) => feed.iterate(signal) },
  })

  const sessionID = "ses_a"
  const subagentID = "ses_b"
  const events = [
    { type: "session.execution.started", data: { sessionID } },
    // Duplicate start must not emit twice.
    { type: "session.execution.started", data: { sessionID } },
    { type: "permission.asked", data: { sessionID } },
    { type: "permission.replied", data: { sessionID } },
    // A subagent starts while the main session is working: no extra call.
    { type: "session.execution.started", data: { sessionID: subagentID } },
    // The subagent finishing must NOT mark the window done while ses_a works.
    { type: "session.execution.succeeded", data: { sessionID: subagentID } },
    { type: "session.execution.succeeded", data: { sessionID } },
    // A new turn starts again.
    { type: "session.execution.started", data: { sessionID } },
    { type: "session.idle", data: { sessionID } },
    { type: "form.created", data: { form: { sessionID } } },
    { type: "form.replied", data: { sessionID } },
  ]
  for (const event of events) feed.push(event)

  try {
    await waitForCalls(8)
    // Give any extra (wrong) call a chance to appear before asserting.
    await new Promise((resolve) => setTimeout(resolve, 150))
    assertCalls(
      [
        "set-window-status working",
        "set-window-status waiting",
        "set-window-status working",
        "set-window-status done",
        "set-window-status working",
        "set-window-status done",
        "set-window-status waiting",
        "set-window-status working",
      ],
      "status sequence (multi-session, waiting priority, dedupe)",
    )

    const before = readCalls().length
    await cleanup()
    feed.push({ type: "session.status", properties: { sessionID, status: { type: "busy" } } })
    await new Promise((resolve) => setTimeout(resolve, 100))
    if (readCalls().length === before) {
      ok("cleanup stops the event stream")
    } else {
      fail("cleanup stops the event stream", "plugin kept processing events after cleanup")
    }
  } finally {
    feed.close()
    await cleanup()
  }
}

async function runFailureScenario() {
  resetCalls()
  process.env.WORKMUX_FAIL = "1"

  const plugin = await loadPlugin(Date.now())
  const feed = createFeed()
  const cleanup = await plugin.setup({
    event: { subscribe: ({ signal }) => feed.iterate(signal) },
  })

  const errors = []
  const originalError = console.error
  console.error = (...args) => errors.push(args.join(" "))

  try {
    feed.push({ type: "session.execution.started", data: { sessionID: "ses_fail" } })
    feed.push({ type: "session.execution.succeeded", data: { sessionID: "ses_fail" } })

    try {
      await waitForCalls(2)
    } catch (error) {
      fail("survives workmux failure", error.message)
      return
    }

    if (readCalls().length === 2) {
      ok("survives workmux failure and keeps processing")
    } else {
      fail("survives workmux failure and keeps processing", JSON.stringify(readCalls()))
    }

    if (errors.filter((line) => line.includes("[workmux-status]")).length === 1) {
      ok("reports a repeated workmux error once")
    } else {
      fail("reports a repeated workmux error once", JSON.stringify(errors))
    }
  } finally {
    console.error = originalError
    feed.close()
    await cleanup()
    delete process.env.WORKMUX_FAIL
  }
}

console.log("workmux-status plugin")
setupSandbox()
try {
  await runMainScenario()
  await runFailureScenario()
} finally {
  rmSync(sandbox, { recursive: true, force: true })
}

console.log("")
if (failures > 0) {
  console.log(`test failed: ${failures} failure(s)`)
  process.exit(1)
}
console.log("test passed")
