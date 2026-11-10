//! Generated gRPC types for the head-unit API. The `.proto` files in
//! `shared/proto/` are the source of truth; nothing here is hand-written.

#![allow(clippy::all, clippy::pedantic, missing_docs)]

pub mod vehicle {
    pub mod v1 {
        tonic::include_proto!("f250.vehicle.v1");
    }
}

pub mod camera {
    pub mod v1 {
        tonic::include_proto!("f250.camera.v1");
    }
}
