import { defineConfig } from "vitest/config";

// globals:true exposes a global `expect` so the tsarch jest-extension (`tsarch/dist/jest`)
// can register its async `toPassAsync` matcher. Kept minimal and self-contained.
export default defineConfig({
  test: {
    globals: true,
    include: ["tests/**/*.spec.ts"],
    testTimeout: 60000,
  },
});
