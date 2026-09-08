// detailed_design.md 4-3：手書きの型ガード関数。architecture.md 1.2の方針に従い、
// zod等のバリデーションライブラリは導入しない。

import type { AdviceRequest, ChatRequest, ConversationTurn, SummarizeRequest } from "../types";

const MAX_BODY_BYTES = 512 * 1024;
const MAX_BOOK_TITLE_CODE_POINTS = 500;
const MAX_TEXT_CODE_POINTS = 20_000;
const MAX_TOTAL_CODE_POINTS = 100_000;

export async function parseJsonBody(request: Request): Promise<unknown | undefined> {
  const contentLength = request.headers.get("Content-Length");
  if (contentLength !== null && Number(contentLength) > MAX_BODY_BYTES) return undefined;

  try {
    const bytes = await request.arrayBuffer();
    if (bytes.byteLength > MAX_BODY_BYTES) return undefined;
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return undefined;
  }
}

function codePointLength(value: string): number {
  return [...value].length;
}

function isText(value: unknown, min: number, max: number): value is string {
  return (
    typeof value === "string" &&
    (min === 0 || value.trim().length > 0) &&
    codePointLength(value) <= max
  );
}

function isGregorianDate(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;

  const [year, month, day] = match.slice(1).map(Number);
  if (year < 1 || month < 1 || month > 12) return false;

  const lastDay = [
    31,
    year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ][month - 1];
  return day >= 1 && day <= lastDay;
}

function isConversationTurn(value: unknown): value is ConversationTurn {
  if (typeof value !== "object" || value === null) return false;
  const v = value as Record<string, unknown>;
  return isText(v.question, 0, MAX_TEXT_CODE_POINTS) && isText(v.answer, 0, MAX_TEXT_CODE_POINTS);
}

function totalCodePoints(values: unknown[]): number {
  return values.reduce<number>(
    (sum, value) => sum + (typeof value === "string" ? codePointLength(value) : 0),
    0
  );
}

export function isChatRequest(body: unknown): body is ChatRequest {
  if (typeof body !== "object" || body === null) return false;
  const v = body as Record<string, unknown>;
  const history = v.conversationHistory;
  return (
    isText(v.bookTitle, 1, MAX_BOOK_TITLE_CODE_POINTS) &&
    isText(v.memoContent, 1, MAX_TEXT_CODE_POINTS) &&
    Array.isArray(history) &&
    history.length <= 5 &&
    history.every(isConversationTurn) &&
    totalCodePoints([
      v.bookTitle,
      v.memoContent,
      ...history.flatMap((turn) => [turn.question, turn.answer]),
    ]) <= MAX_TOTAL_CODE_POINTS
  );
}

export function isSummarizeRequest(body: unknown): body is SummarizeRequest {
  if (typeof body !== "object" || body === null) return false;
  const v = body as Record<string, unknown>;
  const memos = v.memos;
  const logs = v.conversationLogs;
  const memosValid =
    Array.isArray(memos) &&
    memos.length >= 1 &&
    memos.length <= 1_000 &&
    memos.every(
      (m) =>
        typeof m === "object" &&
        m !== null &&
        isGregorianDate((m as Record<string, unknown>).date) &&
        isText((m as Record<string, unknown>).content, 0, MAX_TEXT_CODE_POINTS)
    );
  const logsValid =
    Array.isArray(logs) &&
    logs.length <= 1_000 &&
    logs.every(
      (l) =>
        typeof l === "object" &&
        l !== null &&
        isGregorianDate((l as Record<string, unknown>).date) &&
        Array.isArray((l as Record<string, unknown>).turns) &&
        (l as { turns: unknown[] }).turns.length <= 5 &&
        (l as { turns: unknown[] }).turns.every(isConversationTurn)
    );
  if (
    !isText(v.bookTitle, 1, MAX_BOOK_TITLE_CODE_POINTS) ||
    !memosValid ||
    !logsValid ||
    !Array.isArray(memos) ||
    !Array.isArray(logs)
  ) {
    return false;
  }

  const strings = [
    v.bookTitle,
    ...memos.flatMap((memo) => {
      const m = memo as { date: string; content: string };
      return [m.date, m.content];
    }),
    ...logs.flatMap((log) => {
      const l = log as { date: string; turns: ConversationTurn[] };
      return [l.date, ...l.turns.flatMap((turn) => [turn.question, turn.answer])];
    }),
  ];
  return totalCodePoints(strings) <= MAX_TOTAL_CODE_POINTS;
}

export function isAdviceRequest(body: unknown): body is AdviceRequest {
  if (typeof body !== "object" || body === null) return false;
  const v = body as Record<string, unknown>;
  const turns = v.conversationTurns;
  return (
    isText(v.bookTitle, 1, MAX_BOOK_TITLE_CODE_POINTS) &&
    isText(v.memoContent, 1, MAX_TEXT_CODE_POINTS) &&
    Array.isArray(turns) &&
    turns.length <= 5 &&
    turns.every(isConversationTurn) &&
    totalCodePoints([
      v.bookTitle,
      v.memoContent,
      ...turns.flatMap((turn) => [turn.question, turn.answer]),
    ]) <= MAX_TOTAL_CODE_POINTS
  );
}
