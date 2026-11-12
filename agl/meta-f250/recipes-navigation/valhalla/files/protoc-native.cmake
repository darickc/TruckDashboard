# Included after Valhalla's project() (CMAKE_PROJECT_valhalla_INCLUDE): the
# target sysroot's Protobuf has no compiler (meta-oe builds protoc only for
# -native), so its CMake package defines no protobuf::protoc, which
# protobuf_generate_cpp runs. This target is the build host's protoc
# (OE_PROTOC, from protobuf-native).
if(NOT TARGET protobuf::protoc)
  add_executable(protobuf::protoc IMPORTED)
  set_target_properties(protobuf::protoc PROPERTIES IMPORTED_LOCATION "${OE_PROTOC}")
endif()
