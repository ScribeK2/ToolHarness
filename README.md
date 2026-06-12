<p align="center">
  <img src="app/assets/images/logo_mark.svg" alt="ToolHarness Logo" width="140" height="140">
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

## Bundled tools

- **Domain:** Registration Lookup (RDAP/WHOIS)
- **DNS:** DNS Lookup (quick + worldwide propagation), Historical DNS, Subdomain Scan
- **Web:** SSL/TLS Inspection, Website Inspection (health + security headers + WordPress detection), Page Speed Report
- **Email:** Email Authentication (SPF/DKIM/DMARC, full or scoped), Email Validity
- **Hosting:** Hosting Diagnostic (full port sweep or quick TCP reachability)
- **Diagnostics:** Blacklist Check, IP Intelligence (IPinfo), Bulk Domain Runner
- **Database:** SQL Workbench &mdash; keyboard-driven ad-hoc SQL against any MySQL-protocol DB (incl. TiDB); read-only by default with a per-connection write toggle
- **Config:** Credentials

The UI is modal (NORMAL / INSERT / CMD / SEARCH), with `:` for a
cmdline, `/` for target search, `?` for a help overlay, and `j`/`k` /
`1`–`9` for tool-rail navigation.

## Themes

ToolHarness ships 11 runtime-switchable themes (6 dark, 5 light): Tokyo Night
Storm (default) & Day, Catppuccin Mocha & Latte, Kanagawa Wave & Lotus, Gruvbox
Material Dark & Light, Everforest Dark & Light, and Nord. Switch with the
`:theme` cmdline verb or the `◆` pill in the status bar — the picker live-previews
with `j`/`k` and persists per browser.

Each theme is a `[data-theme]` block of `--color-*` CSS variables, including two
identity accents (`--color-accent`, `--color-accent-2`) that give each family its
own character — Gruvbox is orange, Everforest green, Kanagawa gold, Nord frost.

To add a theme:

1. Create `app/assets/tailwind/themes/<key>.css` with a `[data-theme="<key>"]`
   block defining every token (copy an existing file; don't forget the two
   `--color-accent*` aliases and `color-scheme`).
2. Add `@import "./themes/<key>.css";` to `app/assets/tailwind/application.css`.
3. Register it in `config/themes.yml` (key, label, scheme).

`test/assets/theme_completeness_test.rb` fails CI if any step is missed.

## Installation (end users)

ToolHarness ships as a single Linux x86_64 AppImage. No Ruby, no Docker, no system packages required.

**Supported distros:** Ubuntu 22.04+, Fedora 38+ (anything with glibc ≥ 2.35).

1. Download the latest `ToolHarness-<version>-x86_64.AppImage` from [Releases](https://github.com/ScribeK2/ToolHarness/releases/latest).
2. Mark it executable: `chmod +x ToolHarness-*.AppImage`
3. Run it: `./ToolHarness-*.AppImage`

The AppImage starts a local web server on `http://localhost:3000` and opens it in your browser. Data is stored under `~/.local/share/toolharness/`. The AppImage is fully self-contained — no host installs.

## Running it for development

Requirements:

- Ruby 3.4.7 (see `.ruby-version`)

```bash
git clone https://github.com/ScribeK2/ToolHarness.git
cd ToolHarness
bundle install
bin/rails db:setup
bin/dev
```

The app listens on **http://localhost:3000**. There is no login —
ToolHarness is single-user local; whoever runs the process is the
user.

## Tests

```bash
bin/rails test
```

## Stack

Rails 8 · SQLite · Solid Queue / Cable / Cache · Hotwire (Turbo +
Stimulus) · Tailwind CSS.

## Releasing

1. Bump the `VERSION` file (semver).
2. Commit and tag: `git tag v$(cat VERSION) && git push --tags`
3. GitHub Actions builds the AppImage, runs a smoke test, and publishes it to the matching GitHub Release.
