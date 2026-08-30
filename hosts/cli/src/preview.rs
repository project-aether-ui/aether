//! `aether preview` — a live window.
//!
//! THE LOOP DEW WILL RUN, at one window. Events are drained from the platform,
//! forwarded to the guest, a frame is stepped and painted, and the pixels are
//! blitted. Dew adds windows, hotkeys, a tray and a sandbox around this; it does
//! not add anything *inside* it, which is why the body lives on `Driver` rather
//! than here.

use crate::Args;

#[cfg(not(windows))]
pub fn run(_args: &Args) -> Result<(), String> {
    // A CLEAR REFUSAL, not a stub that opens nothing and returns success. The
    // portable half of this CLI is `snapshot`, and it stays useful here.
    Err("preview needs a window and is Windows-only for now; use `aether snapshot`".into())
}

#[cfg(windows)]
pub fn run(args: &Args) -> Result<(), String> {
    use crate::snapshot::{painter, size_of};
    use aether_runtime::{Application, Capabilities, Driver, Modifiers, Pointer, Rgb};
    use aether_window::{Button, Event, Surface, Window};
    use std::time::{Duration, Instant};

    let root = args
        .entry
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_default());

    let app = Application::load(Capabilities::cli(root), &args.entry)
        .map_err(|e| format!("could not load {}: {e}", args.entry.display()))?;

    let (width, height) = size_of(&app, args.size);
    let session = app.session().map_err(|e| e.to_string())?;
    let mut driver = Driver::new(session, painter(width, height)?, Some(Rgb(13, 17, 23)));

    // AN ORDINARY WINDOW. `preview` is for looking at a component while writing
    // it — chrome, a title bar and a taskbar entry are what that wants. The
    // floating-widget surface is Dew's business, where a widget is the product
    // rather than the subject.
    let surface = Surface::Window {
        title: format!("aether — {}", args.entry.display()),
    };
    let mut window = Window::new(&surface, width, height)?;

    println!("previewing {} at {width}x{height}", args.entry.display());

    let target = Duration::from_micros(16_667); // 60 Hz
    let mut last = Instant::now();

    loop {
        let Some(events) = window.poll() else {
            break;
        };

        for event in events {
            match event {
                Event::PointerMove { x, y } => {
                    driver.pointer(Pointer::Move, x, y).map_err(|e| e.to_string())?;
                }
                // LEFT ONLY REACHES THE GUEST. `Live.Session` models one pointer
                // with one button, so forwarding a right-click as a press would
                // activate whatever is under it. Right and middle belong to a
                // context menu the shell owns, and dropping them here is honest
                // until there is one.
                Event::PointerDown { x, y, button: Button::Left } => {
                    driver.pointer(Pointer::Down, x, y).map_err(|e| e.to_string())?;
                }
                Event::PointerUp { x, y, button: Button::Left } => {
                    driver.pointer(Pointer::Up, x, y).map_err(|e| e.to_string())?;
                }
                Event::PointerDown { .. } | Event::PointerUp { .. } => {}
                Event::Wheel { x, y, delta } => {
                    driver.wheel(x, y, delta).map_err(|e| e.to_string())?;
                }
                Event::Char(c) => {
                    driver
                        .key(&c.to_string(), Modifiers::default())
                        .map_err(|e| e.to_string())?;
                }
                Event::Key { name, shift, ctrl } => {
                    let consumed = driver
                        .key(&name, Modifiers { shift, ctrl })
                        .map_err(|e| e.to_string())?;
                    // ONLY IF THE GUEST DID NOT WANT IT. Escape closing the
                    // preview is a shell accelerator, and a focused text field
                    // that handles Escape must win — otherwise typing in a
                    // component quits the program.
                    if !consumed && name == "Escape" {
                        return Ok(());
                    }
                }
                Event::Resized { .. } | Event::Exposed => {
                    // The surface holds nothing patchable now, so the next frame
                    // must be a full one. Resizing the SURFACE is not wired yet —
                    // the window scales the blit — which is a visible stretch and
                    // deliberately not a silent mismatch.
                    driver.invalidate();
                }
                Event::CloseRequested => return Ok(()),
            }
        }

        let dt = last.elapsed().as_secs_f32();
        last = Instant::now();

        // PAINT ONLY WHEN SOMETHING CHANGED, but BLIT every frame regardless: the
        // window may have been uncovered or resized since, and the pixels we hold
        // are still the right ones to show.
        driver.frame(dt).map_err(|e| format!("while rendering: {e}"))?;

        if let Some(bgra) = driver.painter_mut().canvas_mut().bgra() {
            window.present(bgra, width, height);
        }

        let elapsed = last.elapsed();
        if elapsed < target {
            std::thread::sleep(target - elapsed);
        }
    }

    Ok(())
}
