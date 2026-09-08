// detailed_design.md 3-3：Gemini APIとの通信を1箇所に集約するモジュール。
// モデル名を変更する場合もこのファイルのみ変更すればよい（architecture.md 5章）。
//
// APIキーの渡し方：Google公式ドキュメント（2026年時点）は`x-goog-api-key`ヘッダーを
// 現在の標準的な方式として案内している（`?key=`クエリパラメータは後方互換のため残るのみ）。
// クエリパラメータに秘密情報を含めるとログに残りやすいため、ヘッダー方式を採用する。

import type { Env } from "../types";

const MODEL_NAME = "gemini-3.1-flash-lite";
const GEMINI_ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL_NAME}:generateContent`;

/// Gemini APIが429（無料枠超過）を返した場合。routes/*.tsはrate_limited（429）に変換する
export class GeminiRateLimitedError extends Error {}

/// Gemini API呼び出し失敗・タイムアウト・レスポンス形式異常（NF-03）。
/// routes/*.tsはgeneration_failed（500）に変換する
export class GeminiRequestFailedError extends Error {}

/// promptを渡し、Gemini APIの生成テキストを1件返す。
/// NF-03：レスポンスはプレーンテキストとして扱う（JSON形式のレスポンスは期待しない）。
export async function generateText(prompt: string, env: Env): Promise<string> {
  let response: Response;
  try {
    response = await fetch(GEMINI_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": env.GEMINI_API_KEY,
      },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
      }),
    });
  } catch {
    throw new GeminiRequestFailedError("Gemini APIへのリクエストが失敗しました");
  }

  if (response.status === 429) {
    throw new GeminiRateLimitedError("Gemini APIのレート制限に達しました");
  }
  if (!response.ok) {
    throw new GeminiRequestFailedError(`Gemini APIがエラーを返しました（HTTP ${response.status}）`);
  }

  let json: unknown;
  try {
    json = await response.json();
  } catch {
    throw new GeminiRequestFailedError("Gemini APIのレスポンスをJSONとしてパースできません");
  }

  const extractedText = extractText(json);
  const text = extractedText?.trim();
  if (text === undefined || text.length === 0 || Array.from(text).length > 20_000) {
    // NF-03：空文字・20,000 Unicodeコードポイント超過・想定外の形式は異常系として扱う
    throw new GeminiRequestFailedError("生成テキストの長さ、またはレスポンス形式が不正です");
  }
  return text;
}

function extractText(json: unknown): string | null {
  if (typeof json !== "object" || json === null) return null;
  const candidates = (json as Record<string, unknown>).candidates;
  if (!Array.isArray(candidates) || candidates.length === 0) return null;

  const first = candidates[0];
  if (typeof first !== "object" || first === null) return null;
  const content = (first as Record<string, unknown>).content;
  if (typeof content !== "object" || content === null) return null;
  const parts = (content as Record<string, unknown>).parts;
  if (!Array.isArray(parts) || parts.length === 0) return null;

  const firstPart = parts[0];
  if (typeof firstPart !== "object" || firstPart === null) return null;
  const text = (firstPart as Record<string, unknown>).text;
  return typeof text === "string" ? text : null;
}
