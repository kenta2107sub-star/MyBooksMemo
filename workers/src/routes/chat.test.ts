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

function makeSizedRequest(body: unknown, byteLength: number, headers: Record<string, string> = {}): Request {
  const json = JSON.stringify(body);
  const paddingLength = byteLength - new TextEncoder().encode(json).byteLength;
  if (paddingLength < 0) throw new Error("テスト本文が指定サイズを超えています");
  return new Request("https://example.com/chat", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Shared-Secret": "correct-secret",
      ...headers,
    },
    body: json + " ".repeat(paddingLength),
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

  it("境界値：実本文512 KiBとContent-Length 512 KiBは受理し、1 byte超過はGeminiを呼ばず400", async () => {
    vi.mocked(generateText).mockResolvedValue("質問");
    const maxBytes = 512 * 1024;

    const atLimit = await handleChat(
      makeSizedRequest(validBody, maxBytes, { "Content-Length": String(maxBytes) }),
      env
    );
    const overActual = await handleChat(makeSizedRequest(validBody, maxBytes + 1), env);

    expect(atLimit.status).toBe(200);
    expect(overActual.status).toBe(400);
    expect(generateText).toHaveBeenCalledTimes(1);
  });

  it("境界値：Content-Lengthが512 KiBを超える場合は本文読取前に400", async () => {
    const request = makeRequest(validBody, {
      "X-Shared-Secret": "correct-secret",
      "Content-Length": String(512 * 1024 + 1),
    });
    const arrayBuffer = vi.spyOn(request, "arrayBuffer");

    const response = await handleChat(request, env);

    expect(response.status).toBe(400);
    expect(arrayBuffer).not.toHaveBeenCalled();
    expect(generateText).not.toHaveBeenCalled();
  });

  it("境界値：bookTitleは500コードポイントを受理し、501はGeminiを呼ばず400", async () => {
    vi.mocked(generateText).mockResolvedValue("質問");

    const atLimit = await handleChat(makeRequest({ ...validBody, bookTitle: "本".repeat(500) }), env);
    const overLimit = await handleChat(makeRequest({ ...validBody, bookTitle: "本".repeat(501) }), env);

    expect(atLimit.status).toBe(200);
    expect(overLimit.status).toBe(400);
    expect(generateText).toHaveBeenCalledTimes(1);
  });

  it("境界値：絵文字20,000コードポイントを受理し、20,001はGeminiを呼ばず400", async () => {
    vi.mocked(generateText).mockResolvedValue("質問");

    const atLimit = await handleChat(makeRequest({ ...validBody, memoContent: "😀".repeat(20_000) }), env);
    const overLimit = await handleChat(makeRequest({ ...validBody, memoContent: "😀".repeat(20_001) }), env);

    expect(atLimit.status).toBe(200);
    expect(overLimit.status).toBe(400);
    expect(generateText).toHaveBeenCalledTimes(1);
  });

  it("境界値：conversationHistoryは5件を受理し、6件はGeminiを呼ばず400", async () => {
    vi.mocked(generateText).mockResolvedValue("質問");
    const turn = { question: "Q", answer: "A" };

    const atLimit = await handleChat(
      makeRequest({ ...validBody, conversationHistory: Array.from({ length: 5 }, () => turn) }),
      env
    );
    const overLimit = await handleChat(
      makeRequest({ ...validBody, conversationHistory: Array.from({ length: 6 }, () => turn) }),
      env
    );

    expect(atLimit.status).toBe(200);
    expect(overLimit.status).toBe(400);
    expect(generateText).toHaveBeenCalledTimes(1);
  });

  it("境界値：全文字列合計100,000コードポイントを受理し、100,001はGeminiを呼ばず400", async () => {
    vi.mocked(generateText).mockResolvedValue("質問");
    const conversationHistory = Array.from({ length: 2 }, () => ({
      question: "Q".repeat(20_000),
      answer: "A".repeat(20_000),
    }));

    const atLimit = await handleChat(
      makeRequest({ bookTitle: "本", memoContent: "M".repeat(19_999), conversationHistory }),
      env
    );
    const overLimit = await handleChat(
      makeRequest({ bookTitle: "本", memoContent: "M".repeat(20_000), conversationHistory }),
      env
    );

    expect(atLimit.status).toBe(200);
    expect(overLimit.status).toBe(400);
    expect(generateText).toHaveBeenCalledTimes(1);
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

  it("異常系：本文ストリームの読取失敗は400 invalid_requestを返す", async () => {
    const request = makeRequest(validBody);
    vi.spyOn(request, "arrayBuffer").mockRejectedValue(new Error("body read failed"));

    const response = await handleChat(request, env);

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "invalid_request",
      message: "リクエストボディがJSONとしてパースできません",
    });
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

  it.each([
    ["欠落", {}],
    ["不一致", { "X-Shared-Secret": "wrong-secret" }],
  ])("異常系：X-Shared-Secretが%sの場合は本文を読まず401 unauthorizedを返す", async (_case, headers) => {
    const request = makeRequest({}, headers);
    const arrayBuffer = vi.spyOn(request, "arrayBuffer");

    const response = await handleChat(request, env);

    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ error: "unauthorized" });
    expect(arrayBuffer).not.toHaveBeenCalled();
    expect(generateText).not.toHaveBeenCalled();
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
