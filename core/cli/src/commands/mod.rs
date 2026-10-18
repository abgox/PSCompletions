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
pub mod tpl;
pub mod update;

/// Run `work` over `items` with at most `workers` concurrent scoped threads.
pub fn run_parallel<T, F>(items: &[T], workers: usize, work: F)
where
    T: Sync,
    F: Fn(usize, &T) + Sync,
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
                // The index rides along so a caller can slot its result by argument position:
                // workers finish in any order, and a report follows the arguments.
                work(i, &items[i]);
            });
        }
    });
}

/// Drop repeated names, keeping the first occurrence: `add demo demo` is one install, not two
/// workers racing on the same pid-suffixed staging directory (and `rm git git` is one removal).
pub fn dedup_names(names: impl IntoIterator<Item = String>) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    names
        .into_iter()
        .filter(|n| seen.insert(n.clone()))
        .collect()
}
