import { afterEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../types";
import {
  generateText,
  GeminiRateLimitedError,
  GeminiRequestFailedError,
} from "./gemini";

const env: Env = {
  GEMINI_API_KEY: "dummy-key",
  WORKERS_SHARED_SECRET: "dummy-secret",
};

function successfulResponse(text: string): Response {
  return Response.json({
    candidates: [{ content: { parts: [{ text }] } }],
  });
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("generateText", () => {
  it("前後の空白を除去したテキストを返す", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(successfulResponse("  応答\n"));

    await expect(generateText("prompt", env)).resolves.toBe("応答");
  });

  it("20,000 Unicodeコードポイントは返す", async () => {
    const text = "a".repeat(20_000);
    vi.spyOn(globalThis, "fetch").mockResolvedValue(successfulResponse(text));

    await expect(generateText("prompt", env)).resolves.toBe(text);
  });

  it("絵文字20,000個を20,000 Unicodeコードポイントとして返す", async () => {
    const text = "😀".repeat(20_000);
    vi.spyOn(globalThis, "fetch").mockResolvedValue(successfulResponse(text));

    await expect(generateText("prompt", env)).resolves.toBe(text);
  });

  it("20,001 Unicodeコードポイントは切り詰めず失敗する", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(successfulResponse("a".repeat(20_001)));

    await expect(generateText("prompt", env)).rejects.toBeInstanceOf(GeminiRequestFailedError);
  });

  it("空白だけのテキストは失敗する", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(successfulResponse(" \n\t "));

    await expect(generateText("prompt", env)).rejects.toBeInstanceOf(GeminiRequestFailedError);
  });

  it("想定外のJSON形式は失敗する", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json({ candidates: [] }));

    await expect(generateText("prompt", env)).rejects.toBeInstanceOf(GeminiRequestFailedError);
  });

  it("JSONとして解析できない応答は失敗する", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response("not-json", { status: 200 }));

    await expect(generateText("prompt", env)).rejects.toBeInstanceOf(GeminiRequestFailedError);
  });

  it("429応答はレート制限エラーに変換する", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 429 }));

    await expect(generateText("prompt", env)).rejects.toBeInstanceOf(GeminiRateLimitedError);
  });

  it("429以外の異常応答は生成失敗に変換する", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 500 }));

    await expect(generateText("prompt", env)).rejects.toBeInstanceOf(GeminiRequestFailedError);
  });

  it("通信失敗は生成失敗に変換する", async () => {
    vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("network failure"));

    await expect(generateText("prompt", env)).rejects.toBeInstanceOf(GeminiRequestFailedError);
  });
});
