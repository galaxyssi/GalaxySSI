package com.galaxyssi.chat

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.lang.reflect.Modifier
import java.util.Locale

enum class LocalModelAcceleratorKind {
    CPU,
    GPU,
    NNAPI,
    VENDOR_SDK
}

enum class LocalModelAcceleratorState {
    READY,
    HARDWARE_ONLY,
    UNAVAILABLE
}

data class LocalModelAcceleratorCapability(
    val kind: LocalModelAcceleratorKind,
    val state: LocalModelAcceleratorState,
    val provider: String,
    val hardwareEvidence: String,
    val runtimeEvidence: String
) {
    val ready: Boolean
        get() = state == LocalModelAcceleratorState.READY
}

data class LocalModelAcceleratorSnapshot(
    val capabilities: List<LocalModelAcceleratorCapability>,
    val checkedAtMillis: Long = System.currentTimeMillis()
) {
    operator fun get(kind: LocalModelAcceleratorKind): LocalModelAcceleratorCapability =
        capabilities.first { it.kind == kind }
}

data class LocalModelAcceleratorProbe(
    val cpuHardwareAvailable: Boolean,
    val cpuDescription: String,
    val cpuRuntimeAvailable: Boolean,
    val cpuRuntimeDescription: String,
    val gpuHardwareAvailable: Boolean,
    val gpuDescription: String,
    val gpuRuntimeAvailable: Boolean,
    val gpuRuntimeDescription: String,
    val nnapiPlatformAvailable: Boolean,
    val nnapiProviderAvailable: Boolean,
    val nnapiDescription: String,
    val vendorFamily: String,
    val vendorHardwareEvidence: String,
    val vendorSdkAvailable: Boolean,
    val vendorRuntimeEvidence: String
)

object LocalModelAcceleratorPolicy {
    fun evaluate(probe: LocalModelAcceleratorProbe): LocalModelAcceleratorSnapshot =
        LocalModelAcceleratorSnapshot(
            capabilities = listOf(
                capability(
                    kind = LocalModelAcceleratorKind.CPU,
                    hardware = probe.cpuHardwareAvailable,
                    runtime = probe.cpuRuntimeAvailable,
                    provider = "CPU",
                    hardwareEvidence = probe.cpuDescription,
                    runtimeEvidence = probe.cpuRuntimeDescription
                ),
                capability(
                    kind = LocalModelAcceleratorKind.GPU,
                    hardware = probe.gpuHardwareAvailable,
                    runtime = probe.gpuRuntimeAvailable,
                    provider = "Vulkan / OpenGL ES",
                    hardwareEvidence = probe.gpuDescription,
                    runtimeEvidence = probe.gpuRuntimeDescription
                ),
                capability(
                    kind = LocalModelAcceleratorKind.NNAPI,
                    hardware = probe.nnapiPlatformAvailable,
                    runtime = probe.nnapiProviderAvailable,
                    provider = "Android NNAPI",
                    hardwareEvidence = probe.nnapiDescription,
                    runtimeEvidence = if (probe.nnapiProviderAvailable) {
                        "ONNX Runtime exposes the NNAPI execution provider"
                    } else {
                        "The bundled inference runtime does not expose NNAPI"
                    }
                ),
                capability(
                    kind = LocalModelAcceleratorKind.VENDOR_SDK,
                    hardware = probe.vendorFamily.isNotBlank(),
                    runtime = probe.vendorSdkAvailable,
                    provider = probe.vendorFamily.ifBlank { "Vendor accelerator" },
                    hardwareEvidence = probe.vendorHardwareEvidence,
                    runtimeEvidence = probe.vendorRuntimeEvidence
                )
            )
        )

    private fun capability(
        kind: LocalModelAcceleratorKind,
        hardware: Boolean,
        runtime: Boolean,
        provider: String,
        hardwareEvidence: String,
        runtimeEvidence: String
    ) = LocalModelAcceleratorCapability(
        kind = kind,
        state = when {
            hardware && runtime -> LocalModelAcceleratorState.READY
            hardware -> LocalModelAcceleratorState.HARDWARE_ONLY
            else -> LocalModelAcceleratorState.UNAVAILABLE
        },
        provider = provider,
        hardwareEvidence = hardwareEvidence,
        runtimeEvidence = runtimeEvidence
    )
}

