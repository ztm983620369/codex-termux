use super::lock_exclusive;
use super::lock_shared;
use super::try_lock_exclusive;
use super::try_lock_shared;

#[test]
fn exclusive_and_shared_locks_are_available() -> std::io::Result<()> {
    let exclusive = tempfile::tempfile()?;
    lock_exclusive(&exclusive)?;

    let shared = tempfile::tempfile()?;
    lock_shared(&shared)?;

    Ok(())
}

#[test]
fn nonblocking_locks_are_available() -> std::io::Result<()> {
    let exclusive = tempfile::tempfile()?;
    try_lock_exclusive(&exclusive).map_err(std::io::Error::from)?;

    let shared = tempfile::tempfile()?;
    try_lock_shared(&shared).map_err(std::io::Error::from)?;

    Ok(())
}
