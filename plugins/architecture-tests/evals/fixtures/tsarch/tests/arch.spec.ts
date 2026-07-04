// Human-owned, reviewed ts-arch architecture spec. This file is the LOCKED BODY the contract
// hashes (a single leaf spec). It asserts the layering rule; it never derives the rule from
// contract prose. The fixture ships an intentional violation so a real run reports fail.
import "tsarch/dist/jest";
import { filesOfProject } from "tsarch";
import { describe, it, expect } from "vitest";

describe("architecture", () => {
  it("domain should not depend on infrastructure", async () => {
    const rule = filesOfProject()
      .inFolder("domain")
      .shouldNot()
      .dependOnFiles()
      .inFolder("infrastructure");
    await expect(rule).toPassAsync();
  });
});
