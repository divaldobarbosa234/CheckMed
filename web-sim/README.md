# CheckMed web simulator

Static preview of the **current SwiftUI** CheckMed IA (not the legacy Expo/RN app).

## Start locally

```bash
cd web-sim
python3 -m http.server 8788
```

Open http://127.0.0.1:8788

## Shareable HTTPS (this Mac)

Expo already uses 8081. This sim uses **8788**.

```bash
python3 -m http.server 8788 --bind 127.0.0.1
cloudflared tunnel --url http://127.0.0.1:8788
```

The `trycloudflare.com` URL dies when the tunnel or this Mac stops.
