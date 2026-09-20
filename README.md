# Dottie Calendar

Omarchy calendar app. Day, week, month, and year. Local events plus ICS feeds.

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
