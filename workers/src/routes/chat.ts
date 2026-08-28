// detailed_design.md 2-3・3-3：POST /chat ハンドラ（FR-04）。
// validate → 認証(lib/auth) → プロンプト構築 → lib/gemini呼び出し → { question } を返す

import type { ChatRequest, ChatResponse, Env, ErrorResponse } from "../types";
import { isAuthorized } from "../lib/auth";
import { isChatRequest } from "../lib/validate";
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

function buildPrompt(body: ChatRequest): string {
  const historyText =
    body.conversationHistory.length === 0
      ? "（まだ質問と回答のやり取りはありません。これが最初の質問です）"
      : body.conversationHistory
          .map((turn, index) => `${index + 1}往復目\n質問：${turn.question}\n回答：${turn.answer}`)
          .join("\n\n");

  return [
    "あなたは読書メモの言語化・具体性向上を助けるコーチです。",
    `本のタイトル：${body.bookTitle}`,
    `その日のメモ：\n${body.memoContent}`,
    `これまでの対話：\n${historyText}`,
    "ユーザーが自分の言葉で具体的に言語化できるよう、次に投げかける質問を1つだけ、日本語の文章として出力してください。",
    "質問文以外の前置き・説明・記号（ラベルや引用符など）は付けないでください。",
  ].join("\n\n");
}

export async function handleChat(request: Request, env: Env): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse("invalid_request", "リクエストボディがJSONとしてパースできません", 400);
  }

  if (!isChatRequest(body)) {
    return errorResponse("invalid_request", "リクエストボディの形式が不正です", 400);
  }

  if (!isAuthorized(request, env)) {
    return errorResponse("unauthorized", "X-Shared-Secretが一致しません", 401);
  }

  try {
    const question = await generateText(buildPrompt(body), env);
    const response: ChatResponse = { question };
    return jsonResponse(response, 200);
  } catch (error) {
    if (error instanceof GeminiRateLimitedError) {
      return errorResponse("rate_limited", error.message, 429);
    }
    return errorResponse("generation_failed", error instanceof Error ? error.message : "不明なエラーです", 500);
  }
}
