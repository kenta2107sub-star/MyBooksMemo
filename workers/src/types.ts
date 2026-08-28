// detailed_design.md 4-2：Cloudflare Workers `/chat`・`/summarize`・`/advice`の型定義。
// iOS側（Services/CloudflareWorkersClient.swift）と1対1で対応させる。

export interface ConversationTurn {
  question: string;
  answer: string;
}

export interface ChatRequest {
  bookTitle: string;
  memoContent: string;
  conversationHistory: ConversationTurn[];
}
export interface ChatResponse {
  question: string;
}

export interface MemoSummaryInput {
  date: string;
  content: string;
}
export interface ConversationLogSummaryInput {
  date: string;
  turns: ConversationTurn[];
}
export interface SummarizeRequest {
  bookTitle: string;
  memos: MemoSummaryInput[];
  conversationLogs: ConversationLogSummaryInput[];
}
export interface SummarizeResponse {
  summary: string;
}

export interface AdviceRequest {
  bookTitle: string;
  memoContent: string;
  conversationTurns: ConversationTurn[];
}
export interface AdviceResponse {
  advice: string;
}

export type ErrorCode = "invalid_request" | "unauthorized" | "rate_limited" | "generation_failed";

export interface ErrorResponse {
  error: ErrorCode;
  message?: string;
}

// Workers環境変数（wrangler secret put / .dev.varsで設定）。architecture.md 10.1参照。
export interface Env {
  GEMINI_API_KEY: string;
  WORKERS_SHARED_SECRET: string;
}
