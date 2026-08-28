// Phase 7 Step B（testing-runner）：Cloudflare Workers公式のテスト方式。
// 通常のNode環境ではなく、実際のworkerdランタイム上でテストを実行する
// （crypto.subtle.timingSafeEqual等、Workers固有のAPI拡張を使うためNode環境では動作しない）。
// vitest 4系の@cloudflare/vitest-pool-workersはプラグイン方式(@cloudflare/vitest-plugin)に
// 統合されたため、公式ドキュメント（2026年8月時点）に従いこちらを使用する。
import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
    }),
  ],
});
