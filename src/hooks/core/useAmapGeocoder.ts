import { round, trim } from 'lodash-es'
import { useAmapSdk } from './useAmapSdk'

interface AMapLngLatLike {
  lng?: number
  lat?: number
  getLng?: () => number
  getLat?: () => number
}

interface AMapGeocodeResult {
  geocodes?: Array<{
    location?: AMapLngLatLike
  }>
}

interface AMapGeocoderInstance {
  getLocation: (
    address: string,
    callback: (status: string, result: AMapGeocodeResult) => void
  ) => void
}

interface AMapConstructor {
  Geocoder: new (options: { city: string }) => AMapGeocoderInstance
}

export interface AmapGeocodeLocation {
  longitude: number
  latitude: number
}

/**
 * Converts a text address to a GCJ-02 coordinate through the AMap browser SDK.
 * An empty/no-result address resolves to null; SDK configuration and load errors reject.
 */
export function useAmapGeocoder() {
  const { loadAmap } = useAmapSdk<AMapConstructor>({
    key: () => import.meta.env.VITE_AMAP_KEY,
    plugins: ['AMap.Geocoder'],
    securityJsCode: () => import.meta.env.VITE_AMAP_SECURITY_JS_CODE
  })

  async function geocodeAddress(
    address: string,
    city = '全国'
  ): Promise<AmapGeocodeLocation | null> {
    const normalizedAddress = trim(address)
    if (!normalizedAddress) return null

    const AMap = await loadAmap()
    const geocoder = new AMap.Geocoder({ city: trim(city) || '全国' })

    return new Promise((resolve) => {
      geocoder.getLocation(normalizedAddress, (status, result) => {
        if (status !== 'complete') {
          resolve(null)
          return
        }

        const location = result?.geocodes?.[0]?.location
        const longitude = typeof location?.getLng === 'function' ? location.getLng() : location?.lng
        const latitude = typeof location?.getLat === 'function' ? location.getLat() : location?.lat
        if (!isValidCoordinate(longitude, latitude)) {
          resolve(null)
          return
        }

        resolve({
          longitude: round(Number(longitude), 6),
          latitude: round(Number(latitude), 6)
        })
      })
    })
  }

  return { geocodeAddress }
}

function isValidCoordinate(longitude?: number, latitude?: number): boolean {
  return (
    Number.isFinite(longitude) &&
    Number.isFinite(latitude) &&
    Number(longitude) >= -180 &&
    Number(longitude) <= 180 &&
    Number(latitude) >= -90 &&
    Number(latitude) <= 90
  )
}
