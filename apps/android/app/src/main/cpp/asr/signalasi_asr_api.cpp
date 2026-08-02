#if defined(_WIN32)
#define SIGNALASI_ASR_EXPORT __declspec(dllexport)
#else
#define SIGNALASI_ASR_EXPORT __attribute__((visibility("default")))
#endif

extern "C" SIGNALASI_ASR_EXPORT int signalasi_asr_frontend_abi_version() noexcept {
    return 1;
}
