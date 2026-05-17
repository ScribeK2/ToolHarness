**ToolHarness – Full Project Specification Sheet**

**Version:** 1.0 (Draft for Claude Code / Cursor / Windsurf)  
**Author:** Aweiward (based on existing SiteProbe)  
**Date:** May 2026  
**Goal:** Transform SiteProbe into a local-first, extensible **Tool Harness** for Tier 2 Tech Support reps (domain registration, web hosting, email). Each user runs their own private instance via Docker/Podman on Linux (Fedora, Ubuntu, Arch). No central server required.

### 1. Project Overview
- **Name:** ToolHarness
- **Description:** A self-contained desktop-like web app that acts as a unified “harness” for dozens of diagnostic tools. Users enter a domain, email, IP, ticket ID, or hosting identifier and instantly access relevant probes. Results are fast, consistent, and copy-paste ready for tickets.
- **Core Philosophy:**
  - 100% local execution (SQLite + Docker).
  - Extremely easy for non-dev coworkers to run (“double-click a script” experience).
  - Pluggable architecture so new tools can be added in minutes/hours, not days.
  - Built on the proven foundation of **SiteProbe** (fork it).

### 2. Non-Functional Requirements
- **Platforms:** Fedora, Ubuntu, Arch Linux (Docker or Podman).
- **Installation:** One script + Docker pull. No Ruby/Node/PostgreSQL on host.
- **Runtime:** Fully offline-capable except for outbound API/DNS/WHOIS calls.
- **Performance:** Sub-5s cold start for most probes; real-time streaming via Hotwire.
- **Security:** No sensitive credentials in UI; rate limiting on external calls; audit log of every run.
- **Updates:** Simple `docker pull` + restart.
- **Privacy:** All history stays on the user’s machine.

### 3. Tech Stack (Inherited + Extended from SiteProbe)
- **Framework:** Ruby on Rails 8 (latest)
- **Database:** SQLite3 only (production + dev). Persistent volume at `/rails/storage/production.sqlite3`
- **Background Jobs:** Solid Queue
- **Real-time:** Solid Cable (Action Cable)
- **Caching:** Solid Cache
- **Frontend:** Hotwire (Turbo + Stimulus) + Tailwind CSS + ViewComponent (recommended)
- **Auth:** Devise (single local user or simple password-protected mode)
- **Container:** Official Rails multi-stage Dockerfile
- **Modularity:** Rails Engines (mountable) for major tools + lightweight registry for quick tools

### 4. Core Features

#### Dashboard & Navigation
- Global quick-search bar (auto-detects domain/email/IP/ticket).
- Sidebar or card-based Tool Catalog, grouped by category:
  - Domain & Registration
  - DNS
  - SSL/TLS & Security
  - Hosting & Server
  - Email Authentication
  - General Diagnostics
- Recent Checks history (searchable, filterable, exportable to JSON/CSV).
- One-click “Copy formatted summary to clipboard” for every result.

#### Tool Execution
- All tools run asynchronously with live progress (Hotwire Turbo Streams).
- Consistent result UI: severity badges (Critical / Warning / Info), expandable sections, actionable recommendations, raw data toggle.
- Unified `ToolHarness::Result` presenter object.

#### Extensibility (The Harness)
**Preferred Approach: Hybrid**
1. **Lightweight tools** → `app/services/tools/*.rb` following a standard interface (registry pattern).
2. **Complex tools** → Mountable Rails Engines (gems) for isolation.

**Tool Interface Example (for simple tools):**
```ruby
module Tools
  class HostingDiagnostic
    include ToolHarness::Tool

    def self.name = "Hosting Server Diagnostic"
    def self.category = :hosting
    def self.description = "..."
    def self.form_fields = { server: :text, port: :number, ... }

    def execute(params)
      # return ToolHarness::Result object
    end
  end
end
```

**Registry:** Auto-discovers tools on boot. Dashboard dynamically renders forms and result cards.

**Engine Registration (for bigger tools):**
```ruby
# In engine's lib/tool_harness_email_queue/engine.rb
ToolHarness::Registry.register(:email_queue, ToolHarness::EmailQueue::Engine)
```

### 5. Local Docker Packaging (Critical)
- `docker-compose.yml` with single service.
- Persistent volume for SQLite + cache.
- `start-tool-harness.sh` launcher (pull + up + open browser).
- `.dockerignore`, production-ready Dockerfile (multi-stage, minimal size).
- Environment variables for company-specific defaults (e.g., internal WHOIS mirror, API keys).

**Example docker-compose.yml snippet:**
```yaml
services:
  harness:
    image: ghcr.io/yourorg/toolharness:latest
    ports: ["3000:3000"]
    volumes: ["harness_data:/rails/storage"]
    environment:
      RAILS_ENV: production
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
```

### 6. Existing SiteProbe Features to Preserve / Migrate
- All current checkers (DNS, WHOIS, SSL, HTTP Headers, SPF/DKIM/DMARC, Subdomains).
- Real-time streaming.
- Caching strategy.
- Severity system + recommendations.
- Export functionality.
- Devise auth (keep simple).

### 7. New / Enhanced Tools (Priority Order)
1. Hosting diagnostics (cPanel/WHM API wrappers if available, port checks, resource ping).
2. Email queue / bounce analysis.
3. Blacklist checks (IP/domain).
4. Bulk domain checker.
5. Ticket ID lookup (stub for future internal API).
6. Traceroute / ping wrapper (safe shell-out).

### 8. UI/UX Standards
- Dark mode default.
- Keyboard shortcuts (`/` for search, `Esc` to close modals).
- Mobile-friendly (reps may use on laptops).
- Consistent branding: clean, professional, tech-support blue/gray.

### 9. Project Structure (High-Level)
```
toolharness/
├── app/
│   ├── services/tools/          # lightweight tools
│   ├── components/              # ViewComponent result cards
│   ├── controllers/
│   └── ...
├── engines/                     # or separate gems: tool_harness_hosting, etc.
├── config/
│   ├── initializers/tool_registry.rb
│   └── database.yml             # production points to /rails/storage/
├── docker-compose.yml
├── start-tool-harness.sh
├── Dockerfile
└── README.md (with full team setup instructions)
```

### 10. Deliverables Claude Should Produce First
1. Fork-ready repo structure (copy SiteProbe + rename + add registry).
2. `ToolHarness::Registry` + base `Tool` concern.
3. Updated Dockerfile + docker-compose.yml + launcher script.
4. Sample lightweight tool + one engine example.
5. Migration plan for existing SiteProbe services.
6. Updated README with screenshots placeholder.
7. Basic tests for new harness components.

### 11. Success Criteria
- A non-technical coworker can run `./start-tool-harness.sh` and be productive in < 2 minutes.
- Adding a brand-new simple tool takes < 30 minutes.
- The app feels fast and reliable on typical support laptops.
- Zero external hosting or shared server required.
