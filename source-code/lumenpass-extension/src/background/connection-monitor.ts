/**
 * Connection / vault-status monitor used by the background service worker.
 *
 * This module is the testable core of the polling logic. It is deliberately
 * decoupled from `webextension-polyfill` so it can be unit-tested without a
 * browser environment — the SW wires it up to `ping`, broadcasting, alarms,
 * and tab/window focus listeners.
 */

export interface VaultState {
  connected: boolean;
  vaultOpen: boolean;
}

export interface MonitorOptions {
  /** Performs a single ping to the desktop. Should resolve with `vaultOpen`
   *  on success and reject on transport failure. */
  ping: () => Promise<{ vaultOpen: boolean }>;
  /** Called whenever the resolved `(connected, vaultOpen)` tuple changes. */
  onStateChange: (state: VaultState) => void | Promise<void>;
  /** Called every successful check (regardless of transition) — useful for
   *  refreshing UI/icon state on every successful ping. */
  onSettled?: (state: VaultState) => void | Promise<void>;
  /** Delay before the second attempt when the first ping rejects. */
  retryDelayMs?: number;
  /** Test seam — defaults to Date.now. */
  now?: () => number;
  /** Test seam — defaults to setTimeout-based wait. */
  wait?: (ms: number) => Promise<void>;
}

export class ConnectionMonitor {
  private readonly opts: Required<Omit<MonitorOptions, "onSettled">> & {
    onSettled?: MonitorOptions["onSettled"];
  };
  private state: VaultState = { connected: false, vaultOpen: false };
  private inFlight: Promise<void> | null = null;
  private lastCheckAt = 0;

  constructor(options: MonitorOptions) {
    this.opts = {
      retryDelayMs: 800,
      now: () => Date.now(),
      wait: (ms) => new Promise<void>((resolve) => setTimeout(resolve, ms)),
      ...options,
    };
  }

  getState(): VaultState {
    return { ...this.state };
  }

  /** Ping with one retry on transient failure. Concurrent calls share the
   *  same in-flight promise so a burst of triggers (e.g. tabs re-pinging)
   *  collapses into a single network round-trip. */
  async check(): Promise<VaultState> {
    if (this.inFlight) {
      await this.inFlight;
      return this.getState();
    }
    this.inFlight = (async () => {
      const prev = { ...this.state };
      try {
        const result = await this.pingWithRetry();
        this.state = { connected: true, vaultOpen: result.vaultOpen };
      } catch {
        this.state = { connected: false, vaultOpen: false };
      }
      this.lastCheckAt = this.opts.now();
      if (this.opts.onSettled) {
        await this.opts.onSettled(this.getState());
      }
      if (prev.connected !== this.state.connected || prev.vaultOpen !== this.state.vaultOpen) {
        await this.opts.onStateChange(this.getState());
      }
    })();
    try {
      await this.inFlight;
    } finally {
      this.inFlight = null;
    }
    return this.getState();
  }

  /** Like `check`, but skips when the previous successful (non-in-flight)
   *  check happened within `minIntervalMs`. */
  async maybeCheck(minIntervalMs: number): Promise<VaultState> {
    if (this.opts.now() - this.lastCheckAt < minIntervalMs && !this.inFlight) {
      return this.getState();
    }
    return this.check();
  }

  private async pingWithRetry(): Promise<{ vaultOpen: boolean }> {
    try {
      return await this.opts.ping();
    } catch (firstErr) {
      await this.opts.wait(this.opts.retryDelayMs);
      try {
        return await this.opts.ping();
      } catch (secondErr) {
        // Surface the most recent error — the caller treats both as offline.
        throw secondErr ?? firstErr;
      }
    }
  }
}
