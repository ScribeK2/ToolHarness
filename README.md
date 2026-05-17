<p align="center">
  <img src="public/icon.png" alt="ToolHarness Logo" width="120" height="120">
</p>

<h1 align="center">ToolHarness</h1>

<p align="center">
  <strong>A keyboard-driven workbench for running domain &amp; network diagnostics.</strong>
</p>

---

## What is it?

ToolHarness is a single-user, local-first Rails app that puts a pile of
domain / DNS / email / TLS diagnostic tools behind one consistent
keyboard-first interface. You pick a tool from the rail (or by command),
type a target, hit Enter — results are stored, filterable from a history
view, and exportable.

Bundled tools:

- **Domain:** WHOIS lookup
- **DNS:** DNS lookup, subdomain scan
- **TLS / HTTP:** SSL/TLS inspection, HTTP &amp; security headers
- **Email auth:** SPF, DKIM, DMARC, combined email-auth overview
- **Network:** ping, traceroute, hosting diagnostic
- **Misc:** blacklist check, bulk domain runner, ticket lookup

The UI is modal (NORMAL / INSERT / CMD / SEARCH), with `:` for a
cmdline, `/` for target search, `?` for a help overlay, and `j`/`k` /
`1`–`9` for tool-rail navigation.

## Running it locally

Requirements:

- Ruby 3.4.7 (see `.ruby-version`)
- A working `whois` system command (used as a fallback)

```bash
git clone https://github.com/ScribeK2/ToolHarness.git
cd ToolHarness
bundle install
bin/rails db:setup
bin/dev
```

The app listens on **http://localhost:3737**. `db:setup` seeds a
default user — `admin@localhost` / `changeme123` — or override via
`TOOLHARNESS_DEFAULT_USER_EMAIL` and `TOOLHARNESS_DEFAULT_USER_PASSWORD`.

## Tests

```bash
bin/rails test
```

## Stack

Rails 8 · SQLite · Solid Queue / Cable / Cache · Hotwire (Turbo +
Stimulus) · Tailwind CSS · Devise.
