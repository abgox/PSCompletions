//! `psc` binary: thin entry point over the `psc_cli` library.

use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    psc_cli::run::run(args)
}
