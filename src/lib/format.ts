export function formatPct(value: number, digits = 2): string {
  return `${value.toFixed(digits)}%`
}

export function formatSigned(value: number, digits = 2): string {
  const sign = value > 0 ? '+' : ''
  return `${sign}${value.toFixed(digits)}`
}

export function classNames(...values: Array<string | false | null | undefined>): string {
  return values.filter(Boolean).join(' ')
}
