//! Calendar store + ICS subscribe. Std only. Fetch via system curl.

mod ics;
mod store;

use std::env;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::{Command, ExitCode};
use std::time::{SystemTime, UNIX_EPOCH};

use store::{Calendar, Event, LOCAL_COLOR, LOCAL_ID, Store};

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    let cmd = args.next().unwrap_or_else(|| "help".into());
    let rest: Vec<String> = args.collect();
    let result = match cmd.as_str() {
        "path" => cmd_path(),
        "list" => cmd_list(),
        "add" => cmd_add(rest),
        "rm" | "remove" => cmd_rm(rest.first().cloned()),
        "subscribe" => cmd_subscribe(rest),
        "unsubscribe" => cmd_unsubscribe(rest.first().cloned()),
        "calendars" => cmd_calendars(),
        "toggle" => cmd_toggle(rest.first().cloned()),
        "rename" => cmd_rename(rest),
        "color" => cmd_color(rest),
        "sync" => cmd_sync(),
        "help" | "-h" | "--help" => {
            print_help();
            Ok(())
        }
        other => Err(format!("unknown command: {other}")),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            let _ = writeln!(io::stderr(), "sd-calendar: {err}");
            ExitCode::FAILURE
        }
    }
}

fn print_help() {
    let _ = writeln!(
        io::stdout(),
        "\
sd-calendar — local events + ICS subscribe, std only

  path                         print store path
  list                         print JSON
  add <date> <title> [HH:MM]   add a local event
  rm <id>                      remove an event
  calendars                    list calendars
  subscribe <name> <url> [color]
  unsubscribe <id>
  toggle <id>                  show or hide a calendar
  rename <id> <name>
  color <id> <#hex>
  sync                         refresh subscribed ICS feeds

date is YYYY-MM-DD. webcal:// URLs are fetched as https://"
    );
}

fn store_path() -> PathBuf {
    let base = env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".local/state"));
    base.join("omarchy/sd-calendar.json")
}

fn home_dir() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn load_store() -> Result<Store, String> {
    store::load(&store_path())
}

fn save_store(store: &Store) -> Result<(), String> {
    store::save(&store_path(), store)
}

fn cmd_path() -> Result<(), String> {
    writeln!(io::stdout(), "{}", store_path().display()).map_err(io_err)
}

fn cmd_list() -> Result<(), String> {
    write_stdout(&store::encode(&load_store()?))
}

fn cmd_calendars() -> Result<(), String> {
    let store = load_store()?;
    for cal in &store.calendars {
        let mark = if cal.enabled { "on " } else { "off" };
        let kind = if cal.url.is_empty() { "local" } else { "ics" };
        writeln!(
            io::stdout(),
            "{mark}  {}  {}  {kind}  {}",
            cal.id, cal.color, cal.name
        )
        .map_err(io_err)?;
    }
    Ok(())
}

fn cmd_add(args: Vec<String>) -> Result<(), String> {
    if args.len() < 2 {
        return Err("usage: add <YYYY-MM-DD> <title> [HH:MM]".into());
    }
    let date_key = args[0].clone();
    if !valid_date(&date_key) {
        return Err("date must be YYYY-MM-DD".into());
    }
    let mut title_parts: Vec<&str> = Vec::new();
    let mut start = String::new();
    for (i, part) in args[1..].iter().enumerate() {
        if i == args[1..].len() - 1 && valid_time(part) && args.len() > 2 {
            start = part.clone();
        } else {
            title_parts.push(part);
        }
    }
    let title = title_parts.join(" ");
    if title.is_empty() {
        return Err("title required".into());
    }
    let mut store = load_store()?;
    let event = Event {
        id: new_id(),
        calendar_id: LOCAL_ID.into(),
        date_key,
        title,
        start,
        end: String::new(),
        color: store
            .calendars
            .iter()
            .find(|c| c.id == LOCAL_ID)
            .map(|c| c.color.clone())
            .unwrap_or_else(|| LOCAL_COLOR.into()),
        all_day: false,
    };
    let id = event.id.clone();
    store.events.push(event);
    save_store(&store)?;
    writeln!(io::stdout(), "{id}").map_err(io_err)
}

fn cmd_rm(id: Option<String>) -> Result<(), String> {
    let id = id.ok_or_else(|| "usage: rm <id>".to_string())?;
    let mut store = load_store()?;
    let before = store.events.len();
    store.events.retain(|e| e.id != id);
    if store.events.len() == before {
        return Err(format!("no event {id}"));
    }
    save_store(&store)
}

