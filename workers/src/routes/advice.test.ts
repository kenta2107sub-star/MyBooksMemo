// Phase 7 Step B（testing-runner）：FR-09 /advice のユニットテスト。
// lib/gemini.ts をvi.mockで差し替え、バリデーション・認証・エラーハンドリングを検証する。

import { describe, it, expect, vi, beforeEach } from "vitest";
import type { Env } from "../types";

vi.mock("../lib/gemini", () => {
  class GeminiRateLimitedError extends Error {}
  class GeminiRequestFailedError extends Error {}
  return {
    GeminiRateLimitedError,
    GeminiRequestFailedError,
    generateText: vi.fn(),
  };
});

import { handleAdvice } from "./advice";
import { generateText, GeminiRateLimitedError } from "../lib/gemini";

const env: Env = { GEMINI_API_KEY: "dummy-key", WORKERS_SHARED_SECRET: "correct-secret" };

function makeRequest(body: unknown, headers: Record<string, string> = { "X-Shared-Secret": "correct-secret" }): Request {
  return new Request("https://example.com/advice", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

const validBody = {
  bookTitle: "テスト駆動開発",
  memoContent: "今日の気づき",
  conversationTurns: [],
};

beforeEach(() => {
  vi.mocked(generateText).mockReset();
});

describe("POST /advice", () => {
  it("正常系：有効なリクエストで200・adviceを返す", async () => {
    vi.mocked(generateText).mockResolvedValue("次はぜひ実践してみましょう。");

    const response = await handleAdvice(makeRequest(validBody), env);

    expect(response.status).toBe(200);
    const json = await response.json();
    expect(json).toEqual({ advice: "次はぜひ実践してみましょう。" });
  });

  it("異常系：JSONパース不能なボディは400 invalid_requestを返す", async () => {
    const request = new Request("https://example.com/advice", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Shared-Secret": "correct-secret" },
      body: "{{broken",
    });

    const response = await handleAdvice(request, env);

    expect(response.status).toBe(400);
  });

  it("異常系：memoContentが欠落している場合400 invalid_requestを返す", async () => {
    const { memoContent: _omit, ...rest } = validBody;
    const response = await handleAdvice(makeRequest(rest), env);

    expect(response.status).toBe(400);
  });

  it("境界値：conversationTurnsは5件を受理し、6件はGeminiを呼ばず400", async () => {
    vi.mocked(generateText).mockResolvedValue("アドバイス");
    const turn = { question: "Q", answer: "A" };

    const atLimit = await handleAdvice(
      makeRequest({ ...validBody, conversationTurns: Array.from({ length: 5 }, () => turn) }),
      env
    );
    const overLimit = await handleAdvice(
      makeRequest({ ...validBody, conversationTurns: Array.from({ length: 6 }, () => turn) }),
      env
    );

    expect(atLimit.status).toBe(200);
    expect(overLimit.status).toBe(400);
    expect(generateText).toHaveBeenCalledTimes(1);
  });

  it.each([
    ["欠落", {}],
    ["不一致", { "X-Shared-Secret": "wrong-secret" }],
  ])("異常系：X-Shared-Secretが%sの場合は本文を読まず401 unauthorizedを返す", async (_case, headers) => {
    const request = makeRequest({}, headers);
    const arrayBuffer = vi.spyOn(request, "arrayBuffer");

    const response = await handleAdvice(request, env);

    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ error: "unauthorized" });
    expect(arrayBuffer).not.toHaveBeenCalled();
    expect(generateText).not.toHaveBeenCalled();
  });

  it("異常系：WORKERS_SHARED_SECRET未設定（空文字）の環境では常に401を返す", async () => {
    const brokenEnv: Env = { GEMINI_API_KEY: "dummy-key", WORKERS_SHARED_SECRET: "" };

    const response = await handleAdvice(makeRequest(validBody, { "X-Shared-Secret": "" }), brokenEnv);

    expect(response.status).toBe(401);
  });

  it("異常系：Geminiレート制限エラーは429 rate_limitedを返す", async () => {
    vi.mocked(generateText).mockRejectedValue(new GeminiRateLimitedError("rate limited"));

    const response = await handleAdvice(makeRequest(validBody), env);

    expect(response.status).toBe(429);
  });

  it("異常系：Gemini呼び出し失敗は500 generation_failedを返す", async () => {
    vi.mocked(generateText).mockRejectedValue(new Error("boom"));

    const response = await handleAdvice(makeRequest(validBody), env);

    expect(response.status).toBe(500);
  });
});
