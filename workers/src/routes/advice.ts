// detailed_design.md 2-3・3-3：POST /advice ハンドラ（FR-09）。
// validate → 認証(lib/auth) → プロンプト構築 → lib/gemini呼び出し → { advice } を返す

import type { AdviceRequest, AdviceResponse, Env, ErrorResponse } from "../types";
import { isAuthorized } from "../lib/auth";
import { isAdviceRequest } from "../lib/validate";
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

function buildPrompt(body: AdviceRequest): string {
  const turnsText =
    body.conversationTurns.length === 0
      ? "（AI対話は行っていません）"
      : body.conversationTurns
          .map((turn, index) => `${index + 1}往復目\n質問：${turn.question}\n回答：${turn.answer}`)
          .join("\n\n");

  return [
    "あなたは読書メモに寄り添う、静かで丁寧なコーチです。",
    `本のタイトル：${body.bookTitle}`,
    `その日のメモ：\n${body.memoContent}`,
    `その日のAI対話：\n${turnsText}`,
    "今日の気づきを次の行動に活かすための、短く前向きなアドバイスを1〜3文の日本語で出力してください。",
    "前置きや挨拶、箇条書きの記号は不要です。アドバイス本文のみを出力してください。",
  ].join("\n\n");
}

export async function handleAdvice(request: Request, env: Env): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse("invalid_request", "リクエストボディがJSONとしてパースできません", 400);
  }

  if (!isAdviceRequest(body)) {
    return errorResponse("invalid_request", "リクエストボディの形式が不正です", 400);
  }

  if (!isAuthorized(request, env)) {
    return errorResponse("unauthorized", "X-Shared-Secretが一致しません", 401);
  }

  try {
    const advice = await generateText(buildPrompt(body), env);
    const response: AdviceResponse = { advice };
    return jsonResponse(response, 200);
  } catch (error) {
    if (error instanceof GeminiRateLimitedError) {
      return errorResponse("rate_limited", error.message, 429);
    }
    return errorResponse("generation_failed", error instanceof Error ? error.message : "不明なエラーです", 500);
  }
}
