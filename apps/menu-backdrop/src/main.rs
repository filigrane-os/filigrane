// Voile plein écran translucide derrière fuzzel (calque "menu-backdrop"); niri le floute (layer-rule).
// Ne capte aucun clic. Lancé par `menu` avec en argument un fichier créé une fois le voile affiché
// (menu y attend avant d'ouvrir fuzzel). Se ferme dès que fuzzel a disparu.
use std::{env, fs, io::Write, os::fd::AsFd, process, thread, time::Duration};

use wayland_client::{
    delegate_noop,
    globals::{registry_queue_init, GlobalListContents},
    protocol::{wl_buffer, wl_compositor, wl_region, wl_registry, wl_shm, wl_shm_pool, wl_surface},
    Connection, Dispatch, QueueHandle,
};
use wayland_protocols::wp::viewporter::client::{wp_viewport::WpViewport, wp_viewporter::WpViewporter};
use wayland_protocols_wlr::layer_shell::v1::client::{
    zwlr_layer_shell_v1::{Layer, ZwlrLayerShellV1},
    zwlr_layer_surface_v1::{self, Anchor, KeyboardInteractivity, ZwlrLayerSurfaceV1},
};

// Un seul pixel rgba(24, 29, 37, 0.35) (nuit profond Filigrane), étiré à tout l'écran par le viewporter
// (niri n'a pas single-pixel-buffer). ARGB8888 prémultiplié, octets en petit-boutiste: B, G, R, A.
const PIXEL: [u8; 4] = [13, 10, 8, 89];

struct App {
    surface: wl_surface::WlSurface,
    viewport: WpViewport,
    buffer: wl_buffer::WlBuffer,
    ready_file: Option<String>,
}

fn fuzzel_running() -> bool {
    fs::read_dir("/proc").is_ok_and(|d| {
        d.flatten().any(|e| fs::read_to_string(e.path().join("comm")).is_ok_and(|c| c.trim() == "fuzzel"))
    })
}

fn main() {
    let conn = Connection::connect_to_env().expect("pas de session Wayland");
    let (globals, mut queue) = registry_queue_init::<App>(&conn).unwrap();
    let qh = queue.handle();

    let compositor: wl_compositor::WlCompositor = globals.bind(&qh, 4..=6, ()).expect("wl_compositor absent");
    let layer_shell: ZwlrLayerShellV1 = globals.bind(&qh, 1..=4, ()).expect("layer-shell absent");
    let viewporter: WpViewporter = globals.bind(&qh, 1..=1, ()).expect("viewporter absent");
    let shm: wl_shm::WlShm = globals.bind(&qh, 1..=1, ()).expect("wl_shm absent");

    let surface = compositor.create_surface(&qh, ());
    let viewport = viewporter.get_viewport(&surface, &qh, ());
    // Fichier partagé avec niri: créé puis effacé du disque, il ne vit que par son descripteur
    let path = format!("{}/menu-backdrop-{}", env::var("XDG_RUNTIME_DIR").unwrap_or("/tmp".into()), process::id());
    let mut file = fs::File::options().read(true).write(true).create_new(true).open(&path).expect("tampon");
    let _ = fs::remove_file(&path);
    file.write_all(&PIXEL).expect("tampon");
    let pool = shm.create_pool(file.as_fd(), 4, &qh, ());
    let buffer = pool.create_buffer(0, 1, 1, 4, wl_shm::Format::Argb8888, &qh, ());
    pool.destroy();

    // Aucun clic: région d'entrée vide
    let region = compositor.create_region(&qh, ());
    surface.set_input_region(Some(&region));
    region.destroy();

    let layer = layer_shell.get_layer_surface(&surface, None, Layer::Top, "menu-backdrop".into(), &qh, ());
    layer.set_anchor(Anchor::Top | Anchor::Bottom | Anchor::Left | Anchor::Right);
    layer.set_exclusive_zone(-1);
    layer.set_keyboard_interactivity(KeyboardInteractivity::None);
    surface.commit();

    // Fermeture: 1,2 s sans fuzzel (entre deux sélections imbriquées il est relancé en quelques ms);
    // si fuzzel n'est jamais apparu, abandon après 10 s
    thread::spawn(|| {
        let (mut misses, mut ticks, mut seen) = (0, 0, false);
        loop {
            thread::sleep(Duration::from_millis(400));
            ticks += 1;
            let up = fuzzel_running();
            seen |= up;
            misses = if up { 0 } else { misses + 1 };
            if misses >= 3 && (seen || ticks > 25) {
                process::exit(0);
            }
        }
    });

    let mut app = App { surface, viewport, buffer, ready_file: env::args().nth(1) };
    loop {
        queue.blocking_dispatch(&mut app).unwrap();
    }
}

impl Dispatch<ZwlrLayerSurfaceV1, ()> for App {
    fn event(app: &mut Self, layer: &ZwlrLayerSurfaceV1, event: zwlr_layer_surface_v1::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        match event {
            zwlr_layer_surface_v1::Event::Configure { serial, width, height } => {
                layer.ack_configure(serial);
                app.viewport.set_destination(width.max(1) as i32, height.max(1) as i32);
                app.surface.attach(Some(&app.buffer), 0, 0);
                app.surface.damage_buffer(0, 0, 1, 1);
                app.surface.commit();
                // 80 ms de plus pour que niri ait calculé le flou avant que fuzzel s'ouvre
                if let Some(f) = app.ready_file.take() {
                    thread::spawn(move || {
                        thread::sleep(Duration::from_millis(80));
                        let _ = fs::File::create(f);
                    });
                }
            }
            zwlr_layer_surface_v1::Event::Closed => process::exit(0),
            _ => {}
        }
    }
}

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for App {
    fn event(_: &mut Self, _: &wl_registry::WlRegistry, _: wl_registry::Event, _: &GlobalListContents, _: &Connection, _: &QueueHandle<Self>) {}
}

delegate_noop!(App: ignore wl_compositor::WlCompositor);
delegate_noop!(App: ignore wl_surface::WlSurface);
delegate_noop!(App: ignore wl_region::WlRegion);
delegate_noop!(App: ignore wl_buffer::WlBuffer);
delegate_noop!(App: ignore ZwlrLayerShellV1);
delegate_noop!(App: ignore WpViewporter);
delegate_noop!(App: ignore WpViewport);
delegate_noop!(App: ignore wl_shm::WlShm);
delegate_noop!(App: ignore wl_shm_pool::WlShmPool);
