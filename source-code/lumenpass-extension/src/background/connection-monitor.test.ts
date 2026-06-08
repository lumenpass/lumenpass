/**
 * Unit tests for the ConnectionMonitor.
 *
 * These tests cover the vault-status synchronization fix:
 *  - state transitions trigger `onStateChange`
 *  - transient ping failures are absorbed by a single retry
 *  - concurrent calls dedupe to a single network round-trip
 *  - `maybeCheck` honors the rate-limit window
 *
 * The monitor is platform-agnostic (no webextension globals), so the same
 * tests cover Chrome, Firefox, Edge, and Safari MV3.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ConnectionMonitor, type VaultState } from "./connection-monitor";

function makeMonitor(opts: {
  ping: () => Promise<{ vaultOpen: boolean }>;
  retryDelayMs?: number;
  nowSeed?: number;
}): {
  monitor: ConnectionMonitor;
  transitions: VaultState[];
  settled: VaultState[];
  advance: (ms: number) => void;
} {
  let now = opts.nowSeed ?? 1_000_000;
  const transitions: VaultState[] = [];
  const settled: VaultState[] = [];
  const monitor = new ConnectionMonitor({
    ping: opts.ping,
    retryDelayMs: opts.retryDelayMs ?? 0,
    onStateChange: (s) => { transitions.push({ ...s }); },
    onSettled: (s) => { settled.push({ ...s }); },
    now: () => now,
    wait: (_ms) => Promise.resolve(),
  });
  return { monitor, transitions, settled, advance: (ms) => { now += ms; } };
}

describe("ConnectionMonitor", () => {
  beforeEach(() => { vi.useRealTimers(); });
  afterEach(() => { vi.restoreAllMocks(); });

  it("starts disconnected and reports the unlocked state on a successful ping", async () => {
    const ping = vi.fn().mockResolvedValue({ vaultOpen: true });
    const { monitor, transitions, settled } = makeMonitor({ ping });

    expect(monitor.getState()).toEqual({ connected: false, vaultOpen: false });
    await monitor.check();

    expect(monitor.getState()).toEqual({ connected: true, vaultOpen: true });
    expect(transitions).toEqual([{ connected: true, vaultOpen: true }]);
    expect(settled).toEqual([{ connected: true, vaultOpen: true }]);
    expect(ping).toHaveBeenCalledTimes(1);
  });

  it("emits a transition when the desktop transitions locked → unlocked", async () => {
    const states = [
      { vaultOpen: false },
      { vaultOpen: false },
      { vaultOpen: true }, // user unlocks the desktop here
    ];
    const ping = vi.fn().mockImplementation(async () => states.shift()!);
    const { monitor, transitions } = makeMonitor({ ping });

    await monitor.check();
    await monitor.check();
    await monitor.check();

    // 1: disconnected → connected+locked, 2: locked → unlocked.
    // (Second check is no-op because state did not change.)
    expect(transitions.map((s) => s.vaultOpen)).toEqual([false, true]);
    expect(monitor.getState()).toEqual({ connected: true, vaultOpen: true });
  });

  it("absorbs a single transient ping failure via retry", async () => {
    const ping = vi.fn()
      .mockRejectedValueOnce(new Error("ECONNREFUSED"))
      .mockResolvedValueOnce({ vaultOpen: true });
    const { monitor, transitions } = makeMonitor({ ping });

    await monitor.check();

    expect(ping).toHaveBeenCalledTimes(2);
    expect(monitor.getState()).toEqual({ connected: true, vaultOpen: true });
    expect(transitions).toEqual([{ connected: true, vaultOpen: true }]);
  });

  it("flips to disconnected after two consecutive failures", async () => {
    const ping = vi.fn().mockRejectedValue(new Error("offline"));
    const { monitor, transitions } = makeMonitor({ ping });

    // Seed: pretend we were previously connected so we observe a transition.
    // The monitor's internal `state` starts as disconnected — we run a
    // success first to put it into the connected state, then a failure.
    ping.mockResolvedValueOnce({ vaultOpen: true });
    ping.mockRejectedValueOnce(new Error("offline 1"));
    ping.mockRejectedValueOnce(new Error("offline 2"));

    await monitor.check();
    expect(monitor.getState().connected).toBe(true);
    transitions.length = 0;

    await monitor.check();
    expect(monitor.getState()).toEqual({ connected: false, vaultOpen: false });
    expect(transitions).toEqual([{ connected: false, vaultOpen: false }]);
  });

  it("dedupes concurrent check() calls into a single ping round-trip", async () => {
    let resolvePing: (v: { vaultOpen: boolean }) => void;
    const ping = vi.fn().mockImplementation(() => new Promise<{ vaultOpen: boolean }>((r) => { resolvePing = r; }));
    const { monitor } = makeMonitor({ ping });

    const a = monitor.check();
    const b = monitor.check();
    const c = monitor.check();

    // Only one network call should be issued.
    expect(ping).toHaveBeenCalledTimes(1);

    resolvePing!({ vaultOpen: true });
    await Promise.all([a, b, c]);

    expect(monitor.getState()).toEqual({ connected: true, vaultOpen: true });
    expect(ping).toHaveBeenCalledTimes(1);
  });

  it("maybeCheck() respects the rate-limit window", async () => {
    const ping = vi.fn().mockResolvedValue({ vaultOpen: true });
    const { monitor, advance } = makeMonitor({ ping });

    await monitor.check();
    expect(ping).toHaveBeenCalledTimes(1);

    advance(500);
    await monitor.maybeCheck(2000);
    expect(ping).toHaveBeenCalledTimes(1); // skipped (within window)

    advance(2500);
    await monitor.maybeCheck(2000);
    expect(ping).toHaveBeenCalledTimes(2); // ran (window elapsed)
  });

  it("maybeCheck() always runs while a previous check is still in flight", async () => {
    let resolvePing: (v: { vaultOpen: boolean }) => void;
    const ping = vi.fn().mockImplementation(() => new Promise<{ vaultOpen: boolean }>((r) => { resolvePing = r; }));
    const { monitor } = makeMonitor({ ping });

    const first = monitor.check();
    // No interceding wait → maybeCheck must still await the in-flight call.
    const second = monitor.maybeCheck(60_000);

    expect(ping).toHaveBeenCalledTimes(1);
    resolvePing!({ vaultOpen: false });
    await Promise.all([first, second]);

    expect(monitor.getState()).toEqual({ connected: true, vaultOpen: false });
  });

  it("treats `{ vaultOpen: false }` as connected-but-locked, not disconnected", async () => {
    const ping = vi.fn().mockResolvedValue({ vaultOpen: false });
    const { monitor, transitions } = makeMonitor({ ping });

    await monitor.check();

    expect(monitor.getState()).toEqual({ connected: true, vaultOpen: false });
    expect(transitions).toEqual([{ connected: true, vaultOpen: false }]);
  });

  it("does not double-broadcast when the same state repeats", async () => {
    const ping = vi.fn().mockResolvedValue({ vaultOpen: true });
    const { monitor, transitions, settled } = makeMonitor({ ping });

    await monitor.check();
    await monitor.check();
    await monitor.check();

    expect(transitions).toHaveLength(1); // only the initial transition
    expect(settled).toHaveLength(3);     // settled fires every time
  });

  it("emits transition when vault goes unlocked → locked (desktop re-locked)", async () => {
    const states = [
      { vaultOpen: true },
      { vaultOpen: false },
    ];
    const ping = vi.fn().mockImplementation(async () => states.shift()!);
    const { monitor, transitions } = makeMonitor({ ping });

    await monitor.check();
    expect(monitor.getState()).toEqual({ connected: true, vaultOpen: true });

    await monitor.check();
    expect(monitor.getState()).toEqual({ connected: true, vaultOpen: false });
    expect(transitions).toEqual([
      { connected: true, vaultOpen: true },
      { connected: true, vaultOpen: false },
    ]);
  });

  it("emits transition when reconnecting after disconnect", async () => {
    const ping = vi.fn()
      .mockResolvedValueOnce({ vaultOpen: true })
      .mockRejectedValueOnce(new Error("offline"))
      .mockRejectedValueOnce(new Error("offline"))
      .mockResolvedValueOnce({ vaultOpen: true });
    const { monitor, transitions } = makeMonitor({ ping });

    await monitor.check();
    expect(monitor.getState().connected).toBe(true);

    await monitor.check();
    expect(monitor.getState().connected).toBe(false);

    await monitor.check();
    expect(monitor.getState()).toEqual({ connected: true, vaultOpen: true });

    expect(transitions).toEqual([
      { connected: true, vaultOpen: true },
      { connected: false, vaultOpen: false },
      { connected: true, vaultOpen: true },
    ]);
  });

  it("onSettled fires even when state does not change", async () => {
    const ping = vi.fn().mockResolvedValue({ vaultOpen: true });
    const { monitor, transitions, settled } = makeMonitor({ ping });

    await monitor.check();
    await monitor.check();

    expect(transitions).toHaveLength(1);
    expect(settled).toHaveLength(2);
    expect(settled[0]).toEqual(settled[1]);
  });

  it("recovers after a transient failure on the first attempt", async () => {
    const ping = vi.fn()
      .mockRejectedValueOnce(new Error("timeout"))
      .mockResolvedValueOnce({ vaultOpen: false });
    const { monitor, transitions } = makeMonitor({ ping });

    await monitor.check();
    expect(monitor.getState()).toEqual({ connected: true, vaultOpen: false });
    expect(transitions).toEqual([{ connected: true, vaultOpen: false }]);
  });

  it("emits transition for each connected→disconnected→connected cycle", async () => {
    // This models the reconnect loop: desktop crashes → monitor detects
    // offline → desktop restarts → monitor reconnects.
    const ping = vi.fn()
      .mockRejectedValueOnce(new Error("offline 1"))
      .mockRejectedValueOnce(new Error("offline 2")) // first check fails
      .mockRejectedValueOnce(new Error("offline 1")) // backoff retry 1 fails
      .mockRejectedValueOnce(new Error("offline 2"))
      .mockResolvedValueOnce({ vaultOpen: true }); // backoff retry 2 succeeds
    const { monitor, transitions } = makeMonitor({ ping, nowSeed: 0 });

    // Seed connected state first.
    ping.mockResolvedValueOnce({ vaultOpen: true });
    ping.mockRejectedValueOnce(new Error("crash"));
    ping.mockRejectedValueOnce(new Error("crash"));

    // Actually let's rewrite: first get connected, then go through cycles.
    const p = vi.fn()
      .mockResolvedValueOnce({ vaultOpen: true })   // initial: connected+unlocked
      .mockRejectedValueOnce(new Error("down"))       // check: connected→disconnected
      .mockRejectedValueOnce(new Error("down"))
      .mockResolvedValueOnce({ vaultOpen: true });   // reconnect: disconnected→connected

    const m = makeMonitor({ ping: p });
    await m.monitor.check();
    expect(m.monitor.getState()).toEqual({ connected: true, vaultOpen: true });
    expect(m.transitions).toEqual([{ connected: true, vaultOpen: true }]);

    // Desktop goes offline — the first check detects it.
    await m.monitor.check();
    expect(m.monitor.getState()).toEqual({ connected: false, vaultOpen: false });

    // Desktop comes back — a subsequent check reconnects.
    await m.monitor.check();
    expect(m.monitor.getState()).toEqual({ connected: true, vaultOpen: true });

    expect(m.transitions).toEqual([
      { connected: true, vaultOpen: true },
      { connected: false, vaultOpen: false },
      { connected: true, vaultOpen: true },
    ]);
  });
});
