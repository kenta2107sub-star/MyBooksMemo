// Phase 7 Step B（testing-runner）：NF-02（共有シークレット認証）の単体テスト。
// モック不要（外部API呼び出しを含まない純粋ロジック）。

import { describe, it, expect } from "vitest";
import { isAuthorized } from "./auth";
import type { Env } from "../types";

function makeRequest(secret?: string): Request {
  const headers: Record<string, string> = {};
  if (secret !== undefined) headers["X-Shared-Secret"] = secret;
  return new Request("https://example.com/chat", { method: "POST", headers });
}

describe("isAuthorized", () => {
  const env: Env = { GEMINI_API_KEY: "key", WORKERS_SHARED_SECRET: "correct-secret" };

  it("正しいシークレットが一致する場合trueを返す", () => {
    expect(isAuthorized(makeRequest("correct-secret"), env)).toBe(true);
  });

  it("シークレットが不一致の場合falseを返す", () => {
    expect(isAuthorized(makeRequest("wrong-secret"), env)).toBe(false);
  });

  it("ヘッダーが無い場合falseを返す", () => {
    expect(isAuthorized(makeRequest(undefined), env)).toBe(false);
  });

  it("長さが異なるシークレットでも例外を投げずfalseを返す", () => {
    expect(isAuthorized(makeRequest("short"), env)).toBe(false);
    expect(isAuthorized(makeRequest("this-is-a-much-longer-secret-than-expected"), env)).toBe(false);
  });

  it("空文字のヘッダー値はfalseを返す", () => {
    expect(isAuthorized(makeRequest(""), env)).toBe(false);
  });

  it("WORKERS_SHARED_SECRETが未設定（空文字）の場合、常にfalseを返す（設定ミスで認証をバイパスしない）", () => {
    const brokenEnv: Env = { GEMINI_API_KEY: "key", WORKERS_SHARED_SECRET: "" };
    expect(isAuthorized(makeRequest(""), brokenEnv)).toBe(false);
    expect(isAuthorized(makeRequest("anything"), brokenEnv)).toBe(false);
  });
});
