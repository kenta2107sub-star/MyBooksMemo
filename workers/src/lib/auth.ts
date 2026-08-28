// detailed_design.md 2-2／3-3：X-Shared-Secretヘッダーと環境変数WORKERS_SHARED_SECRETの比較関数。
// FR-06共通ルールNo.6・NF-02の実体。routes/chat.ts・summarize.ts・advice.tsの3つ全てから
// 呼ばれる共通関数として1箇所に集約し、認証ロジックの重複を防ぐ。
//
// セキュリティ強化（security-guidance）：単純な文字列比較（===）はタイミング攻撃
// （比較にかかる時間の差からシークレットの内容を推測される攻撃）に対して脆弱なため、
// Cloudflare Workers公式ドキュメントが推奨する`crypto.subtle.timingSafeEqual`を使用する。
// 長さが異なる場合に早期リターンすると、その分岐自体がタイミング差として漏洩しうるため、
// 公式サンプル通り「長さが異なる場合はユーザー入力を自分自身と比較して常にfalseにする」
// ことで、成功/失敗いずれの経路でも一定時間の比較処理を行う。

import type { Env } from "../types";

export function isAuthorized(request: Request, env: Env): boolean {
  const provided = request.headers.get("X-Shared-Secret") ?? "";
  const expected = env.WORKERS_SHARED_SECRET ?? "";

  if (expected.length === 0) {
    // WORKERS_SHARED_SECRET未設定は設定ミスであり、認証をバイパスしてはならない
    return false;
  }

  const encoder = new TextEncoder();
  const providedBytes = encoder.encode(provided);
  const expectedBytes = encoder.encode(expected);

  const lengthsMatch = providedBytes.byteLength === expectedBytes.byteLength;
  const isEqual = lengthsMatch
    ? crypto.subtle.timingSafeEqual(providedBytes, expectedBytes)
    : !crypto.subtle.timingSafeEqual(providedBytes, providedBytes);

  return isEqual;
}
