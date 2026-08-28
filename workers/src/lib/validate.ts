// detailed_design.md 4-3：手書きの型ガード関数。architecture.md 1.2の方針に従い、
// zod等のバリデーションライブラリは導入しない。

import type { AdviceRequest, ChatRequest, ConversationTurn, SummarizeRequest } from "../types";

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isConversationTurn(value: unknown): value is ConversationTurn {
  if (typeof value !== "object" || value === null) return false;
  const v = value as Record<string, unknown>;
  return typeof v.question === "string" && typeof v.answer === "string";
}

export function isChatRequest(body: unknown): body is ChatRequest {
  if (typeof body !== "object" || body === null) return false;
  const v = body as Record<string, unknown>;
  return (
    isNonEmptyString(v.bookTitle) &&
    isNonEmptyString(v.memoContent) &&
    Array.isArray(v.conversationHistory) &&
    v.conversationHistory.every(isConversationTurn)
  );
}

export function isSummarizeRequest(body: unknown): body is SummarizeRequest {
  if (typeof body !== "object" || body === null) return false;
  const v = body as Record<string, unknown>;
  const memosValid =
    Array.isArray(v.memos) &&
    v.memos.length > 0 &&
    v.memos.every(
      (m) =>
        typeof m === "object" &&
        m !== null &&
        isNonEmptyString((m as Record<string, unknown>).date) &&
        typeof (m as Record<string, unknown>).content === "string"
    );
  const logsValid =
    Array.isArray(v.conversationLogs) &&
    v.conversationLogs.every(
      (l) =>
        typeof l === "object" &&
        l !== null &&
        isNonEmptyString((l as Record<string, unknown>).date) &&
        Array.isArray((l as Record<string, unknown>).turns) &&
        (l as { turns: unknown[] }).turns.every(isConversationTurn)
    );
  return isNonEmptyString(v.bookTitle) && memosValid && logsValid;
}

export function isAdviceRequest(body: unknown): body is AdviceRequest {
  if (typeof body !== "object" || body === null) return false;
  const v = body as Record<string, unknown>;
  return (
    isNonEmptyString(v.bookTitle) &&
    isNonEmptyString(v.memoContent) &&
    Array.isArray(v.conversationTurns) &&
    v.conversationTurns.every(isConversationTurn)
  );
}
