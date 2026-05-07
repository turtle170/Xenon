fn main() {
    prost_build::compile_protos(&["../protos/context.proto"], &["../protos"]).unwrap();
    tauri_build::build();
}
