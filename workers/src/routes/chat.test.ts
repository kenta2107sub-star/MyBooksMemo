// Phase 7 Step B（testing-runner）：FR-04 /chat のユニットテスト。
// lib/gemini.ts（実際のGemini API呼び出し）をvi.mockで差し替え、
// バリデーション・認証・エラーハンドリングのロジックのみを検証する。

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

import { handleChat } from "./chat";
import { generateText, GeminiRateLimitedError } from "../lib/gemini";

const env: Env = { GEMINI_API_KEY: "dummy-key", WORKERS_SHARED_SECRET: "correct-secret" };

function makeRequest(body: unknown, headers: Record<string, string> = { "X-Shared-Secret": "correct-secret" }): Request {
  return new Request("https://example.com/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

const validBody = {
  bookTitle: "テスト駆動開発",
  memoContent: "テストを先に書く効用について",
  conversationHistory: [],
};

beforeEach(() => {
  vi.mocked(generateText).mockReset();
});

describe("POST /chat", () => {
  it("正常系：有効なリクエストと正しい認証で200・questionを返す", async () => {
    vi.mocked(generateText).mockResolvedValue("次に何を考えましたか？");

    const response = await handleChat(makeRequest(validBody), env);

    expect(response.status).toBe(200);
    const json = await response.json();
    expect(json).toEqual({ question: "次に何を考えましたか？" });
    expect(generateText).toHaveBeenCalledTimes(1);
  });

  it("正常系：conversationHistoryがある場合もプロンプト生成に成功し200を返す", async () => {
    vi.mocked(generateText).mockResolvedValue("続きの質問");
    const body = {
      ...validBody,
      conversationHistory: [{ question: "最初の質問", answer: "最初の回答" }],
    };

    const response = await handleChat(makeRequest(body), env);

    expect(response.status).toBe(200);
  });

  it("異常系：JSONとしてパースできないボディは400 invalid_requestを返す", async () => {
    const request = new Request("https://example.com/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Shared-Secret": "correct-secret" },
      body: "{not-json",
    });

    const response = await handleChat(request, env);

    expect(response.status).toBe(400);
    const json = await response.json();
    expect(json).toMatchObject({ error: "invalid_request" });
    expect(generateText).not.toHaveBeenCalled();
  });

  it("異常系：必須フィールド欠落（bookTitleなし）は400 invalid_requestを返す", async () => {
    const { bookTitle: _omit, ...rest } = validBody;
    const response = await handleChat(makeRequest(rest), env);

    expect(response.status).toBe(400);
    const json = await response.json();
    expect(json).toMatchObject({ error: "invalid_request" });
  });

  it("異常系：空文字のmemoContentは400 invalid_requestを返す（trim済み空文字はNG）", async () => {
    const response = await handleChat(makeRequest({ ...validBody, memoContent: "   " }), env);

    expect(response.status).toBe(400);
  });

  it("異常系：X-Shared-Secretヘッダーなしは401 unauthorizedを返す", async () => {
    const response = await handleChat(makeRequest(validBody, {}), env);

    expect(response.status).toBe(401);
    const json = await response.json();
    expect(json).toMatchObject({ error: "unauthorized" });
    expect(generateText).not.toHaveBeenCalled();
  });

  it("異常系：X-Shared-Secretが不一致の場合401 unauthorizedを返す", async () => {
    const response = await handleChat(makeRequest(validBody, { "X-Shared-Secret": "wrong-secret" }), env);

    expect(response.status).toBe(401);
  });

  it("優先順位：ボディ不正・認証も不正の場合はバリデーションが先に走り400を返す", async () => {
    const response = await handleChat(makeRequest({}, { "X-Shared-Secret": "wrong-secret" }), env);

    expect(response.status).toBe(400);
  });

  it("異常系：Geminiがレート制限エラーを投げた場合429 rate_limitedを返す", async () => {
    vi.mocked(generateText).mockRejectedValue(new GeminiRateLimitedError("rate limited"));

    const response = await handleChat(makeRequest(validBody), env);

    expect(response.status).toBe(429);
    const json = await response.json();
    expect(json).toMatchObject({ error: "rate_limited" });
  });

  it("異常系：Gemini呼び出しが一般的なエラーで失敗した場合500 generation_failedを返す", async () => {
    vi.mocked(generateText).mockRejectedValue(new Error("upstream failure"));

    const response = await handleChat(makeRequest(validBody), env);

    expect(response.status).toBe(500);
    const json = await response.json();
    expect(json).toMatchObject({ error: "generation_failed" });
  });
});
