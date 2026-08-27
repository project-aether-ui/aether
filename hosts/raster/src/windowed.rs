//! The windowed GPU path: vello_hybrid presenting straight to a Win32 window.
//!
//! WHY THIS SHAPE, and it was chosen by a measurement rather than a preference.
//! `hybrid_probe` established that a HEADLESS GPU renders 2.4-3.5x faster than
//! `vello_cpu` and then gives all of it back to the readback -- 0.94-1.07x net,
//! a wash. The GPU only pays if the pixels never come home. So this owns the
//! swapchain and presents directly, and there is deliberately no `ar_bgra`
//! equivalent here: the moment a caller can read the pixels back, the reason for
//! this file is gone.
//!
//! WHAT THAT COSTS, stated rather than discovered later:
//!   * GDI CANNOT DRAW HERE. A wgpu surface and GDI do not compose on one window,
//!     so the text-over-the-blit arrangement is unavailable and vello's own glyph
//!     rendering is the only text. That is why text moved into the renderer
//!     first, on the CPU backend, where every existing gate still applied.
//!   * SWAPCHAIN BUFFERS ROTATE. "The surface still holds the previous frame" is
//!     false here, so the damage-clipped repaint the CPU backends use does not
//!     apply. Every frame is drawn whole, which is affordable precisely because
//!     the GPU is drawing it.

use raw_window_handle::{RawDisplayHandle, RawWindowHandle, Win32WindowHandle, WindowsDisplayHandle};
use std::num::NonZeroIsize;
use vello_cpu::color::{AlphaColor, Srgb};
use vello_cpu::kurbo::{BezPath, Rect as VRect, RoundedRect, Shape, Stroke as VStroke};
use vello_cpu::peniko::Gradient as VGradient;
use vello_hybrid::{RenderSize, RenderTargetConfig, Renderer, Resources, Scene, TextureBindings};

pub struct Windowed {
    device: wgpu::Device,
    queue: wgpu::Queue,
    surface: wgpu::Surface<'static>,
    config: wgpu::SurfaceConfiguration,
    renderer: Renderer,
    resources: Resources,
    pub scene: Scene,
    pub width: u16,
    pub height: u16,
    /// Clip depth, so an unbalanced stack can be unwound before presenting.
    /// vello PANICS on an outstanding clip rather than drawing something odd.
    pub depth: usize,
}

impl Windowed {
    /// Attach to an existing Win32 window.
    ///
    /// The HWND arrives as an integer across `zune.ffi`, which is the whole
    /// reason this is unsafe: nothing here can verify it is a window, and the
    /// caller must keep it alive for as long as the surface exists.
    pub fn attach(hwnd: isize, hinstance: isize, width: u16, height: u16) -> Option<Self> {
        Self::attach_reporting(hwnd, hinstance, width, height).ok()
    }

