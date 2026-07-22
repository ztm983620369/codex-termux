use std::fs::File;
use std::fs::TryLockError;
use std::io;

pub fn lock_exclusive(file: &File) -> io::Result<()> {
    lock(file, LockMode::Exclusive, /*nonblocking*/ false)
}

pub fn lock_shared(file: &File) -> io::Result<()> {
    lock(file, LockMode::Shared, /*nonblocking*/ false)
}

pub fn try_lock_exclusive(file: &File) -> Result<(), TryLockError> {
    try_lock(file, LockMode::Exclusive)
}

pub fn try_lock_shared(file: &File) -> Result<(), TryLockError> {
    try_lock(file, LockMode::Shared)
}

#[derive(Clone, Copy)]
enum LockMode {
    Exclusive,
    Shared,
}

fn try_lock(file: &File, mode: LockMode) -> Result<(), TryLockError> {
    match lock(file, mode, /*nonblocking*/ true) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == io::ErrorKind::WouldBlock => Err(TryLockError::WouldBlock),
        Err(err) => Err(TryLockError::Error(err)),
    }
}

#[cfg(target_os = "android")]
fn lock(file: &File, mode: LockMode, nonblocking: bool) -> io::Result<()> {
    use std::os::fd::AsRawFd;

    let mut operation = match mode {
        LockMode::Exclusive => libc::LOCK_EX,
        LockMode::Shared => libc::LOCK_SH,
    };
    if nonblocking {
        operation |= libc::LOCK_NB;
    }

    loop {
        let result = unsafe { libc::flock(file.as_raw_fd(), operation) };
        if result == 0 {
            return Ok(());
        }

        let err = io::Error::last_os_error();
        if err.kind() != io::ErrorKind::Interrupted {
            return Err(err);
        }
    }
}

#[cfg(not(target_os = "android"))]
fn lock(file: &File, mode: LockMode, nonblocking: bool) -> io::Result<()> {
    if nonblocking {
        let result = match mode {
            LockMode::Exclusive => file.try_lock(),
            LockMode::Shared => file.try_lock_shared(),
        };
        result.map_err(io::Error::from)
    } else {
        match mode {
            LockMode::Exclusive => file.lock(),
            LockMode::Shared => file.lock_shared(),
        }
    }
}

#[cfg(test)]
#[path = "lib_tests.rs"]
mod tests;
