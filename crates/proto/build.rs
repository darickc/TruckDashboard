//! Generates Rust types from shared/proto. Requires `protoc` on PATH
//! (`brew install protobuf` / `apt install protobuf-compiler`).

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = "../../shared/proto";
    let files = [
        "f250/vehicle/v1/vehicle.proto",
        "f250/vehicle/v1/diagnostics.proto",
        "f250/camera/v1/camera.proto",
    ];
    for f in files {
        println!("cargo:rerun-if-changed={root}/{f}");
    }
    let paths: Vec<String> = files.iter().map(|f| format!("{root}/{f}")).collect();
    tonic_prost_build::configure().compile_protos(&paths, &[root.to_string()])?;
    Ok(())
}
