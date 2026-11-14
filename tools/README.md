# Measurement tools

Small single-file Swift programs used to test CallGuard. They're described in [docs/how-it-works.md](../docs/how-it-works.md#repeating-the-measurements).

```bash
swiftc -O tools/meter.swift -o tools/meter
```

They change only what you tell them to, on the device you name. `inset` and `outset` change mute settings, so put things back afterwards.
