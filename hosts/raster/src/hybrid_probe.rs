//! A bounded experiment: what does GPU rendering cost when the pixels have to
//! come BACK to the CPU?
//!
//! `vello_hybrid` supports headless rendering, which means it can slot behind the
//! existing `ar_*` ABI exactly as `vello_cpu` did -- render to a texture, read the
//! pixels back, let GDI draw text over them, blit. No window handle, no swapchain,
//! and the text half stays delegated.
//!
//! The catch is the readback. A GPU→CPU copy is a full pipeline sync, and at
//! 1280x720 it moves 3.7 MB per frame. `vello_cpu` already rasterises shop's whole
//! frame in 1.70 ms, so the GPU only wins if render PLUS readback beats that --
//! and that is not obvious enough to assume in either direction.
//!
//! This measures it before anything is restructured, because the answer decides
//! whether the windowed architecture (which forces text into vello) is required or
//! merely optional.

use vello_cpu::color::{AlphaColor, Srgb};
use vello_cpu::kurbo::{BezPath, Rect as VRect, RoundedRect, Shape};
use vello_hybrid::{RenderSize, RenderTargetConfig, Renderer, Resources, Scene, TextureBindings};

pub struct Gpu {
    device: wgpu::Device,
    queue: wgpu::Queue,
    renderer: Renderer,
    resources: Resources,
    texture: wgpu::Texture,
    view: wgpu::TextureView,
    buffer: wgpu::Buffer,
    bytes_per_row: u32,
    width: u16,
    height: u16,
}

impl Gpu {
    pub fn new(width: u16, height: u16) -> Option<Self> {
        let instance = wgpu::Instance::default();
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            force_fallback_adapter: false,
            compatible_surface: None,
        }))
        .ok()?;
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("aether"),
            required_features: wgpu::Features::empty(),
            ..Default::default()
        }))
        .ok()?;

        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("aether target"),
            size: wgpu::Extent3d {
                width: width.into(),
                height: height.into(),
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8Unorm,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        let (renderer, resources) = Renderer::new(
            &device,
            &RenderTargetConfig {
                format: texture.format(),
                width: width.into(),
                height: height.into(),
            },
        );
        // 256-byte row alignment is a wgpu requirement for buffer copies, so the
        // readback buffer is WIDER than the image and every row has to be
        // un-padded on the way out.
        let bytes_per_row = (u32::from(width) * 4).next_multiple_of(256);
        let buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("aether readback"),
            size: u64::from(bytes_per_row) * u64::from(height),
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        Some(Self {
            device,
            queue,
            renderer,
            resources,
            texture,
            view,
            buffer,
            bytes_per_row,
            width,
            height,
        })
    }

    /// Render one scene and bring the pixels back. Returns (render_ms, readback_ms).
    pub fn render_and_read(&mut self, scene: &Scene, out: &mut Vec<u8>) -> (f64, f64) {
        let t0 = std::time::Instant::now();
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
        self.renderer
            .render(
                scene,
                &mut self.resources,
                &self.device,
                &self.queue,
                &mut encoder,
                &RenderSize {
                    width: self.width.into(),
                    height: self.height.into(),
                },
                &self.view,
                &TextureBindings::new(),
            )
            .expect("hybrid render");
        encoder.copy_texture_to_buffer(
            wgpu::TexelCopyTextureInfo {
                texture: &self.texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::TexelCopyBufferInfo {
                buffer: &self.buffer,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(self.bytes_per_row),
                    rows_per_image: None,
                },
            },
            wgpu::Extent3d {
                width: self.width.into(),
                height: self.height.into(),
                depth_or_array_layers: 1,
            },
        );
        self.queue.submit([encoder.finish()]);
        let render_ms = t0.elapsed().as_secs_f64() * 1000.0;

        let t1 = std::time::Instant::now();
        self.buffer.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        self.device
            .poll(wgpu::PollType::wait_indefinitely())
            .unwrap();
        out.clear();
        let w = usize::from(self.width) * 4;
        for row in self
            .buffer
            .slice(..)
            .get_mapped_range()
            .chunks_exact(self.bytes_per_row as usize)
        {
            out.extend_from_slice(&row[0..w]);
        }
        self.buffer.unmap();
        let readback_ms = t1.elapsed().as_secs_f64() * 1000.0;
        (render_ms, readback_ms)
    }
}

/// A scene shaped like shop: overlapping large translucent rounded panels, which
/// is the fill-rate-bound case the GPU is supposed to win.
pub fn shoplike_scene(width: u16, height: u16, nodes: usize) -> Scene {
    let mut scene = Scene::new(width, height);
    scene.set_paint(AlphaColor::<Srgb>::from_rgba8(11, 13, 18, 255));
    scene.fill_rect(&VRect::new(0.0, 0.0, width as f64, height as f64));
    let rounded = |x: f64, y: f64, w: f64, h: f64, r: f64| -> BezPath {
        RoundedRect::new(x, y, x + w, y + h, r).to_path(0.1)
    };
    for i in 0..nodes {
        let f = i as f64;
        let x = 40.0 + (f * 17.0) % (width as f64 - 300.0);
        let y = 40.0 + (f * 29.0) % (height as f64 - 220.0);
        scene.set_paint(AlphaColor::<Srgb>::from_rgba8(
            (30 + i * 3) as u8,
            (41 + i * 2) as u8,
            (59 + i) as u8,
            200,
        ));
        scene.fill_path(&rounded(x, y, 260.0, 180.0, 12.0));
    }
    scene
}

/// The SAME geometry, drawn into vello_cpu, so the two backends are compared on
/// identical work rather than on two different screens.
///
/// Duplicated rather than abstracted over a trait: `Scene` and `RenderContext`
/// share method names but not a trait, and inventing one here would put a layer
/// between the measurement and the thing being measured.
pub fn shoplike_cpu_ms(width: u16, height: u16, nodes: usize, iters: usize) -> f64 {
    use vello_cpu::{Pixmap as VPixmap, RenderContext, Resources as CpuResources};
    let mut ctx = RenderContext::new(width, height);
    let mut pixmap = VPixmap::new(width, height);
    let mut resources = CpuResources::new();
    let rounded = |x: f64, y: f64, w: f64, h: f64, r: f64| -> BezPath {
        RoundedRect::new(x, y, x + w, y + h, r).to_path(0.1)
    };

    let mut record_and_render = || {
        ctx.reset();
        ctx.set_paint(AlphaColor::<Srgb>::from_rgba8(11, 13, 18, 255));
        ctx.fill_rect(&VRect::new(0.0, 0.0, width as f64, height as f64));
        for i in 0..nodes {
            let f = i as f64;
            let x = 40.0 + (f * 17.0) % (width as f64 - 300.0);
            let y = 40.0 + (f * 29.0) % (height as f64 - 220.0);
            ctx.set_paint(AlphaColor::<Srgb>::from_rgba8(
                (30 + i * 3) as u8,
                (41 + i * 2) as u8,
                (59 + i) as u8,
                200,
            ));
            ctx.fill_path(&rounded(x, y, 260.0, 180.0, 12.0));
        }
        ctx.flush();
        ctx.render(&mut pixmap, &mut resources);
    };

    record_and_render();
    let t = std::time::Instant::now();
    for _ in 0..iters {
        record_and_render();
    }
    t.elapsed().as_secs_f64() * 1000.0 / iters as f64
}
