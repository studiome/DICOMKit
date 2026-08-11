#pragma once

// CharLS publishes a stable C API. Keeping this header as the C module's only
// public header prevents SwiftPM from treating CharLS' optional C++ APIs as
// part of the imported Clang umbrella module.
#include "../../../Vendor/CharLS/include/charls/charls.h"
