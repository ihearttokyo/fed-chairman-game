import { readdir, readFile } from 'node:fs/promises'
import { gzipSync } from 'node:zlib'
import path from 'node:path'

const distAssets = path.resolve('dist/assets')
const jsWarningBytes = 300 * 1024
const cssLimitBytes = 40 * 1024

async function filesByExtension(extension) {
  const files = await readdir(distAssets)
  return files.filter((file) => file.endsWith(extension)).map((file) => path.join(distAssets, file))
}

async function gzipSize(file) {
  const contents = await readFile(file)
  return gzipSync(contents).byteLength
}

const jsFiles = await filesByExtension('.js')
const cssFiles = await filesByExtension('.css')

if (jsFiles.length === 0 || cssFiles.length === 0) {
  throw new Error('Performance budget check requires built JS and CSS assets in dist/assets.')
}

let largestJs = 0
for (const file of jsFiles) {
  largestJs = Math.max(largestJs, await gzipSize(file))
}

let totalCss = 0
for (const file of cssFiles) {
  totalCss += await gzipSize(file)
}

if (largestJs > jsWarningBytes) {
  console.warn(`Largest JS gzip size is ${(largestJs / 1024).toFixed(1)} KB, above the 300 KB warning budget.`)
}

if (totalCss > cssLimitBytes) {
  throw new Error(`CSS gzip size is ${(totalCss / 1024).toFixed(1)} KB, above the 40 KB budget.`)
}

console.log(`Performance budget: JS max ${(largestJs / 1024).toFixed(1)} KB gzip, CSS total ${(totalCss / 1024).toFixed(1)} KB gzip.`)