object LocalModelAcceleratorDetector {
    fun detect(context: Context): LocalModelAcceleratorSnapshot {
        val appContext = context.applicationContext
        val packageManager = appContext.packageManager
        val nativeLibraryDirectory = File(appContext.applicationInfo.nativeLibraryDir)
        val providers = onnxRuntimeProviders()
        val gpu = gpuHardware(packageManager, appContext)
        val vendor = vendorHardware()
        val bundledLibraries = nativeLibraryDirectory
            .listFiles()
            .orEmpty()
            .filter(File::isFile)
            .mapTo(linkedSetOf()) { it.name.lowercase(Locale.ROOT) }
        val vendorLibraryNames = vendorLibraryNames(vendor.family)
        val bundledVendorLibraries = bundledLibraries.filter { library ->
            vendorLibraryNames.any { expected -> expected in library }
        }
        val systemVendorLibraries = vendorSystemLibraryRoots()
            .flatMap { root -> vendorLibraryNames.map { name -> File(root, name) } }
            .filter(File::isFile)
        val localLlmRuntime = LocalModelInferenceRuntime.available()
        val smeExposed = localLlmRuntime && LocalModelInferenceRuntime.osExposesSme()
        val cpuRuntime = localLlmRuntime ||
            File(nativeLibraryDirectory, System.mapLibraryName("whisper")).isFile ||
            providers.any { it == "CPU" || it == "CPU_EXECUTION_PROVIDER" }
        val gpuRuntimeLibraries = setOf(
            "libggml-vulkan.so",
            "libggml-opencl.so",
            "libvulkan_delegate.so",
            "libgpu_delegate.so"
        )
        val gpuRuntime = bundledLibraries.any(gpuRuntimeLibraries::contains) ||
            providers.any { it.contains("VULKAN") || it.contains("OPENCL") || it.contains("GPU") }
        return LocalModelAcceleratorPolicy.evaluate(
            LocalModelAcceleratorProbe(
                cpuHardwareAvailable = Build.SUPPORTED_ABIS.isNotEmpty(),
                cpuDescription = buildString {
                    append(Runtime.getRuntime().availableProcessors().coerceAtLeast(1))
                    append(" cores / ")
                    append(Build.SUPPORTED_ABIS.joinToString().ifBlank { "unknown ABI" })
                    append(if (smeExposed) " / SME-QMX exposed" else " / NEON fallback")
                },
                cpuRuntimeAvailable = cpuRuntime,
                cpuRuntimeDescription = if (localLlmRuntime) {
                    if (smeExposed) {
                        "llama.cpp can dispatch compatible operations to KleidiAI SME kernels"
                    } else {
                        "llama.cpp will use its runtime-dispatched NEON CPU backend"
                    }
                } else if (cpuRuntime) {
                    "Bundled GGML or ONNX Runtime CPU backend detected"
                } else {
                    "No bundled CPU inference backend detected"
                },
                gpuHardwareAvailable = gpu.available,
                gpuDescription = gpu.description,
                gpuRuntimeAvailable = gpuRuntime,
                gpuRuntimeDescription = if (gpuRuntime) {
                    "A bundled GPU inference backend was detected"
                } else {
                    "GGML Vulkan/OpenCL delegate is not bundled in this build"
                },
                nnapiPlatformAvailable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1,
                nnapiProviderAvailable = providers.any { it.contains("NNAPI") },
                nnapiDescription = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    "Android ${Build.VERSION.RELEASE} exposes the NNAPI platform"
                } else {
                    "NNAPI requires Android 8.1 or later"
                },
                vendorFamily = vendor.family,
                vendorHardwareEvidence = vendor.evidence,
                vendorSdkAvailable = bundledVendorLibraries.isNotEmpty(),
                vendorRuntimeEvidence = when {
                    bundledVendorLibraries.isNotEmpty() ->
                        "Bundled runtime: ${bundledVendorLibraries.sorted().joinToString()}"
                    systemVendorLibraries.isNotEmpty() ->
                        "System runtime detected, but no app SDK adapter is bundled"
                    vendor.family.isNotBlank() ->
                        "Compatible SoC family detected, but no app SDK adapter is bundled"
                    else ->
                        "No supported vendor accelerator family was identified"
                }
            )
        )
    }

    private fun onnxRuntimeProviders(): Set<String> = runCatching {
        val environmentClass = Class.forName("ai.onnxruntime.OrtEnvironment")
        val method = environmentClass.methods.firstOrNull {
            it.name == "getAvailableProviders" && it.parameterCount == 0
        } ?: return@runCatching emptySet()
        val receiver = if (Modifier.isStatic(method.modifiers)) {
            null
        } else {
            environmentClass.getMethod("getEnvironment").invoke(null)
        }
        val value = method.invoke(receiver)
        when (value) {
            is Iterable<*> -> value.mapNotNull { it?.toString() }
            is Array<*> -> value.mapNotNull { it?.toString() }
            else -> emptyList()
        }.mapTo(linkedSetOf()) { it.uppercase(Locale.ROOT) }
    }.getOrDefault(emptySet())

    private fun gpuHardware(
        packageManager: PackageManager,
        context: Context
    ): GpuHardware {
        val featureInfo = packageManager.systemAvailableFeatures.orEmpty()
        val vulkanVersion = featureInfo.firstOrNull {
            it.name == PackageManager.FEATURE_VULKAN_HARDWARE_VERSION
        }?.version ?: 0
        val vulkanLevel = featureInfo.firstOrNull {
            it.name == PackageManager.FEATURE_VULKAN_HARDWARE_LEVEL
        }?.version ?: 0
        val glEsVersion = context.getSystemService(ActivityManager::class.java)
            ?.deviceConfigurationInfo
            ?.reqGlEsVersion
            ?: 0
        val vulkanAvailable = vulkanVersion > 0 || packageManager.hasSystemFeature(
            PackageManager.FEATURE_VULKAN_HARDWARE_VERSION
        )
        val glEsAvailable = glEsVersion >= OPENGL_ES_3_1
        val description = buildList {
            if (vulkanAvailable) {
                add("Vulkan ${formatVulkanVersion(vulkanVersion)} / level $vulkanLevel")
            }
            if (glEsAvailable) {
                add("OpenGL ES ${formatGlEsVersion(glEsVersion)}")
            }
        }.joinToString().ifBlank { "No Vulkan or OpenGL ES 3.1 compute signal" }
        return GpuHardware(vulkanAvailable || glEsAvailable, description)
    }

    private fun vendorHardware(): VendorHardware {
        val values = buildList {
            add(Build.MANUFACTURER)
            add(Build.BRAND)
            add(Build.HARDWARE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Build.SOC_MANUFACTURER)
                add(Build.SOC_MODEL)
            }
        }.filter(String::isNotBlank)
        val identity = values.joinToString(" ").lowercase(Locale.ROOT)
        val family = when {
            listOf("qualcomm", "qcom", "snapdragon").any(identity::contains) -> "Qualcomm QNN"
            listOf("mediatek", "dimensity").any(identity::contains) ||
                Regex("\\bmt[0-9]{4,}\\b").containsMatchIn(identity) -> "MediaTek NeuroPilot"
            listOf("samsung", "exynos").any(identity::contains) -> "Samsung ENN"
            listOf("google", "tensor").all(identity::contains) -> "Google Tensor"
            listOf("huawei", "kirin", "hisilicon").any(identity::contains) -> "Huawei HiAI"
            else -> ""
        }
        return VendorHardware(
            family = family,
            evidence = values.distinct().joinToString().ifBlank { "Unknown SoC" }
        )
    }

    private fun vendorLibraryNames(family: String): Set<String> = when (family) {
        "Qualcomm QNN" -> setOf(
            "libqnnhtp.so",
            "libqnnsystem.so",
            "libsnpe.so",
            "libggml-hexagon.so",
            "libggml-htp-v68.so",
            "libggml-htp-v69.so",
            "libggml-htp-v73.so",
            "libggml-htp-v75.so",
            "libggml-htp-v79.so",
            "libggml-htp-v81.so"
        )
        "MediaTek NeuroPilot" -> setOf("libneuron_adapter.so", "libneuronusdk_adapter.so")
        "Samsung ENN" -> setOf("libenn_public_api_cpp.so", "libenn_user.so")
        "Google Tensor" -> setOf("libedgetpu_delegate.so", "libgoogle_nn.so")
        "Huawei HiAI" -> setOf("libhiai.so", "libhiai_ir.so")
        else -> emptySet()
    }

    private fun vendorSystemLibraryRoots(): List<File> = listOf(
        File("/vendor/lib64"),
        File("/vendor/lib"),
        File("/system/vendor/lib64"),
        File("/system/vendor/lib")
    )

    private fun formatVulkanVersion(value: Int): String {
        if (value <= 0) return "available"
        val major = value ushr 22
        val minor = (value ushr 12) and 0x3ff
        val patch = value and 0xfff
        return "$major.$minor.$patch"
    }

    private fun formatGlEsVersion(value: Int): String =
        "${value ushr 16}.${value and 0xffff}"

    private data class GpuHardware(val available: Boolean, val description: String)
    private data class VendorHardware(val family: String, val evidence: String)

    private const val OPENGL_ES_3_1 = 0x00030001
}
