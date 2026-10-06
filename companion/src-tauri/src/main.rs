// No console window behind the tray app in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    if std::env::args().any(|a| a == "--sync-once") {
        soapstone_companion_lib::sync_once();
    } else {
        soapstone_companion_lib::run();
    }
}