fn cmd_subscribe(args: Vec<String>) -> Result<(), String> {
    if args.len() < 2 {
        return Err("usage: subscribe <name> <url> [color]".into());
    }
    let name = args[0].trim().to_string();
    let url = normalize_url(&args[1]);
    if name.is_empty() {
        return Err("name required".into());
    }
    if !(url.starts_with("https://") || url.starts_with("http://")) {
        return Err("url must be http(s) or webcal".into());
    }
    let mut store = load_store()?;
    if store.calendars.iter().any(|c| c.url == url) {
        return Err("already subscribed to that url".into());
    }
    let color = args
        .get(2)
        .cloned()
        .unwrap_or_else(|| store::next_color(store.calendars.len()));
    let id = unique_id(&store, &slug(&name));
    store.calendars.push(Calendar {
        id: id.clone(),
        name,
        url: url.clone(),
        color,
        enabled: true,
    });
    save_store(&store)?;
    match sync_one(&mut store, &id) {
        Ok(n) => {
            save_store(&store)?;
            writeln!(io::stdout(), "{id}  synced {n} events").map_err(io_err)
        }
        Err(err) => {
            save_store(&store)?;
            Err(format!("subscribed as {id}, sync failed: {err}"))
        }
    }
}

fn cmd_unsubscribe(id: Option<String>) -> Result<(), String> {
    let id = id.ok_or_else(|| "usage: unsubscribe <id>".to_string())?;
    if id == LOCAL_ID {
        return Err("cannot unsubscribe the local calendar".into());
    }
    let mut store = load_store()?;
    let before = store.calendars.len();
    store.calendars.retain(|c| c.id != id);
    if store.calendars.len() == before {
        return Err(format!("no calendar {id}"));
    }
    store.events.retain(|e| e.calendar_id != id);
    save_store(&store)
}

fn cmd_rename(args: Vec<String>) -> Result<(), String> {
    if args.len() < 2 {
        return Err("usage: rename <id> <name>".into());
    }
    let id = args[0].clone();
    let name = args[1..].join(" ");
    if name.trim().is_empty() {
        return Err("name required".into());
    }
    let mut store = load_store()?;
    let cal = store
        .calendars
        .iter_mut()
        .find(|c| c.id == id)
        .ok_or_else(|| format!("no calendar {id}"))?;
    cal.name = name.trim().to_string();
    save_store(&store)?;
    writeln!(io::stdout(), "{id} renamed").map_err(io_err)
}

fn cmd_color(args: Vec<String>) -> Result<(), String> {
    if args.len() < 2 {
        return Err("usage: color <id> <#hex>".into());
    }
    let id = args[0].clone();
    let color = args[1].trim().to_string();
    if !valid_color(&color) {
        return Err("color must be #rgb or #rrggbb".into());
    }
    let mut store = load_store()?;
    let cal = store
        .calendars
        .iter_mut()
        .find(|c| c.id == id)
        .ok_or_else(|| format!("no calendar {id}"))?;
    cal.color = color.clone();
    for event in &mut store.events {
        if event.calendar_id == id {
            event.color = color.clone();
        }
    }
    save_store(&store)?;
    writeln!(io::stdout(), "{id} {color}").map_err(io_err)
}

fn valid_color(s: &str) -> bool {
    let b = s.as_bytes();
    if b.first() != Some(&b'#') {
        return false;
    }
    let digits = &b[1..];
    (digits.len() == 3 || digits.len() == 6) && digits.iter().all(|c| c.is_ascii_hexdigit())
}

fn cmd_toggle(id: Option<String>) -> Result<(), String> {
    let id = id.ok_or_else(|| "usage: toggle <id>".to_string())?;
    let mut store = load_store()?;
    let (enabled, has_url) = {
        let cal = store
            .calendars
            .iter_mut()
            .find(|c| c.id == id)
            .ok_or_else(|| format!("no calendar {id}"))?;
        cal.enabled = !cal.enabled;
        (cal.enabled, !cal.url.is_empty())
    };
    let mut extra = String::new();
    if enabled && has_url {
        match sync_one(&mut store, &id) {
            Ok(n) => extra = format!("  synced {n} events"),
            Err(err) => extra = format!("  sync failed: {err}"),
        }
    }
    save_store(&store)?;
    let state = if enabled { "on" } else { "off" };
    writeln!(io::stdout(), "{id} {state}{extra}").map_err(io_err)
}

