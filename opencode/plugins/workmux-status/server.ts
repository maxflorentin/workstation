import { execFile } from "node:child_process"
import { Plugin } from "@opencode/plugin"

const WORKMUX_TIMEOUT_MS = 2_000

type WindowStatus = "working" | "waiting" | "done"

export default Plugin.define({
  id: "workmux-status",

  setup(ctx) {
    // OpenCode emits events per session, and subagents are sessions too, while
    // a tmux window shows a single status. Track each session and derive the
    // window status: any session waiting for input wins, then any working,
    // otherwise done.
    const stateBySession = new Map<string, "working" | "waiting">()
    let lastWindowStatus: WindowStatus | undefined
    let lastReportedError: string | undefined
    const controller = new AbortController()

    // workmux status is cosmetic: never let a failure break the event stream,
    // but surface each distinct error once so it is not silent either.
    function reportOnce(detail: string) {
      if (lastReportedError === detail) {
        return
      }
      lastReportedError = detail
      console.error(`[workmux-status] ${detail}`)
    }

    function runWorkmux(status: WindowStatus) {
      return new Promise<void>((resolve) => {
        execFile(
          "workmux",
          ["set-window-status", status],
          { timeout: WORKMUX_TIMEOUT_MS },
          (error, _stdout, stderr) => {
            if (error) {
              reportOnce(stderr.trim() || error.message)
            } else {
              lastReportedError = undefined
            }
            resolve()
          },
        )
      })
    }

    async function publish() {
      let next: WindowStatus = "done"
      for (const state of stateBySession.values()) {
        if (state === "waiting") {
          next = "waiting"
          break
        }
        next = "working"
      }
      if (next === lastWindowStatus) {
        return
      }
      lastWindowStatus = next
      await runWorkmux(next)
    }

    function start(sessionID: string) {
      stateBySession.set(sessionID, "working")
      return publish()
    }

    function wait(sessionID: string) {
      stateBySession.set(sessionID, "waiting")
      return publish()
    }

    function finish(sessionID: string) {
      stateBySession.delete(sessionID)
      return publish()
    }

    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          switch (event.type) {
            case "session.execution.started":
            case "session.retry.scheduled":
              await start(event.data.sessionID)
              break
            case "session.execution.succeeded":
            case "session.execution.failed":
            case "session.execution.interrupted":
            case "session.idle":
              await finish(event.data.sessionID)
              break
            case "permission.asked":
              await wait(event.data.sessionID)
              break
            case "permission.replied":
              await start(event.data.sessionID)
              break
            case "form.created":
              await wait(event.data.form.sessionID)
              break
            case "form.replied":
            case "form.cancelled":
              await start(event.data.sessionID)
              break
          }
        }
      } catch (error) {
        if (!controller.signal.aborted) {
          console.error("[workmux-status] event stream failed", error)
        }
      }
    })()

    return () => controller.abort()
  },
})
