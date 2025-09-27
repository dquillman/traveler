from typing import Optional, Tuple
from django.conf import settings
from urllib.parse import urlencode
import json
import time
import requests

def build_query_from_stay(stay) -> Optional[str]:
    parts = []
    # Include park/campground name for better accuracy
    for attr in ("park", "address", "city", "state", "zipcode"):
        val = getattr(stay, attr, None)
        if val:
            s = str(val).strip()
            if s:
                parts.append(s)
    if not parts:
        return None
    return ", ".join(parts)

def geocode_address(query: str) -> Optional[Tuple[float, float]]:
    """Geocode via geopy Nominatim if available; fallback to direct HTTP using requests.

    Returns (lat, lng) on success, else None.
    """
    user_agent = getattr(settings, "GEOCODER_USER_AGENT", "traveler-app")

    # Try geopy if installed
    try:
        from geopy.geocoders import Nominatim  # type: ignore
        geolocator = Nominatim(user_agent=user_agent, timeout=10)
        loc = geolocator.geocode(query)
        if loc:
            return (float(loc.latitude), float(loc.longitude))
    except Exception:
        pass

    # Fallback: direct HTTP to Nominatim
    try:
        params = {"format": "json", "q": query}
        url = "https://nominatim.openstreetmap.org/search?" + urlencode(params)
        headers = {"User-Agent": user_agent}
        resp = requests.get(url, headers=headers, timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            if isinstance(data, list) and data:
                item = data[0]
                lat = float(item.get("lat"))
                lon = float(item.get("lon"))
                return (lat, lon)
    except Exception:
        return None

    return None
