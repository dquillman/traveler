from django.conf import settings


def site_appearance(request):
    """Provide a lightweight, optional site appearance context.

    Reads from settings.SITE_APPEARANCE if present, else uses sensible defaults.
    Exposes under `site_appearance` with keys: site_name, primary_color, secondary_color, background_url.
    """
    cfg = getattr(settings, "SITE_APPEARANCE", {}) or {}
    site_name = cfg.get("site_name") or getattr(settings, "SITE_NAME", "Traveler")
    pri = cfg.get("primary_color", "#0d6efd")
    sec = cfg.get("secondary_color", "#6c757d")
    bg = cfg.get("background_url", None)
    theme = (cfg.get("theme") or "dark").lower()
    # Allow cookie override set by the Appearance page toggle
    try:
        cookie_theme = (request.COOKIES.get("theme") or "").lower()
        if cookie_theme in {"dark", "light"}:
            theme = cookie_theme
    except Exception:
        pass

    return {
        "site_appearance": {
            "site_name": site_name,
            "primary_color": pri,
            "secondary_color": sec,
            "background_url": bg,
            "theme": theme,
        },
        "app_version": getattr(settings, "APP_VERSION", "v0.1.0"),
    }
