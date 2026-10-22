import { useEffect, useRef, useState } from 'react'

/** Ancho en px de un elemento, actualizado al redimensionar (para SVG responsivos). */
export function useElementWidth(initial = 320) {
  const ref = useRef(null)
  const [width, setWidth] = useState(initial)
  useEffect(() => {
    const el = ref.current
    if (!el) return undefined
    const ro = new ResizeObserver(([entry]) => setWidth(Math.max(200, Math.floor(entry.contentRect.width))))
    ro.observe(el)
    return () => ro.disconnect()
  }, [])
  return [ref, width]
}
