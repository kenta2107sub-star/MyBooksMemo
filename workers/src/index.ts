// architecture.md 5章・detailed_design.md 3-3：fetchハンドラのエントリポイント。
// pathnameで/chat・/summarize・/adviceに振り分け、それ以外は404を返す。
// ビジネスロジック（Geminiへのプロンプト構築等）はここに書かず、routes/*.tsに委譲する。

import type { Env } from "./types";
import { handleChat } from "./routes/chat";
import { handleSummarize } from "./routes/summarize";
import { handleAdvice } from "./routes/advice";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return new Response("Not Found", { status: 404 });
    }

    switch (url.pathname) {
      case "/chat":
        return handleChat(request, env);
      case "/summarize":
        return handleSummarize(request, env);
      case "/advice":
        return handleAdvice(request, env);
      default:
        return new Response("Not Found", { status: 404 });
    }
  },
};
