export function BrandMark({ size = 48 }: { size?: number }) {
  return (
    <svg className="brand-mark" width={size} height={size} viewBox="0 0 64 64" role="img" aria-label="Policy command mark">
      <rect x="6" y="6" width="52" height="52" rx="8" fill="currentColor" opacity="0.12" />
      <path d="M16 43h32" stroke="currentColor" strokeWidth="4" strokeLinecap="round" />
      <path d="M18 36l8-10 8 7 12-17" fill="none" stroke="currentColor" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M20 17h24M20 25h12M38 25h6" stroke="currentColor" strokeWidth="2" opacity="0.45" strokeLinecap="round" />
      <circle cx="34" cy="33" r="4" fill="currentColor" />
    </svg>
  )
}
