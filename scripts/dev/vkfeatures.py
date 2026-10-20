#!/usr/bin/env python3
"""Print Vulkan 1.1/1.2 compute-relevant features and subgroup properties
of every GPU, using only ctypes (no Vulkan Python bindings needed).

Usage: vkfeatures.py
"""
import ctypes as C

vk = C.CDLL("libvulkan.so.1")

VK_STRUCTURE_TYPE_APPLICATION_INFO = 0
VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1
VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 = 1000059000
VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2 = 1000059001
VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_FLOAT16_INT8_FEATURES = 1000082000
VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES = 1000083000
VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_8BIT_STORAGE_FEATURES = 1000177000
VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_PROPERTIES = 1000094000
VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES = 1000197000


class AppInfo(C.Structure):
    _fields_ = [("sType", C.c_int), ("pNext", C.c_void_p),
                ("pApplicationName", C.c_char_p), ("applicationVersion", C.c_uint32),
                ("pEngineName", C.c_char_p), ("engineVersion", C.c_uint32),
                ("apiVersion", C.c_uint32)]


class InstanceCreateInfo(C.Structure):
    _fields_ = [("sType", C.c_int), ("pNext", C.c_void_p), ("flags", C.c_uint32),
                ("pApplicationInfo", C.POINTER(AppInfo)),
                ("enabledLayerCount", C.c_uint32), ("ppEnabledLayerNames", C.c_void_p),
                ("enabledExtensionCount", C.c_uint32), ("ppEnabledExtensionNames", C.c_void_p)]


def bools(name, fields):
    return type(name, (C.Structure,), {
        "_fields_": [("sType", C.c_int), ("pNext", C.c_void_p)] + [(f, C.c_uint32) for f in fields]})


F16I8 = bools("F16I8", ["shaderFloat16", "shaderInt8"])
S16 = bools("S16", ["storageBuffer16BitAccess", "uniformAndStorageBuffer16BitAccess",
                    "storagePushConstant16", "storageInputOutput16"])
S8 = bools("S8", ["storageBuffer8BitAccess", "uniformAndStorageBuffer8BitAccess",
                  "storagePushConstant8"])


class Features2(C.Structure):
    _fields_ = [("sType", C.c_int), ("pNext", C.c_void_p), ("features", C.c_uint32 * 55)]


class Subgroup(C.Structure):
    _fields_ = [("sType", C.c_int), ("pNext", C.c_void_p), ("subgroupSize", C.c_uint32),
                ("supportedStages", C.c_uint32), ("supportedOperations", C.c_uint32),
                ("quadOperationsInAllStages", C.c_uint32)]


class FloatControls(C.Structure):
    _fields_ = [("sType", C.c_int), ("pNext", C.c_void_p), ("denormBehaviorIndependence", C.c_int),
                ("roundingModeIndependence", C.c_int)] + [(n, C.c_uint32) for n in (
        "shaderSignedZeroInfNanPreserveFloat16", "shaderSignedZeroInfNanPreserveFloat32",
        "shaderSignedZeroInfNanPreserveFloat64", "shaderDenormPreserveFloat16",
        "shaderDenormPreserveFloat32", "shaderDenormPreserveFloat64",
        "shaderDenormFlushToZeroFloat16", "shaderDenormFlushToZeroFloat32",
        "shaderDenormFlushToZeroFloat64", "shaderRoundingModeRTEFloat16",
        "shaderRoundingModeRTEFloat32", "shaderRoundingModeRTEFloat64",
        "shaderRoundingModeRTZFloat16", "shaderRoundingModeRTZFloat32",
        "shaderRoundingModeRTZFloat64")]


class Properties2(C.Structure):
    _fields_ = [("sType", C.c_int), ("pNext", C.c_void_p),
                ("apiVersion", C.c_uint32), ("driverVersion", C.c_uint32),
                ("vendorID", C.c_uint32), ("deviceID", C.c_uint32), ("deviceType", C.c_int),
                ("deviceName", C.c_char * 256), ("rest", C.c_uint8 * 4096)]


SUBGROUP_OPS = ["basic", "vote", "arithmetic", "ballot", "shuffle", "shuffle_relative",
                "clustered", "quad", "partitioned_nv"]

app = AppInfo(VK_STRUCTURE_TYPE_APPLICATION_INFO, None, b"vkfeatures", 1, None, 0, (1 << 22) | (2 << 12))
ci = InstanceCreateInfo(VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, None, 0, C.pointer(app), 0, None, 0, None)
inst = C.c_void_p()
assert vk.vkCreateInstance(C.byref(ci), None, C.byref(inst)) == 0, "vkCreateInstance failed"

n = C.c_uint32()
vk.vkEnumeratePhysicalDevices(inst, C.byref(n), None)
devs = (C.c_void_p * n.value)()
vk.vkEnumeratePhysicalDevices(inst, C.byref(n), devs)

get_f2 = vk.vkGetPhysicalDeviceFeatures2
get_p2 = vk.vkGetPhysicalDeviceProperties2
for d in devs:
    s8 = S8(VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_8BIT_STORAGE_FEATURES, None)
    s16 = S16(VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES, C.cast(C.pointer(s8), C.c_void_p))
    f16 = F16I8(VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_FLOAT16_INT8_FEATURES, C.cast(C.pointer(s16), C.c_void_p))
    f2 = Features2(VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, C.cast(C.pointer(f16), C.c_void_p))
    get_f2(C.c_void_p(d), C.byref(f2))

    fc = FloatControls(VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES, None)
    sg = Subgroup(VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_PROPERTIES, C.cast(C.pointer(fc), C.c_void_p))
    p2 = Properties2(VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, C.cast(C.pointer(sg), C.c_void_p))
    get_p2(C.c_void_p(d), C.byref(p2))

    v = p2.apiVersion
    print(f"device: {p2.deviceName.decode()}  api {v >> 22}.{(v >> 12) & 0x3ff}.{v & 0xfff}")
    for s in (f16, s16, s8):
        for name, _ in s._fields_[2:]:
            print(f"  {name} = {getattr(s, name)}")
    ops = [o for i, o in enumerate(SUBGROUP_OPS) if sg.supportedOperations & (1 << i)]
    print(f"  subgroupSize = {sg.subgroupSize}")
    print(f"  subgroupOps  = {', '.join(ops)}")
    print(f"  subgroupStages = 0x{sg.supportedStages:x} (compute = {bool(sg.supportedStages & 0x20)})")
    for name in ("shaderRoundingModeRTEFloat16", "shaderDenormPreserveFloat16",
                 "shaderSignedZeroInfNanPreserveFloat16"):
        print(f"  {name} = {getattr(fc, name)}")
