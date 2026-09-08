#include <jni.h>
#include <cmath>
#include <cstdint>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
#include "llama.h"

namespace {
void wipe(void * data, size_t size) {
    auto * bytes = static_cast<volatile unsigned char *>(data);
    while (size-- > 0) *bytes++ = 0;
}

template <typename T> struct SensitiveVector : std::vector<T> {
    using std::vector<T>::vector;
    ~SensitiveVector() { wipe(this->data(), this->size() * sizeof(T)); }
};

struct Encoder {
    llama_model * model = nullptr;
    llama_context * context = nullptr;
    ~Encoder() {
        if (context) llama_free(context);
        if (model) llama_model_free(model);
    }
};

// Separate from the chat runtime lock and model. Handles cannot become dangling pointers.
std::mutex encoder_mutex;
std::unordered_map<jlong, std::unique_ptr<Encoder>> encoders;
jlong next_handle = 1;

void fail(JNIEnv * env, const std::exception & error) {
    if (env->ExceptionCheck()) return;
    jclass type = env->FindClass("java/lang/IllegalStateException");
    if (type) env->ThrowNew(type, error.what());
}

SensitiveVector<char> read_bytes(JNIEnv * env, jbyteArray array) {
    if (!array) throw std::runtime_error("Missing embedding input");
    const jsize size = env->GetArrayLength(array);
    SensitiveVector<char> bytes(static_cast<size_t>(size));
    env->GetByteArrayRegion(array, 0, size, reinterpret_cast<jbyte *>(bytes.data()));
    if (env->ExceptionCheck()) throw std::runtime_error("Could not read embedding input");
    return bytes;
}

struct Batch {
    llama_batch value;
    explicit Batch(int count) : value(llama_batch_init(count, 0, 1)) {}
    ~Batch() {
        if (value.token) wipe(value.token, value.n_tokens * sizeof(llama_token));
        llama_batch_free(value);
    }
};

struct ClearMemory {
    llama_context * context;
    ~ClearMemory() {
        auto memory = llama_get_memory(context);
        if (memory) llama_memory_clear(memory, true);
    }
};

struct ClearOutput {
    float * data;
    int dimensions;
    ~ClearOutput() { if (data && dimensions > 0) wipe(data, dimensions * sizeof(float)); }
};
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_galaxyssi_llama_GalaxySSIEmbeddingRuntime_00024Companion_nativeOpen(
        JNIEnv * env, jobject, jbyteArray path_bytes, jint context_tokens, jint threads) {
    std::lock_guard<std::mutex> lock(encoder_mutex);
    try {
        if (context_tokens < 32 || context_tokens > 8192 || threads < 1 || threads > 64)
            throw std::runtime_error("Invalid embedding runtime configuration");
        auto path = read_bytes(env, path_bytes);
        path.push_back('\0');
        auto encoder = std::make_unique<Encoder>();
        auto model_params = llama_model_default_params();
        model_params.n_gpu_layers = 0;
        model_params.load_mode = LLAMA_LOAD_MODE_MMAP;
        encoder->model = llama_model_load_from_file(path.data(), model_params);
        if (!encoder->model) throw std::runtime_error("Could not load embedding GGUF");
        if (context_tokens > llama_model_n_ctx_train(encoder->model))
            throw std::runtime_error("Embedding context exceeds the model training window");
        if (llama_model_has_encoder(encoder->model) && llama_model_has_decoder(encoder->model))
            throw std::runtime_error("Encoder-decoder embedding models are unsupported");
        auto params = llama_context_default_params();
        params.n_ctx = context_tokens;
        params.n_batch = context_tokens;
        params.n_ubatch = context_tokens;
        params.n_seq_max = 1;
        params.n_threads = threads;
        params.n_threads_batch = threads;
        params.embeddings = true;
        params.pooling_type = LLAMA_POOLING_TYPE_UNSPECIFIED;
        encoder->context = llama_init_from_model(encoder->model, params);
        if (!encoder->context) throw std::runtime_error("Could not create embedding context");
        const auto pooling = llama_pooling_type(encoder->context);
        if (pooling != LLAMA_POOLING_TYPE_CLS && pooling != LLAMA_POOLING_TYPE_MEAN &&
                pooling != LLAMA_POOLING_TYPE_LAST)
            throw std::runtime_error("Model must provide sequence embedding pooling");
        const jlong handle = next_handle++;
        encoders.emplace(handle, std::move(encoder));
        return handle;
    } catch (const std::exception & error) { fail(env, error); return 0; }
}

extern "C" JNIEXPORT jfloatArray JNICALL
Java_com_galaxyssi_llama_GalaxySSIEmbeddingRuntime_nativeEmbed(
        JNIEnv * env, jobject, jlong handle, jbyteArray input) {
    std::lock_guard<std::mutex> lock(encoder_mutex);
    try {
        auto found = encoders.find(handle);
        if (found == encoders.end()) throw std::runtime_error("Embedding runtime is closed");
        auto & encoder = *found->second;
        auto text = read_bytes(env, input);
        if (text.empty()) throw std::runtime_error("Embedding input is empty");
        const auto * vocab = llama_model_get_vocab(encoder.model);
        int count = llama_tokenize(vocab, text.data(), static_cast<int>(text.size()), nullptr, 0, true, false);
        if (count == INT32_MIN) throw std::runtime_error("Embedding token count overflow");
        if (count < 0) count = -count;
        if (count <= 0 || static_cast<uint32_t>(count) > llama_n_ctx(encoder.context))
            throw std::runtime_error("Embedding input exceeds the model token window; split it into chunks");
        SensitiveVector<llama_token> tokens(static_cast<size_t>(count));
        count = llama_tokenize(vocab, text.data(), static_cast<int>(text.size()), tokens.data(), count, true, false);
        if (count <= 0) throw std::runtime_error("Embedding tokenization failed");
        ClearMemory clear{encoder.context};
        auto memory = llama_get_memory(encoder.context);
        if (memory) llama_memory_clear(memory, true);
        Batch batch(count);
        if (!batch.value.token || !batch.value.pos || !batch.value.n_seq_id ||
                !batch.value.seq_id || !batch.value.logits)
            throw std::runtime_error("Embedding batch allocation failed");
        batch.value.n_tokens = count;
        for (int i = 0; i < count; ++i) {
            batch.value.token[i] = tokens[i];
            batch.value.pos[i] = i;
            batch.value.n_seq_id[i] = 1;
            batch.value.seq_id[i][0] = 0;
            batch.value.logits[i] = true;
        }
        if (llama_decode(encoder.context, batch.value) != 0)
            throw std::runtime_error("Embedding inference failed");
        float * embedding = llama_get_embeddings_seq(encoder.context, 0);
        const int dimensions = llama_model_n_embd_out(encoder.model);
        ClearOutput clear_output{embedding, dimensions};
        if (!embedding || dimensions <= 0) throw std::runtime_error("Model produced no sequence embedding");
        double norm = 0;
        for (int i = 0; i < dimensions; ++i) norm += static_cast<double>(embedding[i]) * embedding[i];
        if (!std::isfinite(norm) || norm <= 0) throw std::runtime_error("Model produced an invalid embedding");
        norm = std::sqrt(norm);
        SensitiveVector<float> normalized(static_cast<size_t>(dimensions));
        for (int i = 0; i < dimensions; ++i) normalized[i] = static_cast<float>(embedding[i] / norm);
        jfloatArray result = env->NewFloatArray(dimensions);
        if (result) env->SetFloatArrayRegion(result, 0, dimensions, normalized.data());
        return result;
    } catch (const std::exception & error) { fail(env, error); return nullptr; }
}

extern "C" JNIEXPORT void JNICALL
Java_com_galaxyssi_llama_GalaxySSIEmbeddingRuntime_nativeClose(JNIEnv *, jobject, jlong handle) {
    std::lock_guard<std::mutex> lock(encoder_mutex);
    encoders.erase(handle);
}
