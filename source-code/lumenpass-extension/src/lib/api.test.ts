import { afterEach, describe, expect, it, vi } from "vitest";
import { saveEntry } from "./api";

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("saveEntry", () => {
  it("allows a large vault to finish persisting after the ordinary request timeout", async () => {
    vi.useFakeTimers();
    vi.stubGlobal("fetch", vi.fn((_url: string, options: RequestInit) => new Promise<Response>((resolve, reject) => {
      options.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
      setTimeout(() => resolve(new Response(JSON.stringify({ ok: true, id: "saved" }), { status: 200 })), 6000);
    })));

    const result = saveEntry({
      title: "Synthetic registration",
      username: "tester",
      password: "test-password",
      url: "http://localhost:3000",
    });
    await vi.advanceTimersByTimeAsync(6000);

    await expect(result).resolves.toMatchObject({ ok: true, id: "saved" });
  });
});