    /// The same thing, but saying WHICH step failed, as a code the host maps to
    /// text.
    ///
    /// `attach` returned a bare `Option` and the host turned that into "no GPU
    /// adapter could present to this window" whatever had actually gone wrong.
    /// Five different failures shared one message, and the real one -- a null
    /// window handle -- was not among the things that message suggested.
    ///
    /// A CODE rather than a string: a `&str` is not NUL-terminated, so handing
    /// its pointer to a C caller invites a read past the end.
    pub fn attach_reporting(
        hwnd: isize,
        hinstance: isize,
        width: u16,
        height: u16,
    ) -> Result<Self, u32> {
        let hwnd = NonZeroIsize::new(hwnd).ok_or(1_u32)?;
        let instance = wgpu::Instance::default();
        let target = wgpu::SurfaceTargetUnsafe::RawHandle {
            // WINDOWS STILL NEEDS A DISPLAY HANDLE, even though it has nothing to
            // put in one. `None` is what the field's type invites and what the
            // wgpu example passes, and it fails with "No `DisplayHandle` is
            // available to create this surface with" -- a message that reads like
            // an X11/Wayland concern and is not. `WindowsDisplayHandle` is empty;
            // it exists so the API has something to be given.
            raw_display_handle: Some(RawDisplayHandle::Windows(WindowsDisplayHandle::new())),
            raw_window_handle: RawWindowHandle::Win32({
                let mut h = Win32WindowHandle::new(hwnd);
                // VULKAN REQUIRES THIS. `VkWin32SurfaceCreateInfoKHR` takes both
                // the window and its module instance, so leaving it None made
                // surface creation fail on any machine wgpu chose Vulkan for.
                h.hinstance = NonZeroIsize::new(hinstance);
                h
            }),
        };
        // SAFETY: the caller guarantees `hwnd` is a live window owned by this
        // thread and outliving the surface. See the note on `attach`.
        let surface = unsafe { instance.create_surface_unsafe(target) }.map_err(|_| 2_u32)?;

        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            force_fallback_adapter: false,
            // COMPATIBLE WITH THIS SURFACE, not merely any adapter. A machine can
            // hold an adapter that cannot present to this window, and the failure
            // then arrives later as a configure error rather than here.
            compatible_surface: Some(&surface),
        }))
        .map_err(|_| 3_u32)?;
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("aether windowed"),
            required_features: wgpu::Features::empty(),
            ..Default::default()
        }))
        .map_err(|_| 4_u32)?;

        let caps = surface.get_capabilities(&adapter);
        // A NON-SRGB FORMAT, deliberately. The display list carries plain sRGB
        // bytes and every other painter writes them unchanged; an `*Srgb` surface
        // would have the hardware convert them a second time, and the native host
        // would quietly differ from the browser and from Roblox.
        let format = caps
            .formats
            .iter()
            .copied()
            .find(|f| {
                matches!(
                    f,
                    wgpu::TextureFormat::Bgra8Unorm | wgpu::TextureFormat::Rgba8Unorm
                )
            })
            .or_else(|| caps.formats.first().copied())
            .ok_or(5_u32)?;
        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            width: width.into(),
            height: height.into(),
            // NOT FIFO -- and the reason was written into this file before it was
            // acted on. Every pacing decision in this host is made by the frame
            // loop (`timeBeginPeriod`, a measured dt, a remainder sleep), and FIFO
            // adds a second, invisible one in the driver that fights it: measured,
            // `present` cost 6.57 ms of an 8.69 ms GPU frame, nearly all of it
            // waiting for a vertical blank the loop had already accounted for.
            //
            // Mailbox first (no tearing, no blocking), then Immediate, then FIFO
            // as the guaranteed-supported floor. `--fps` stays the throttle.
            present_mode: if caps.present_modes.contains(&wgpu::PresentMode::Mailbox) {
                wgpu::PresentMode::Mailbox
            } else if caps.present_modes.contains(&wgpu::PresentMode::Immediate) {
                wgpu::PresentMode::Immediate
            } else {
                wgpu::PresentMode::Fifo
            },
            alpha_mode: caps
                .alpha_modes
                .first()
                .copied()
                .unwrap_or(wgpu::CompositeAlphaMode::Auto),
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };
        surface.configure(&device, &config);

        let (renderer, resources) = Renderer::new(
            &device,
            &RenderTargetConfig {
                format,
                width: width.into(),
                height: height.into(),
            },
        );
        Ok(Self {
            device,
            queue,
            surface,
            config,
            renderer,
            resources,
            scene: Scene::new(width, height),
            width,
            height,
            depth: 0,
        })
    }

    pub fn begin(&mut self, r: u8, g: u8, b: u8) {
        while self.depth > 0 {
            self.scene.pop_clip_path();
            self.depth -= 1;
        }
        self.scene.reset();
        self.scene
            .set_paint(AlphaColor::<Srgb>::from_rgba8(r, g, b, 255));
        self.scene
            .fill_rect(&VRect::new(0.0, 0.0, self.width as f64, self.height as f64));
    }

    pub fn path(x: f32, y: f32, w: f32, h: f32, r: f32) -> Option<BezPath> {
        if w <= 0.0 || h <= 0.0 {
            return None;
        }
        let (x0, y0) = (x as f64, y as f64);
        let (x1, y1) = ((x + w) as f64, (y + h) as f64);
        let r = (r.min(w / 2.0).min(h / 2.0).max(0.0)) as f64;
        Some(if r <= 0.0 {
            VRect::new(x0, y0, x1, y1).to_path(0.1)
        } else {
            RoundedRect::new(x0, y0, x1, y1, r).to_path(0.1)
        })
    }

    pub fn fill(&mut self, path: &BezPath, r: u8, g: u8, b: u8, a: u8) {
        self.scene
            .set_paint(AlphaColor::<Srgb>::from_rgba8(r, g, b, a));
        self.scene.fill_path(path);
    }

    pub fn stroke(&mut self, path: &BezPath, width: f32, r: u8, g: u8, b: u8, a: u8) {
        self.scene
            .set_paint(AlphaColor::<Srgb>::from_rgba8(r, g, b, a));
        self.scene.set_stroke(VStroke::new(width.max(0.1) as f64));
        self.scene.stroke_path(path);
    }

    pub fn gradient(&mut self, path: &BezPath, grad: VGradient) {
        self.scene.set_paint(grad);
        self.scene.fill_path(path);
        // Back to a solid, or the next fill silently inherits the ramp.
        self.scene
            .set_paint(AlphaColor::<Srgb>::from_rgba8(0, 0, 0, 255));
    }

    /// Draw a positioned glyph run.
    ///
    /// A method rather than exposing `scene` and `resources` separately: vello
    /// borrows both at once for a glyph run, so a caller holding one could not
    /// obtain the other. Keeping the pair private makes that impossible to get
    /// wrong from outside.
    ///
    /// `glyphs` arrive already positioned on the baseline -- the same
    /// `FontStore::layout` output the CPU backend uses, so the two cannot lay
    /// text out differently.
    pub fn glyphs(
        &mut self,
        font: &vello_cpu::peniko::FontData,
        size: f32,
        colour: (u8, u8, u8, u8),
        glyphs: impl Iterator<Item = vello_cpu::Glyph> + Clone,
    ) {
        let (r, g, b, a) = colour;
        self.scene
            .set_paint(AlphaColor::<Srgb>::from_rgba8(r, g, b, a));
        self.scene
            .glyph_run(&mut self.resources, font)
            .font_size(size)
            .hint(true)
            .fill_glyphs(glyphs);
    }

    pub fn clip_push(&mut self, x: i32, y: i32, w: i32, h: i32) {
        let rect = VRect::new(x as f64, y as f64, (x + w) as f64, (y + h) as f64);
        self.scene.push_clip_path(&rect.to_path(0.1));
        self.depth += 1;
    }

    pub fn clip_pop(&mut self) {
        if self.depth > 0 {
            self.scene.pop_clip_path();
            self.depth -= 1;
        }
    }

    pub fn resize(&mut self, width: u16, height: u16) {
        if width == 0 || height == 0 || (width == self.width && height == self.height) {
            return;
        }
        self.width = width;
        self.height = height;
        self.config.width = width.into();
        self.config.height = height.into();
        self.surface.configure(&self.device, &self.config);
        self.scene.reset_and_resize(width, height);
        self.depth = 0;
    }

    /// Rasterise the CURRENT scene to an off-screen texture and bring the pixels
    /// back, as `0x00RRGGBB` per pixel.
    ///
    /// FOR VERIFICATION ONLY, and the distinction is the whole point of this
    /// file. `hybrid_probe` measured that a readback costs more than the GPU
    /// saves, which is why the frame loop presents and never reads. But a
    /// renderer with no way to inspect its output has no automated gate at all --
    /// it can draw garbage and only a human eye will catch it, which is the exact
    /// failure mode this host keeps meeting.
    ///
    /// So the readback exists, on a path the frame loop cannot reach: it
    /// allocates its own target every call and is deliberately slow. That makes
    /// it useless as a shortcut and sufficient as a check.
    pub fn read_back(&mut self) -> Option<Vec<u32>> {
        let (w, h) = (self.width, self.height);
        let texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("aether verify"),
            size: wgpu::Extent3d {
                width: w.into(),
                height: h.into(),
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: self.config.format,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
        self.renderer
            .render(
                &self.scene,
                &mut self.resources,
                &self.device,
                &self.queue,
                &mut encoder,
                &RenderSize {
                    width: w.into(),
                    height: h.into(),
                },
                &view,
                &TextureBindings::new(),
            )
            .ok()?;

        // 256-byte row alignment is a wgpu requirement for buffer copies, so the
        // readback buffer is WIDER than the image and every row must be un-padded
        // on the way out.
        let bytes_per_row = (u32::from(w) * 4).next_multiple_of(256);
        let buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("aether verify readback"),
            size: u64::from(bytes_per_row) * u64::from(h),
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_texture_to_buffer(
            wgpu::TexelCopyTextureInfo {
                texture: &texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::TexelCopyBufferInfo {
                buffer: &buffer,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(bytes_per_row),
                    rows_per_image: None,
                },
            },
            wgpu::Extent3d {
                width: w.into(),
                height: h.into(),
                depth_or_array_layers: 1,
            },
        );
        self.queue.submit([encoder.finish()]);

        buffer.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        self.device.poll(wgpu::PollType::wait_indefinitely()).ok()?;

        // THE SURFACE FORMAT DECIDES THE CHANNEL ORDER. A Bgra8 surface and an
        // Rgba8 one hold the same picture with red and blue swapped, and reading
        // one as the other reports every pixel as differing -- which would look
        // like a rasteriser disagreement rather than a byte order.
        let bgra = matches!(self.config.format, wgpu::TextureFormat::Bgra8Unorm);
        let mut out = Vec::with_capacity(usize::from(w) * usize::from(h));
        {
            let view = buffer.slice(..).get_mapped_range();
            for row in view.chunks_exact(bytes_per_row as usize) {
                for px in row[..usize::from(w) * 4].chunks_exact(4) {
                    let (r, g, b) = if bgra {
                        (px[2], px[1], px[0])
                    } else {
                        (px[0], px[1], px[2])
                    };
                    out.push(((r as u32) << 16) | ((g as u32) << 8) | b as u32);
                }
            }
        }
        buffer.unmap();
        Some(out)
    }

    /// Render the recorded scene and PRESENT it. Returns false when the frame was
    /// dropped, which a caller should treat as "try again", not as an error.
    pub fn present(&mut self) -> bool {
        while self.depth > 0 {
            self.scene.pop_clip_path();
            self.depth -= 1;
        }
        // wgpu 29 reports acquisition as an ENUM rather than a Result, and the
        // distinction it draws is the useful one: several of these are ordinary
        // conditions, not failures.
        let frame = match self.surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(f) => f,
            // SUBOPTIMAL STILL HAS A TEXTURE. Presenting it is correct -- dropping
            // the frame would stutter on every window move -- but the surface
            // wants reconfiguring, so do both.
            wgpu::CurrentSurfaceTexture::Suboptimal(f) => {
                self.surface.configure(&self.device, &self.config);
                f
            }
            // A lost or outdated swapchain is NORMAL -- a resize, a display
            // change, a lock screen. Reconfiguring and skipping one frame is the
            // correct response; treating it as fatal would kill the window on
            // events the user considers ordinary.
            wgpu::CurrentSurfaceTexture::Outdated | wgpu::CurrentSurfaceTexture::Lost => {
                self.surface.configure(&self.device, &self.config);
                return false;
            }
            // Occluded means minimised or fully covered: there is nothing to
            // present and nothing wrong. Timeout means try again.
            _ => return false,
        };
        let view = frame
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
        let ok = self
            .renderer
            .render(
                &self.scene,
                &mut self.resources,
                &self.device,
                &self.queue,
                &mut encoder,
                &RenderSize {
                    width: self.width.into(),
                    height: self.height.into(),
                },
                &view,
                &TextureBindings::new(),
            )
            .is_ok();
        self.queue.submit([encoder.finish()]);
        frame.present();
        ok
    }
}
