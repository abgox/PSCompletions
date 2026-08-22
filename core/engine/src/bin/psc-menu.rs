use std::process::ExitCode;
use std::sync::OnceLock;

use psc_engine::menu::protocol::*;
use psc_engine::menu::{app, model, state};

const USAGE: &str = "usage: psc-menu <input.json> --result <output.json>";

/// Result path for the panic hook, so a crash still writes the error state to output.json.
static RESULT_PATH: OnceLock<std::path::PathBuf> = OnceLock::new();

fn run_sort_mode(args: &[String]) -> ExitCode {
    let (Some(input_path), Some(result_path)) =
        (get_flag(args, "--sort"), get_flag(args, "--result"))
    else {
        eprintln!("usage: psc-menu --sort <input.json> --result <out.json>");
        return ExitCode::FAILURE;
    };
    let input: SortInput = match std::fs::read_to_string(&input_path) {
        Ok(t) => match serde_json::from_str(&t) {
            Ok(i) => i,
            Err(e) => {
                eprintln!("bad sort input: {e}");
                return ExitCode::FAILURE;
            }
        },
        Err(e) => {
            eprintln!("read input failed: {e}");
            return ExitCode::FAILURE;
        }
    };
    let is_root = sort_input_is_root(&input);
    let mut items = input.items;
    apply_order_sort(&mut items, &input.order, is_root);
    if std::fs::write(
        &result_path,
        serde_json::to_string(&items).unwrap_or_default(),
    )
    .is_err()
    {
        eprintln!("write result failed");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.iter().any(|a| a == "--self-test") {
        return match self_test() {
            Ok(()) => {
                println!("self-test ok");
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("self-test failed: {e}");
                ExitCode::FAILURE
            }
        };
    }

    // History-order ranking of host-provided items (native fallback): `psc-menu --sort <input.json> --result <out.json>`
    if args.iter().any(|a| a == "--sort") {
        return run_sort_mode(&args);
    }

    let input_path = args.first().cloned();
    let result_path = get_flag(&args, "--result");
    let (Some(input_path), Some(result_path)) = (input_path, result_path) else {
        eprintln!("{USAGE}");
        return ExitCode::FAILURE;
    };

    let _ = RESULT_PATH.set(std::path::PathBuf::from(&result_path));
    std::panic::set_hook(Box::new(|info| {
        if let Some(path) = RESULT_PATH.get() {
            let out = model::Output::error(format!("panic in menu: {info}"));
            if let Ok(json) = serde_json::to_string(&out) {
                let _ = std::fs::write(path, json);
            }
        }
        eprintln!("psc-menu panic: {info}");
    }));

    if args.iter().any(|a| a == "--panic-test") {
        panic!("intentional panic-test");
    }

    // Build mode: when the host passes a manifest build context instead of items, build the
    // candidates here so the menu runs in a single process call. A build failure is reported
    // via an error result (never silently cancelled) so the host can surface it.
    let mut build_error: Option<String> = None;
    if let Ok(text) = std::fs::read_to_string(&input_path) {
        if let Ok(mut input) = serde_json::from_str::<model::Input>(&text) {
            if input.items.is_empty() && input.build.is_some() {
                let build = input.build.clone().unwrap();
                let ci: Option<CompleteInput> = match serde_json::from_value::<CompleteInput>(build)
                {
                    Ok(ci) => Some(ci),
                    Err(e) => {
                        build_error = Some(format!("bad build context: {e}"));
                        None
                    }
                };
                if let Some(ci) = ci {
                    match build_candidate_items(&ci) {
                        Ok((items, ctx)) => {
                            let switch_sym = input.config.context_switch.clone();
                            let stay_sym = input.config.context_stay.clone();
                            input.items = items
                                .iter()
                                .map(|it| lua_to_model_item(it, &switch_sym, &stay_sym))
                                .collect();
                            if input.initial_filter.is_none() {
                                input.initial_filter = ctx
                                    .pending
                                    .as_ref()
                                    .and_then(|p| p.text.as_deref())
                                    .filter(|t| !t.is_empty())
                                    .map(|t| format!("^{t}"));
                            }
                            if let Ok(json) = serde_json::to_string(&input) {
                                let _ = std::fs::write(&input_path, json);
                            }
                        }
                        Err(e) => build_error = Some(e.to_string()),
                    }
                }
            }
        }
    }

    if let Some(msg) = build_error {
        let out = model::Output::error(msg);
        return match std::fs::write(
            &result_path,
            serde_json::to_string(&out).expect("serialize output"),
        ) {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("failed to write result: {e}");
                ExitCode::FAILURE
            }
        };
    }

    let out = app::run(&input_path);

    match std::fs::write(
        &result_path,
        serde_json::to_string(&out).expect("serialize output"),
    ) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("failed to write result: {e}");
            ExitCode::FAILURE
        }
    }
}

/// Smoke test for CI: parse a bundled sample, build state, exercise filters
/// and layout. No terminal is touched.
fn self_test() -> Result<(), String> {
    let input: model::Input =
        serde_json::from_str(SAMPLE_INPUT).map_err(|e| format!("sample parse: {e}"))?;
    if input.items.is_empty() {
        return Err("sample has no items".into());
    }
    let cfg = input.config;
    let term = input.terminal;
    let mut state = state::MenuState::new(input.items, &cfg, &term);
    if state.min_area {
        return Err("unexpected min_area".into());
    }
    if state.filtered.len() != 6 {
        return Err(format!("expected 6 items, got {}", state.filtered.len()));
    }
    state.insert_at_cursor('c');
    match state.apply_filter(&cfg, &term) {
        state::FilterOutcome::Input(_) => return Err("unexpected input outcome".into()),
        state::FilterOutcome::None => {}
    }
    // checkout, commit, branch, cherry-pick all contain 'c'
    if state.filtered.len() != 4 {
        return Err(format!(
            "expected 4 matches for 'c', got {}",
            state.filtered.len()
        ));
    }
    state.move_selection(true, &cfg);
    state.move_selection(true, &cfg);
    if state.selected != 2 {
        return Err(format!("expected selected 2, got {}", state.selected));
    }
    Ok(())
}

const SAMPLE_INPUT: &str = r##"{
  "items": [
    { "completion_text": "add", "list_item_text": "add ~", "tip": "Add files", "result_type": 16 },
    { "completion_text": "apply", "list_item_text": "apply ~", "tip": "Apply a stash", "result_type": 16 },
    { "completion_text": "checkout", "list_item_text": "checkout ~", "tip": "Switch branches", "result_type": 16 },
    { "completion_text": "commit", "list_item_text": "commit ~", "tip": "Record changes", "result_type": 16 },
    { "completion_text": "branch", "list_item_text": "branch ~", "tip": "Manage branches", "result_type": 16 },
    { "completion_text": "cherry-pick", "list_item_text": "cherry-pick ~", "tip": "Apply commits", "result_type": 16 }
  ],
  "config": {
    "flags": {
      "enable_list_loop": true,
      "filter_mode": "wildcard",
      "enable_tip": true,
      "enable_apply_when_single": false,
      "enable_apply_when_no_match": false
    }
  },
  "terminal": {
    "cursor": { "x": 4, "y": 3 },
    "buffer": { "w": 120, "h": 30 },
    "platform": "windows"
  }
}"##;
