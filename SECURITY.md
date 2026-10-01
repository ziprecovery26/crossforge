# Security Policy

## Reporting a vulnerability

**Privately report karo**, public issue na kholo:

* GitHub → **Security** tab → *Report a vulnerability* (Security Advisories), ya
* maintainers ko issue ke bajaye advisory mein ping karo.

Include karo: kya problem hai, kahan (kaun sa release asset + SHA256), repro steps, impact.

**Response target:** 72 hours mein acknowledgement, 7 din mein assessment.

## Scope

| in-scope | out-of-scope |
|---|---|
| CrossForge ke workflows/scripts mein bug | Upstream project ke andar ka bug (upstream ko report karo) |
| Published binary source ke saath match nahi karta | Third-party mirrors se download kiye gaye assets |
| Tampered artifact / cheksum mismatch | Tumhare environment ki misconfiguration |

## Our guarantees

1. Har binary **public source** se, **public GitHub Actions run** mein banta hai.
2. Release ke saath `SHA256SUMS` hoti hai; installer verify karta hai.
3. Har archive mein `NOTICE.md` — commit SHA, toolchain versions, run URL ke saath.
4. Hum **kabhi** prebuilt third-party blobs shaamil nahi karte.
5. `GITHUB_TOKEN` least-privilege scopes ke saath chalta hai.

## Verifying a download (recommended)

```bash
# Linux/macOS
sha256sum -c SHA256SUMS --ignore-missing

# Windows
Get-FileHash .\opencode-windows-x64.zip -Algorithm SHA256
```

## Supply-chain notes

* Actions major-version tags par pinned hain; Dependabot updates raise karta hai.
* Nightly diff state (`.state/last-built.json`) audit trail hai — kis commit se kya bana.
* Build requests par double license gate chalta hai (triage + pre-build).
