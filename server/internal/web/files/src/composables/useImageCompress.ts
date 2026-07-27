// 把 File 读成 base64 字符串，同时缩到 512px max side + JPEG 0.7
// 与 iOS ImageProcessor.swift / 旧 app.js 的约定一致
export function useImageCompress() {
  function fileToBase64(file: File): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = (e) => {
        const img = new Image()
        img.onload = () => {
          const MAX = 512
          let { width, height } = img
          if (width > height && width > MAX) {
            height = Math.round((height * MAX) / width)
            width = MAX
          } else if (height > MAX) {
            width = Math.round((width * MAX) / height)
            height = MAX
          }
          const canvas = document.createElement('canvas')
          canvas.width = width
          canvas.height = height
          const ctx = canvas.getContext('2d')!
          ctx.drawImage(img, 0, 0, width, height)
          const dataUrl = canvas.toDataURL('image/jpeg', 0.7)
          // 剥离 "data:image/jpeg;base64," 前缀，与服务端约定一致
          resolve(dataUrl.split(',')[1])
        }
        img.onerror = () => reject(new Error('图片解析失败'))
        img.src = e.target!.result as string
      }
      reader.onerror = () => reject(new Error('文件读取失败'))
      reader.readAsDataURL(file)
    })
  }

  return { fileToBase64 }
}
