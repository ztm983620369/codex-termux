//! Native Termux session identity notifications for crash-safe tab restoration.

use std::fmt;
use std::io;
#[cfg(target_os = "android")]
use std::io::IsTerminal;
use std::io::stdout;

use crossterm::Command;
use ratatui::crossterm::execute;
use serde::Serialize;

use crate::session_state::ThreadSessionState;

const TERMUX_HOST_CONTROL_OSC: u16 = 8900;
const TERMUX_CODEX_COMMAND: &str = "codex-session";
const PROTOCOL_VERSION: u8 = 1;
const MAX_PATH_CHARS: usize = 4096;
const MAX_TITLE_CHARS: usize = 256;
// Termux's OSC accumulator is 8192 UTF-16 code units. A byte limit below that
// keeps the complete frame valid even when JSON contains multibyte text.
const MAX_HOST_CONTROL_FRAME_BYTES: usize = 7600;

#[derive(Serialize)]
struct ReadyPayload {
    version: u8,
    event: &'static str,
    thread_id: String,
    pid: u32,
    cwd: String,
    rollout_path: String,
    title: String,
}

#[derive(Serialize)]
struct ClosedPayload {
    version: u8,
    event: &'static str,
    thread_id: String,
}

pub(crate) fn notify_session_ready(session: &ThreadSessionState) -> io::Result<()> {
    if !is_native_termux_terminal() {
        return Ok(());
    }

    let Some(rollout_path) = session.rollout_path.as_deref() else {
        return Ok(());
    };
    let rollout_path = bounded_text(rollout_path.to_string_lossy().as_ref(), MAX_PATH_CHARS);
    if rollout_path.is_empty() {
        return Ok(());
    }

    let payload = ReadyPayload {
        version: PROTOCOL_VERSION,
        event: "ready",
        thread_id: session.thread_id.to_string(),
        pid: std::process::id(),
        cwd: bounded_text(
            session.cwd.as_path().to_string_lossy().as_ref(),
            MAX_PATH_CHARS,
        ),
        rollout_path: rollout_path.clone(),
        title: session
            .thread_name
            .as_deref()
            .map(|title| bounded_text(title, MAX_TITLE_CHARS))
            .unwrap_or_default(),
    };
    let frame = encode_ready_payload(payload)?;
    emit_frame(frame)?;
    tracing::info!(
        thread_id = %session.thread_id,
        rollout_path = %rollout_path,
        "published durable Codex session identity to Termux"
    );
    Ok(())
}

pub(crate) fn notify_session_closed(thread_id: codex_protocol::ThreadId) -> io::Result<()> {
    if !is_native_termux_terminal() {
        return Ok(());
    }

    emit_payload(&ClosedPayload {
        version: PROTOCOL_VERSION,
        event: "closed",
        thread_id: thread_id.to_string(),
    })?;
    tracing::info!(%thread_id, "cleared Codex session identity in Termux");
    Ok(())
}

fn emit_payload(payload: &impl Serialize) -> io::Result<()> {
    let frame = encode_payload(payload)?;
    emit_frame(frame)
}

fn emit_frame(frame: String) -> io::Result<()> {
    execute!(stdout(), TermuxHostControl(frame))
}

fn encode_payload(payload: &impl Serialize) -> io::Result<String> {
    let json = serde_json::to_string(payload).map_err(io::Error::other)?;
    let frame = format!("\x1b]{TERMUX_HOST_CONTROL_OSC};{TERMUX_CODEX_COMMAND};{json}\x07");
    if frame.len() > MAX_HOST_CONTROL_FRAME_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Termux session identity exceeds the OSC frame limit",
        ));
    }
    Ok(frame)
}

fn encode_ready_payload(mut payload: ReadyPayload) -> io::Result<String> {
    match encode_payload(&payload) {
        Ok(frame) => return Ok(frame),
        Err(err) if err.kind() == io::ErrorKind::InvalidInput => {}
        Err(err) => return Err(err),
    }

    payload.title.clear();
    if let Ok(frame) = encode_payload(&payload) {
        return Ok(frame);
    }

    // The rollout path is the durable authority. Cwd is optional on the host,
    // so discard it before rejecting an otherwise recoverable identity.
    payload.cwd.clear();
    encode_payload(&payload)
}

fn bounded_text(value: &str, max_chars: usize) -> String {
    value.chars().take(max_chars).collect()
}

#[cfg(target_os = "android")]
fn is_native_termux_terminal() -> bool {
    if !stdout().is_terminal() {
        return false;
    }
    std::env::var_os("TERMUX_VERSION").is_some()
        || std::env::var_os("PREFIX").is_some_and(|prefix| {
            std::path::Path::new(&prefix).starts_with("/data/data/com.termux/files/usr")
        })
}

#[cfg(not(target_os = "android"))]
fn is_native_termux_terminal() -> bool {
    false
}

struct TermuxHostControl(String);

impl Command for TermuxHostControl {
    fn write_ansi(&self, f: &mut impl fmt::Write) -> fmt::Result {
        f.write_str(&self.0)
    }

    #[cfg(windows)]
    fn execute_winapi(&self) -> io::Result<()> {
        Err(io::Error::other(
            "Termux host control is only available through ANSI output",
        ))
    }

    #[cfg(windows)]
    fn is_ansi_code_supported(&self) -> bool {
        true
    }
}

#[cfg(test)]
#[path = "termux_session_tests.rs"]
mod tests;
