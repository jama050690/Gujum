export const LOCATION_PREFIX = "__LOCATION__:";

export function encodeLocation(lat, lng) {
  const safeLat = Number(lat);
  const safeLng = Number(lng);
  if (Number.isNaN(safeLat) || Number.isNaN(safeLng)) return "";
  return `${LOCATION_PREFIX}${safeLat.toFixed(6)},${safeLng.toFixed(6)}`;
}

export function parseLocationMessage(content) {
  if (!content || typeof content !== "string") return null;
  if (!content.startsWith(LOCATION_PREFIX)) return null;

  const coords = content.slice(LOCATION_PREFIX.length).trim().split(",");
  if (coords.length < 2) return null;
  const lat = Number(coords[0].trim());
  const lng = Number(coords[1].trim());
  if (Number.isNaN(lat) || Number.isNaN(lng)) return null;
  return { lat, lng };
}
