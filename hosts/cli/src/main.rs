//! `aether` — render an Aether component to a file, or to a window.
//!
//! The first shell over `aether_runtime`, and deliberately the smaller one. It
//! runs the AUTHOR'S OWN code, the way `cargo run` does, so it grants a
//! permissive capability set — but it takes the same guarded path Dew does
//! rather than a privileged one, because a boundary only Dew ever crosses is a
//! boundary nobody is watching.

mod preview;
mod snapshot;

use std::path::PathBuf;
use std::process::ExitCode;

const USAGE: &str = "\
aether — render an Aether component off-engine

USAGE:
    aether snapshot <entry.luau> [-o out.png] [--size WxH] [--frames N]
    aether preview  <entry.luau> [--size WxH]

COMMANDS:
    snapshot    Draw one frame to a PNG. Needs no display, so this is the
                form CI runs.
    preview     Open a window and drive the component live. Windows only.

OPTIONS:
    -o, --out <path>    Where to write (default: aether.png)
        --size <WxH>    Override the size the entry point asks for
        --frames <N>    Step N frames before drawing, so animation and any
                        settling have happened (default: 1)

The entry point is a Luau module returning { Session = Live.Session(...) }.
See examples/counter/entry/desktop.luau.
";

pub struct Args {
    pub entry: PathBuf,
    pub out: PathBuf,
    pub size: Option<(u32, u32)>,
    pub frames: u32,
}

fn parse(command: String, argv: Vec<String>) -> Result<(String, Args), String> {
    let mut rest = argv.into_iter();

    let mut entry: Option<PathBuf> = None;
    let mut out = PathBuf::from("aether.png");
    let mut size = None;
    let mut frames = 1;

    while let Some(arg) = rest.next() {
        match arg.as_str() {
            "-o" | "--out" => out = PathBuf::from(rest.next().ok_or("--out needs a path")?),
            "--size" => {
                let raw = rest.next().ok_or("--size needs WxH")?;
                let (w, h) = raw
                    .split_once(['x', 'X'])
                    .ok_or_else(|| format!("--size wants WxH, got {raw:?}"))?;
                size = Some((
                    w.parse().map_err(|_| format!("bad width in {raw:?}"))?,
                    h.parse().map_err(|_| format!("bad height in {raw:?}"))?,
                ));
            }
            "--frames" => {
                frames = rest
                    .next()
                    .ok_or("--frames needs a number")?
                    .parse()
                    .map_err(|_| "--frames wants a number")?;
            }
            other if other.starts_with('-') => return Err(format!("unknown option {other:?}")),
            other => entry = Some(PathBuf::from(other)),
        }
    }

    let entry = entry.ok_or("no entry module given")?;
    if !entry.is_file() {
        return Err(format!("{} is not a file", entry.display()));
    }

    Ok((command, Args { entry, out, size, frames }))
}

fn main() -> ExitCode {
    let mut args = std::env::args();
    let _exe = args.next();

    // HELP IS ANSWERED BEFORE PARSING, because parsing demands an entry module
    // and `aether --help` has none. Handled after, it produced "no entry module
    // given" followed by the usage text — technically the right text, arrived at
    // by reporting an error the user did not make.
    let mut argv: Vec<String> = args.collect();
    if argv.is_empty() || matches!(argv[0].as_str(), "help" | "--help" | "-h") {
        print!("{USAGE}");
        return ExitCode::SUCCESS;
    }

    let command = argv.remove(0);
    let (command, args) = match parse(command, argv) {
        Ok(v) => v,
        Err(message) => {
            eprintln!("aether: {message}\n\n{USAGE}");
            return ExitCode::FAILURE;
        }
    };

    let result = match command.as_str() {
        "snapshot" => snapshot::run(&args),
        "preview" => preview::run(&args),
        other => Err(format!("unknown command {other:?}\n\n{USAGE}")),
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("aether: {message}");
            ExitCode::FAILURE
        }
    }
}
