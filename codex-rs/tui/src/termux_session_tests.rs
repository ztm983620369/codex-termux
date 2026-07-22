use super::*;
use pretty_assertions::assert_eq;

#[test]
fn ready_frame_is_a_single_json_host_control_message() {
    let frame = encode_payload(&ReadyPayload {
        version: PROTOCOL_VERSION,
        event: "ready",
        thread_id: "019abcdef".to_string(),
        pid: 42,
        cwd: "/data/data/com.termux/files/home/work".to_string(),
        rollout_path: "/data/data/com.termux/files/home/.codex/sessions/thread.jsonl".to_string(),
        title: "work".to_string(),
    })
    .expect("encode ready frame");

    assert_eq!(
        frame,
        "\u{1b}]8900;codex-session;{\"version\":1,\"event\":\"ready\",\"thread_id\":\"019abcdef\",\"pid\":42,\"cwd\":\"/data/data/com.termux/files/home/work\",\"rollout_path\":\"/data/data/com.termux/files/home/.codex/sessions/thread.jsonl\",\"title\":\"work\"}\u{7}"
    );
}

#[test]
fn payload_control_characters_are_json_escaped() {
    let frame = encode_payload(&ReadyPayload {
        version: PROTOCOL_VERSION,
        event: "ready",
        thread_id: "thread".to_string(),
        pid: 42,
        cwd: "cwd\u{1b}]8900;evil\u{7}".to_string(),
        rollout_path: String::new(),
        title: "title\nnext".to_string(),
    })
    .expect("encode escaped frame");

    assert_eq!(frame.matches('\u{1b}').count(), 1);
    assert_eq!(frame.matches('\u{7}').count(), 1);
    assert!(frame.contains("cwd\\u001b]8900;evil\\u0007"));
    assert!(frame.contains("title\\nnext"));
}

#[test]
fn closed_frame_contains_only_versioned_identity() {
    let frame = encode_payload(&ClosedPayload {
        version: PROTOCOL_VERSION,
        event: "closed",
        thread_id: "019abcdef".to_string(),
    })
    .expect("encode closed frame");

    assert_eq!(
        frame,
        "\u{1b}]8900;codex-session;{\"version\":1,\"event\":\"closed\",\"thread_id\":\"019abcdef\"}\u{7}"
    );
}

#[test]
fn bounded_text_limits_unicode_by_character() {
    assert_eq!(bounded_text("一二三四", 3), "一二三");
}

#[test]
fn oversized_ready_frame_drops_optional_fields_before_rollout_identity() {
    let rollout_path = format!("/{}", "r".repeat(4000));
    let frame = encode_ready_payload(ReadyPayload {
        version: PROTOCOL_VERSION,
        event: "ready",
        thread_id: "019abcdef".to_string(),
        pid: 42,
        cwd: format!("/{}", "c".repeat(4000)),
        rollout_path: rollout_path.clone(),
        title: "title".repeat(50),
    })
    .expect("fit required rollout identity");

    assert!(frame.len() <= MAX_HOST_CONTROL_FRAME_BYTES);
    assert!(frame.contains("\"cwd\":\"\""));
    assert!(frame.contains(&rollout_path));
}

#[test]
fn oversized_required_rollout_identity_is_rejected() {
    let err = encode_ready_payload(ReadyPayload {
        version: PROTOCOL_VERSION,
        event: "ready",
        thread_id: "019abcdef".to_string(),
        pid: 42,
        cwd: String::new(),
        rollout_path: format!("/{}", "r".repeat(MAX_HOST_CONTROL_FRAME_BYTES)),
        title: String::new(),
    })
    .expect_err("reject an unrepresentable rollout identity");

    assert_eq!(err.kind(), std::io::ErrorKind::InvalidInput);
}
