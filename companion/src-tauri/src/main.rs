// No console window behind the tray app in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    soapstone_companion_lib::run()
}
