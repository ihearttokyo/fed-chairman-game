function hashString(input: string): number {
  let hash = 2166136261
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  return hash >>> 0
}

export class SeededRng {
  private state: number

  constructor(seed: string, cursor = 0) {
    this.state = (hashString(seed) + cursor) >>> 0
  }

  next(): number {
    this.state += 0x6d2b79f5
    let value = this.state
    value = Math.imul(value ^ (value >>> 15), value | 1)
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61)
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296
  }

  between(min: number, max: number): number {
    return min + (max - min) * this.next()
  }
}

export function deterministicNoise(seed: string, quarterIndex: number, salt: string, scale: number): number {
  const rng = new SeededRng(`${seed}:${quarterIndex}:${salt}`)
  return rng.between(-scale, scale)
}
