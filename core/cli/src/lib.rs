//! PSCompletions CLI library (`psc`).
//! Platform-agnostic management CLI: module data layer (settings.json / completions.json /
//! psc info), network fetches, and the command implementations.

pub mod commands;
pub mod data;
pub mod input;
pub mod messages;
pub mod net;
pub mod output;
pub mod postcheck;
pub mod run;
pub mod validate;
