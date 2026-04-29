fn main() {
    // Compile the IOKit USB seize helper on macOS
    #[cfg(target_os = "macos")]
    {
        cc::Build::new()
            .file("seize_usb.c")
            .compile("seize_usb");

        // Link against IOKit and CoreFoundation
        println!("cargo:rustc-link-lib=framework=IOKit");
        println!("cargo:rustc-link-lib=framework=CoreFoundation");
    }
}