fn cmd_sync() -> Result<(), String> {
    let mut store = load_store()?;
    let ids: Vec<String> = store
        .calendars
        .iter()
        .filter(|c| c.enabled && !c.url.is_empty())
        .map(|c| c.id.clone())
        .collect();
    let mut total = 0;
    let mut errors = Vec::new();
    for id in ids {
        match sync_one(&mut store, &id) {
            Ok(n) => total += n,
            Err(err) => errors.push(format!("{id}: {err}")),
        }
    }
    save_store(&store)?;
    if errors.is_empty() {
        writeln!(io::stdout(), "synced {total} events").map_err(io_err)
    } else {
        Err(format!("synced {total} events; {}", errors.join("; ")))
    }
}

fn sync_one(store: &mut Store, id: &str) -> Result<usize, String> {
    let cal = store
        .calendars
        .iter()
        .find(|c| c.id == id)
        .cloned()
        .ok_or_else(|| format!("no calendar {id}"))?;
    if cal.url.is_empty() {
        return Ok(store.events.iter().filter(|e| e.calendar_id == id).count());
    }
    let ics_text = fetch_ics(&cal.url)?;
    let (start, end) = ics::window();
    let mut events = ics::events_from_ics(&ics_text, &cal.id, &cal.color, start, end);
    if let Some(almanac_id) = almanac_id_for_url(&cal.url) {
        for item in ics::sealed_items(&ics_text) {
            let Ok(plain) = open_seal(&almanac_id, &item.uid, &item.seal) else {
                continue;
            };
            let wrapped = ics_from_opened(&item.uid, &plain);
            events.extend(ics::events_from_ics(&wrapped, &cal.id, &cal.color, start, end));
        }
    }
    let count = events.len();
    store.events.retain(|e| e.calendar_id != id);
    store.events.extend(events);
    Ok(count)
}

fn almanac_id_for_url(url: &str) -> Option<String> {
    let path = env::var("ALMANAC_CONFIG").ok().map(PathBuf::from).or_else(|| {
        let home = env::var("HOME").ok()?;
        let base = env::var("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from(home).join(".config"));
        Some(base.join("almanac").join("hosted-calendars.json"))
    })?;
    let text = std::fs::read_to_string(path).ok()?;
    let want = url.trim().trim_end_matches('/');
    for row in text.split('{').skip(1) {
        let Some(id) = json_string(row, "id") else {
            continue;
        };
        let subscribe = json_string(row, "subscribe").unwrap_or_default();
        if subscribe.trim().trim_end_matches('/') == want {
            return Some(id);
        }
    }
    None
}

fn binary_seals(path: &std::path::Path) -> bool {
    let Ok(bytes) = std::fs::read(path) else {
        return false;
    };
    let needle = b"almanac-seal-v1";
    bytes.windows(needle.len()).any(|window| window == needle)
}

fn open_seal(calendar_id: &str, uid: &str, seal: &str) -> Result<String, String> {
    let bin = env::var("ALMANAC_BIN")
        .ok()
        .filter(|s| !s.is_empty() && binary_seals(std::path::Path::new(s)))
        .unwrap_or_else(|| {
            if let Some(home) = env::var("HOME").ok() {
                for name in ["release", "debug"] {
                    let built = PathBuf::from(&home)
                        .join("Projects/almanac/target")
                        .join(name)
                        .join("almanac");
                    if binary_seals(&built) {
                        return built.to_string_lossy().into_owned();
                    }
                }
            }
            "almanac".into()
        });
    let mut child = Command::new(&bin);
    child.args(["open", "--cal", calendar_id, "--kind", "event", "--uid", uid]);
    if let Ok(config) = env::var("ALMANAC_CONFIG") {
        child.env("ALMANAC_CREDS", config);
    }
    let mut child = child
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    if let Some(mut stdin) = child.stdin.take() {
        use std::io::Write;
        let _ = stdin.write_all(seal.as_bytes());
    }
    let out = child.wait_with_output().map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err("seal was rejected".into());
    }
    String::from_utf8(out.stdout).map_err(|e| e.to_string())
}

