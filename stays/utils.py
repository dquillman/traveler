from typing import Optional, Tuple
from django.conf import settings

def build_query_from_stay(stay) -> Optional[str]:
    parts = []
    # Adjust these field names if your model differs
    for attr in ("address", "city", "state", "zipcode"):
        val = getattr(stay, attr, None)
        if val:
            parts.append(str(val))
    if not parts:
        return None
    return ", ".join(parts)

def geocode_address(query: str) -> Optional[Tuple[float, float]]:
    # Lazy import to avoid hard dep if command isn't used
    try:
        from geopy.geocoders import Nominatim
    except Exception:
        return None
    user_agent = getattr(settings, "GEOCODER_USER_AGENT", "traveler-app")
    geolocator = Nominatim(user_agent=user_agent, timeout=10)
    try:
        loc = geolocator.geocode(query)
    except Exception:
        return None
    if not loc:
        return None
    return (loc.latitude, loc.longitude)