export function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) {
    return min
  }
  return Math.min(max, Math.max(min, value))
}

export function roundTo(value: number, digits = 2): number {
  const factor = 10 ** digits
  return Math.round(value * factor) / factor
}

export function mean(values: number[]): number {
  if (values.length === 0) {
    return 0
  }
  return values.reduce((total, value) => total + value, 0) / values.length
}

export function meanAbs(values: number[]): number {
  return mean(values.map((value) => Math.abs(value)))
}
