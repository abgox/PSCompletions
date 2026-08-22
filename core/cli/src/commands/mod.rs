//! Management-command implementations. One file per command (or tight group), each
//! carrying its own tests; `mod.rs` holds shared helpers.

pub mod add;
pub mod alias;
pub mod completion;
pub mod config;
pub mod info;
pub mod init;
pub mod list;
pub mod rm;
pub mod update;

/// Run `work` over `items` with at most `workers` concurrent scoped threads.
pub fn run_parallel<T, F>(items: &[T], workers: usize, work: F)
where
    T: Sync,
    F: Fn(&T) + Sync,
{
    if items.is_empty() {
        return;
    }
    let workers = workers.clamp(1, items.len());
    let next = std::sync::atomic::AtomicUsize::new(0);
    std::thread::scope(|s| {
        for _ in 0..workers {
            s.spawn(|| loop {
                let i = next.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                if i >= items.len() {
                    break;
                }
                work(&items[i]);
            });
        }
    });
}
