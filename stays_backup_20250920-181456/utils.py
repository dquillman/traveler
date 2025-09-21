import requests
def geocode_city_state(city: str, state: str):
    if not (city and state):
        return None, None
    q = f"{city}, {state}"
    url = "https://nominatim.openstreetmap.org/search"
    params = {"q": q, "format": "json", "limit": 1}
    headers = {"User-Agent": "traveler-app/1.0 (contact: you@example.com)"}
    r = requests.get(url, params=params, headers=headers, timeout=10)
    r.raise_for_status()
    data = r.json()
    if not data:
        return None, None
    lat = float(data[0]["lat"])
    lon = float(data[0]["lon"])
    return lat, lon
