from stays.models import Stay
from django.db import transaction

# A few nice spread-out coordinates (lat, lng)
COORDS = [
    (44.0805, -103.2310),  # Rapid City, SD
    (46.7867,  -92.1005),  # Duluth, MN
    (39.7392, -104.9903),  # Denver, CO
    (36.1627,  -86.7816),  # Nashville, TN
    (33.4484, -112.0740),  # Phoenix, AZ
    (47.6062, -122.3321),  # Seattle, WA
    (37.7749, -122.4194),  # San Francisco, CA
    (32.7767,  -96.7970),  # Dallas, TX
    (41.8781,  -87.6298),  # Chicago, IL
    (40.7608, -111.8910),  # Salt Lake City, UT
]

def dump(msg): 
    print(f"[seed_pins] {msg}")

@transaction.atomic
def run():
    # 1) Update existing stays that are missing lat/lng
    qs = Stay.objects.filter(latitude__isnull=True)[:len(COORDS)]
    updated = 0
    for (lat, lng), s in zip(COORDS, qs):
        s.latitude = lat
        s.longitude = lng
        s.save(update_fields=["latitude", "longitude"])
        dump(f"Updated Stay id={s.id} → lat={lat}, lng={lng}")
        updated += 1

    # 2) If we still have spare coords, create demo stays
    created = 0
    i = updated
    while i < len(COORDS):
        lat, lng = COORDS[i]
        s = Stay.objects.create(
            park=f"Demo Park {i+1}",
            city="Demo City",
            state="US",
            check_in="2025-01-01",
            leave="2025-01-02",
            nights=1,
            price_per_night=0,
            rate_per_night=0,
            paid=False,
            latitude=lat,
            longitude=lng,
        )
        dump(f"Created demo Stay id={s.id} → lat={lat}, lng={lng}")
        created += 1
        i += 1

    dump(f"Done. Updated: {updated}, Created: {created}")

if __name__ == "__main__":
    run()
