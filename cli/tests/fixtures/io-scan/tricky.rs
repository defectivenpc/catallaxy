use std::collections::HashMap;
#[cfg(test)]
use std::io::Read;

pub fn caught_in_product_code() {
    let _ = std::fs::read_to_string("/etc/passwd");
}

pub fn a_brace_inside_a_raw_string() -> &'static str {
    r#"{ "not": "a scope }" }"#
}

pub fn a_brace_inside_a_comment() {
    // }
    let _ = std::process::Command::new("true");
}

#[cfg(test)]
mod first_tests {
    use super::*;

    #[test]
    fn tests_may_touch_the_real_filesystem() {
        let _ = std::fs::read_to_string("/tmp/x");
        let _ = tempfile::tempdir();
    }
}

pub fn product_code_after_a_test_module() {
    let _ = std::env::var("HOME");
}

#[cfg(test)]
mod second_tests {
    #[test]
    fn also_exempt() {
        let _ = std::process::Command::new("true");
    }
}

/// Naming a handle type is not acquiring one, so neither of these is a
/// finding. Constructing one two lines down is.
pub fn holds_a_handle(dir: Option<tempfile::TempDir>) -> Option<tempfile::TempDir> {
    dir
}

/// Address arithmetic touches no network.
pub fn addresses(a: std::net::Ipv4Addr) -> std::net::IpAddr {
    std::net::IpAddr::V4(a)
}

pub fn actually_makes_one() {
    let _ = tempfile::TempDir::new();
}