fn ics_from_opened(uid: &str, json: &str) -> String {
    let summary = json_string(json, "summary").unwrap_or_else(|| "Untitled".into());
    let start = json_string(json, "start").unwrap_or_default();
    let end = json_string(json, "end").unwrap_or_default();
    let all_day = json.contains("\"allDay\":true") || (start.len() == 10 && !start.contains('T'));
    let rrule = json_string(json, "rrule").unwrap_or_default();
    let mut lines = vec![
        "BEGIN:VCALENDAR".into(),
        "BEGIN:VEVENT".into(),
        format!("UID:{uid}"),
        format!("SUMMARY:{}", summary.replace('\\', "\\\\").replace(',', "\\,")),
    ];
    if all_day {
        let day: String = start.chars().filter(|c| c.is_ascii_digit()).take(8).collect();
        lines.push(format!("DTSTART;VALUE=DATE:{day}"));
        if !end.is_empty() {
            let end_day: String = end.chars().filter(|c| c.is_ascii_digit()).take(8).collect();
            lines.push(format!("DTEND;VALUE=DATE:{end_day}"));
        }
    } else if !start.is_empty() {
        lines.push(format!("DTSTART:{}", compact_stamp(&start)));
        if !end.is_empty() {
            lines.push(format!("DTEND:{}", compact_stamp(&end)));
        }
    }
    if !rrule.is_empty() {
        lines.push(format!("RRULE:{rrule}"));
    }
    lines.push("END:VEVENT".into());
    lines.push("END:VCALENDAR".into());
    lines.join("\n")
}

fn compact_stamp(value: &str) -> String {
    value.chars().filter(|c| c.is_ascii_digit()).take(14).collect()
}

fn json_string(obj: &str, key: &str) -> Option<String> {
    let pat = format!("\"{key}\":\"");
    let at = obj.find(&pat)?;
    let mut out = String::new();
    let mut esc = false;
    for c in obj[at + pat.len()..].chars() {
        if esc {
            out.push(match c {
                'n' => '\n',
                't' => '\t',
                other => other,
            });
            esc = false;
            continue;
        }
        if c == '\\' {
            esc = true;
            continue;
        }
        if c == '"' {
            break;
        }
        out.push(c);
    }
    Some(out)
}

fn fetch_ics(url: &str) -> Result<String, String> {
    let out = Command::new("curl")
        .args([
            "-fsSL",
            "--max-time",
            "30",
            "--compressed",
            "-A",
            "sd-calendar/0.2",
            url,
        ])
        .output()
        .map_err(|e| format!("curl: {e}"))?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        return Err(if err.trim().is_empty() {
            "curl failed".into()
        } else {
            err.trim().to_string()
        });
    }
    String::from_utf8(out.stdout).map_err(|e| format!("ics is not utf-8: {e}"))
}

fn normalize_url(url: &str) -> String {
    let url = url.trim();
    if let Some(rest) = url.strip_prefix("webcal://") {
        format!("https://{rest}")
    } else if let Some(rest) = url.strip_prefix("webcals://") {
        format!("https://{rest}")
    } else {
        url.to_string()
    }
}

fn slug(name: &str) -> String {
    let mut out = String::new();
    let mut dash = false;
    for c in name.chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c.to_ascii_lowercase());
            dash = false;
        } else if !dash && !out.is_empty() {
            out.push('-');
            dash = true;
        }
    }
    let out = out.trim_matches('-').to_string();
    if out.is_empty() {
        "cal".into()
    } else {
        out
    }
}

fn unique_id(store: &Store, base: &str) -> String {
    if !store.calendars.iter().any(|c| c.id == base) {
        return base.into();
    }
    for n in 2..1000 {
        let id = format!("{base}-{n}");
        if !store.calendars.iter().any(|c| c.id == id) {
            return id;
        }
    }
    format!("{base}-{}", new_id())
}

fn valid_date(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() == 10
        && b[4] == b'-'
        && b[7] == b'-'
        && b[0..4].iter().all(|c| c.is_ascii_digit())
        && b[5..7].iter().all(|c| c.is_ascii_digit())
        && b[8..10].iter().all(|c| c.is_ascii_digit())
}

fn valid_time(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() == 5
        && b[2] == b':'
        && b[0..2].iter().all(|c| c.is_ascii_digit())
        && b[3..5].iter().all(|c| c.is_ascii_digit())
}

fn new_id() -> String {
    let ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    format!("e{ms:x}")
}

fn write_stdout(text: &str) -> Result<(), String> {
    let mut out = io::stdout();
    out.write_all(text.as_bytes()).map_err(io_err)?;
    out.flush().map_err(io_err)
}

fn io_err(err: io::Error) -> String {
    err.to_string()
}
