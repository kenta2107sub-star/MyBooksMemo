// detailed_design.md 2-3・3-3：POST /summarize ハンドラ（FR-05）。
// validate → 認証(lib/auth) → プロンプト構築 → lib/gemini呼び出し → { summary } を返す

import type { Env, ErrorResponse, SummarizeRequest, SummarizeResponse } from "../types";
import { isAuthorized } from "../lib/auth";
import { isSummarizeRequest } from "../lib/validate";
import { GeminiRateLimitedError, generateText } from "../lib/gemini";

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorResponse(error: ErrorResponse["error"], message: string, status: number): Response {
  const body: ErrorResponse = { error, message };
  return jsonResponse(body, status);
}

function buildPrompt(body: SummarizeRequest): string {
  const memosText = body.memos
    .map((memo) => `[${memo.date}]\n${memo.content}`)
    .join("\n\n");

  const logsText =
    body.conversationLogs.length === 0
      ? "（AI対話ログはありません）"
      : body.conversationLogs
          .map((log) => {
            const turnsText = log.turns
              .map((turn, index) => `${index + 1}往復目\n質問：${turn.question}\n回答：${turn.answer}`)
              .join("\n");
            return `[${log.date}]\n${turnsText}`;
          })
          .join("\n\n");

  return [
    "あなたは読書メモを要約するコーチです。",
    `本のタイトル：${body.bookTitle}`,
    `記録された全メモ（日付降順）：\n${memosText}`,
    `記録された全AI対話ログ：\n${logsText}`,
    "この本についてユーザーが記録した気づきや行動目標を、日本語で簡潔に要約してください。",
    "箇条書き（各項目の先頭に「・」）を使い、具体的な気づきや変化があれば日付を添えて触れてください。",
    "前置きや締めの挨拶は不要です。要約本文のみを出力してください。",
  ].join("\n\n");
}

export async function handleSummarize(request: Request, env: Env): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse("invalid_request", "リクエストボディがJSONとしてパースできません", 400);
  }

  if (!isSummarizeRequest(body)) {
    return errorResponse("invalid_request", "リクエストボディの形式が不正です", 400);
  }

  if (!isAuthorized(request, env)) {
    return errorResponse("unauthorized", "X-Shared-Secretが一致しません", 401);
  }

  try {
    const summary = await generateText(buildPrompt(body), env);
    const response: SummarizeResponse = { summary };
    return jsonResponse(response, 200);
  } catch (error) {
    if (error instanceof GeminiRateLimitedError) {
      return errorResponse("rate_limited", error.message, 429);
    }
    return errorResponse("generation_failed", error instanceof Error ? error.message : "不明なエラーです", 500);
  }
}
