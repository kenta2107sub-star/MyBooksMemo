// Phase 7 Step B（testing-runner）：FR-05 /summarize のユニットテスト。
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

import { handleSummarize } from "./summarize";
import { generateText, GeminiRateLimitedError } from "../lib/gemini";

const env: Env = { GEMINI_API_KEY: "dummy-key", WORKERS_SHARED_SECRET: "correct-secret" };

function makeRequest(body: unknown, headers: Record<string, string> = { "X-Shared-Secret": "correct-secret" }): Request {
  return new Request("https://example.com/summarize", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

const validBody = {
  bookTitle: "テスト駆動開発",
  memos: [{ date: "2026-08-01", content: "気づきその1" }],
  conversationLogs: [{ date: "2026-08-01", turns: [{ question: "Q1", answer: "A1" }] }],
};

beforeEach(() => {
  vi.mocked(generateText).mockReset();
});

describe("POST /summarize", () => {
  it("正常系：有効なリクエストで200・summaryを返す", async () => {
    vi.mocked(generateText).mockResolvedValue("・要約その1");

    const response = await handleSummarize(makeRequest(validBody), env);

    expect(response.status).toBe(200);
    const json = await response.json();
    expect(json).toEqual({ summary: "・要約その1" });
  });

  it("正常系：conversationLogsが空配列でも200を返す（対話ログなしのケース）", async () => {
    vi.mocked(generateText).mockResolvedValue("要約");
    const body = { ...validBody, conversationLogs: [] };

    const response = await handleSummarize(makeRequest(body), env);

    expect(response.status).toBe(200);
  });

  it("境界値：memosは1,000件を受理し、1,001件はGeminiを呼ばず400", async () => {
    vi.mocked(generateText).mockResolvedValue("要約");
    const memo = { date: "2026-08-01", content: "" };

    const atLimit = await handleSummarize(
      makeRequest({ ...validBody, memos: Array.from({ length: 1_000 }, () => memo) }),
      env
    );
    const overLimit = await handleSummarize(
      makeRequest({ ...validBody, memos: Array.from({ length: 1_001 }, () => memo) }),
      env
    );

    expect(atLimit.status).toBe(200);
    expect(overLimit.status).toBe(400);
    expect(generateText).toHaveBeenCalledTimes(1);
  });

  it("境界値：conversationLogsは1,000件を受理し、1,001件はGeminiを呼ばず400", async () => {
    vi.mocked(generateText).mockResolvedValue("要約");
    const log = { date: "2026-08-01", turns: [] };

    const atLimit = await handleSummarize(
      makeRequest({ ...validBody, conversationLogs: Array.from({ length: 1_000 }, () => log) }),
      env
    );
    const overLimit = await handleSummarize(
      makeRequest({ ...validBody, conversationLogs: Array.from({ length: 1_001 }, () => log) }),
      env
    );

    expect(atLimit.status).toBe(200);
    expect(overLimit.status).toBe(400);
    expect(generateText).toHaveBeenCalledTimes(1);
  });

  it("境界値：各conversationLogのturnsは5件を受理し、6件はGeminiを呼ばず400", async () => {
    vi.mocked(generateText).mockResolvedValue("要約");
    const turn = { question: "Q", answer: "A" };

    const atLimit = await handleSummarize(
      makeRequest({
        ...validBody,
        conversationLogs: [{ date: "2026-08-01", turns: Array.from({ length: 5 }, () => turn) }],
      }),
      env
    );
    const overLimit = await handleSummarize(
      makeRequest({
        ...validBody,
        conversationLogs: [{ date: "2026-08-01", turns: Array.from({ length: 6 }, () => turn) }],
      }),
      env
    );

    expect(atLimit.status).toBe(200);
    expect(overLimit.status).toBe(400);
    expect(generateText).toHaveBeenCalledTimes(1);
  });

  it("境界値：平年と閏年の実在日を受理し、平年2月29日はGeminiを呼ばず400", async () => {
    vi.mocked(generateText).mockResolvedValue("要約");

    const commonYear = await handleSummarize(
      makeRequest({ ...validBody, memos: [{ date: "2023-02-28", content: "平年" }] }),
      env
    );
    const leapYear = await handleSummarize(
      makeRequest({ ...validBody, memos: [{ date: "2024-02-29", content: "閏年" }] }),
      env
    );
    const invalid = await handleSummarize(
      makeRequest({ ...validBody, memos: [{ date: "2023-02-29", content: "存在しない日" }] }),
      env
    );

    expect(commonYear.status).toBe(200);
    expect(leapYear.status).toBe(200);
    expect(invalid.status).toBe(400);
    expect(generateText).toHaveBeenCalledTimes(2);
  });

  it("境界値：全文字列合計100,000コードポイントを受理し、100,001はGeminiを呼ばず400", async () => {
    vi.mocked(generateText).mockResolvedValue("要約");
    const fixedMemos = Array.from({ length: 4 }, (_, index) => ({
      date: `2026-08-0${index + 1}`,
      content: "M".repeat(20_000),
    }));

    const atLimit = await handleSummarize(
      makeRequest({
        bookTitle: "本",
        memos: [...fixedMemos, { date: "2026-08-05", content: "M".repeat(19_949) }],
        conversationLogs: [],
      }),
      env
    );
    const overLimit = await handleSummarize(
      makeRequest({
        bookTitle: "本",
        memos: [...fixedMemos, { date: "2026-08-05", content: "M".repeat(19_950) }],
        conversationLogs: [],
      }),
      env
    );

    expect(atLimit.status).toBe(200);
    expect(overLimit.status).toBe(400);
    expect(generateText).toHaveBeenCalledTimes(1);
  });

  it("異常系：JSONパース不能なボディは400 invalid_requestを返す", async () => {
    const request = new Request("https://example.com/summarize", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Shared-Secret": "correct-secret" },
      body: "not-json{{",
    });

    const response = await handleSummarize(request, env);

    expect(response.status).toBe(400);
  });

  it("異常系：memosが空配列は400 invalid_request（要約対象が1件も無い）", async () => {
    const response = await handleSummarize(makeRequest({ ...validBody, memos: [] }), env);

    expect(response.status).toBe(400);
    const json = await response.json();
    expect(json).toMatchObject({ error: "invalid_request" });
  });

  it("異常系：turnsの形式が不正（answerが数値）な場合400 invalid_requestを返す", async () => {
    const body = {
      ...validBody,
      conversationLogs: [{ date: "2026-08-01", turns: [{ question: "Q1", answer: 123 }] }],
    };

    const response = await handleSummarize(makeRequest(body), env);

    expect(response.status).toBe(400);
  });

  it.each([
    ["欠落", {}],
    ["不一致", { "X-Shared-Secret": "wrong-secret" }],
  ])("異常系：X-Shared-Secretが%sの場合は本文を読まず401 unauthorizedを返す", async (_case, headers) => {
    const request = makeRequest({}, headers);
    const arrayBuffer = vi.spyOn(request, "arrayBuffer");

    const response = await handleSummarize(request, env);

    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ error: "unauthorized" });
    expect(arrayBuffer).not.toHaveBeenCalled();
    expect(generateText).not.toHaveBeenCalled();
  });

  it("異常系：Geminiレート制限エラーは429 rate_limitedを返す", async () => {
    vi.mocked(generateText).mockRejectedValue(new GeminiRateLimitedError("rate limited"));

    const response = await handleSummarize(makeRequest(validBody), env);

    expect(response.status).toBe(429);
  });

  it("異常系：Gemini呼び出し失敗は500 generation_failedを返す", async () => {
    vi.mocked(generateText).mockRejectedValue(new Error("boom"));

    const response = await handleSummarize(makeRequest(validBody), env);

    expect(response.status).toBe(500);
    const json = await response.json();
    expect(json).toMatchObject({ error: "generation_failed" });
  });
});
