from typing import Optional, Tuple, List
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
    q = ", ".join(parts)
    if q and ("USA" not in q and "United States" not in q):
        q = q + ", USA"
    return q


def geocode_from_stay(stay) -> Optional[Tuple[float, float]]:
    """Try multiple progressively simpler queries to geocode a Stay.

    Strategy:
    - Full: park/address + city + state + zipcode
    - City + State
    - Park + State
    - City only
    Returns first successful (lat, lng), else None.
    """
    queries: List[str] = []
    # Build components
    park = (getattr(stay, "park", None) or "").strip()
    addr = (getattr(stay, "address", None) or "").strip()
    city = (getattr(stay, "city", None) or "").strip()
    state = (getattr(stay, "state", None) or "").strip()
    zipcode = (getattr(stay, "zipcode", None) or "").strip()

    def fmt(*parts: str) -> Optional[str]:
        parts = tuple(p for p in (p.strip() for p in parts) if p)
        if not parts:
            return None
        q = ", ".join(parts)
        if "USA" not in q and "United States" not in q:
            q = f"{q}, USA"
        return q

    full = fmt(park or addr, city, state, zipcode)
    if full:
        queries.append(full)
    if city and state:
        qs = fmt(city, state)
        if qs:
            queries.append(qs)
    if park and state:
        qs = fmt(park, state)
        if qs:
            queries.append(qs)
    if city:
        qs = fmt(city)
        if qs:
            queries.append(qs)

    # De-dupe and try
    seen = set()
    ordered = []
    for q in queries:
        if q not in seen:
            seen.add(q)
            ordered.append(q)
    for q in ordered:
        coords = geocode_address(q)
        if coords:
            return coords
    return None

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
