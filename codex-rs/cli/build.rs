fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        println!("cargo:rustc-link-arg=-ObjC");
    }

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        link_android_compiler_rt();
    }
}

fn link_android_compiler_rt() {
    const NDK_ENV_VARS: [&str; 3] = ["ANDROID_NDK_HOME", "ANDROID_NDK_ROOT", "NDK_HOME"];

    for name in NDK_ENV_VARS {
        println!("cargo:rerun-if-env-changed={name}");
    }

    let Ok(target_arch) = std::env::var("CARGO_CFG_TARGET_ARCH") else {
        panic!("CARGO_CFG_TARGET_ARCH must be set for Android builds");
    };
    let runtime_arch = match target_arch.as_str() {
        "aarch64" => "aarch64",
        "arm" => "arm",
        "x86" => "i686",
        "x86_64" => "x86_64",
        other => panic!("unsupported Android target architecture: {other}"),
    };
    let archive_name = format!("libclang_rt.builtins-{runtime_arch}-android.a");

    let ndk_root = NDK_ENV_VARS
        .iter()
        .find_map(|name| std::env::var_os(name).map(std::path::PathBuf::from))
        .unwrap_or_else(|| {
            panic!("Android builds require ANDROID_NDK_HOME, ANDROID_NDK_ROOT, or NDK_HOME")
        });
    let archive = find_compiler_rt_archive(&ndk_root, &archive_name).unwrap_or_else(|| {
        panic!(
            "could not find {archive_name} under Android NDK {}",
            ndk_root.display()
        )
    });

    println!("cargo:rerun-if-changed={}", archive.display());
    println!("cargo:rustc-link-arg-bin=codex={}", archive.display());
}

fn find_compiler_rt_archive(ndk_root: &std::path::Path, name: &str) -> Option<std::path::PathBuf> {
    let prebuilt_root = ndk_root.join("toolchains/llvm/prebuilt");

    let Ok(host_dirs) = std::fs::read_dir(prebuilt_root) else {
        return None;
    };
    for host_dir in host_dirs.flatten() {
        let clang_root = host_dir.path().join("lib/clang");
        let Ok(version_dirs) = std::fs::read_dir(clang_root) else {
            continue;
        };
        for version_dir in version_dirs.flatten() {
            let runtime_root = version_dir.path().join("lib");
            let Ok(platform_dirs) = std::fs::read_dir(runtime_root) else {
                continue;
            };
            for platform_dir in platform_dirs.flatten() {
                let candidate = platform_dir.path().join(name);
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
        }
    }

    None
}
