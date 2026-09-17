export const WORDMARK_IMAGE_WIDTH = 1008
export const WORDMARK_IMAGE_HEIGHT = 240

export interface WordmarkPixelBounds {
  x: number
  y: number
  width: number
  height: number
}

export interface WordmarkPlacement {
  x: number
  y: number
  width: number
  height: number
}

export function findOpaqueBounds(
  pixels: Uint8ClampedArray,
  width: number,
  height: number,
  alphaThreshold = 8
): WordmarkPixelBounds | null {
  if (width <= 0 || height <= 0 || pixels.length < width * height * 4) return null

  let minX = width
  let minY = height
  let maxX = -1
  let maxY = -1

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const alpha = pixels[(y * width + x) * 4 + 3] ?? 0
      if (alpha <= alphaThreshold) continue
      minX = Math.min(minX, x)
      minY = Math.min(minY, y)
      maxX = Math.max(maxX, x)
      maxY = Math.max(maxY, y)
    }
  }

  if (maxX < minX || maxY < minY) return null
  return {
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1
  }
}

export function fitWordmarkBounds(
  source: Pick<WordmarkPixelBounds, 'width' | 'height'>,
  targetWidth = WORDMARK_IMAGE_WIDTH,
  targetHeight = WORDMARK_IMAGE_HEIGHT,
  horizontalPadding = 36,
  verticalPadding = 24
): WordmarkPlacement {
  const availableWidth = Math.max(targetWidth - horizontalPadding * 2, 1)
  const availableHeight = Math.max(targetHeight - verticalPadding * 2, 1)
  const sourceWidth = Math.max(source.width, 1)
  const sourceHeight = Math.max(source.height, 1)
  const scale = Math.min(availableWidth / sourceWidth, availableHeight / sourceHeight)
  const width = Math.max(Math.round(sourceWidth * scale), 1)
  const height = Math.max(Math.round(sourceHeight * scale), 1)

  return {
    x: Math.round((targetWidth - width) / 2),
    y: Math.round((targetHeight - height) / 2),
    width,
    height
  }
}

const loadImage = async (source: string): Promise<HTMLImageElement> =>
  await new Promise((resolve, reject) => {
    const image = new Image()
    image.onload = () => resolve(image)
    image.onerror = () => reject(new Error('生成的品牌字图无法读取'))
    image.src = source
  })

const canvasToBlob = async (canvas: HTMLCanvasElement): Promise<Blob> =>
  await new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob)
      else reject(new Error('品牌字图处理失败'))
    }, 'image/png')
  })

function createThemedWordmarkCanvas(
  maskCanvas: HTMLCanvasElement,
  theme: Api.SystemManage.WebsiteWordmarkTheme
): HTMLCanvasElement {
  const canvas = document.createElement('canvas')
  canvas.width = WORDMARK_IMAGE_WIDTH
  canvas.height = WORDMARK_IMAGE_HEIGHT
  const context = canvas.getContext('2d')
  if (!context) throw new Error('当前浏览器无法导出品牌字图')

  context.drawImage(maskCanvas, 0, 0)
  context.globalCompositeOperation = 'source-in'
  const gradient = context.createLinearGradient(0, 0, WORDMARK_IMAGE_WIDTH, 0)
  if (theme === 'light') {
    gradient.addColorStop(0, '#071c4c')
    gradient.addColorStop(0.55, '#0b3b82')
    gradient.addColorStop(1, '#1768c4')
  } else {
    gradient.addColorStop(0, '#ffffff')
    gradient.addColorStop(0.58, '#d9efff')
    gradient.addColorStop(1, '#8fcfff')
  }
  context.fillStyle = gradient
  context.fillRect(0, 0, WORDMARK_IMAGE_WIDTH, WORDMARK_IMAGE_HEIGHT)
  context.globalCompositeOperation = 'source-over'
  return canvas
}

export async function createGeneratedWordmarkFiles(
  response: Api.SystemManage.WebsiteWordmarkGenerateResponse,
  siteName: string
): Promise<Record<Api.SystemManage.WebsiteWordmarkTheme, File>> {
  const source = `data:${response.mimeType};base64,${response.imageBase64}`
  const image = await loadImage(source)
  const sourceCanvas = document.createElement('canvas')
  sourceCanvas.width = image.naturalWidth
  sourceCanvas.height = image.naturalHeight
  const sourceContext = sourceCanvas.getContext('2d', { willReadFrequently: true })
  if (!sourceContext) throw new Error('当前浏览器无法处理品牌字图')
  sourceContext.drawImage(image, 0, 0)

  const pixels = sourceContext.getImageData(0, 0, sourceCanvas.width, sourceCanvas.height)
  const bounds =
    findOpaqueBounds(pixels.data, sourceCanvas.width, sourceCanvas.height) ??
    ({
      x: 0,
      y: 0,
      width: sourceCanvas.width,
      height: sourceCanvas.height
    } satisfies WordmarkPixelBounds)
  const placement = fitWordmarkBounds(bounds)

  const maskCanvas = document.createElement('canvas')
  maskCanvas.width = WORDMARK_IMAGE_WIDTH
  maskCanvas.height = WORDMARK_IMAGE_HEIGHT
  const outputContext = maskCanvas.getContext('2d')
  if (!outputContext) throw new Error('当前浏览器无法导出品牌字图')
  outputContext.imageSmoothingEnabled = true
  outputContext.imageSmoothingQuality = 'high'
  outputContext.drawImage(
    sourceCanvas,
    bounds.x,
    bounds.y,
    bounds.width,
    bounds.height,
    placement.x,
    placement.y,
    placement.width,
    placement.height
  )

  const safeName = siteName.trim().replace(/[\\/:*?"<>|\s]+/g, '-') || 'website'
  const [lightBlob, darkBlob] = await Promise.all([
    canvasToBlob(createThemedWordmarkCanvas(maskCanvas, 'light')),
    canvasToBlob(createThemedWordmarkCanvas(maskCanvas, 'dark'))
  ])
  return {
    light: new File([lightBlob], `${safeName}-wordmark-light.png`, { type: 'image/png' }),
    dark: new File([darkBlob], `${safeName}-wordmark-dark.png`, { type: 'image/png' })
  }
}
