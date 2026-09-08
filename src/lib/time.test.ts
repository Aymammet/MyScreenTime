import { describe, expect, it } from "vitest";
import { calculateDurationMinutes } from "./time";

describe("calculateDurationMinutes", () => {
  it("calculates a 30-minute session", () => {
    const start = new Date("2026-09-07T11:00:00Z");
    const end = new Date("2026-09-07T11:30:00Z");

    expect(calculateDurationMinutes(start, end)).toBe(30);
  });

  it("rejects an end time before the start time", () => {
    const start = new Date("2026-09-07T11:30:00Z");
    const end = new Date("2026-09-07T11:00:00Z");

    expect(() => calculateDurationMinutes(start, end)).toThrow(
      "End time must be later than start time.",
    );
  });
});
