
import sys, json, requests

def check(url):
    try:
        r = requests.get(url, timeout=5)
        return {"url": url, "status": r.status_code, "ok": r.ok}
    except Exception as e:
        return {"url": url, "error": str(e)}

def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
    endpoints = ["/", "/stays/", "/stays/add/"]
    results = [check(base + ep) for ep in endpoints]
    print(json.dumps(results, indent=2))

if __name__ == "__main__":
    main()
