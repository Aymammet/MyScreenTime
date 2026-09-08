export function calculateDurationMinutes(
  startedAt: Date,
  endedAt: Date,
): number {
  const durationMilliseconds = endedAt.getTime() - startedAt.getTime();

  if (durationMilliseconds <= 0) {
    throw new Error("End time must be later than start time.");
  }

  return Math.ceil(durationMilliseconds / 60_000);
}
