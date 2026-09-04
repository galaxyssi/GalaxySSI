#include <android/log.h>
#include <dlfcn.h>

typedef void * (*ggml_backend_registry_fn)(void);

__attribute__((visibility("default")))
int ggml_backend_score(void) {
    return 1000;
}

__attribute__((visibility("default")))
void * ggml_backend_init(void) {
    static void * handle = NULL;
    static ggml_backend_registry_fn registry = NULL;
    if (registry != NULL) {
        return registry();
    }
    handle = dlopen("libggml-hexagon.so", RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        __android_log_print(
            ANDROID_LOG_ERROR,
            "GalaxySSIQnn",
            "Unable to load Qualcomm Hexagon GGML backend: %s",
            dlerror()
        );
        return NULL;
    }
    registry = (ggml_backend_registry_fn) dlsym(handle, "ggml_backend_hexagon_reg");
    if (registry == NULL) {
        __android_log_print(
            ANDROID_LOG_ERROR,
            "GalaxySSIQnn",
            "Hexagon GGML registry symbol is unavailable: %s",
            dlerror()
        );
        return NULL;
    }
    return registry();
}
