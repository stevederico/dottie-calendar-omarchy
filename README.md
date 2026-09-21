# Dottie Calendar

Omarchy calendar app. Day, week, month, and year. Almanac events plus ICS feeds.

**New** (or `n`) adds an event on the selected day. Click an Almanac event to edit or delete. Writes go to Almanac over POST (Cloudflare blocks PATCH). A sealed calendar is written as a seal and opened locally from `X-ALMANAC-SEAL`. A plain calendar stays a normal ICS feed. Then the feed syncs.

Launch as **dottie** or **calendar**. Plugin id is `sd.calendar`.

## Install

Review the plugin, then enable it. Omarchy plugins run unsandboxed inside `omarchy-shell`.

```sh
omarchy plugin add https://github.com/stevederico/dottie-calendar-omarchy.git
omarchy plugin enable sd.calendar --section right
```

Build the backend if `bin/sd-calendar` is missing:

```sh
cargo build --release --manifest-path backend/Cargo.toml
```
