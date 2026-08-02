set(SIGNALASI_ASR_CORE_SOURCES
    audio_frontend.cpp
    audio_resampler.cpp
    audio_ring_buffer.cpp
    log_mel_extractor.cpp
    rolling_window.cpp
    streaming_frontend_session.cpp
    transcript_stabilizer.cpp
    vad_engine.cpp
)

add_library(signalasi_asr_core STATIC ${SIGNALASI_ASR_CORE_SOURCES})
set_target_properties(signalasi_asr_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(signalasi_asr_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(signalasi_asr_core PUBLIC cxx_std_17)

add_library(signalasi_asr SHARED signalasi_asr_api.cpp ${SIGNALASI_ASR_CORE_SOURCES})
target_include_directories(signalasi_asr PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(signalasi_asr PUBLIC cxx_std_17)

foreach(SIGNALASI_ASR_TARGET signalasi_asr_core signalasi_asr)
    target_compile_options(${SIGNALASI_ASR_TARGET} PRIVATE
        -O3
        -Wall
        -Wextra
        -Wpedantic
        -fvisibility=hidden
        -fvisibility-inlines-hidden
    )
endforeach()

if(ANDROID)
    find_library(SIGNALASI_ASR_LOG_LIB log)
    find_library(SIGNALASI_ASR_ANDROID_LIB android)
    target_link_libraries(signalasi_asr PRIVATE
        ${SIGNALASI_ASR_LOG_LIB}
        ${SIGNALASI_ASR_ANDROID_LIB}
        ${CMAKE_DL_LIBS}
    )
endif()
