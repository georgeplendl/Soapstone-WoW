fn main() {
    // The addon is built into the companion (src/addon.rs).
    println!("cargo:rerun-if-changed=../../Soapstone");
    tauri_build::build()
}
